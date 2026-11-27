// Builds addon/WowAssistant/TalentData.lua: Forever's talent trees for every class, from the data
// behind Wowhead's Forever talent calculator (wowhead.com/forever/talent-calc): each talent's tree,
// row, column, icon, ranks (one spell per rank), prerequisite, the points its row needs, and the
// tooltip text of every rank with the numbers read out of it. Forever has its own talents (the
// rogue's Efficient Strikes and Coup de Grace, the mage's Heating Up), so Classic data will not do.
//
// The tree's shape also comes from the game client (Talent.lua reads it); this file adds what the
// client does not say: the text and numbers of the ranks you do not have, and which spell is which
// rank. Talent.lua matches the two by talent name and reports where they differ.
//
// The raw data is cached in data/talent-calc.json (--refresh fetches it again). Both outputs are
// generated Wowhead data and stay out of the repo.
//
//   node scripts/build-talents.mjs [--refresh] [--install]
import { readFileSync, writeFileSync, existsSync, mkdirSync, copyFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const addonDir = join(root, "addon", "WowAssistant");
const cacheFile = join(root, "data", "talent-calc.json");
const out = join(addonDir, "TalentData.lua");
const PAGE = "https://www.wowhead.com/forever/talent-calc";
const UA = { "User-Agent": "Mozilla/5.0" };

// The first WH.setPageData("...", {...}) object in a script: the JSON between its braces.
function pageData(text) {
  const at = text.indexOf("WH.setPageData(");
  if (at < 0) throw new Error("no WH.setPageData in the talent data");
  const start = text.indexOf("{", at);
  let depth = 0, inStr = false, i = start;
  for (; i < text.length; i++) {
    const c = text[i];
    if (inStr) { if (c === "\\") i++; else if (c === '"') inStr = false; continue; }
    if (c === '"') inStr = true;
    else if (c === "{") depth++;
    else if (c === "}" && --depth === 0) break;
  }
  return JSON.parse(text.slice(start, i + 1));
}

let raw;
if (existsSync(cacheFile) && !process.argv.includes("--refresh")) {
  raw = JSON.parse(readFileSync(cacheFile, "utf8"));
} else {
  const page = await (await fetch(PAGE, { headers: UA })).text();
  const m = page.match(/https:\/\/nether\.wowhead\.com\/forever\/data\/talents-classic\?[^"' ]+/);
  if (!m) throw new Error(`no talent data script on ${PAGE}`);
  const url = m[0].replace(/&amp;/g, "&");
  const res = await fetch(url, { headers: UA });
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
  const data = pageData(await res.text());
  raw = { fetched: new Date().toISOString().slice(0, 10), url, trees: data.trees, talents: data.talents, hashVersion: data.hashVersion };
  mkdirSync(dirname(cacheFile), { recursive: true });
  writeFileSync(cacheFile, JSON.stringify(raw));
}

// Wowhead's tree names ("MageFire", "WarlockCurses") -> class, the in-game tab (the Classic order,
// as Enchant.lua's role table uses it) and the name players know.
const CLASSES = ["Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid"];
const TREES = {
  Warrior: { Arms: [1, "Arms"], Fury: [2, "Fury"], Protection: [3, "Protection"] },
  Paladin: { Holy: [1, "Holy"], Protection: [2, "Protection"], Combat: [3, "Retribution"] },
  Hunter: { BeastMastery: [1, "Beast Mastery"], Marksmanship: [2, "Marksmanship"], Survival: [3, "Survival"] },
  Rogue: { Assassination: [1, "Assassination"], Combat: [2, "Combat"], Subtlety: [3, "Subtlety"] },
  Priest: { Discipline: [1, "Discipline"], Holy: [2, "Holy"], Shadow: [3, "Shadow"] },
  Shaman: { ElementalCombat: [1, "Elemental"], Enhancement: [2, "Enhancement"], Restoration: [3, "Restoration"] },
  Mage: { Arcane: [1, "Arcane"], Fire: [2, "Fire"], Frost: [3, "Frost"] },
  Warlock: { Curses: [1, "Affliction"], Summoning: [2, "Demonology"], Destruction: [3, "Destruction"] },
  Druid: { Balance: [1, "Balance"], FeralCombat: [2, "Feral Combat"], Restoration: [3, "Restoration"] },
};
const ROLE = { 0: "tank", 1: "healer", 2: "dps" };

// Lua 5.1 string: no \u escapes, so control characters go as \ddd.
const luaStr = (s) => '"' + String(s).replace(/[\\"]/g, (c) => "\\" + c).replace(/\r?\n/g, "\\n")
  .replace(/[\x00-\x1f]/g, (c) => "\\" + c.charCodeAt(0)) + '"';
// The numbers of a rank's text, in order ("by 0.1 sec", "by 7%", "3 Energy"): what a rank changes.
const numbers = (s) => [...String(s).matchAll(/\d+(?:\.\d+)?/g)].map((m) => Number(m[0]));

const byClass = {};
const problems = [];
for (const [id, tree] of Object.entries(raw.trees)) {
  const cls = CLASSES.find((c) => tree.description.startsWith(c));
  const key = cls && tree.description.slice(cls.length);
  const known = cls && TREES[cls][key];
  if (!known) { problems.push(`ismeretlen fa: ${id} ${tree.description}`); continue; }
  const c = (byClass[cls.toUpperCase()] ??= { trees: [], talents: [] });
  c.trees.push({ id: Number(id), key, tab: known[0], name: known[1], role: ROLE[tree.role] ?? "dps" });
  const talents = Object.values(raw.talents[id] ?? {});
  const nameOf = Object.fromEntries(talents.map((t) => [t.id, t.name]));
  for (const t of talents.sort((a, b) => a.row - b.row || a.col - b.col)) {
    const ranks = t.ranks.length;
    const desc = [], vals = [];
    for (let r = 1; r <= ranks; r++) {
      const d = (t.descriptions?.[r] ?? "").replace(/\s+/g, " ").trim();
      if (!d) problems.push(`${cls} ${t.name}: nincs leírás a(z) ${r}. ranghoz`);
      desc.push(d);
      vals.push(numbers(d));
    }
    const req = t.requires?.[0];
    if (req && !nameOf[req.id]) problems.push(`${cls} ${t.name}: az előfeltétel (${req.id}) nincs a fában`);
    c.talents.push({ name: t.name, tree: Number(id), tier: t.row + 1, col: t.col + 1, max: ranks, icon: t.icon, spells: t.ranks,
      req: req && nameOf[req.id] ? [nameOf[req.id], req.qty] : null, reqPoints: t.requiredPoints ?? t.row * 5, desc, vals });
  }
}

const lines = [
  `-- Generated by scripts/build-talents.mjs on ${new Date().toISOString().slice(0, 10)} from Wowhead's Forever talent calculator data`,
  `-- (${PAGE}, data fetched ${raw.fetched}, layout ${raw.hashVersion}). Do not edit.`,
  "-- CLASS = { trees = { { id, key, tab (the Classic tab order), name, role } },",
  "--   talents = { { name, tree, tier, col, max, icon, spells = { per rank }, req = { talent, rank } or nil, reqPoints,",
  "--                 desc = { per rank }, vals = { { the numbers of that rank's text } } } } }",
  "WowAssistantTalents = {",
  `  source = ${luaStr(PAGE)}, fetched = ${luaStr(raw.fetched)},`,
];
let total = 0;
for (const cls of Object.keys(byClass).sort()) {
  const c = byClass[cls];
  c.trees.sort((a, b) => a.tab - b.tab);
  lines.push(`  ${cls} = {`, "    trees = {");
  for (const t of c.trees) lines.push(`      { id = ${t.id}, key = ${luaStr(t.key)}, tab = ${t.tab}, name = ${luaStr(t.name)}, role = ${luaStr(t.role)} },`);
  lines.push("    },", "    talents = {");
  for (const t of c.talents) {
    total++;
    lines.push(`      { name = ${luaStr(t.name)}, tree = ${t.tree}, tier = ${t.tier}, col = ${t.col}, max = ${t.max}, icon = ${luaStr(t.icon)},` +
      ` spells = { ${t.spells.join(", ")} }, req = ${t.req ? `{ ${luaStr(t.req[0])}, ${t.req[1]} }` : "nil"}, reqPoints = ${t.reqPoints},` +
      ` desc = { ${t.desc.map(luaStr).join(", ")} }, vals = { ${t.vals.map((v) => `{ ${v.join(", ")} }`).join(", ")} } },`);
  }
  lines.push("    },", "  },");
}
lines.push("}", "");
writeFileSync(out, lines.join("\n"));
console.log(`${out}: ${Object.keys(byClass).length} kaszt, ${total} talent (adat: ${raw.fetched})`);
for (const cls of Object.keys(byClass).sort()) {
  console.log(`  ${cls}: ${byClass[cls].trees.map((t) => `${t.name} ${byClass[cls].talents.filter((x) => x.tree === t.id).length}`).join(", ")}`);
}
for (const p of problems) console.log(`  figyelem: ${p}`);
if (process.argv.includes("--install")) {
  const game = process.env.WOW_ADDON_DIR ?? "F:/World of Warcraft/_forever_/Interface/AddOns/WowAssistant";
  copyFileSync(out, join(game, "TalentData.lua"));
  console.log(`telepítve: ${game}`);
}
