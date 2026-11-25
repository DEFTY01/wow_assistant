// Loads addon SavedVariables (WowAssistant, SessionBar, AzerothChronicle) into SQLite.
// Every insert is idempotent, so a file can be read again at any time.
import { existsSync, statSync } from "node:fs";
import { join } from "node:path";
import type { DatabaseSync } from "node:sqlite";
import type { Config } from "../config.ts";
import { tx } from "../db.ts";
import { readSavedVariables, type LuaValue } from "../lua.ts";
import { accountSavedVariables, characterDirs, type CharacterDir } from "../paths.ts";

type Obj = Record<string, LuaValue>;
const obj = (v: LuaValue | undefined): Obj => (v && typeof v === "object" && !Array.isArray(v) ? (v as Obj) : {});
const arr = (v: LuaValue | undefined): LuaValue[] =>
  Array.isArray(v) ? v : v && typeof v === "object" ? Object.values(v as Obj) : [];
const num = (v: LuaValue | undefined): number | null => (typeof v === "number" && Number.isFinite(v) ? v : null);
const text = (v: LuaValue | undefined): string | null => (typeof v === "string" ? v : null);
const sum = (o: Obj): number => Object.values(o).reduce<number>((s, v) => s + (num(v) ?? 0), 0);

export interface SvIngestResult {
  files: number;
  skipped: number;
  characters: number;
  snapshots: number;
  sessions: number;
  xpSamples: number;
  guildRows: number;
  errors: string[];
}

function changed(db: DatabaseSync, file: string, force: boolean): boolean {
  const st = statSync(file);
  const row = db.prepare("SELECT mtime, size FROM ingest_state WHERE path = ?").get(file) as { mtime: number; size: number } | undefined;
  if (!force && row && row.mtime === st.mtimeMs && row.size === st.size) return false;
  return true;
}

function markRead(db: DatabaseSync, file: string): void {
  const st = statSync(file);
  db.prepare("INSERT INTO ingest_state (path, mtime, size, offset) VALUES (?, ?, ?, NULL) ON CONFLICT(path) DO UPDATE SET mtime = excluded.mtime, size = excluded.size")
    .run(file, st.mtimeMs, st.size);
}

function upsertCharacter(db: DatabaseSync, c: { key: string; account?: string | null; name: string; realm?: string | null; class?: string | null; race?: string | null; faction?: string | null; guild?: string | null }): void {
  db.prepare(
    `INSERT INTO characters (key, account, name, realm, class, race, faction, guild, updated)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(key) DO UPDATE SET
       account = COALESCE(excluded.account, account), realm = COALESCE(excluded.realm, realm),
       class = COALESCE(excluded.class, class), race = COALESCE(excluded.race, race),
       faction = COALESCE(excluded.faction, faction), guild = COALESCE(excluded.guild, guild),
       updated = excluded.updated`,
  ).run(c.key, c.account ?? null, c.name, c.realm ?? null, c.class ?? null, c.race ?? null, c.faction ?? null, c.guild ?? null, Math.floor(Date.now() / 1000));
}

/** WowAssistantDB.chars is keyed by first name only; resolve to Name-Realm when that is unambiguous. */
function resolveKey(chars: CharacterDir[], account: string, name: string): { key: string; realm: string | null } {
  const matches = chars.filter((c) => c.account === account && c.name === name);
  return matches.length === 1 ? { key: matches[0].key, realm: matches[0].realm } : { key: name, realm: null };
}

function ingestWowAssistant(db: DatabaseSync, account: string, data: Obj, chars: CharacterDir[], r: SvIngestResult): void {
  const insXp = db.prepare("INSERT OR IGNORE INTO xp_samples (char_key, ts, xp, level, xp_max, zone) VALUES (?, ?, ?, ?, ?, ?)");
  for (const [name, raw] of Object.entries(obj(data.chars))) {
    const c = obj(raw);
    const { key, realm } = resolveKey(chars, account, name);
    upsertCharacter(db, { key, account, name, realm, class: text(c.class) });
    r.characters++;
    // Samples of a shared name may already have been moved to their Name-Realm (see resolve.ts).
    const siblings = chars.filter((d) => d.account === account && d.name === name).map((d) => d.key);
    const moved = new Set<number>();
    if (realm == null && siblings.length) {
      const ph = siblings.map(() => "?").join(",");
      for (const row of db.prepare(`SELECT ts FROM xp_samples WHERE char_key IN (${ph})`).all(...siblings) as { ts: number }[]) moved.add(row.ts);
    }
    for (const s of arr(c.xp)) {
      if (!Array.isArray(s)) continue;
      const [ts, xp, level, xpMax, zone] = s;
      if (num(ts) == null || moved.has(num(ts)!)) continue;
      r.xpSamples += Number(insXp.run(key, num(ts), num(xp), num(level), num(xpMax), text(zone)).changes);
    }
  }
}

