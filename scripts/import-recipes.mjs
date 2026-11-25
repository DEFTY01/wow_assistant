// Loads recipe lists saved from the Wowhead Forever profession pages into the app.
//
// Each file in data/wowhead/<professionId>.json holds what the page's listviewspells and g_items
// contain, in short form: { p: professionId, r: [[spellId, name, colors, creates, reagents,
// trainingCost, sources], ...], i: { itemId: [name, sellPrice] } }.
//
// Usage: node scripts/import-recipes.mjs [APP_URL]   (default: the local app, http://127.0.0.1:8787)
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const app = (process.argv[2] ?? process.env.APP_URL ?? "http://127.0.0.1:8787").replace(/\/$/, "");
const dir = join(import.meta.dirname, "..", "data", "wowhead");

for (const file of readdirSync(dir).filter((f) => /^\d+\.json$/.test(f))) {
  const d = JSON.parse(readFileSync(join(dir, file), "utf8"));
  const body = {
    professionId: d.p,
    recipes: d.r.map(([id, name, colors, creates, reagents, trainingcost, source]) => ({
      id, name, colors, creates: creates ?? undefined, reagents, trainingcost: trainingcost ?? undefined, source,
    })),
    items: Object.fromEntries(Object.entries(d.i).map(([id, [name]]) => [id, name])),
    sell: Object.fromEntries(Object.entries(d.i).filter(([, v]) => v[1] != null).map(([id, [, sell]]) => [id, sell])),
  };
  const res = await fetch(`${app}/api/import/recipes`, { method: "POST", body: JSON.stringify(body) });
  console.log(`${file}: ${res.status} ${await res.text()}`);
}
