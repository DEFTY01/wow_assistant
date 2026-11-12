import type { Env } from "./env";

/** What a buff adds. `statPct` multiplies total Agility and Strength (Blessing of Kings). */
export interface BuffEffect {
  agi?: number;
  str?: number;
  ap?: number;
  crit?: number; // %
  statPct?: number; // 0.10 = +10%
}

interface BuffDef {
  id: string;
  name: string;
  source: string;
  group: "party" | "consumable";
  /** Ranks by the level they become available; the highest one at or below your level is used. */
  tiers: ({ level: number; label?: string } & BuffEffect)[];
}

// Values read from the Wowhead Forever tooltips on 2026-11-12 (they differ from Classic).
// Only buffs that change a rogue's damage are listed. Party buffs use the rank a caster of
// your own level would have.
const BUFFS: BuffDef[] = [
  {
    id: "motw", name: "Mark of the Wild", source: "Druid", group: "party",
    tiers: [
      { level: 10, agi: 3, str: 3 }, { level: 20, agi: 5, str: 5 }, { level: 30, agi: 8, str: 8 },
      { level: 40, agi: 11, str: 11 }, { level: 50, agi: 14, str: 14 }, { level: 60, agi: 16, str: 16 },
    ],
  },
  { id: "kings", name: "Blessing of Kings", source: "Paladin", group: "party", tiers: [{ level: 20, statPct: 0.1 }] },
  {
    id: "might", name: "Blessing of Might", source: "Paladin", group: "party",
    tiers: [
      { level: 4, ap: 14 }, { level: 12, ap: 25 }, { level: 22, ap: 40 }, { level: 32, ap: 61 },
      { level: 42, ap: 83 }, { level: 52, ap: 112 }, { level: 60, ap: 133 },
    ],
  },
  {
    id: "shout", name: "Battle Shout", source: "Warrior", group: "party",
    tiers: [
      { level: 1, ap: 12 }, { level: 12, ap: 24 }, { level: 22, ap: 36 }, { level: 32, ap: 56 },
      { level: 42, ap: 83 }, { level: 52, ap: 116 }, { level: 60, ap: 140 },
    ],
  },
  {
    id: "soe", name: "Strength of Earth Totem", source: "Shaman", group: "party",
    tiers: [{ level: 10, str: 7 }, { level: 24, str: 14 }, { level: 38, str: 25 }, { level: 52, str: 42 }, { level: 60, str: 53 }],
  },
  {
    id: "goa", name: "Grace of Air Totem", source: "Shaman", group: "party",
    tiers: [{ level: 42, agi: 49 }, { level: 56, agi: 77 }, { level: 60, agi: 89 }],
  },
  { id: "lotp", name: "Leader of the Pack", source: "Feral Druid", group: "party", tiers: [{ level: 1, crit: 3 }] },
  {
    id: "elixir-agi", name: "Agility elixir", source: "Alchemy", group: "consumable",
    tiers: [
      { level: 2, agi: 4, label: "Elixir of Minor Agility" }, { level: 18, agi: 8, label: "Elixir of Lesser Agility" },
      { level: 27, agi: 15, label: "Elixir of Agility" }, { level: 38, agi: 25, label: "Elixir of Greater Agility" },
      { level: 46, agi: 25, crit: 2, label: "Elixir of the Mongoose" },
    ],
  },
  {
    id: "scroll-agi", name: "Scroll of Agility", source: "Tekercs", group: "consumable",
    tiers: [
      { level: 10, agi: 5, label: "Scroll of Agility" }, { level: 25, agi: 9, label: "Scroll of Agility II" },
      { level: 40, agi: 13, label: "Scroll of Agility III" }, { level: 55, agi: 17, label: "Scroll of Agility IV" },
    ],
  },
  {
    id: "scroll-str", name: "Scroll of Strength", source: "Tekercs", group: "consumable",
    tiers: [
      { level: 10, str: 5, label: "Scroll of Strength" }, { level: 25, str: 9, label: "Scroll of Strength II" },
      { level: 40, str: 13, label: "Scroll of Strength III" }, { level: 55, str: 17, label: "Scroll of Strength IV" },
    ],
  },
  { id: "firewater", name: "Winterfall Firewater", source: "Felwood", group: "consumable", tiers: [{ level: 45, ap: 35 }] },
  { id: "scorpok", name: "Ground Scorpok Assay", source: "Blasted Lands", group: "consumable", tiers: [{ level: 45, agi: 25 }] },
  { id: "roids", name: "R.O.I.D.S.", source: "Blasted Lands", group: "consumable", tiers: [{ level: 45, str: 25 }] },
  { id: "juju-power", name: "Juju Power", source: "Winterspring", group: "consumable", tiers: [{ level: 55, str: 30 }] },
  { id: "juju-might", name: "Juju Might", source: "Winterspring", group: "consumable", tiers: [{ level: 55, ap: 40 }] },
];

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
  const row = await env.DB.prepare("SELECT value FROM manual_state WHERE key = 'buffs'").first<{ value: string }>();
  try {
    return new Set(row ? (JSON.parse(row.value) as string[]) : []);
  } catch {
    return new Set();
  }
}

export async function saveSelectedBuffs(env: Env, ids: string[]): Promise<void> {
  const known = new Set(BUFFS.map((b) => b.id));
  await env.DB.prepare(
    "INSERT INTO manual_state (key, value, updated_at) VALUES ('buffs', ?, ?) " +
      "ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
  )
    .bind(JSON.stringify(ids.filter((id) => known.has(id))), new Date().toISOString())
    .run();
}
