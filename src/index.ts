import { Hono } from "hono";
import { importAddon, loadAddon } from "./addon";
import { apiGet } from "./blizzard";
import { saveSelectedBuffs } from "./buffs";
import { combatReport, storeFights } from "./combat";
import { combatPage } from "./combatView";
import type { Env } from "./env";
import { gearReport, importLoot, type LootImport } from "./gear";
import { gearPage } from "./gearView";
import { compareHouses, importRecipes, planRoutes, syncItems, syncPrices, type RecipeImport } from "./professions";
import { professionsPage } from "./professionsView";
import { latestSnapshots, syncAll } from "./sync";
import { dashboard, type DashboardData } from "./view";

// NOTE: there is no auth in the app itself. Before exposing it on a public
// domain, put it behind Cloudflare Access so only you can reach it.
const app = new Hono<{ Bindings: Env }>();

async function loadDashboard(env: Env): Promise<DashboardData> {
  const [addon, snapshots, log, gold, skills] = await Promise.all([
    loadAddon(env),
    latestSnapshots(env),
    env.DB.prepare(
      "SELECT kind, status, changed, message, at FROM sync_log ORDER BY id DESC LIMIT 15",
    ).all<DashboardData["log"][number]>(),
    env.DB.prepare("SELECT value FROM manual_state WHERE key = 'gold_copper'").first<{
      value: string;
    }>(),
    env.DB.prepare(
      "SELECT name, rank, required_level, cost_copper, learned, state FROM trainer_skills " +
        "ORDER BY learned, required_level, name, rank",
    ).all<DashboardData["trainerSkills"][number]>(),
  ]);
  return {
    slug: env.CHARACTER_SLUG,
    snapshots,
    log: log.results,
    goldCopper: gold ? Number(gold.value) : null,
    trainerSkills: skills.results,
    addon: addon
      ? {
          updatedAt: addon.updatedAt,
          bagItems: Object.keys(addon.state.bags ?? {}).length,
          bankItems: addon.state.bankAt ? Object.keys(addon.state.bank ?? {}).length : null,
          skills: Object.entries(addon.state.skills ?? {}).map(([name, s]) => ({ name, rank: s.rank, max: s.max })),
        }
      : null,
  };
}

app.get("/", async (c) => c.html(await dashboard(await loadDashboard(c.env))));

app.get("/api/state", async (c) => c.json(await loadDashboard(c.env)));

// Read-only explorer for game data endpoints, e.g. /api/raw?path=/data/wow/recipe/55184&ns=static
app.get("/api/raw", async (c) => {
  const path = c.req.query("path") ?? "";
  const ns = c.req.query("ns") === "dynamic" ? "dynamic" : "static";
  if (!/^\/data\/wow\/[\w\-\/]+$/.test(path)) return c.text("Csak /data/wow/ útvonal kérhető", 400);
  const { status, body } = await apiGet(c.env, path, ns);
  return c.json({ status, body });
});

// Upload target for scripts/uploader.mjs (parsed SavedVariables of the in-game addon).
app.post("/api/addon", async (c) => {
  if (c.env.UPLOAD_TOKEN && c.req.header("Authorization") !== `Bearer ${c.env.UPLOAD_TOKEN}`) {
    return c.text("Unauthorized", 401);
  }
  return c.json(await importAddon(c.env, await c.req.json()));
});

// Fights parsed from the game's combat log file by scripts/uploader.mjs.
app.post("/api/fights", async (c) => {
  if (c.env.UPLOAD_TOKEN && c.req.header("Authorization") !== `Bearer ${c.env.UPLOAD_TOKEN}`) {
    return c.text("Unauthorized", 401);
  }
  return c.json({ stored: await storeFights(c.env, await c.req.json()) });
});

app.get("/combat", async (c) => c.html(await combatPage(await combatReport(c.env))));
app.get("/api/combat", async (c) => c.json(await combatReport(c.env)));

app.post("/gear/buffs", async (c) => {
  const form = await c.req.parseBody({ all: true });
  const picked = form.buff == null ? [] : Array.isArray(form.buff) ? form.buff : [form.buff];
  await saveSelectedBuffs(c.env, picked.map(String));
  return c.redirect("/gear", 303);
});

app.get("/gear", async (c) => c.html(await gearPage(await gearReport(c.env))));
app.get("/api/gear", async (c) => c.json(await gearReport(c.env)));

// Seed import of dungeon loot. Body: JSON as text.
app.post("/api/import/loot", async (c) => {
  const data = JSON.parse(await c.req.text()) as LootImport;
  if (!Array.isArray(data?.dungeons) || !Array.isArray(data.items)) return c.text("Hibás import", 400);
  return c.json(await importLoot(c.env, data));
});

app.get("/professions", async (c) => {
  const target = Math.min(300, Math.max(1, Number(c.req.query("target")) || 225));
  const [routes, at] = await Promise.all([
    planRoutes(c.env, target),
    c.env.DB.prepare("SELECT MAX(updated_at) AS at FROM prices").first<{ at: string | null }>(),
  ]);
  return c.html(
    await professionsPage(routes, { house: c.env.AUCTION_HOUSE_ID, pricesAt: at?.at ?? null, target }),
  );
});

app.get("/api/routes", async (c) => c.json(await planRoutes(c.env, Number(c.req.query("target")) || 225)));

app.post("/professions/refresh", async (c) => {
  await syncPrices(c.env);
  await syncItems(c.env);
  return c.redirect("/professions", 303);
});

app.post("/api/items/sync", async (c) => c.json(await syncItems(c.env)));
app.post("/api/prices/sync", async (c) => c.json(await syncPrices(c.env)));

// Which auction house is yours? Compare one item's price across houses with the in-game price.
app.get("/api/ah/compare", async (c) => {
  const item = Number(c.req.query("item")) || 2319;
  const houses = (c.req.query("houses") ?? "113,114,115,120,124").split(",").map(Number).filter(Boolean);
  return c.json({ item, houses: await compareHouses(c.env, item, houses) });
});

// Seed import of recipe metadata (skill thresholds, reagents, trainer cost). Body: JSON as text.
app.post("/api/import/recipes", async (c) => {
  const data = JSON.parse(await c.req.text()) as RecipeImport;
  if (!Number.isInteger(data?.professionId) || !Array.isArray(data.recipes)) return c.text("Hibás import", 400);
  return c.json({ imported: await importRecipes(c.env, data) });
});

app.post("/sync", async (c) => {
  await syncAll(c.env);
  return c.redirect("/", 303);
});

app.post("/manual/gold", async (c) => {
  const form = await c.req.parseBody();
  const gold = Number(form.gold);
  if (!Number.isFinite(gold) || gold < 0) return c.text("Érvénytelen gold érték", 400);
  await c.env.DB.prepare(
    "INSERT INTO manual_state (key, value, updated_at) VALUES ('gold_copper', ?, ?) " +
      "ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
  )
    .bind(String(Math.round(gold * 10000)), new Date().toISOString())
    .run();
  return c.redirect("/", 303);
});

export default {
  fetch: app.fetch,
  async scheduled(_event: ScheduledController, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(syncAll(env));
    // Auction data refreshes about hourly, so only pull it on the full hour.
    if (new Date(_event.scheduledTime).getUTCMinutes() === 0) {
      ctx.waitUntil(syncPrices(env).catch((err) => console.error("price sync failed", err)));
    }
  },
} satisfies ExportedHandler<Env>;