function ingestSessionBar(db: DatabaseSync, c: CharacterDir, data: Obj, r: SvIngestResult): void {
  const charDb = obj(data.SessionBarCharDB);
  const put = db.prepare(
    `INSERT INTO sessions (char_key, start, duration, start_level, levels, xp, income, expense, income_json, expense_json, is_current)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(char_key, start) DO UPDATE SET duration = excluded.duration, levels = excluded.levels, xp = excluded.xp,
       income = excluded.income, expense = excluded.expense, income_json = excluded.income_json,
       expense_json = excluded.expense_json, is_current = excluded.is_current`,
  );
  const add = (s: Obj, current: boolean) => {
    const start = num(s.start);
    if (start == null) return;
    const duration = num(s.duration) ?? (num(s.last) ?? start) - start;
    const income = obj(s.income);
    const expense = obj(s.expense);
    put.run(c.key, start, duration, num(s.startLevel), num(s.levels) ?? 0, num(s.xp) ?? 0, sum(income), sum(expense),
      JSON.stringify(income), JSON.stringify(expense), current ? 1 : 0);
    r.sessions++;
  };
  db.prepare("UPDATE sessions SET is_current = 0 WHERE char_key = ?").run(c.key);
  for (const h of arr(charDb.history)) add(obj(h), false);
  if (charDb.current) add(obj(charDb.current), true);
}

function ingestChronicle(db: DatabaseSync, account: string, data: Obj, r: SvIngestResult): void {
  const putSnap = db.prepare(
    `INSERT INTO snapshots (char_key, ts, level, xp, xp_max, money, cxp, deaths, quests, skills, zone)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(char_key, ts) DO UPDATE SET level = excluded.level, xp = excluded.xp, xp_max = excluded.xp_max,
       money = excluded.money, cxp = excluded.cxp, deaths = excluded.deaths, quests = excluded.quests,
       skills = excluded.skills, zone = excluded.zone`,
  );
  for (const [key, raw] of Object.entries(obj(data.chars))) {
    const c = obj(raw);
    const dash = key.lastIndexOf("-");
    upsertCharacter(db, {
      key, account, name: dash > 0 ? key.slice(0, dash) : key, realm: dash > 0 ? key.slice(dash + 1) : null,
      class: text(c.class), race: text(c.race), faction: text(c.faction), guild: text(c.guild),
    });
    r.characters++;
    for (const s of arr(c.snapshots)) {
      const o = obj(s);
      if (num(o.ts) == null) continue;
      putSnap.run(key, num(o.ts), num(o.level), num(o.xp), num(o.xpMax), num(o.money), num(o.cxp), num(o.deaths), num(o.quests), num(o.skills), text(o.zone));
      r.snapshots++;
    }
  }
  const putGuild = db.prepare(
    `INSERT INTO guild_standings (guild, week, member, ts, class, level, xp, money, levels, skills, quests, deaths)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(guild, week, member) DO UPDATE SET ts = excluded.ts, class = excluded.class, level = excluded.level,
       xp = excluded.xp, money = excluded.money, levels = excluded.levels, skills = excluded.skills,
       quests = excluded.quests, deaths = excluded.deaths
     WHERE excluded.ts >= COALESCE(guild_standings.ts, 0)`,
  );
  for (const [guild, weeks] of Object.entries(obj(data.guild))) {
    for (const [week, members] of Object.entries(obj(weeks))) {
      for (const [member, raw] of Object.entries(obj(members))) {
        const m = obj(raw);
        putGuild.run(guild, Number(week), member, num(m.ts), text(m.class), num(m.level), num(m.xp), num(m.money),
          num(m.levels), num(m.skills), num(m.quests), num(m.deaths));
        r.guildRows++;
      }
    }
  }
}

export function ingestSavedVariables(db: DatabaseSync, cfg: Config, force = false): SvIngestResult {
  const r: SvIngestResult = { files: 0, skipped: 0, characters: 0, snapshots: 0, sessions: 0, xpSamples: 0, guildRows: 0, errors: [] };
  const chars = characterDirs(cfg.wowDir);
  const run = (file: string, fn: (data: Obj) => void) => {
    if (!changed(db, file, force)) {
      r.skipped++;
      return;
    }
    try {
      const data = readSavedVariables(file) as Obj;
      tx(db, () => {
        fn(data);
        markRead(db, file);
      });
      r.files++;
    } catch (e) {
      r.errors.push(`${file}: ${(e as Error).message}`);
    }
  };

  for (const c of chars) upsertCharacter(db, { key: c.key, account: c.account, name: c.name, realm: c.realm });
  for (const { account, file } of accountSavedVariables(cfg.wowDir, "WowAssistant")) {
    run(file, (d) => ingestWowAssistant(db, account, obj(d.WowAssistantDB), chars, r));
  }
  for (const { account, file } of accountSavedVariables(cfg.wowDir, "AzerothChronicle")) {
    run(file, (d) => ingestChronicle(db, account, obj(d.AzerothChronicleDB), r));
  }
  for (const c of chars) {
    const file = join(c.svDir, "SessionBar.lua");
    if (existsSync(file)) run(file, (d) => ingestSessionBar(db, c, d, r));
  }
  return r;
}
