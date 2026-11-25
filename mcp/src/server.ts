import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { basename, join } from "node:path";
import type { DatabaseSync } from "node:sqlite";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import type { Config } from "./config.ts";
import { openReadOnly, schemaText } from "./db.ts";
import { ingestAll } from "./ingest/index.ts";
import { readSavedVariables, type LuaValue } from "./lua.ts";
import { accountSavedVariables, addonsDir, characterDirs } from "./paths.ts";
import { writeInbox } from "./writeback.ts";

const VERSION = "0.1.0";
const MAX_TEXT = 60_000;
const WEEK = 604800;
const WEEK_OFFSET = 6 * 86400 + 7 * 3600; // weeks start Wednesday 07:00 UTC (EU reset), same as the addon

export const weekKey = (ts: number) => Math.floor((ts - WEEK_OFFSET) / WEEK);
export const weekStart = (k: number) => k * WEEK + WEEK_OFFSET;
const iso = (ts: number | null | undefined) => (ts == null ? null : new Date(ts * 1000).toISOString());

function toTs(v: string | number | undefined, fallback: number): number {
  if (v === undefined || v === "") return fallback;
  if (typeof v === "number") return v;
  if (/^\d+$/.test(v)) return Number(v);
  const t = Date.parse(v);
  if (Number.isNaN(t)) throw new Error(`Not a date: ${v}`);
  return Math.floor(t / 1000);
}

const HINT = "Reply was too long: lower the limit or narrow the query.";
const ser = (v: unknown) => JSON.stringify(v, null, 1) ?? "null";

/** Largest non-empty array inside holder.v (by serialized length), with a setter to replace it. */
function largestArray(holder: { v: unknown }): { arr: unknown[]; set: (a: unknown[]) => void; path: string } | null {
  let best: { arr: unknown[]; set: (a: unknown[]) => void; path: string; size: number } | null = null;
  const walk = (node: unknown, set: (a: unknown[]) => void, path: string) => {
    if (Array.isArray(node)) {
      const size = ser(node).length;
      if (node.length && (!best || size > best.size)) best = { arr: node, set, path, size };
      node.forEach((x, i) => walk(x, (a) => (node[i] = a), `${path}[${i}]`));
    } else if (node && typeof node === "object") {
      const o = node as Record<string, unknown>;
      for (const k of Object.keys(o)) walk(o[k], (a) => (o[k] = a), path === "(result)" ? k : `${path}.${k}`);
    }
  };
  walk(holder.v, (a) => (holder.v = a), "(result)");
  return best;
}

/**
 * Serializes a tool result within `max` characters, always as valid JSON. Trailing items of the largest
 * arrays are dropped until it fits; an array result keeps its shape and the truncation note goes in a
 * second content block, an object result gets a `_truncated` field. Anything else becomes a preview
 * string inside a small envelope.
 */
export function fitJson(data: unknown, max = MAX_TEXT): { text: string; note?: string } {
  const full = ser(data);
  if (full.length <= max) return { text: full };
  const holder = { v: structuredClone(data) as unknown };
  const budget = Math.max(0, max - 600); // room for the _truncated field
  const cuts: { path: string; returned: number; total: number }[] = [];
  for (let guard = 0; guard < 50 && ser(holder.v).length > budget; guard++) {
    const big = largestArray(holder);
    if (!big) break;
    const all = big.arr;
    let lo = 0;
    let hi = all.length - 1;
    while (lo < hi) {
      const mid = Math.ceil((lo + hi) / 2);
      big.set(all.slice(0, mid));
      if (ser(holder.v).length <= budget) lo = mid;
      else hi = mid - 1;
    }
    big.set(all.slice(0, lo));
    const prev = cuts.find((c) => c.path === big.path);
    if (prev) prev.returned = lo;
    else cuts.push({ path: big.path, returned: lo, total: all.length });
  }
  const text = ser(holder.v);
  if (text.length > max) {
    return { text: ser({ truncated: true, characters: full.length, hint: HINT, preview: full.slice(0, Math.max(0, max - 500)) }) };
  }
  const info = { truncated: true, cuts, characters: full.length, hint: HINT };
  if (Array.isArray(holder.v) || !holder.v || typeof holder.v !== "object") return { text, note: ser(info) };
  const withInfo = ser({ ...(holder.v as Record<string, unknown>), _truncated: info });
  return withInfo.length <= max ? { text: withInfo } : { text, note: ser(info) };
}

