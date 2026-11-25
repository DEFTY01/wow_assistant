// Streams WoWCombatLog*.txt files into fight segments. Only closed fights are stored; a fight that
// may still be running is re-read on the next pass (the saved offset stops at its first line).
// Field layout after the timestamp (COMBAT_LOG_VERSION 22, advanced logging), 0-based:
//   0 event, 1 srcGUID, 2 srcName, 3-4 flags, 5 dstGUID, 6 dstName, 7-8 flags, then the payload.
//   SWING_DAMAGE amount: 28 · SPELL_/RANGE_/PERIODIC damage amount: 31 · SPELL_HEAL amount 31, overheal 32
import { closeSync, openSync, readSync, statSync } from "node:fs";
import type { DatabaseSync } from "node:sqlite";
import type { Config } from "../config.ts";
import { tx } from "../db.ts";
import { combatLogFiles } from "../paths.ts";

export function splitCsv(line: string): string[] {
  const out: string[] = [];
  let cur = "";
  let quoted = false;
  let depth = 0; // [] and () groups in COMBATANT_INFO stay in one field
  for (const ch of line) {
    if (ch === '"') quoted = !quoted;
    else if (!quoted && (ch === "[" || ch === "(")) {
      depth++;
      cur += ch;
    } else if (!quoted && (ch === "]" || ch === ")")) {
      depth--;
      cur += ch;
    } else if (ch === "," && !quoted && depth <= 0) {
      out.push(cur);
      cur = "";
    } else cur += ch;
  }
  out.push(cur);
  return out;
}

/** "11/25/2026 08:48:04.6201" (local time) -> epoch seconds. */
export function parseTime(stamp: string): number | null {
  const m = /^(\d+)\/(\d+)\/(\d+) (\d+):(\d+):(\d+)\.(\d{3})/.exec(stamp);
  if (!m) return null;
  return new Date(+m[3], +m[1] - 1, +m[2], +m[4], +m[5], +m[6], +m[7]).getTime() / 1000;
}

const DAMAGE_AT: Record<string, number> = {
  SWING_DAMAGE: 28, SPELL_DAMAGE: 31, SPELL_PERIODIC_DAMAGE: 31, RANGE_DAMAGE: 31, DAMAGE_SHIELD: 31, DAMAGE_SPLIT: 31,
};
const HEAL_AT: Record<string, number> = { SPELL_HEAL: 31, SPELL_PERIODIC_HEAL: 31 };
const KNOWN = new Set([
  ...Object.keys(DAMAGE_AT), ...Object.keys(HEAL_AT), "COMBAT_LOG_VERSION", "ZONE_CHANGE", "MAP_CHANGE", "ENCOUNTER_START",
  "ENCOUNTER_END", "CHALLENGE_MODE_START", "CHALLENGE_MODE_END", "UNIT_DIED", "UNIT_DESTROYED", "SPELL_INTERRUPT",
  "SPELL_DISPEL", "SWING_MISSED", "SPELL_MISSED", "RANGE_MISSED", "SPELL_CAST_SUCCESS", "SPELL_CAST_START", "SPELL_CAST_FAILED",
  "SPELL_AURA_APPLIED", "SPELL_AURA_REMOVED", "SPELL_AURA_REFRESH", "SPELL_AURA_APPLIED_DOSE", "SPELL_AURA_REMOVED_DOSE",
  "SPELL_AURA_BROKEN", "SPELL_AURA_BROKEN_SPELL", "SPELL_ENERGIZE", "SPELL_PERIODIC_ENERGIZE", "SPELL_DRAIN", "SPELL_PERIODIC_DRAIN",
  "SPELL_LEECH", "SPELL_SUMMON", "SPELL_CREATE", "SPELL_ABSORBED", "SPELL_RESURRECT", "SPELL_INSTAKILL", "SPELL_EXTRA_ATTACKS",
  "ENVIRONMENTAL_DAMAGE", "SWING_DAMAGE_LANDED", "ENCHANT_APPLIED", "ENCHANT_REMOVED", "DAMAGE_SHIELD_MISSED", "PARTY_KILL",
  "SPELL_PERIODIC_MISSED", "COMBATANT_INFO", "SPELL_DURABILITY_DAMAGE", "SPELL_DISPEL_FAILED", "SPELL_STOLEN",
]);

