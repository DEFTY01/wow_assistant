import { apiGet } from "./blizzard";
import type { Env } from "./env";

type Obj = Record<string, any>;

export interface Character {
  slug: string;
  name: string | null;
  class_id: number | null;
  level: number | null;
  faction: string | null;
  ruleset_id: number | null;
  share_key: string | null;
  is_owner: number;
  created_at: string;
  last_sync: string | null;
}

const MAX_CHARACTERS = 25;
const INVITE_KEY = "invite_code"; // global, not per character

/** An env that makes every data function work on one character. */
export function scopedEnv(env: Env, slug: string, sharePrefix?: string): Env {
  return { ...env, CHARACTER_SLUG: slug, SHARE_PREFIX: sharePrefix };
}

export async function listCharacters(env: Env): Promise<Character[]> {
  const rows = await env.DB.prepare("SELECT * FROM characters ORDER BY is_owner DESC, created_at").all<Character>();
  return rows.results;
}

export async function findByKey(env: Env, key: string): Promise<Character | null> {
  if (!/^[0-9a-f]{32}$/.test(key)) return null;
  return env.DB.prepare("SELECT * FROM characters WHERE share_key = ?").bind(key).first<Character>();
}

/** The code a new user needs to register a character; created on first use. */
export async function inviteCode(env: Env): Promise<string> {
  const row = await env.DB.prepare("SELECT value FROM manual_state WHERE key = ?").bind(INVITE_KEY).first<{ value: string }>();
  if (row) return row.value;
  const code = crypto.randomUUID().replace(/-/g, "").slice(0, 16);
  await env.DB.prepare("INSERT INTO manual_state (key, value, updated_at) VALUES (?, ?, ?)")
    .bind(INVITE_KEY, code, new Date().toISOString())
    .run();
  return code;
}

/** "Defty Graveshade" -> "defty-graveshade", the form the Blizzard API uses. */
export function toSlug(input: string): string {
  return input
    .trim()
    .toLowerCase()
    .replace(/[\s_]+/g, "-")
    .replace(/[^\p{L}\p{N}-]/gu, "")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

/** Register a character after checking it exists on the Blizzard API. */
export async function createCharacter(env: Env, input: string): Promise<{ character?: Character; error?: string }> {
  const slug = toSlug(input);
  if (!slug || slug.length > 60) return { error: "Írd be a karakter teljes nevét (keresztnév és vezetéknév)." };
  const existing = await env.DB.prepare("SELECT * FROM characters WHERE slug = ?").bind(slug).first<Character>();
  if (existing) {
    return existing.share_key ? { character: existing } : { error: "Ez a karakter a tulajdonosé." };
  }
  const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM characters").first<{ n: number }>();
  if ((count?.n ?? 0) >= MAX_CHARACTERS) return { error: "Betelt a hely: ez a példány legfeljebb 25 karaktert kezel." };

  const { status, body } = await apiGet(scopedEnv(env, slug), `/profile/wow/character/${encodeURIComponent(slug)}`, "profile");
  if (status !== 200) {
    return {
      error:
        status === 404
          ? "Ilyen karaktert nem talál a Blizzard API. Legalább 10-es szintűnek kell lennie, és ki kell jelentkezned vele egyszer."
          : `A Blizzard API hibát adott (HTTP ${status}), próbáld újra később.`,
    };
  }
  const p = body as Obj;
  const key = crypto.randomUUID().replace(/-/g, "");
  await env.DB.prepare(
    "INSERT INTO characters (slug, name, class_id, level, faction, ruleset_id, share_key, is_owner, created_at) " +
      "VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)",
  )
    .bind(slug, p.name ?? slug, p.character_class?.id ?? null, p.level ?? null, p.faction?.type ?? null, p.ruleset?.id ?? null, key, new Date().toISOString())
    .run();
  const character = await env.DB.prepare("SELECT * FROM characters WHERE slug = ?").bind(slug).first<Character>();
  return { character: character ?? undefined };
}

export async function removeCharacter(env: Env, slug: string): Promise<void> {
  const c = await env.DB.prepare("SELECT is_owner FROM characters WHERE slug = ?").bind(slug).first<{ is_owner: number }>();
  if (!c || c.is_owner) return;
  await env.DB.batch([
    env.DB.prepare("DELETE FROM characters WHERE slug = ?").bind(slug),
    env.DB.prepare("DELETE FROM snapshots WHERE slug = ?").bind(slug),
    env.DB.prepare("DELETE FROM sync_log WHERE slug = ?").bind(slug),
    env.DB.prepare("DELETE FROM fights WHERE slug = ?").bind(slug),
    env.DB.prepare("DELETE FROM trainer_skills WHERE slug = ?").bind(slug),
    env.DB.prepare("DELETE FROM manual_state WHERE key LIKE ?").bind(`${slug}:%`),
  ]);
}

/** Keep the character list's summary columns in step with the latest profile. */
export async function touchCharacter(env: Env, profile: Obj | undefined): Promise<void> {
  if (!profile) return;
  await env.DB.prepare(
    "UPDATE characters SET name = ?, class_id = ?, level = ?, faction = ?, ruleset_id = ?, last_sync = ? WHERE slug = ?",
  )
    .bind(
      profile.name ?? null,
      profile.character_class?.id ?? null,
      profile.level ?? null,
      profile.faction?.type ?? null,
      profile.ruleset?.id ?? null,
      new Date().toISOString(),
      env.CHARACTER_SLUG,
    )
    .run();
}
