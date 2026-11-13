import type { MiddlewareHandler } from "hono";
import type { Env } from "./env";

// The app has no login of its own; Cloudflare Access sits in front of it. This guard makes
// sure a request really came through Access, so a missing or misconfigured Access
// application does not leave the site open.
//
// With ACCESS_TEAM_DOMAIN and ACCESS_AUD set, the Access JWT is fully verified (signature,
// audience, expiry). Without them only the header's presence is checked, which stops
// casual visitors but can be forged, so set both.

const TOKEN_PATHS = new Set(["/api/addon", "/api/fights"]); // protected by an upload token instead
// Shared characters live under /u/<secret key>; the key in the link is their protection.
const isShared = (path: string) => path === "/u" || path.startsWith("/u/");

interface Jwk {
  kid: string;
  kty: string;
  n: string;
  e: string;
  alg?: string;
}
let jwks: { keys: Jwk[]; at: number } | null = null;

function b64url(s: string): Uint8Array {
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(s.length / 4) * 4, "="));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

async function verify(token: string, teamDomain: string, aud: string): Promise<boolean> {
  const parts = token.split(".");
  if (parts.length !== 3) return false;
  const header = JSON.parse(new TextDecoder().decode(b64url(parts[0]))) as { kid?: string; alg?: string };
  const payload = JSON.parse(new TextDecoder().decode(b64url(parts[1]))) as { aud?: string | string[]; exp?: number; iss?: string };
  if (header.alg !== "RS256") return false;
  const issuer = `https://${teamDomain}`;
  if (payload.iss !== issuer) return false;
  if (!payload.exp || payload.exp * 1000 < Date.now()) return false;
  const auds = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!auds.includes(aud)) return false;

  if (!jwks || Date.now() - jwks.at > 3600_000 || !jwks.keys.some((k) => k.kid === header.kid)) {
    const res = await fetch(`${issuer}/cdn-cgi/access/certs`);
    if (!res.ok) return false;
    jwks = { keys: ((await res.json()) as { keys: Jwk[] }).keys, at: Date.now() };
  }
  const jwk = jwks.keys.find((k) => k.kid === header.kid);
  if (!jwk) return false;
  const key = await crypto.subtle.importKey(
    "jwk",
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
  return crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    b64url(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
}

export const requireAccess: MiddlewareHandler<{ Bindings: Env }> = async (c, next) => {
  // wrangler dev rewrites the request host to the production route, so local development is
  // marked by a variable that only the dev script sets (see package.json).
  if (c.env.LOCAL_DEV === "1") return next();
  if (TOKEN_PATHS.has(c.req.path) || isShared(c.req.path)) return next();

  const token = c.req.header("Cf-Access-Jwt-Assertion");
  if (!token) {
    return c.text("Ez az oldal csak Cloudflare Access mögül érhető el, és a kérés nem azon keresztül jött.", 403);
  }
  if (c.env.ACCESS_TEAM_DOMAIN && c.env.ACCESS_AUD) {
    let ok = false;
    try {
      ok = await verify(token, c.env.ACCESS_TEAM_DOMAIN, c.env.ACCESS_AUD);
    } catch {
      ok = false;
    }
    if (!ok) return c.text("Érvénytelen Cloudflare Access token.", 403);
  }
  return next();
};
