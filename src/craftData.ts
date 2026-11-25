// Crafting facts shared by the web app and the in-game addon data (scripts/build-addon-recipes.mjs).
// No imports: the build script loads this file directly with Node.

export const PROFESSIONS: Record<number, string> = {
  171: "Alchemy",
  164: "Blacksmithing",
  333: "Enchanting",
  202: "Engineering",
  165: "Leatherworking",
  197: "Tailoring",
  186: "Mining",
  185: "Cooking",
  129: "First Aid",
};

// Reagents sold by trade supply and general goods vendors (vials, thread, flux, dyes, spices...).
export const VENDOR_SOLD = new Set([
  2320, 2321, 4291, 8343, 14341, // threads
  2324, 2604, 2605, 2325, 4340, 4341, 4342, 6260, 6261, 10290, // bleach, dyes
  3371, 3372, 8925, 18256, // vials
  2880, 3466, 3857, 18567, // flux, coal
  4399, 4400, 10647, 10648, 4289, 6217, 11291, 4470, // stocks, ink, parchment, salt, rod, wood
  159, 1179, 2665, 2678, 2692, 3713, 2894, 2596, 30817, // cooking goods
]);

// Recipes with a cooldown (Wowhead Forever, 2026-11-25): one craft per cooldown, in seconds.
export const COOLDOWN: Record<number, number> = {
  11479: 3600, // Transmute: Iron to Gold
  11480: 3600, // Transmute: Mithril to Truesilver
  17187: 169171, // Transmute: Arcanite (1.958 days)
  17559: 82800, 17560: 82800, 17561: 82800, 17562: 82800, // elemental transmutes, 23 hours
  17563: 82800, 17564: 82800, 17565: 82800, 17566: 82800,
  25146: 600, // Transmute: Elemental Fire
  18560: 341971, // Mooncloth (3.958 days)
};
