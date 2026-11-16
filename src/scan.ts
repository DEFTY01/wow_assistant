import type { Env } from "./env";
import type { ItemStats } from "./gear";
import type { GearItem } from "./market";

type Obj = Record<string, any>;

const QUALITY = ["POOR", "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"];

/** The game's item stat table (GetItemStats) turned into what the damage model uses. */
function normalize(st: Obj | undefined, dmg: number[] | undefined): ItemStats {
  const v = (...keys: string[]) => keys.reduce((a, k) => a + (Number(st?.[k]) || 0), 0);
  return {
    agi: v("ITEM_MOD_AGILITY_SHORT"),
    str: v("ITEM_MOD_STRENGTH_SHORT"),
    ap: v("ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_MELEE_ATTACK_POWER_SHORT"),
    // In this era's data the "ratings" are plain percentages.
    crit: v("ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_MELEE_RATING_SHORT"),
    hit: v("ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT"),
    weapon: Array.isArray(dmg) && dmg.length === 3 && dmg[2] > 0 ? { min: dmg[0], max: dmg[1], speed: dmg[2] } : null,
  };
}

export interface ScanUpload {
  at?: number;
  items?: Obj[];
  note?: string;
}

/** Replace the stored scan with a newer one. Returns how many listings were stored. */
export async function storeScan(env: Env, scan: ScanUpload | undefined): Promise<number> {
  const items = Array.isArray(scan?.items) ? scan!.items! : [];
  if (!scan?.at || !items.length) return 0;
  const at = new Date(scan.at * 1000).toISOString();
  const latest = await env.DB.prepare("SELECT MAX(scanned_at) AS at FROM ah_scan").first<{ at: string | null }>();
  if (latest?.at && latest.at >= at) return 0; // already have this scan or a newer one

  const stmts: D1PreparedStatement[] = [env.DB.prepare("DELETE FROM ah_scan")];
  const seen = new Set<string>();
  for (const it of items) {
    const id = Number(it.id);
    const slot = String(it.slot ?? "").replace(/^INVTYPE_/, "");
    const price = Number(it.price);
    if (!id || !slot || !(price > 0)) continue;
    const key = `${id}:${Number(it.suffix) || 0}:${Number(it.ilvl) || 0}`;
    if (seen.has(key)) continue;
    seen.add(key);
    stmts.push(
      env.DB.prepare(
        "INSERT INTO ah_scan (key, item_id, name, quality, req_level, slot, item_class, subclass, price, listings, stats, scanned_at, slug) " +
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      ).bind(
        key,
        id,
        String(it.name ?? `Item #${id}`),
        it.q ?? null,
        it.req ?? null,
        slot,
        Number(it.cls) || 0,
        Number(it.sub) || 0,
        Math.round(price),
        Number(it.count) || 0,
        JSON.stringify(normalize(it.st, it.dmg)),
        at,
        env.CHARACTER_SLUG,
      ),
    );
  }
  for (let i = 0; i < stmts.length; i += 80) await env.DB.batch(stmts.slice(i, i + 80));
  return stmts.length - 1;
}

/** Scanned listings as gear, when the scan is recent enough to act on. */
export async function loadScannedGear(
  env: Env,
  maxAgeHours = 12,
): Promise<{ at: string | null; fresh: boolean; items: { item: GearItem; price: number; listings: number }[] }> {
  const head = await env.DB.prepare("SELECT MAX(scanned_at) AS at FROM ah_scan").first<{ at: string | null }>();
  const at = head?.at ?? null;
  const fresh = !!at && Date.now() - new Date(at).getTime() < maxAgeHours * 3600_000;
  if (!fresh) return { at, fresh, items: [] };
  const rows = await env.DB.prepare(
    "SELECT s.*, i.req_level AS api_req FROM ah_scan s LEFT JOIN items i ON i.item_id = s.item_id",
  ).all<Obj>();
  const items: { item: GearItem; price: number; listings: number }[] = [];
  for (const r of rows.results) {
    const stats = JSON.parse(r.stats) as ItemStats;
    if (r.item_class === 2 && !stats.weapon) continue;
    items.push({
      item: {
        itemId: r.item_id,
        name: r.name,
        slot: r.slot,
        itemClass: r.item_class,
        subclass: r.subclass,
        reqLevel: Number(r.req_level ?? r.api_req ?? 0),
        itemLevel: 0,
        quality: QUALITY[Number(r.quality)] ?? "COMMON",
        binding: null,
        stats,
      },
      price: r.price,
      listings: r.listings,
    });
  }
  return { at, fresh, items };
}

// ---------------------------------------------------------------- experience

export async function storeXp(env: Env, samples: unknown): Promise<number> {
  const list = (Array.isArray(samples) ? samples : []) as unknown[][];
  // The addon re-sends its whole sample list: store only what is newer than the last stored one.
  const last = await env.DB.prepare("SELECT MAX(t) AS t FROM xp_samples WHERE slug = ?").bind(env.CHARACTER_SLUG).first<{ t: number | null }>();
  const stmts = list
    .filter((s) => Array.isArray(s) && Number(s[0]) > (last?.t ?? 0))
    .map((s) =>
      env.DB.prepare("INSERT OR REPLACE INTO xp_samples (slug, t, xp, level, xp_max, zone) VALUES (?, ?, ?, ?, ?, ?)").bind(
        env.CHARACTER_SLUG,
        Number(s[0]),
        Number(s[1]) || 0,
        Number(s[2]) || 0,
        Number(s[3]) || 0,
        String(s[4] ?? ""),
      ),
    );
  for (let i = 0; i < stmts.length; i += 80) await env.DB.batch(stmts.slice(i, i + 80));
  return stmts.length;
}

