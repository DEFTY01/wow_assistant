import type { Env } from "./env";

// Small per-character key/value store on top of manual_state: keys are "<slug>:<key>".
const k = (env: Env, key: string) => `${env.CHARACTER_SLUG}:${key}`;

export async function stateGet(env: Env, key: string): Promise<{ value: string; updatedAt: string } | null> {
  const row = await env.DB.prepare("SELECT value, updated_at FROM manual_state WHERE key = ?")
    .bind(k(env, key))
    .first<{ value: string; updated_at: string }>();
  return row ? { value: row.value, updatedAt: row.updated_at } : null;
}

export function statePutStmt(env: Env, key: string, value: string, now = new Date().toISOString()): D1PreparedStatement {
  return env.DB.prepare(
    "INSERT INTO manual_state (key, value, updated_at) VALUES (?, ?, ?) " +
      "ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
  ).bind(k(env, key), value, now);
}

export async function statePut(env: Env, key: string, value: string): Promise<void> {
  await statePutStmt(env, key, value).run();
}
