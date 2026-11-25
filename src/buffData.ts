// Buff and consumable facts shared by the web app and the in-game addon data
// (scripts/build-addon-recipes.mjs). No imports: the build script loads this file directly with Node.

/** What a buff adds. `statPct` multiplies total Agility and Strength (Blessing of Kings). */
export interface BuffEffect {
  agi?: number;
  str?: number;
  ap?: number;
  crit?: number; // %
  statPct?: number; // 0.10 = +10%
}

export interface BuffDef {
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
export const BUFFS: BuffDef[] = [
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

// Item id and duration of each consumable, keyed by its name (ids from the Wowhead Forever database).
export const CONSUMABLE_ITEMS: Record<string, { itemId: number; minutes: number }> = {
  "Elixir of Minor Agility": { itemId: 2457, minutes: 60 },
  "Elixir of Lesser Agility": { itemId: 3390, minutes: 60 },
  "Elixir of Agility": { itemId: 8949, minutes: 60 },
  "Elixir of Greater Agility": { itemId: 9187, minutes: 60 },
  "Elixir of the Mongoose": { itemId: 13452, minutes: 60 },
  "Scroll of Agility": { itemId: 3012, minutes: 30 },
  "Scroll of Agility II": { itemId: 1477, minutes: 30 },
  "Scroll of Agility III": { itemId: 4425, minutes: 30 },
  "Scroll of Agility IV": { itemId: 10309, minutes: 30 },
  "Scroll of Strength": { itemId: 954, minutes: 30 },
  "Scroll of Strength II": { itemId: 2289, minutes: 30 },
  "Scroll of Strength III": { itemId: 4426, minutes: 30 },
  "Scroll of Strength IV": { itemId: 10310, minutes: 30 },
  "Winterfall Firewater": { itemId: 12820, minutes: 20 },
  "Juju Power": { itemId: 12451, minutes: 30 },
  "Juju Might": { itemId: 12460, minutes: 10 },
};