export interface XpReport {
  level: number;
  toLevel: number; // XP still needed
  recentPerHour: number; // XP per hour over the last active hours
  hoursToLevel: number | null;
  zones: { zone: string; hours: number; perHour: number; killsPerHour: number; fightShare: number; avgFight: number; mobLevel: number | null }[];
  sessions: { start: number; hours: number; xp: number; perHour: number; zone: string }[];
  notes: string[];
}

const SESSION_GAP = 600; // seconds without XP ends a session

export async function xpReport(env: Env): Promise<XpReport | null> {
  const rows = await env.DB.prepare("SELECT t, xp, level, xp_max, zone FROM xp_samples WHERE slug = ? ORDER BY t DESC LIMIT 3000")
    .bind(env.CHARACTER_SLUG)
    .all<{ t: number; xp: number; level: number; xp_max: number; zone: string }>();
  const samples = rows.results.reverse();
  if (samples.length < 3) return null;
  const fights = await env.DB.prepare("SELECT start, duration, json FROM fights WHERE slug = ? AND start >= ? ORDER BY start")
    .bind(env.CHARACTER_SLUG, samples[0].t - 60)
    .all<{ start: number; duration: number; json: string }>();

  // Stretches of play: consecutive samples no more than SESSION_GAP apart, in one zone.
  interface Stretch { start: number; end: number; xp: number; zone: string }
  const stretches: Stretch[] = [];
  let cur: Stretch | null = null;
  for (let i = 1; i < samples.length; i++) {
    const a = samples[i - 1];
    const b = samples[i];
    const dt = b.t - a.t;
    const gained = b.level > a.level ? Math.max(0, a.xp_max - a.xp) + b.xp : Math.max(0, b.xp - a.xp);
    if (dt > SESSION_GAP || dt <= 0) {
      cur = null;
      continue;
    }
    if (!cur || cur.zone !== b.zone) {
      cur = { start: a.t, end: b.t, xp: 0, zone: b.zone };
      stretches.push(cur);
    }
    cur.end = b.t;
    cur.xp += gained;
  }
  if (!stretches.length) return null;

  const byZone = new Map<string, { secs: number; xp: number; kills: number; fightSecs: number; lvlSum: number; lvlN: number }>();
  for (const s of stretches) {
    const z = byZone.get(s.zone) ?? { secs: 0, xp: 0, kills: 0, fightSecs: 0, lvlSum: 0, lvlN: 0 };
    z.secs += s.end - s.start;
    z.xp += s.xp;
    for (const f of fights.results) {
      if (f.start < s.start - 30 || f.start > s.end) continue;
      z.kills++;
      z.fightSecs += f.duration;
      const lvl = (JSON.parse(f.json) as Obj).targetLevel;
      if (lvl > 0) {
        z.lvlSum += lvl;
        z.lvlN++;
      }
    }
    byZone.set(s.zone, z);
  }
  const zones = [...byZone.entries()]
    .filter(([, z]) => z.secs >= 600)
    .map(([zone, z]) => ({
      zone: zone || "?",
      hours: z.secs / 3600,
      perHour: z.xp / (z.secs / 3600),
      killsPerHour: z.kills / (z.secs / 3600),
      fightShare: z.secs ? (z.fightSecs / z.secs) * 100 : 0,
      avgFight: z.kills ? z.fightSecs / z.kills : 0,
      mobLevel: z.lvlN ? z.lvlSum / z.lvlN : null,
    }))
    .sort((a, b) => b.perHour - a.perHour);

  // Merge stretches into sessions for the recent list.
  const sessions: XpReport["sessions"] = [];
  for (const s of stretches) {
    const last = sessions[sessions.length - 1];
    if (last && s.start - (last.start + last.hours * 3600) < SESSION_GAP) {
      last.hours = (s.end - last.start) / 3600;
      last.xp += s.xp;
    } else {
      sessions.push({ start: s.start, hours: (s.end - s.start) / 3600, xp: s.xp, perHour: 0, zone: s.zone });
    }
  }
  for (const s of sessions) s.perHour = s.hours > 0 ? s.xp / s.hours : 0;

  // Recent pace: the last three hours of actual play.
  let secs = 0;
  let xp = 0;
  for (const s of [...stretches].reverse()) {
    if (secs >= 3 * 3600) break;
    secs += s.end - s.start;
    xp += s.xp;
  }
  const last = samples[samples.length - 1];
  const recentPerHour = secs > 0 ? xp / (secs / 3600) : 0;
  const toLevel = Math.max(0, last.xp_max - last.xp);
  const notes: string[] = [];
  if (zones.length >= 2) {
    const best = zones[0];
    const worst = zones[zones.length - 1];
    notes.push(
      `A leggyorsabb helyed: ${best.zone} (${Math.round(best.perHour).toLocaleString("hu-HU")} XP/óra), a leglassabb: ${worst.zone} ` +
        `(${Math.round(worst.perHour).toLocaleString("hu-HU")} XP/óra).`,
    );
  }
  const idle = zones.find((z) => z.hours >= 0.5 && z.fightShare < 35 && z.killsPerHour > 0);
  if (idle) {
    notes.push(
      `${idle.zone}: az idődnek csak ${idle.fightShare.toFixed(0)}%-a telik harccal. A többi futás, evés vagy várakozás; ` +
        "sűrűbb mobcsoport vagy kötszer használata többet hozna, mint bármilyen felszerelés.",
    );
  }
  return {
    level: last.level,
    toLevel,
    recentPerHour,
    hoursToLevel: recentPerHour > 0 ? toLevel / recentPerHour : null,
    zones,
    sessions: sessions.filter((s) => s.hours >= 0.1).slice(-8).reverse(),
    notes,
  };
}
