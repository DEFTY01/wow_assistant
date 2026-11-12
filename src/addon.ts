import { storeFights } from "./combat";
import type { Env } from "./env";

type Obj = Record<string, any>;

export interface AddonState {
  name: string;
  level?: number;
  money?: number;
  at?: number;
  bags?: Record<string, number>;
  bagsAt?: number;
  bank?: Record<string, number>;
  bankAt?: number;
  skills?: Record<string, { rank: number; max: number }>;
  spells?: { name: string; rank: string; id?: number }[];
  api?: Record<string, unknown>;
  errors?: Record<string, string>;
  trainer?: Record<string, { name: string; rank: string; state: string; cost: number; level: number; tradeskill: boolean }>;
}

/** Store what the in-game addon exported (the uploader script posts the parsed SavedVariables). */
export async function importAddon(env: Env, db: Obj) {
  const chars = (db?.chars ?? {}) as Record<string, AddonState>;
  const first = env.CHARACTER_SLUG.split("-")[0];
  const key =
    Object.keys(chars).find((k) => k.toLowerCase() === first) ?? (db.last as string) ?? Object.keys(chars)[0];
  const c = chars[key];
  if (!c) throw new Error("Nincs karakteradat a feltöltésben");

  // Fights go to their own table; keep them out of the state blob.
  const fights = await storeFights(env, (c as Obj).fights);
  delete (c as Obj).fights;

  const now = new Date().toISOString();
  const put = (k: string, v: string) =>
    env.DB.prepare(
      "INSERT INTO manual_state (key, value, updated_at) VALUES (?, ?, ?) " +
        "ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
    ).bind(k, v, now);

  const stmts = [put("addon", JSON.stringify(c))];
  if (typeof c.money === "number") stmts.push(put("gold_copper", String(c.money)));

  const trainer = Object.values(c.trainer ?? {});
  for (const t of trainer) {
    const rank = Number(String(t.rank).match(/\d+/)?.[0] ?? 0);
    stmts.push(
      env.DB.prepare(
        "INSERT INTO trainer_skills (name, rank, required_level, cost_copper, learned, updated_at) VALUES (?, ?, ?, ?, ?, ?) " +
          "ON CONFLICT(name, rank) DO UPDATE SET required_level = excluded.required_level, " +
          "cost_copper = excluded.cost_copper, learned = excluded.learned, updated_at = excluded.updated_at",
      ).bind(t.name, rank, t.level || null, t.cost || 0, t.state === "used" ? 1 : 0, now),
    );
  }
  for (let i = 0; i < stmts.length; i += 80) await env.DB.batch(stmts.slice(i, i + 80));
  return {
    character: c.name,
    money: c.money ?? null,
    bagItems: Object.keys(c.bags ?? {}).length,
    bankItems: Object.keys(c.bank ?? {}).length,
    trainerSkills: trainer.length,
    fights,
    spells: Array.isArray(c.spells) ? c.spells.length : 0,
    skills: Object.keys(c.skills ?? {}).length,
    api: c.api ?? null,
    errors: c.errors ?? null,
  };
}

export async function loadAddon(env: Env): Promise<{ state: AddonState; updatedAt: string } | null> {
  const row = await env.DB.prepare("SELECT value, updated_at FROM manual_state WHERE key = 'addon'").first<{
    value: string;
    updated_at: string;
  }>();
  return row ? { state: JSON.parse(row.value), updatedAt: row.updated_at } : null;
}

/** Bags + bank, itemId -> count. */
export function ownedItems(state: AddonState | undefined): Map<number, number> {
  const owned = new Map<number, number>();
  for (const src of [state?.bags, state?.bank]) {
    for (const [id, n] of Object.entries(src ?? {})) owned.set(Number(id), (owned.get(Number(id)) ?? 0) + Number(n));
  }
  return owned;
}