const isPlayer = (guid: string | undefined) => !!guid && guid.startsWith("Player-");
// COMBATLOG_OBJECT_AFFILIATION_* bits of a unit flag: mine 0x1, party 0x2, raid 0x4, outsider 0x8.
export function affiliation(flags: string | undefined): string {
  const a = (Number.parseInt(flags ?? "", 16) || 0) & 0xf;
  return a & 1 ? "self" : a & 2 ? "party" : a & 4 ? "raid" : "other";
}
const isPet = (guid: string | undefined) => !!guid && guid.startsWith("Pet-");
// Forever writes player names as "Name-Realm-Ruleset-Region" (e.g. "Defty-Graveshade-Normal-EU");
// keep "Name-Realm" so they match the character keys.
const unq = (s: string | undefined) => (s && s !== "nil" ? s.replace(/-[A-Za-z]+-(EU|US|KR|TW|CN)$/, "") : null);

interface UnitAgg {
  guid: string; name: string; kind: string;
  damage_done: number; healing_done: number; overhealing: number; damage_taken: number;
  deaths: number; interrupts: number; dispels: number; abilities: Record<string, number>;
}
interface Recap { t: number; src: string | null; spell: string; amount: number; kind: "damage" | "heal" }
interface Segment {
  kind: "world" | "encounter"; name: string | null; encounterId: number | null; difficulty: number | null;
  groupSize: number | null; success: number | null; start: number; last: number; byteStart: number; byteEnd: number;
  zone: string | null; units: Map<string, UnitAgg>; targets: Map<string, number>;
  deaths: { t: number; guid: string; name: string; killer: string | null; recap: Recap[]; affiliation: string }[];
  interrupts: { t: number; source: string; spell: string; target: string; interrupted: string }[];
}

export interface LogIngestResult { files: number; lines: number; segments: number; deaths: number; unknown: Record<string, number>; errors: string[] }

const CHUNK = 4 * 1024 * 1024;

export function ingestCombatLogs(db: DatabaseSync, cfg: Config, opts: { final?: boolean } = {}): LogIngestResult {
  const res: LogIngestResult = { files: 0, lines: 0, segments: 0, deaths: 0, unknown: {}, errors: [] };
  for (const file of combatLogFiles(cfg.wowDir)) {
    try {
      ingestFile(db, cfg, file, res, opts.final ?? false);
    } catch (e) {
      res.errors.push(`${file}: ${(e as Error).message}`);
    }
  }
  return res;
}

