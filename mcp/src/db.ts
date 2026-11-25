import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";

const SCHEMA = `
CREATE TABLE IF NOT EXISTS characters (
  key TEXT PRIMARY KEY,            -- "Name-Realm" (or "Name" when the source has no realm)
  account TEXT, name TEXT NOT NULL, realm TEXT, class TEXT, race TEXT, faction TEXT, guild TEXT,
  updated INTEGER
);
CREATE TABLE IF NOT EXISTS snapshots (
  char_key TEXT NOT NULL, ts INTEGER NOT NULL,
  level INTEGER, xp INTEGER, xp_max INTEGER, money INTEGER,
  cxp INTEGER,                     -- cumulative XP gained since tracking began
  deaths INTEGER, quests INTEGER, skills INTEGER, zone TEXT,
  PRIMARY KEY (char_key, ts)
);
CREATE TABLE IF NOT EXISTS xp_samples (   -- from WowAssistantDB.chars[*].xp
  char_key TEXT NOT NULL, ts INTEGER NOT NULL, xp INTEGER, level INTEGER, xp_max INTEGER, zone TEXT,
  PRIMARY KEY (char_key, ts)
);
CREATE TABLE IF NOT EXISTS sessions (     -- from SessionBar
  char_key TEXT NOT NULL, start INTEGER NOT NULL, duration INTEGER, start_level INTEGER, levels INTEGER, xp INTEGER,
  income INTEGER, expense INTEGER, income_json TEXT, expense_json TEXT, is_current INTEGER DEFAULT 0,
  PRIMARY KEY (char_key, start)
);
CREATE TABLE IF NOT EXISTS guild_standings (  -- from AzerothChronicle guild sync
  guild TEXT NOT NULL, week INTEGER NOT NULL, member TEXT NOT NULL,
  ts INTEGER, class TEXT, level INTEGER, xp INTEGER, money INTEGER, levels INTEGER,
  skills INTEGER, quests INTEGER, deaths INTEGER,
  PRIMARY KEY (guild, week, member)
);
CREATE TABLE IF NOT EXISTS combat_logs (
  path TEXT PRIMARY KEY, log_version INTEGER, advanced INTEGER, build TEXT,
  first_ts REAL, last_ts REAL, unknown_events TEXT
);
CREATE TABLE IF NOT EXISTS segments (
  id INTEGER PRIMARY KEY, log_path TEXT NOT NULL, kind TEXT NOT NULL,   -- world | encounter
  name TEXT, encounter_id INTEGER, difficulty INTEGER, group_size INTEGER, success INTEGER,
  start_ts REAL NOT NULL, end_ts REAL NOT NULL, duration REAL,
  byte_start INTEGER, byte_end INTEGER, zone TEXT, top_targets TEXT,
  UNIQUE (log_path, byte_start)
);
CREATE TABLE IF NOT EXISTS segment_units (
  segment_id INTEGER NOT NULL, guid TEXT NOT NULL, name TEXT, kind TEXT,   -- player | pet
  damage_done INTEGER DEFAULT 0, healing_done INTEGER DEFAULT 0, overhealing INTEGER DEFAULT 0,
  damage_taken INTEGER DEFAULT 0, deaths INTEGER DEFAULT 0, interrupts INTEGER DEFAULT 0, dispels INTEGER DEFAULT 0,
  abilities TEXT,                 -- JSON {spell: damage}
  PRIMARY KEY (segment_id, guid)
);
CREATE TABLE IF NOT EXISTS deaths (
  id INTEGER PRIMARY KEY, segment_id INTEGER NOT NULL, ts REAL, guid TEXT, name TEXT, killer TEXT, recap TEXT
);
CREATE TABLE IF NOT EXISTS interrupts (
  segment_id INTEGER NOT NULL, ts REAL, source TEXT, spell TEXT, target TEXT, interrupted TEXT
);
CREATE TABLE IF NOT EXISTS ingest_state (path TEXT PRIMARY KEY, mtime REAL, size INTEGER, offset INTEGER);
CREATE INDEX IF NOT EXISTS segments_start ON segments(start_ts);
CREATE INDEX IF NOT EXISTS deaths_seg ON deaths(segment_id);
CREATE INDEX IF NOT EXISTS interrupts_seg ON interrupts(segment_id);
`;

export function openDb(path: string): DatabaseSync {
  mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;");
  db.exec(SCHEMA);
  return db;
}

/** A second connection that cannot write: used for model-written SQL. */
export function openReadOnly(path: string): DatabaseSync {
  return new DatabaseSync(path, { readOnly: true });
}

export function schemaText(db: DatabaseSync): string {
  const rows = db.prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND sql IS NOT NULL ORDER BY name").all() as { sql: string }[];
  return rows.map((r) => r.sql + ";").join("\n\n");
}

export function tx<T>(db: DatabaseSync, fn: () => T): T {
  db.exec("BEGIN");
  try {
    const out = fn();
    db.exec("COMMIT");
    return out;
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}
