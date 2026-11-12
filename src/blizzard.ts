import type { Env } from "./env";

const TOKEN_KEY = "blizzard_token";

async function getToken(env: Env): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const cached = await env.DB.prepare(
    "SELECT value, expires_at FROM kv_cache WHERE key = ?",
  )
    .bind(TOKEN_KEY)
    .first<{ value: string; expires_at: number }>();
  if (cached && cached.expires_at > now + 60) return cached.value;

  if (!env.BLIZZARD_CLIENT_ID || !env.BLIZZARD_CLIENT_SECRET) {
    throw new Error("BLIZZARD_CLIENT_ID / BLIZZARD_CLIENT_SECRET are not set");
  }
  const res = await fetch("https://oauth.battle.net/token", {
    method: "POST",
    headers: {
      Authorization:
        "Basic " + btoa(`${env.BLIZZARD_CLIENT_ID}:${env.BLIZZARD_CLIENT_SECRET}`),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });
  if (!res.ok) throw new Error(`Token request failed: HTTP ${res.status}`);
  const body = (await res.json()) as { access_token: string; expires_in: number };

  await env.DB.prepare(
    "INSERT INTO kv_cache (key, value, expires_at) VALUES (?, ?, ?) " +
      "ON CONFLICT(key) DO UPDATE SET value = excluded.value, expires_at = excluded.expires_at",
  )
    .bind(TOKEN_KEY, body.access_token, now + body.expires_in)
    .run();
  return body.access_token;
}

export type NamespaceKind = "profile" | "static" | "dynamic";

export interface ApiResult {
  status: number;
  body: unknown;
}

/** GET a Blizzard API path, e.g. `/profile/wow/character/defty-graveshade/equipment`. */
export async function apiGet(
  env: Env,
  path: string,
  namespace: NamespaceKind,
): Promise<ApiResult> {
  const token = await getToken(env);
  const url = new URL(`https://${env.REGION}.api.blizzard.com${path}`);
  url.searchParams.set(
    "namespace",
    `${namespace}-${env.GAME_NAMESPACE_SUFFIX}-${env.REGION}`,
  );
  url.searchParams.set("locale", env.LOCALE);
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    // non-JSON error body
  }
  return { status: res.status, body };
}
