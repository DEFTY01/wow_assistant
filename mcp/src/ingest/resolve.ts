// WowAssistantDB keys characters by first name only, so alts with the same name on other realms
// share one XP sample list. This assigns every sample to its Name-Realm character:
//   1. by the combat log: the account's own "Name-Realm" seen in a fight near the sample's time,
//   2. else by continuity with the neighbouring samples (same level and XP not going down, or +1 level).
// Samples that stay unresolved keep the bare name.
import type { DatabaseSync } from "node:sqlite";
import { tx } from "../db.ts";

const NEAR = 30 * 60; // a fight within 30 minutes of a sample places the character

interface Sample { ts: number; xp: number | null; level: number | null; key: string | null }

/** Continuity: b can follow a on the same character. */
const follows = (a: Sample, b: Sample) =>
  a.level != null && b.level != null &&
  ((b.level === a.level && (b.xp ?? 0) >= (a.xp ?? 0)) || b.level === a.level + 1);

/** Bare-name characters that have Name-Realm siblings on the same account. */
export function ambiguousNames(db: DatabaseSync): { name: string; account: string | null; candidates: string[] }[] {
  const rows = db.prepare(
    `SELECT b.name, b.account, GROUP_CONCAT(c.key, '\u0001') AS keys
     FROM characters b JOIN characters c ON c.name = b.name AND c.realm IS NOT NULL AND c.account IS b.account
     WHERE b.realm IS NULL AND b.key = b.name GROUP BY b.key`,
  ).all() as { name: string; account: string | null; keys: string }[];
  return rows.map((r) => ({ name: r.name, account: r.account, candidates: r.keys.split("\u0001") }));
}

export function resolveCharacters(db: DatabaseSync): { resolved: number; unresolved: number } {
  let resolved = 0;
  let unresolved = 0;
  for (const { name, candidates } of ambiguousNames(db)) {
    const samples = db.prepare("SELECT ts, xp, level FROM xp_samples WHERE char_key = ? ORDER BY ts").all(name) as unknown as Sample[];
    if (!samples.length) {
      dropIfEmpty(db, name);
      continue;
    }
    const ph = candidates.map(() => "?").join(",");
    const seen = db.prepare(
      `SELECT s.start_ts AS a, s.end_ts AS b, u.name AS key FROM segment_units u JOIN segments s ON s.id = u.segment_id
       WHERE u.kind = 'player' AND u.name IN (${ph}) ORDER BY s.start_ts`,
    ).all(...candidates) as { a: number; b: number; key: string }[];

    // 1. combat log presence (nearest fight within NEAR seconds)
    let j = 0;
    for (const s of samples) {
      s.key = null;
      while (j < seen.length - 1 && seen[j + 1].a <= s.ts) j++;
      let best: { d: number; key: string } | null = null;
      for (const k of [j - 1, j, j + 1]) {
        const p = seen[k];
        if (!p) continue;
        const d = s.ts < p.a ? p.a - s.ts : s.ts > p.b ? s.ts - p.b : 0;
        if (d <= NEAR && (!best || d < best.d)) best = { d, key: p.key };
      }
      if (best) s.key = best.key;
    }
    // 2. continuity, forwards then backwards
    for (let i = 1; i < samples.length; i++) {
      if (!samples[i].key && samples[i - 1].key && follows(samples[i - 1], samples[i])) samples[i].key = samples[i - 1].key;
    }
    for (let i = samples.length - 2; i >= 0; i--) {
      if (!samples[i].key && samples[i + 1].key && follows(samples[i], samples[i + 1])) samples[i].key = samples[i + 1].key;
    }

    tx(db, () => {
      const move = db.prepare("UPDATE OR REPLACE xp_samples SET char_key = ? WHERE char_key = ? AND ts = ?");
      for (const s of samples) {
        if (s.key) {
          move.run(s.key, name, s.ts);
          resolved++;
        } else unresolved++;
      }
      // The addon's class belongs to the character that played last.
      const last = [...samples].reverse().find((s) => s.key);
      if (last) {
        db.prepare("UPDATE characters SET class = COALESCE(class, (SELECT class FROM characters WHERE key = ?)) WHERE key = ?").run(name, last.key);
      }
      dropIfEmpty(db, name);
    });
  }
  return { resolved, unresolved };
}

export function dropIfEmpty(db: DatabaseSync, key: string): void {
  db.prepare(
    `DELETE FROM characters WHERE key = ?
       AND NOT EXISTS (SELECT 1 FROM xp_samples WHERE char_key = ?)
       AND NOT EXISTS (SELECT 1 FROM snapshots WHERE char_key = ?)
       AND NOT EXISTS (SELECT 1 FROM sessions WHERE char_key = ?)`,
  ).run(key, key, key, key);
}
