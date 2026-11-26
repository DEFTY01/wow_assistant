// Builds addon/WowAssistant/Enchants.lua: every enchant the enchanting recipes can put on gear,
// with what it gives on Forever. The recipes come from Recipes.lua (build-addon-recipes.mjs); the
// effect of each enchant from its Wowhead Forever spell tooltip ("Permanently enchant bracers so
// they increase the wearer's Stamina by 3."), fetched once and cached in data/enchant-tooltips.json.
// Forever's values differ from Classic's (Minor Stamina on bracers is +3 there, +1 in Classic), so
// they are read, not assumed. Both outputs are generated Wowhead data and stay out of the repo.
//
//   node scripts/build-enchants.mjs [--install]
import { readFileSync, writeFileSync, existsSync, mkdirSync, copyFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const addonDir = join(root, "addon", "WowAssistant");
const cacheFile = join(root, "data", "enchant-tooltips.json");
const out = join(addonDir, "Enchants.lua");

// recipe rows: {spell,profession,skill,product,min,max,trainerCost,cooldown,"name",{reagents},"sources",yellow,grey}
const recipesLua = readFileSync(join(addonDir, "Recipes.lua"), "utf8");
const rows = [];
for (const m of recipesLua.matchAll(/^\s*\{(\d+),333,(\d+),(\d+),\d+,\d+,(-?\d+),\d+,"(Enchant [^"]+)",\{([^}]*)\},"([^"]*)",/gm)) {
  const [, spell, skill, product, trainerCost, name, reagents, sources] = m;
  if (Number(product) !== 0) continue; // an item (a rod, an oil), not an enchant on gear
  rows.push({ spell: Number(spell), skill: Number(skill), trainerCost: Number(trainerCost), name, reagents: reagents ? reagents.split(",").map(Number) : [], sources });
}

// The slot from the name: "Enchant Bracer - Minor Stamina", "Enchant 2H Weapon - Lesser Impact".
const SLOT = {
  Bracer: "WRIST", Bracers: "WRIST", Chest: "CHEST", Cloak: "BACK", Boots: "FEET", Gloves: "HANDS", Shield: "OFF_HAND",
  Weapon: "MAIN_HAND", "2H Weapon": "MAIN_HAND", Helm: "HEAD", Legs: "LEGS", Shoulder: "SHOULDER", Shoulders: "SHOULDER",
  Ring: "FINGER", Belt: "WAIST",
};

const cache = existsSync(cacheFile) ? JSON.parse(readFileSync(cacheFile, "utf8")) : {};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let fetched = 0;
for (const r of rows) {
  if (cache[r.spell]) continue;
  const res = await fetch(`https://nether.wowhead.com/forever/tooltip/spell/${r.spell}`, { headers: { "User-Agent": "Mozilla/5.0" } });
  if (!res.ok) { console.warn(`spell ${r.spell}: HTTP ${res.status}`); continue; }
  const j = await res.json();
  cache[r.spell] = (j.tooltip ?? "").replace(/<[^>]+>/g, " ").replace(/&nbsp;/g, " ").replace(/\s+/g, " ").trim();
  fetched++;
  await sleep(150);
}
mkdirSync(dirname(cacheFile), { recursive: true });
writeFileSync(cacheFile, JSON.stringify(cache, null, 1));

// The effect sentence -> stats. Only exact, stated numbers. Forever words them many ways ("increases
// the wearer's Stamina by 3", "to give +5 Stamina", "to add 5 to Intellect", "to grant +15 Agility"),
// so a primary stat is its word plus the sentence's number. Procs ("often", "a chance to", "trigger")
// are kept as text, not valued: how often they happen is not stated.
const SCHOOLS = "nature|arcane|fire|frost|holy|shadow";
function parse(text) {
  const t = text.toLowerCase();
  const nums = [...t.matchAll(/\d+/g)].map((m) => Number(m[0]));
  const st = {};
  const proc = /often|trigger|have a chance|chance per hit|small chance|chance of/.test(t);
  if (proc) return { stats: st, proc };
  let m;
  if (/heal/.test(t) && /damage/.test(t)) {
    if (/damage and healing/.test(t)) { st.heal = nums[0]; st.sp = nums[0]; }
    else { st.heal = nums[0]; st.sp = nums[1]; }
  } else if ((m = t.match(new RegExp(`(${SCHOOLS}) damage by up to ([0-9]+)`)))) st["sp_" + m[1]] = Number(m[2]);
  else if ((m = t.match(new RegExp(`([0-9]+) additional (${SCHOOLS}) damage when casting`)))) st["sp_" + m[2]] = Number(m[1]);
  else if (/spell power|damage to spells/.test(t)) st.sp = nums[0];
  else if (/all stats/.test(t)) for (const k of ["str", "agi", "sta", "int", "spi"]) st[k] = nums[0];
  else if (/all (?:resistances|schools)/.test(t)) st.resAll = nums[0];
  else if ((m = t.match(new RegExp(`resistance to (${SCHOOLS})|(${SCHOOLS}) resistance`)))) st["res_" + (m[1] ?? m[2])] = nums[0];
  else if (/armor/.test(t)) st.armor = nums[0];
  else if (/defense/.test(t)) st.def = nums[0];
  else if (/chance to dodge/.test(t)) st.dodge = nums[0];
  else if (/chance to block/.test(t)) st.block = nums[0];
  else if (/critical strike chance/.test(t)) st.crit = nums[0];
  else if (/attack and casting speed/.test(t)) st.haste = nums[0];
  else if (/mana every 5/.test(t)) st.mp5 = nums[0];
  else if (/threat/.test(t)) st.threat = /decrease/.test(t) ? -nums[0] : nums[0];
  else if (/movement speed/.test(t)) st.run = nums[0];
  else if ((m = t.match(/(mining|herbalism|skinning|fishing) skill/))) st[m[1]] = nums[0];
  else if (/damage to beasts|against elementals|demons/.test(t)) st.dmgVs = nums[0];
  else if (/additional points? of damage|\+\d+ damage/.test(t)) st.dmg = nums[0];
  else if ((m = t.match(/(strength|agility|stamina|intellect|spirit)/))) st[{ strength: "str", agility: "agi", stamina: "sta", intellect: "int", spirit: "spi" }[m[1]]] = nums[0];
  for (const k of Object.keys(st)) if (!Number.isFinite(st[k])) delete st[k];
  return { stats: st, proc };
}
const enchants = [];
for (const r of rows) {
  const slotName = r.name.match(/^Enchant (.+?) - /)?.[1];
  const slot = SLOT[slotName];
  if (!slot) continue;
  const tip = cache[r.spell] ?? "";
  const text = tip.match(/(?:Permanently enchant|Enchant (?:a |an ))[^.]*(?:\.\d+)?[^.]*\.(?: Cannot[^.]*\.)?/)?.[0] ?? "";
  const { stats, proc } = parse(text);
  enchants.push({ ...r, slot, twoHand: slotName === "2H Weapon", text, stats, proc });
}

const lua = (v) => typeof v === "string" ? JSON.stringify(v) : String(v);
const lines = [
  `-- Generated by scripts/build-enchants.mjs on ${new Date().toISOString().slice(0, 10)} from Wowhead Forever spell tooltips. Do not edit.`,
  "-- { spell, slot, twoHand, name, enchanting skill, trainer cost (-1: not from a trainer), { reagent, qty, ... },",
  "--   stats = { str agi sta int spi, armor def dodge block, heal sp sp_<school>, mp5, dmg dmgVs, crit haste, resAll res_<school>,",
  "--             threat run <gathering skill> }, proc, text }",
  "WowAssistantEnchants = {",
  ...enchants.map((e) => `  { ${e.spell}, ${lua(e.slot)}, ${e.twoHand}, ${lua(e.name)}, ${e.skill}, ${e.trainerCost}, { ${e.reagents.join(", ")} }, ` +
    `{ ${Object.entries(e.stats).map(([k, v]) => `${k} = ${v}`).join(", ")} }, ${e.proc}, ${lua(e.text)} },`),
  "}",
  "",
];
writeFileSync(out, lines.join("\n"));
const noStats = enchants.filter((e) => !e.proc && Object.keys(e.stats).length === 0);
console.log(`${out}: ${enchants.length} enchant (${fetched} tooltip letöltve, ${enchants.filter((e) => e.proc).length} proc, ${noStats.length} szám nélkül)`);
for (const e of noStats.slice(0, 40)) console.log(`  szám nélkül: ${e.name}: ${e.text}`);
if (process.argv.includes("--install")) {
  const game = process.env.WOW_ADDON_DIR ?? "F:/World of Warcraft/_forever_/Interface/AddOns/WowAssistant";
  copyFileSync(out, join(game, "Enchants.lua"));
  console.log(`telepítve: ${game}`);
}