function ingestFile(db: DatabaseSync, cfg: Config, file: string, res: LogIngestResult, final: boolean): void {
  const st = statSync(file);
  const state = db.prepare("SELECT offset, size FROM ingest_state WHERE path = ?").get(file) as { offset: number | null; size: number } | undefined;
  let offset = state?.offset ?? 0;
  if (offset > st.size) offset = 0; // the file was replaced
  if (state && offset === st.size) return;
  // A log the game has not touched for a minute cannot hold a fight still in progress.
  const idle = final || Date.now() - st.mtimeMs > 60_000;
  res.files++;

  const gap = cfg.logGapSeconds;
  const recaps = new Map<string, Recap[]>(); // last incoming events per player, for death recaps
  const done: Segment[] = [];
  let seg: Segment | null = null;
  let zone: string | null = null;
  let meta: { version?: number; advanced?: number; build?: string; first?: number; last?: number } = {};
  const unknown: Record<string, number> = {};

  const unit = (guid: string, name: string | undefined): UnitAgg | null => {
    if (!seg || !(isPlayer(guid) || isPet(guid))) return null;
    let u = seg.units.get(guid);
    if (!u) {
      u = { guid, name: unq(name) ?? guid, kind: isPlayer(guid) ? "player" : "pet", damage_done: 0, healing_done: 0, overhealing: 0, damage_taken: 0, deaths: 0, interrupts: 0, dispels: 0, abilities: {} };
      seg.units.set(guid, u);
    }
    return u;
  };
  const close = (): void => {
    if (!seg) return;
    const s = seg;
    seg = null;
    let dmg = 0;
    for (const u of s.units.values()) dmg += u.damage_done + u.damage_taken;
    if (s.kind === "world" && (s.last - s.start < 2 || dmg <= 0)) return;
    done.push(s);
  };
  const touch = (t: number, byte: number): Segment => {
    if (seg && seg.kind === "world" && t - seg.last > gap) close();
    if (!seg) {
      seg = { kind: "world", name: null, encounterId: null, difficulty: null, groupSize: null, success: null, start: t, last: t, byteStart: byte, byteEnd: byte, zone, units: new Map(), targets: new Map(), deaths: [], interrupts: [] };
    }
    seg.last = Math.max(seg.last, t);
    return seg;
  };

  const fd = openSync(file, "r");
  let pos = offset;
  let carry = Buffer.alloc(0);
  let lineStart = offset;
  try {
    for (;;) {
      const buf = Buffer.alloc(CHUNK);
      const n = readSync(fd, buf, 0, CHUNK, pos);
      if (n <= 0) break;
      pos += n;
      let data = Buffer.concat([carry, buf.subarray(0, n)]);
      let from = 0;
      for (;;) {
        const nl = data.indexOf(10, from);
        if (nl < 0) break;
        const line = data.subarray(from, nl).toString("utf8").replace(/\r$/, "");
        const byte = lineStart;
        lineStart += nl - from + 1;
        from = nl + 1;
        res.lines++;
        const sep = line.indexOf("  ");
        if (sep < 0) continue;
        const t = parseTime(line.slice(0, sep));
        if (t == null) continue;
        meta.first ??= t;
        meta.last = t;
        if (seg && seg.kind === "world" && t - seg.last > gap) close();
        const f = splitCsv(line.slice(sep + 2));
        const ev = f[0];
        if (!KNOWN.has(ev)) unknown[ev] = (unknown[ev] ?? 0) + 1;

        if (ev === "COMBAT_LOG_VERSION") {
          meta = { ...meta, version: Number(f[1]), advanced: Number(f[3]), build: f[5] };
          continue;
        }
        if (ev === "ZONE_CHANGE") {
          zone = unq(f[2]);
          continue;
        }
        if (ev === "ENCOUNTER_START") {
          close();
          seg = { kind: "encounter", name: unq(f[2]), encounterId: Number(f[1]), difficulty: Number(f[3]), groupSize: Number(f[4]), success: null, start: t, last: t, byteStart: byte, byteEnd: byte, zone, units: new Map(), targets: new Map(), deaths: [], interrupts: [] };
          continue;
        }
        if (ev === "ENCOUNTER_END") {
          if (seg && seg.kind === "encounter") {
            seg.success = Number(f[5]);
            seg.last = t;
            seg.byteEnd = lineStart;
            seg.kind = "encounter";
            const s = seg as Segment;
            seg = null;
            done.push(s);
          }
          continue;
        }

        const dmgAt = DAMAGE_AT[ev];
        const healAt = HEAL_AT[ev];
        if (dmgAt !== undefined || ev === "ENVIRONMENTAL_DAMAGE") {
          const amount = Number(ev === "ENVIRONMENTAL_DAMAGE" ? f[29] : f[dmgAt!]) || 0;
          const srcP = isPlayer(f[1]) || isPet(f[1]);
          const dstP = isPlayer(f[5]) || isPet(f[5]);
          if (!srcP && !dstP) continue;
          const s = touch(t, byte);
          s.byteEnd = lineStart;
          const spell = ev === "SWING_DAMAGE" ? "Melee" : ev === "ENVIRONMENTAL_DAMAGE" ? `Environment (${f[28]})` : (unq(f[10]) ?? "?");
          const src = srcP ? unit(f[1], f[2]) : null;
          if (src) {
            src.damage_done += amount;
            src.abilities[spell] = (src.abilities[spell] ?? 0) + amount;
            if (!dstP) s.targets.set(unq(f[6]) ?? "?", (s.targets.get(unq(f[6]) ?? "?") ?? 0) + amount);
          }
          if (isPlayer(f[5])) {
            const dst = unit(f[5], f[6]);
            if (dst) dst.damage_taken += amount;
            const list = recaps.get(f[5]) ?? [];
            list.push({ t, src: unq(f[2]), spell, amount, kind: "damage" });
            if (list.length > 10) list.shift();
            recaps.set(f[5], list);
          }
        } else if (healAt !== undefined) {
          if (!isPlayer(f[1]) && !isPlayer(f[5])) continue;
          if (!seg) continue; // healing alone does not start a fight
          const amount = Number(f[healAt]) || 0;
          const over = Number(f[healAt + 1]) || 0;
          const src = unit(f[1], f[2]);
          if (src) {
            src.healing_done += Math.max(0, amount - over);
            src.overhealing += over;
          }
          if (isPlayer(f[5])) {
            const list = recaps.get(f[5]) ?? [];
            list.push({ t, src: unq(f[2]), spell: unq(f[10]) ?? "?", amount: amount - over, kind: "heal" });
            if (list.length > 10) list.shift();
            recaps.set(f[5], list);
          }
        } else if (ev === "UNIT_DIED" && isPlayer(f[5])) {
          const s = touch(t, byte);
          const u = unit(f[5], f[6]);
          if (u) u.deaths++;
          const recap = (recaps.get(f[5]) ?? []).filter((x) => t - x.t <= 15).map((x) => ({ ...x, t: Math.round((x.t - t) * 10) / 10 }));
          const killer = [...recap].reverse().find((x) => x.kind === "damage");
          s.deaths.push({ t, guid: f[5], name: unq(f[6]) ?? f[5], killer: killer ? (killer.src ? `${killer.src}: ${killer.spell}` : killer.spell) : null, recap, affiliation: affiliation(f[7]) });
          recaps.delete(f[5]);
        } else if (ev === "SPELL_INTERRUPT" && seg) {
          const u = unit(f[1], f[2]);
          if (u) {
            u.interrupts++;
            seg.interrupts.push({ t, source: u.name, spell: unq(f[10]) ?? "?", target: unq(f[6]) ?? "?", interrupted: unq(f[13]) ?? "?" });
          }
        } else if (ev === "SPELL_DISPEL" && seg) {
          const u = unit(f[1], f[2]);
          if (u) u.dispels++;
        }
      }
      carry = Buffer.from(data.subarray(from));
    }
  } finally {
    closeSync(fd);
  }

  // Where the next pass starts: after the last complete line, or at the start of an open fight.
  let nextOffset = lineStart;
  if (seg) {
    const open = seg as Segment;
    if (idle) {
      open.byteEnd = lineStart;
      if (open.kind === "encounter") done.push(open);
      else close();
    } else nextOffset = open.byteStart;
  }

  tx(db, () => {
    const insSeg = db.prepare(
      `INSERT OR IGNORE INTO segments (log_path, kind, name, encounter_id, difficulty, group_size, success, start_ts, end_ts, duration, byte_start, byte_end, zone, top_targets)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    );
    const insUnit = db.prepare(
      `INSERT OR REPLACE INTO segment_units (segment_id, guid, name, kind, damage_done, healing_done, overhealing, damage_taken, deaths, interrupts, dispels, abilities)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    );
    const insDeath = db.prepare("INSERT INTO deaths (segment_id, ts, guid, name, killer, recap, affiliation) VALUES (?, ?, ?, ?, ?, ?, ?)");
    const insInt = db.prepare("INSERT INTO interrupts (segment_id, ts, source, spell, target, interrupted) VALUES (?, ?, ?, ?, ?, ?)");
    for (const s of done) {
      const targets = [...s.targets.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5).map(([name, damage]) => ({ name, damage }));
      const r = insSeg.run(file, s.kind, s.name ?? targets[0]?.name ?? null, s.encounterId, s.difficulty, s.groupSize, s.success,
        s.start, s.last, Math.round((s.last - s.start) * 10) / 10, s.byteStart, s.byteEnd, s.zone, JSON.stringify(targets));
      if (!r.changes) continue; // already stored by an earlier pass
      const id = Number(r.lastInsertRowid);
      for (const u of s.units.values()) {
        insUnit.run(id, u.guid, u.name, u.kind, u.damage_done, u.healing_done, u.overhealing, u.damage_taken, u.deaths, u.interrupts, u.dispels, JSON.stringify(u.abilities));
      }
      for (const d of s.deaths) insDeath.run(id, d.t, d.guid, d.name, d.killer, JSON.stringify(d.recap), d.affiliation);
      for (const i of s.interrupts) insInt.run(id, i.t, i.source, i.spell, i.target, i.interrupted);
      res.segments++;
      res.deaths += s.deaths.length;
    }
    const prev = db.prepare("SELECT unknown_events FROM combat_logs WHERE path = ?").get(file) as { unknown_events: string | null } | undefined;
    const mergedUnknown: Record<string, number> = prev?.unknown_events ? JSON.parse(prev.unknown_events) : {};
    for (const [k, v] of Object.entries(unknown)) {
      mergedUnknown[k] = (mergedUnknown[k] ?? 0) + v;
      res.unknown[k] = (res.unknown[k] ?? 0) + v;
    }
    db.prepare(
      `INSERT INTO combat_logs (path, log_version, advanced, build, first_ts, last_ts, unknown_events) VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(path) DO UPDATE SET log_version = COALESCE(excluded.log_version, log_version), advanced = COALESCE(excluded.advanced, advanced),
         build = COALESCE(excluded.build, build), first_ts = COALESCE(first_ts, excluded.first_ts), last_ts = COALESCE(excluded.last_ts, last_ts),
         unknown_events = excluded.unknown_events`,
    ).run(file, meta.version ?? null, meta.advanced ?? null, meta.build ?? null, meta.first ?? null, meta.last ?? null, JSON.stringify(mergedUnknown));
    db.prepare("INSERT INTO ingest_state (path, mtime, size, offset) VALUES (?, ?, ?, ?) ON CONFLICT(path) DO UPDATE SET mtime = excluded.mtime, size = excluded.size, offset = excluded.offset")
      .run(file, st.mtimeMs, st.size, nextOffset);
  });
}
