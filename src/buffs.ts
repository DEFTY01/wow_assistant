import { BUFFS, type BuffEffect, CONSUMABLE_ITEMS } from "./buffData";
import type { Env } from "./env";
import { stateGet, statePut } from "./state";
export type { BuffEffect };

export const CONSUMABLE_ITEM_IDS = Object.values(CONSUMABLE_ITEMS).map((c) => c.itemId);

export interface Consumable {
  name: string;
  itemId: number;
  minutes: number;
  effect: BuffEffect;
  summary: string;
}

/** Every consumable usable at this level, weaker ranks included (they can be the better deal). */
export function consumablesFor(level: number): Consumable[] {
  const out: Consumable[] = [];
  for (const b of BUFFS) {
    if (b.group !== "consumable") continue;
    for (const tier of b.tiers) {
      if (tier.level > level) continue;
      const { level: _level, label, ...effect } = tier;
      const name = label ?? b.name;
      const item = CONSUMABLE_ITEMS[name];
      if (item) out.push({ name, ...item, effect, summary: describe(effect) });
    }
  }
  return out;
}

export interface ResolvedBuff {
  id: string;
  name: string;
  source: string;
  group: "party" | "consumable";
  /** null when no rank is available at this level yet. */
  effect: BuffEffect | null;
  summary: string;
  selected: boolean;
}

function describe(e: BuffEffect): string {
  const bits: string[] = [];
  if (e.agi && e.str && e.agi === e.str) bits.push(`+${e.agi} minden stat`);
  else {
    if (e.agi) bits.push(`+${e.agi} agi`);
    if (e.str) bits.push(`+${e.str} str`);
  }
  if (e.ap) bits.push(`+${e.ap} AP`);
  if (e.crit) bits.push(`+${e.crit}% crit`);
  if (e.statPct) bits.push(`+${Math.round(e.statPct * 100)}% statok`);
  return bits.join(", ");
}

export function resolveBuffs(level: number, selected: Set<string>): ResolvedBuff[] {
  return BUFFS.map((b) => {
    const tier = [...b.tiers].reverse().find((t) => t.level <= level);
    if (!tier) {
      return {
        id: b.id, name: b.name, source: b.source, group: b.group, effect: null,
        summary: `${b.tiers[0].level}-es szinttől`, selected: false,
      };
    }
    const { level: _level, label, ...effect } = tier;
    return {
      id: b.id, name: label ?? b.name, source: b.source, group: b.group, effect,
      summary: describe(effect), selected: selected.has(b.id),
    };
  });
}

export async function loadSelectedBuffs(env: Env): Promise<Set<string>> {
  const row = await stateGet(env, "buffs");
  try {
    return new Set(row ? (JSON.parse(row.value) as string[]) : []);
  } catch {
    return new Set();
  }
}

export async function saveSelectedBuffs(env: Env, ids: string[]): Promise<void> {
  const known = new Set(BUFFS.map((b) => b.id));
  await statePut(env, "buffs", JSON.stringify(ids.filter((id) => known.has(id))));
}
