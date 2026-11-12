import { apiGet } from "./blizzard";
import type { Env } from "./env";

export const KINDS = [
  "profile",
  "equipment",
  "professions",
  "specializations",
  "statistics",
] as const;
export type Kind = (typeof KINDS)[number];

export interface SyncResult {
  kind: Kind;
  status: number;
  changed: boolean;
  message?: string;
}

function pathFor(kind: Kind, slug: string): string {
  const base = `/profile/wow/character/${slug}`;
  return kind === "profile" ? base : `${base}/${kind}`;
}

async function sha256(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function syncOne(env: Env, kind: Kind): Promise<SyncResult> {
  const now = new Date().toISOString();
  let result: SyncResult;
  try {
    const { status, body } = await apiGet(env, pathFor(kind, env.CHARACTER_SLUG), "profile");
    if (status !== 200) {
      result = { kind, status, changed: false, message: JSON.stringify(body).slice(0, 300) };
    } else {
      const json = JSON.stringify(body);
      const hash = await sha256(json);
      const latest = await env.DB.prepare(
        "SELECT id, hash FROM snapshots WHERE kind = ? ORDER BY id DESC LIMIT 1",
      )
        .bind(kind)
        .first<{ id: number; hash: string }>();
      if (latest?.hash === hash) {
        await env.DB.prepare("UPDATE snapshots SET last_seen_at = ? WHERE id = ?")
          .bind(now, latest.id)
          .run();
        result = { kind, status, changed: false };
      } else {
        await env.DB.prepare(
          "INSERT INTO snapshots (kind, hash, json, fetched_at, last_seen_at) VALUES (?, ?, ?, ?, ?)",
        )
          .bind(kind, hash, json, now, now)
          .run();
        result = { kind, status, changed: true };
      }
    }
  } catch (err) {
    result = { kind, status: 0, changed: false, message: String(err).slice(0, 300) };
  }
  await env.DB.prepare(
    "INSERT INTO sync_log (kind, status, changed, message, at) VALUES (?, ?, ?, ?, ?)",
  )
    .bind(kind, result.status, result.changed ? 1 : 0, result.message ?? null, now)
    .run();
  return result;
}

export async function syncAll(env: Env): Promise<SyncResult[]> {
  const results: SyncResult[] = [];
  for (const kind of KINDS) results.push(await syncOne(env, kind));
  // Keep the log bounded.
  await env.DB.prepare(
    "DELETE FROM sync_log WHERE id < (SELECT MAX(id) FROM sync_log) - 2000",
  ).run();
  return results;
}

export interface LatestSnapshot {
  json: unknown;
  fetched_at: string;
  last_seen_at: string;
}

export async function latestSnapshots(env: Env): Promise<Partial<Record<Kind, LatestSnapshot>>> {
  const out: Partial<Record<Kind, LatestSnapshot>> = {};
  for (const kind of KINDS) {
    const row = await env.DB.prepare(
      "SELECT json, fetched_at, last_seen_at FROM snapshots WHERE kind = ? ORDER BY id DESC LIMIT 1",
    )
      .bind(kind)
      .first<{ json: string; fetched_at: string; last_seen_at: string }>();
    if (row) {
      out[kind] = {
        json: JSON.parse(row.json),
        fetched_at: row.fetched_at,
        last_seen_at: row.last_seen_at,
      };
    }
  }
  return out;
}
