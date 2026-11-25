import { storeFights } from "./combat";
import type { Env } from "./env";
import { queueUnknownItems } from "./market";
import { storeScan, storeXp } from "./scan";
import { stateGet, statePutStmt } from "./state";

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

const slugPart = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "");

/**
 * The character a slug ("defty-graveshade") means in WowAssistantDB.chars. Since addon 2.0 the
 * keys are "Name-Realm", or "Name#id" when the client reported no realm (then the record's
 * `realm` field is empty too, and the only Name#id record of that name is taken). Older uploads
 * are keyed by the first name only.
 */
export function pickCharacter(chars: Record<string, Obj>, slug: string, last?: unknown): string | undefined {
  const [first, ...rest] = slug.split("-");
  const realm = slugPart(rest.join("-"));
  const keys = Object.keys(chars);
  const nameOf = (k: string) => String(chars[k]?.name ?? k.replace(/[-#].*$/, ""));
  const exact = keys.find((k) => {
    const dash = k.lastIndexOf("-");
    const r = chars[k]?.realm ? String(chars[k].realm) : dash > 0 ? k.slice(dash + 1) : "";
    return nameOf(k).toLowerCase() === first.toLowerCase() && realm !== "" && slugPart(r) === realm;
  });
  if (exact) return exact;
  const sameName = keys.filter((k) => nameOf(k).toLowerCase() === first.toLowerCase());
  const noRealm = sameName.filter((k) => k.includes("#"));
  if (noRealm.length === 1) return noRealm[0];
  const legacy = sameName.find((k) => !k.includes("-") && !k.includes("#"));
  if (legacy) return legacy;
  if (sameName.length === 1) return sameName[0];
  if (typeof last === "string" && chars[last]) return last;
  return keys[0];
}

/** Store what the in-game addon exported (the uploader script posts the parsed SavedVariables). */
export async function importAddon(env: Env, db: Obj) {
  const chars = (db?.chars ?? {}) as Record<string, AddonState>;
  const key = pickCharacter(chars, env.CHARACTER_SLUG, db?.last);
  const c = key ? chars[key] : undefined;
  if (!c) throw new Error("Nincs karakteradat a feltöltésben");

  // Fights go to their own table; keep them out of the state blob.
  const fights = await storeFights(env, (c as Obj).fights);
  delete (c as Obj).fights;
  // The auction house scan and the XP samples have their own tables too.
  const scanned = await storeScan(env, (c as Obj).ah);
  delete (c as Obj).ah;
  const xpSamples = await storeXp(env, (c as Obj).xp);
  delete (c as Obj).xp;

  // A scan taken while logging out reports zero gold and empty bags. Never let that replace
  // real data: keep what the previous upload had.
  const emptyScan = !c.money && Object.keys(c.bags ?? {}).length === 0;
  if (emptyScan) {
    const prev = (await loadAddon(env))?.state;
    if (prev) {
      c.money = prev.money;
      c.bags = prev.bags;
      c.bagsAt = prev.bagsAt;
    } else {
      delete c.money;
    }
  }

  const now = new Date().toISOString();
  const put = (k: string, v: string) => statePutStmt(env, k, v, now);

  // Most uploads repeat what is already stored: only write what changed.
  const stmts: D1PreparedStatement[] = [];
  const blob = JSON.stringify(c);
  if ((await stateGet(env, "addon"))?.value !== blob) stmts.push(put("addon", blob));
  if (typeof c.money === "number" && (await stateGet(env, "gold_copper"))?.value !== String(c.money)) {
    stmts.push(put("gold_copper", String(c.money)));
  }

  const trainer = Object.values(c.trainer ?? {});
  // The trainer list only changes when you visit a trainer or learn something.
  const trainerSig = JSON.stringify(
    trainer.map((t) => [t.name, t.rank, t.state, t.cost, t.level]).sort((a, b) => String(a).localeCompare(String(b))),
  );
  const trainerChanged = trainer.length > 0 && (await stateGet(env, "trainer_sig"))?.value !== trainerSig;
  if (trainerChanged) {
    stmts.push(put("trainer_sig", trainerSig));
    stmts.push(env.DB.prepare("DELETE FROM trainer_skills WHERE slug = ?").bind(env.CHARACTER_SLUG));
  }
  for (const t of trainerChanged ? trainer : []) {
    // Older addon versions stored the Forever client's (name, category, icon) as (name, rank, state).
    const STATES = ["available", "unavailable", "used"];
    const state = STATES.includes(String(t.rank)) ? String(t.rank) : STATES.includes(String(t.state)) ? String(t.state) : "unavailable";
    const rank = Number(String(t.rank).match(/\d+/)?.[0] ?? 0);
    stmts.push(
      env.DB.prepare(
        "INSERT INTO trainer_skills (slug, name, rank, required_level, cost_copper, state, learned, tradeskill, updated_at) " +
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(slug, name, rank, required_level) DO UPDATE SET " +
          "cost_copper = excluded.cost_copper, state = excluded.state, learned = excluded.learned, updated_at = excluded.updated_at",
      ).bind(env.CHARACTER_SLUG, t.name, rank, t.level || 0, t.cost || 0, state, state === "used" ? 1 : 0, t.tradeskill ? 1 : 0, now),
    );
  }
  for (let i = 0; i < stmts.length; i += 80) await env.DB.batch(stmts.slice(i, i + 80));
  // Look up what is in the bags and bank, so upgrades already owned can be spotted.
  await queueUnknownItems(env, [...Object.keys(c.bags ?? {}), ...Object.keys(c.bank ?? {})].map(Number));
  return {
    character: c.name,
    money: c.money ?? null,
    keptPrevious: emptyScan,
    bagItems: Object.keys(c.bags ?? {}).length,
    bankItems: Object.keys(c.bank ?? {}).length,
    trainerSkills: trainer.length,
    scanned,
    xpSamples,
    fights,
    spells: Array.isArray(c.spells) ? c.spells.length : 0,
    skills: Object.keys(c.skills ?? {}).length,
    api: c.api ?? null,
    errors: c.errors ?? null,
  };
}

export async function loadAddon(env: Env): Promise<{ state: AddonState; updatedAt: string } | null> {
  const row = await stateGet(env, "addon");
  return row ? { state: JSON.parse(row.value), updatedAt: row.updatedAt } : null;
}

/** Bags + bank, itemId -> count. */
export function ownedItems(state: AddonState | undefined): Map<number, number> {
  const owned = new Map<number, number>();
  for (const src of [state?.bags, state?.bank]) {
    for (const [id, n] of Object.entries(src ?? {})) owned.set(Number(id), (owned.get(Number(id)) ?? 0) + Number(n));
  }
  return owned;
}