function reply(data: unknown) {
  const { text, note } = fitJson(data);
  const content = [{ type: "text" as const, text }];
  if (note) content.push({ type: "text" as const, text: note });
  return { content };
}

function fail(msg: string) {
  return { content: [{ type: "text" as const, text: msg }], isError: true };
}

const METRICS = { level: "level", xp: "cxp", money: "money", skills: "skills", quests: "quests", deaths: "deaths" } as const;
type Metric = keyof typeof METRICS;

interface Point { ts: number; level: number | null; cxp: number | null; money: number | null; skills: number | null; quests: number | null; deaths: number | null }

export function createServer(db: DatabaseSync, cfg: Config): McpServer {
  const server = new McpServer({ name: "azeroth", version: VERSION });
  const ro = () => openReadOnly(cfg.dbPath);

  const ownNames = () => new Set((db.prepare("SELECT name FROM characters").all() as { name: string }[]).map((r) => r.name));
  const masker = () => {
    if (!cfg.maskOtherPlayers) return (n: string) => n;
    const own = ownNames();
    const map = new Map<string, string>();
    return (n: string) => {
      const bare = n.split("-")[0];
      if (own.has(bare)) return n;
      if (!map.has(n)) map.set(n, `Player ${map.size + 1}`);
      return map.get(n)!;
    };
  };

  const resolveChar = (c: string): string => {
    const rows = db.prepare("SELECT key FROM characters WHERE key = ? COLLATE NOCASE OR name = ? COLLATE NOCASE").all(c, c) as { key: string }[];
    if (!rows.length) throw new Error(`Unknown character "${c}". Use list_characters.`);
    const exact = rows.find((r) => r.key.toLowerCase() === c.toLowerCase());
    if (exact) return exact.key;
    if (rows.length > 1) throw new Error(`"${c}" matches several characters: ${rows.map((r) => r.key).join(", ")}. Use Name-Realm.`);
    return rows[0].key;
  };

  // Snapshots, or points derived from the WowAssistant XP samples when a character has none yet.
  const points = (key: string): Point[] => {
    const snaps = db.prepare("SELECT ts, level, cxp, money, skills, quests, deaths FROM snapshots WHERE char_key = ? ORDER BY ts").all(key) as unknown as Point[];
    if (snaps.length) return snaps;
    const samples = db.prepare("SELECT ts, xp, level, xp_max FROM xp_samples WHERE char_key = ? ORDER BY ts").all(key) as { ts: number; xp: number; level: number; xp_max: number }[];
    let cxp = 0;
    return samples.map((s, i) => {
      const p = samples[i - 1];
      if (p) cxp += s.level === p.level ? Math.max(0, s.xp - p.xp) : Math.max(0, p.xp_max - p.xp) + s.xp;
      return { ts: s.ts, level: s.level, cxp, money: null, skills: null, quests: null, deaths: null };
    });
  };
  const charKeys = (character?: string) =>
    character ? [resolveChar(character)] : (db.prepare("SELECT key FROM characters ORDER BY key").all() as { key: string }[]).map((r) => r.key);
  const valueAt = (pts: Point[], col: string, ts: number): number | null => {
    let v: number | null = null;
    for (const p of pts) {
      if (p.ts > ts) break;
      const x = (p as unknown as Record<string, number | null>)[col];
      if (x != null) v = x;
    }
    return v;
  };

  // ------------------------------------------------------------------ characters & progress

  server.registerTool("list_characters", {
    title: "List characters",
    description: "All known WoW characters (from the game folders and addon data) with class, guild, latest level and when data was last seen.",
    inputSchema: {},
    annotations: { readOnlyHint: true },
  }, async () => {
    const rows = db.prepare(`
      SELECT c.key, c.name, c.realm, c.account, c.class, c.race, c.faction, c.guild,
        COALESCE((SELECT level FROM snapshots s WHERE s.char_key = c.key ORDER BY ts DESC LIMIT 1),
                 (SELECT level FROM xp_samples x WHERE x.char_key = c.key ORDER BY ts DESC LIMIT 1)) AS level,
        MAX(COALESCE((SELECT MAX(ts) FROM snapshots s WHERE s.char_key = c.key), 0),
            COALESCE((SELECT MAX(ts) FROM xp_samples x WHERE x.char_key = c.key), 0),
            COALESCE((SELECT MAX(start) FROM sessions se WHERE se.char_key = c.key), 0)) AS last_seen
      FROM characters c ORDER BY last_seen DESC`).all() as Record<string, unknown>[];
    return reply(rows.map((r) => ({ ...r, last_seen: r.last_seen ? iso(r.last_seen as number) : null })));
  });

  server.registerTool("get_character", {
    title: "Character details",
    description: "Latest snapshot, latest XP sample, current SessionBar session and totals for one character. `character` is Name-Realm (or a unique first name).",
    inputSchema: { character: z.string() },
    annotations: { readOnlyHint: true },
  }, async ({ character }) => {
    const key = resolveChar(character);
    const info = db.prepare("SELECT * FROM characters WHERE key = ?").get(key);
    const snapshot = db.prepare("SELECT * FROM snapshots WHERE char_key = ? ORDER BY ts DESC LIMIT 1").get(key);
    const xp = db.prepare("SELECT * FROM xp_samples WHERE char_key = ? ORDER BY ts DESC LIMIT 1").get(key);
    const session = db.prepare("SELECT * FROM sessions WHERE char_key = ? ORDER BY start DESC LIMIT 1").get(key);
    const totals = db.prepare("SELECT COUNT(*) AS sessions, SUM(duration) AS seconds, SUM(xp) AS xp, SUM(income) AS income, SUM(expense) AS expense FROM sessions WHERE char_key = ?").get(key);
    return reply({ info, snapshot, latestXpSample: xp, latestSession: session, sessionTotals: totals });
  });

  server.registerTool("get_progress_timeline", {
    title: "Progress timeline",
    description:
      "Time series of one metric per day or week, for one character or the whole account (sum of all characters). " +
      "Metrics: level, xp (cumulative XP gained, comparable across levels), money (copper), skills (sum of profession ranks), quests (turned in), deaths. " +
      "Dates accept ISO strings or unix seconds; default is the last 30 days. Also returns the total gain over the period.",
    inputSchema: {
      metric: z.enum(["level", "xp", "money", "skills", "quests", "deaths"]),
      character: z.string().optional(),
      from: z.union([z.string(), z.number()]).optional(),
      to: z.union([z.string(), z.number()]).optional(),
      bucket: z.enum(["day", "week"]).default("day"),
    },
    annotations: { readOnlyHint: true },
  }, async ({ metric, character, from, to, bucket }) => {
    const end = toTs(to, Math.floor(Date.now() / 1000));
    const start = toTs(from, end - 30 * 86400);
    const col = METRICS[metric as Metric];
    const step = bucket === "week" ? WEEK : 86400;
    const keys = charKeys(character);
    const perChar = keys.map((k) => ({ key: k, pts: points(k) })).filter((c) => c.pts.length);
    const series: { bucket_end: string; value: number | null }[] = [];
    for (let t = start + step; t < end + step; t += step) {
      const at = Math.min(t, end);
      let total: number | null = null;
      for (const c of perChar) {
        const v = valueAt(c.pts, col, at);
        if (v != null) total = (total ?? 0) + v;
      }
      series.push({ bucket_end: iso(at)!, value: total });
    }
    const gains = perChar.map((c) => {
      const a = valueAt(c.pts, col, start) ?? c.pts.find((p) => p.ts >= start && (p as unknown as Record<string, number | null>)[col] != null)?.[col as keyof Point] ?? null;
      const b = valueAt(c.pts, col, end);
      return { character: c.key, start: a, end: b, gain: a != null && b != null ? b - a : null };
    }).filter((g) => g.end != null);
    return reply({ metric, from: iso(start), to: iso(end), bucket, series, gains, totalGain: gains.reduce((s, g) => s + (g.gain ?? 0), 0),
      note: perChar.length ? undefined : "No data yet. Install AzerothChronicle (snapshots) or WowAssistant (XP samples) and /reload in game." });
  });

  server.registerTool("compare_periods", {
    title: "Compare two periods",
    description: "Gain of one metric in period A versus period B (e.g. this week vs last week), for one character or the whole account.",
    inputSchema: {
      metric: z.enum(["level", "xp", "money", "skills", "quests", "deaths"]),
      a_from: z.union([z.string(), z.number()]), a_to: z.union([z.string(), z.number()]),
      b_from: z.union([z.string(), z.number()]), b_to: z.union([z.string(), z.number()]),
      character: z.string().optional(),
    },
    annotations: { readOnlyHint: true },
  }, async ({ metric, a_from, a_to, b_from, b_to, character }) => {
    const col = METRICS[metric as Metric];
    const keys = charKeys(character);
    const gain = (f: number, t: number) => keys.reduce((s, k) => {
      const pts = points(k);
      const first = pts.find((p) => p.ts >= f && (p as unknown as Record<string, number | null>)[col] != null);
      const a = valueAt(pts, col, f) ?? (first ? (first as unknown as Record<string, number>)[col] : null);
      const b = valueAt(pts, col, t);
      return s + (a != null && b != null ? b - a : 0);
    }, 0);
    const A = gain(toTs(a_from, 0), toTs(a_to, 0));
    const B = gain(toTs(b_from, 0), toTs(b_to, 0));
    return reply({ metric, periodA: { from: iso(toTs(a_from, 0)), to: iso(toTs(a_to, 0)), gain: A }, periodB: { from: iso(toTs(b_from, 0)), to: iso(toTs(b_to, 0)), gain: B },
      difference: A - B, percent: B ? Math.round(((A - B) / Math.abs(B)) * 1000) / 10 : null });
  });

  server.registerTool("get_week_summary", {
    title: "Weekly gains per character",
    description: "Gains of every character in one competition week (weeks start Wednesday 07:00 UTC). weeks_ago: 0 = this week, 1 = last week.",
    inputSchema: { weeks_ago: z.number().int().min(0).max(52).default(0) },
    annotations: { readOnlyHint: true },
  }, async ({ weeks_ago }) => {
    const k = weekKey(Date.now() / 1000) - weeks_ago;
    const f = weekStart(k);
    const t = Math.min(f + WEEK, Math.floor(Date.now() / 1000));
    const rows = charKeys().map((key) => {
      const pts = points(key);
      const out: Record<string, unknown> = { character: key };
      let any = false;
      for (const [name, col] of Object.entries(METRICS)) {
        const first = pts.find((p) => p.ts >= f && (p as unknown as Record<string, number | null>)[col] != null);
        const a = valueAt(pts, col, f) ?? (first ? (first as unknown as Record<string, number>)[col] : null);
        const b = valueAt(pts, col, t);
        if (a != null && b != null && pts.some((p) => p.ts >= f && p.ts <= t)) {
          out[name] = b - a;
          any = true;
        }
      }
      return any ? out : null;
    }).filter(Boolean);
    return reply({ week: k, from: iso(f), to: iso(t), characters: rows });
  });

  server.registerTool("list_sessions", {
    title: "Play sessions",
    description: "SessionBar play sessions: duration, XP, levels, gold income and expense by category (copper). Newest first.",
    inputSchema: {
      character: z.string().optional(),
      from: z.union([z.string(), z.number()]).optional(),
      to: z.union([z.string(), z.number()]).optional(),
      limit: z.number().int().min(1).max(200).default(20),
    },
    annotations: { readOnlyHint: true },
  }, async ({ character, from, to, limit }) => {
    const key = character ? resolveChar(character) : null;
    const rows = db.prepare(`SELECT * FROM sessions WHERE (? IS NULL OR char_key = ?) AND start >= ? AND start <= ? ORDER BY start DESC LIMIT ?`)
      .all(key, key, toTs(from, 0), toTs(to, 4102444800), limit) as Record<string, unknown>[];
    return reply(rows.map((r) => ({
      ...r, start_iso: iso(r.start as number),
      xp_per_hour: r.duration ? Math.round(((r.xp as number) * 3600) / (r.duration as number)) : null,
      net_per_hour: r.duration ? Math.round((((r.income as number) - (r.expense as number)) * 3600) / (r.duration as number)) : null,
      income_json: undefined, expense_json: undefined,
      income_by_category: JSON.parse((r.income_json as string) ?? "{}"), expense_by_category: JSON.parse((r.expense_json as string) ?? "{}"),
    })));
  });

  // ------------------------------------------------------------------ combat

  server.registerTool("list_combat_segments", {
    title: "Fights from the combat log",
    description: "Fights parsed from WoWCombatLog files (world fights split by an 8 s gap, boss encounters by ENCOUNTER_START/END). Newest first.",
    inputSchema: {
      from: z.union([z.string(), z.number()]).optional(),
      to: z.union([z.string(), z.number()]).optional(),
      kind: z.enum(["world", "encounter"]).optional(),
      name_contains: z.string().optional(),
      with_deaths: z.boolean().optional(),
      limit: z.number().int().min(1).max(200).default(30),
    },
    annotations: { readOnlyHint: true },
  }, async ({ from, to, kind, name_contains, with_deaths, limit }) => {
    const rows = db.prepare(`
      SELECT s.id, s.kind, s.name, s.zone, s.success, s.start_ts, s.duration, s.top_targets,
        (SELECT COUNT(*) FROM deaths d WHERE d.segment_id = s.id) AS deaths,
        (SELECT SUM(damage_done) FROM segment_units u WHERE u.segment_id = s.id) AS group_damage
      FROM segments s
      WHERE s.start_ts >= ? AND s.start_ts <= ? AND (? IS NULL OR s.kind = ?) AND (? IS NULL OR s.name LIKE ?)
        AND (? = 0 OR EXISTS (SELECT 1 FROM deaths d WHERE d.segment_id = s.id))
      ORDER BY s.start_ts DESC LIMIT ?`)
      .all(toTs(from, 0), toTs(to, 4102444800), kind ?? null, kind ?? null, name_contains ?? null, `%${name_contains ?? ""}%`, with_deaths ? 1 : 0, limit) as Record<string, unknown>[];
    return reply(rows.map((r) => ({ ...r, start: iso(r.start_ts as number), start_ts: undefined, top_targets: JSON.parse((r.top_targets as string) ?? "[]") })));
  });

  server.registerTool("get_segment_summary", {
    title: "Fight summary",
    description: "Per-player damage, healing, damage taken, deaths, interrupts and top abilities for one fight (segment_id from list_combat_segments).",
    inputSchema: { segment_id: z.number().int() },
    annotations: { readOnlyHint: true },
  }, async ({ segment_id }) => {
    const seg = db.prepare("SELECT * FROM segments WHERE id = ?").get(segment_id) as Record<string, unknown> | undefined;
    if (!seg) return fail(`No segment ${segment_id}`);
    const mask = masker();
    const dur = Math.max(1, (seg.duration as number) || 1);
    const units = (db.prepare("SELECT * FROM segment_units WHERE segment_id = ? ORDER BY damage_done DESC").all(segment_id) as Record<string, unknown>[]).map((u) => {
      const abilities = Object.entries(JSON.parse((u.abilities as string) ?? "{}") as Record<string, number>).sort((a, b) => b[1] - a[1]).slice(0, 8);
      return { ...u, name: mask(u.name as string), dps: Math.round((u.damage_done as number) / dur), hps: Math.round((u.healing_done as number) / dur), abilities: Object.fromEntries(abilities), guid: undefined };
    });
    return reply({ ...seg, start: iso(seg.start_ts as number), log: basename(seg.log_path as string), top_targets: JSON.parse((seg.top_targets as string) ?? "[]"), log_path: undefined, units });
  });

  server.registerTool("get_deaths", {
    title: "Deaths with recap",
    description:
      "Player deaths with the last incoming damage and heals (seconds before death). By default only your own characters and the " +
      "members of your party or raid; scope \"all\" adds strangers who died nearby. Filter by segment_id, a time range or player name.",
    inputSchema: {
      segment_id: z.number().int().optional(),
      from: z.union([z.string(), z.number()]).optional(),
      to: z.union([z.string(), z.number()]).optional(),
      player: z.string().optional(),
      scope: z.enum(["mine", "group", "all"]).default("group").describe("mine: your characters only; group: plus party/raid members; all: everyone"),
      limit: z.number().int().min(1).max(100).default(20),
    },
    annotations: { readOnlyHint: true },
  }, async ({ segment_id, from, to, player, scope, limit }) => {
    const mask = masker();
    const own = (db.prepare("SELECT key FROM characters WHERE realm IS NOT NULL").all() as { key: string }[]).map((r) => r.key);
    const ownPh = own.length ? own.map(() => "?").join(",") : "NULL";
    const scopeSql =
      scope === "all" ? "1 = 1"
      : scope === "mine" ? `(d.affiliation = 'self' OR d.name IN (${ownPh}))`
      : `(d.affiliation IN ('self', 'party', 'raid') OR d.name IN (${ownPh}))`;
    const ownArgs = scope === "all" ? [] : own;
    const rows = db.prepare(`SELECT d.*, s.name AS fight, s.zone FROM deaths d JOIN segments s ON s.id = d.segment_id
      WHERE (? IS NULL OR d.segment_id = ?) AND d.ts >= ? AND d.ts <= ? AND (? IS NULL OR d.name LIKE ?) AND ${scopeSql}
      ORDER BY d.ts DESC LIMIT ?`)
      .all(segment_id ?? null, segment_id ?? null, toTs(from, 0), toTs(to, 4102444800), player ?? null, `${player ?? ""}%`, ...ownArgs, limit) as Record<string, unknown>[];
    return reply(rows.map((r) => ({ ...r, guid: undefined, name: mask(r.name as string), time: iso(r.ts as number), recap: JSON.parse((r.recap as string) ?? "[]") })));
  });

  server.registerTool("get_interrupts", {
    title: "Interrupts in a fight",
    description: "Who interrupted what and when in one fight.",
    inputSchema: { segment_id: z.number().int() },
    annotations: { readOnlyHint: true },
  }, async ({ segment_id }) => {
    const mask = masker();
    const rows = db.prepare("SELECT * FROM interrupts WHERE segment_id = ? ORDER BY ts").all(segment_id) as Record<string, unknown>[];
    return reply(rows.map((r) => ({ ...r, source: mask(r.source as string), time: iso(r.ts as number) })));
  });

  // ------------------------------------------------------------------ guild competition

  server.registerTool("get_guild_leaderboard", {
    title: "Guild competition leaderboard",
    description:
      "Weekly guild competition standings shared by AzerothChronicle users (self-reported). Categories: xp, levels, money, skills, quests, survivor (no deaths, ranked by xp).",
    inputSchema: {
      category: z.enum(["xp", "levels", "money", "skills", "quests", "survivor"]).default("xp"),
      guild: z.string().optional(),
      weeks_ago: z.number().int().min(0).max(52).default(0),
    },
    annotations: { readOnlyHint: true },
  }, async ({ category, guild, weeks_ago }) => {
    const k = weekKey(Date.now() / 1000) - weeks_ago;
    const g = guild ?? (db.prepare("SELECT guild FROM guild_standings GROUP BY guild ORDER BY MAX(ts) DESC LIMIT 1").get() as { guild: string } | undefined)?.guild;
    if (!g) return reply({ week: k, note: "No guild data yet. In game: /azc share on, then /azc sync, then /reload." });
    const order = category === "survivor" ? "xp" : category;
    const where = category === "survivor" ? "AND deaths = 0 AND xp > 0" : "";
    const mask = masker();
    const rows = db.prepare(`SELECT member, class, level, xp, money, levels, skills, quests, deaths, ts FROM guild_standings WHERE guild = ? AND week = ? ${where} ORDER BY ${order} DESC`).all(g, k) as Record<string, unknown>[];
    return reply({ guild: g, week: k, from: iso(weekStart(k)), category, standings: rows.map((r, i) => ({ rank: i + 1, ...r, member: mask(r.member as string), updated: iso(r.ts as number), ts: undefined })) });
  });

  server.registerTool("list_guild_weeks", {
    title: "Guild competition weeks",
    description: "Weeks and guilds with competition data, with participant counts.",
    inputSchema: {},
    annotations: { readOnlyHint: true },
  }, async () => {
    const rows = db.prepare("SELECT guild, week, COUNT(*) AS members, MAX(ts) AS updated FROM guild_standings GROUP BY guild, week ORDER BY week DESC").all() as Record<string, unknown>[];
    return reply(rows.map((r) => ({ ...r, from: iso(weekStart(r.week as number)), updated: iso(r.updated as number) })));
  });

  // ------------------------------------------------------------------ raw access

  server.registerTool("query_sql", {
    title: "Read-only SQL",
    description: "Runs one SELECT (or WITH … SELECT) on the local database through a read-only connection. Read the wow://schema resource first. Rows are capped by `limit`.",
    inputSchema: { sql: z.string(), limit: z.number().int().min(1).max(1000).default(200) },
    annotations: { readOnlyHint: true },
  }, async ({ sql, limit }) => {
    const q = sql.trim().replace(/;\s*$/, "");
    if (!/^(select|with)\b/i.test(q)) return fail("Only SELECT / WITH queries are allowed.");
    if (q.includes(";")) return fail("Only one statement is allowed.");
    if (/\b(attach|detach|pragma|insert|update|delete|replace|create|drop|alter|vacuum|reindex)\b/i.test(q)) return fail("That keyword is not allowed.");
    const conn = ro();
    try {
      const rows = conn.prepare(`SELECT * FROM (${q}) LIMIT ${limit}`).all();
      return reply({ rows, count: rows.length });
    } catch (e) {
      return fail(`SQL error: ${(e as Error).message}`);
    } finally {
      conn.close();
    }
  });

  server.registerTool("read_saved_variables", {
    title: "Read addon SavedVariables",
    description: "Parsed contents of any addon's SavedVariables file as JSON. scope 'account' (shared) or 'character' (needs character). `path` picks a subtree with dots, e.g. 'WowAssistantDB.chars.Defty.money'.",
    inputSchema: {
      addon: z.string().regex(/^[\w.\- ]+$/),
      scope: z.enum(["account", "character"]).default("account"),
      character: z.string().optional(),
      path: z.string().optional(),
    },
    annotations: { readOnlyHint: true },
  }, async ({ addon, scope, character, path }) => {
    let file: string | undefined;
    if (scope === "account") file = accountSavedVariables(cfg.wowDir, addon)[0]?.file;
    else {
      if (!character) return fail("character is required for scope 'character'");
      const c = characterDirs(cfg.wowDir).find((d) => d.key.toLowerCase() === character.toLowerCase() || d.name.toLowerCase() === character.toLowerCase());
      if (c) file = join(c.svDir, `${addon}.lua`);
    }
    if (!file || !existsSync(file)) return fail(`No SavedVariables file for ${addon} (${scope}).`);
    let v: LuaValue | Record<string, LuaValue> = readSavedVariables(file);
    for (const part of (path ?? "").split(".").filter(Boolean)) {
      if (v && typeof v === "object") v = (v as Record<string, LuaValue>)[part] ?? (v as Record<string, LuaValue>)[Number(part) - 1];
      else v = null;
    }
    return reply({ file: basename(file), modified: iso(statSync(file).mtimeMs / 1000), value: v ?? null });
  });

  server.registerTool("list_addons", {
    title: "Installed addons",
    description: "Addons in Interface/AddOns with Title, Version and Interface from their .toc, flagging ones built for another client version (Addon Doctor basics).",
    inputSchema: {},
    annotations: { readOnlyHint: true },
  }, async () => {
    const dir = addonsDir(cfg.wowDir);
    if (!existsSync(dir)) return fail(`No AddOns folder at ${dir}`);
    const expected = basename(cfg.wowDir) === "_forever_" ? "16001" : null;
    const out = readdirSync(dir).filter((d) => statSync(join(dir, d)).isDirectory()).map((d) => {
      const toc = readdirSync(join(dir, d)).find((f) => f.toLowerCase() === `${d.toLowerCase()}.toc`) ?? readdirSync(join(dir, d)).find((f) => f.toLowerCase().endsWith(".toc"));
      const meta: Record<string, string> = {};
      if (toc) {
        for (const line of readFileSync(join(dir, d, toc), "utf8").split(/\r?\n/)) {
          const m = /^##\s*([\w-]+)\s*:\s*(.*)$/.exec(line);
          if (m) meta[m[1]] = m[2].replace(/\|c[0-9a-fA-F]{8}|\|r/g, "");
        }
      }
      const interfaces = (meta.Interface ?? "").split(/[,\s]+/).filter(Boolean);
      return { folder: d, title: meta.Title ?? d, version: meta.Version ?? null, interface: interfaces, outOfDate: expected ? !interfaces.includes(expected) : null, dependencies: meta.Dependencies ?? meta.RequiredDeps ?? null };
    });
    return reply({ expectedInterface: expected, count: out.length, outOfDate: out.filter((a) => a.outOfDate).length, addons: out });
  });

  server.registerTool("write_ingame_inbox", {
    title: "Send notes into the game",
    description:
      "Replaces the in-game inbox (AzerothMCP_Data addon) with these notes and goals. The player sees them with /amcp after the next /reload. " +
      "Keep texts short (they are shown in a small window). This is the only write the bridge can make.",
    inputSchema: {
      notes: z.array(z.object({ title: z.string().max(80), text: z.string().max(1000) })).max(20).default([]),
      goals: z.array(z.object({ title: z.string().max(80), text: z.string().max(400) })).max(20).default([]),
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true },
  }, async ({ notes, goals }) => {
    const r = writeInbox(cfg.wowDir, { notes, goals });
    return reply({ written: basename(r.file), bytes: r.bytes, next: "Type /reload in game, then /amcp to read it." });
  });

  server.registerTool("ingest_now", {
    title: "Re-read game files",
    description: "Reads changed SavedVariables and new combat log lines right now (normally automatic). Note: the game writes SavedVariables only on /reload or logout.",
    inputSchema: { full: z.boolean().default(false).describe("Re-read every SavedVariables file even if unchanged") },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true },
  }, async ({ full }) => reply(ingestAll(db, cfg, { force: full })));

  // ------------------------------------------------------------------ resources

  server.registerResource("schema", "wow://schema", { title: "Database schema", description: "SQLite schema for query_sql", mimeType: "text/plain" },
    async (uri) => ({ contents: [{ uri: uri.href, text: schemaText(db) }] }));
  server.registerResource("characters", "wow://characters", { title: "Characters", mimeType: "application/json" },
    async (uri) => ({ contents: [{ uri: uri.href, text: JSON.stringify(db.prepare("SELECT * FROM characters").all(), null, 1) }] }));

  // ------------------------------------------------------------------ prompts

  const userPrompt = (text: string) => ({ messages: [{ role: "user" as const, content: { type: "text" as const, text } }] });
  server.registerPrompt("weekly_review", {
    title: "Weekly review",
    description: "A weekly review of progress, sessions, deaths and suggestions.",
    argsSchema: { character: z.string().optional() },
  }, ({ character }) => userPrompt(
    `Készíts heti áttekintést${character ? ` a(z) ${character} karakterről` : " a WoW fiókomról"} magyarul. ` +
    "Használd: get_week_summary (weeks_ago 0 és 1), list_sessions (az elmúlt 7 nap), get_progress_timeline (xp és money, heti bontás), get_deaths (az elmúlt 7 nap). " +
    "Szerkezet: 1) számokban a hét (XP, szint, nettó arany, játékidő) az előző héthez képest, 2) mi ment jól, 3) hol veszett idő vagy arany, 4) halálok mintázata, 5) három konkrét cél a jövő hétre. " +
    "Ha a célok jók, ajánld fel, hogy a write_ingame_inbox eszközzel beküldöd őket a játékba."));
  server.registerPrompt("wipe_analysis", {
    title: "Fight / death analysis",
    description: "Explains what went wrong in one fight.",
    argsSchema: { segment_id: z.string() },
  }, ({ segment_id }) => userPrompt(
    `Elemezd a(z) ${segment_id} azonosítójú harcot magyarul: get_segment_summary, get_deaths (segment_id), get_interrupts. ` +
    "Mondd el röviden: ki és mitől halt meg, mi volt a halál előtti 5 másodperc, és mit lehetett volna másképp csinálni. Ne találj ki adatot, ami nincs a válaszokban."));
  server.registerPrompt("guild_chronicle", {
    title: "Guild chronicle",
    description: "A narrative weekly chronicle of the guild competition, ready to paste into Discord.",
    argsSchema: { weeks_ago: z.string().optional() },
  }, ({ weeks_ago }) => userPrompt(
    `Írj heti guild-krónikát magyarul a get_guild_leaderboard eredményeiből (weeks_ago: ${weeks_ago ?? "0"}; kategóriák: xp, levels, money, skills, quests, survivor). ` +
    "Hangnem: játékos, kicsit epikus krónikás stílus, de rövid (legfeljebb 15 sor), Discord-barát formázással. Emeld ki a kategóriagyőzteseket és a meglepetéseket. " +
    "Az adat önbevallásos; ne állíts olyat, ami nincs az adatban. A végén egy mondatban hirdesd meg a jövő heti kihívást."));
  server.registerPrompt("addon_health", {
    title: "Addon health check",
    description: "Lists out-of-date or suspicious addons.",
    argsSchema: {},
  }, () => userPrompt(
    "Futtasd a list_addons eszközt, és magyarul foglald össze: mely addonok nem a jelenlegi kliensverzióra készültek, melyek hiányzó függőséggel futhatnak, és mit javasolsz (frissítés, törlés, natív Blizzard-funkció)."));

  return server;
}
