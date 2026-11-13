import { Hono } from "hono";
import { requireAccess } from "./access";
import { importAddon, loadAddon } from "./addon";
import { apiGet } from "./blizzard";
import { saveSelectedBuffs } from "./buffs";
import { combatReport, storeFights } from "./combat";
import { combatPage } from "./combatView";
import type { Env } from "./env";
import { gearReport, importLoot, type LootImport } from "./gear";
import { gearPage } from "./gearView";
import { buildPlan } from "./plan";
import { planPage } from "./planView";
import { compareHouses, importRecipes, planRoutes, syncItems, syncPrices, type RecipeImport } from "./professions";
import { professionsPage } from "./professionsView";
import { createCharacter, findByKey, inviteCode, listCharacters, removeCharacter, scopedEnv } from "./share";
import { joinPage, setupPanel, sharePanel } from "./shareView";
import { stateGet, statePut } from "./state";
import { latestSnapshots, syncAll } from "./sync";
import { dashboard, type DashboardData } from "./view";

// ====================================================================================
// Character pages. Every handler works on the character in env.CHARACTER_SLUG: the owner's
// by default, or a shared one when the request came in under /u/<key>/ (see below).
// ====================================================================================
const app = new Hono<{ Bindings: Env }>();
const shared = (env: Env) => !!env.SHARE_PREFIX;

async function loadDashboard(env: Env): Promise<DashboardData> {
  const [addon, snapshots, log, gold, skills] = await Promise.all([
    loadAddon(env),
    latestSnapshots(env),
    env.DB.prepare("SELECT kind, status, changed, message, at FROM sync_log WHERE slug = ? ORDER BY id DESC LIMIT 15")
      .bind(env.CHARACTER_SLUG)
      .all<DashboardData["log"][number]>(),
    stateGet(env, "gold_copper"),
    env.DB.prepare(
      "SELECT name, rank, required_level, cost_copper, learned, state FROM trainer_skills WHERE slug = ? " +
        "ORDER BY learned, required_level, name, rank",
    )
      .bind(env.CHARACTER_SLUG)
      .all<DashboardData["trainerSkills"][number]>(),
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

app.get("/", async (c) => {
  const snaps = await latestSnapshots(c.env);
  const classId = Number((snaps.profile?.json as Record<string, any> | undefined)?.character_class?.id);
  return c.html(await planPage(await buildPlan(c.env), { hasProfile: !!snaps.profile, rogue: classId === 4 }));
});

app.get("/character", async (c) => {
  const data = await loadDashboard(c.env);
  const origin = new URL(c.req.url).origin;
  const extra = shared(c.env)
    ? setupPanel({
        origin,
        key: c.env.SHARE_PREFIX!.split("/").pop()!,
        name: String((data.snapshots.profile?.json as Record<string, any> | undefined)?.name ?? ""),
      })
    : sharePanel({ origin, code: await inviteCode(c.env), characters: await listCharacters(c.env) });
  return c.html(await dashboard(data, extra));
});

// Pull everything the plan depends on. Auction prices are shared, so only the owner refreshes them.
app.post("/plan/refresh", async (c) => {
  await syncAll(c.env);
  if (!shared(c.env)) {
    await syncPrices(c.env);
    await syncItems(c.env, 40);
  }
  return c.redirect("/", 303);
});

app.get("/combat", async (c) => c.html(await combatPage(await combatReport(c.env))));

app.post("/gear/buffs", async (c) => {
  const form = await c.req.parseBody({ all: true });
  const picked = form.buff == null ? [] : Array.isArray(form.buff) ? form.buff : [form.buff];
  await saveSelectedBuffs(c.env, picked.map(String));
  return c.redirect("/gear", 303);
});

app.get("/gear", async (c) => c.html(await gearPage(await gearReport(c.env))));

app.get("/professions", async (c) => {
  const target = Math.min(300, Math.max(1, Number(c.req.query("target")) || 225));
  const [routes, at] = await Promise.all([
    planRoutes(c.env, target),
    c.env.DB.prepare("SELECT MAX(updated_at) AS at FROM prices").first<{ at: string | null }>(),
  ]);
  return c.html(await professionsPage(routes, { house: c.env.AUCTION_HOUSE_ID, pricesAt: at?.at ?? null, target }));
});

app.post("/professions/refresh", async (c) => {
  if (!shared(c.env)) {
    await syncPrices(c.env);
    await syncItems(c.env);
  }
  return c.redirect("/professions", 303);
});

app.post("/sync", async (c) => {
  await syncAll(c.env);
  return c.redirect("/character", 303);
});

app.post("/manual/gold", async (c) => {
  const form = await c.req.parseBody();
  const gold = Number(form.gold);
  if (!Number.isFinite(gold) || gold < 0) return c.text("Érvénytelen gold érték", 400);
  await statePut(c.env, "gold_copper", String(Math.round(gold * 10000)));
  return c.redirect("/character", 303);
});

// ------------------------------------------------------------------ owner-only tools
const ownerOnly = new Hono<{ Bindings: Env }>();

ownerOnly.get("/api/plan", async (c) => c.json(await buildPlan(c.env)));
ownerOnly.get("/api/state", async (c) => c.json(await loadDashboard(c.env)));
ownerOnly.get("/api/combat", async (c) => c.json(await combatReport(c.env)));
ownerOnly.get("/api/gear", async (c) => c.json(await gearReport(c.env)));
ownerOnly.get("/api/routes", async (c) => c.json(await planRoutes(c.env, Number(c.req.query("target")) || 225)));

// Read-only explorer for game data endpoints, e.g. /api/raw?path=/data/wow/recipe/55184&ns=static
ownerOnly.get("/api/raw", async (c) => {
  const path = c.req.query("path") ?? "";
  const ns = c.req.query("ns") === "dynamic" ? "dynamic" : "static";
  if (!/^\/data\/wow\/[\w\-\/]+$/.test(path)) return c.text("Csak /data/wow/ útvonal kérhető", 400);
  const { status, body } = await apiGet(c.env, path, ns);
  return c.json({ status, body });
});

// Seed imports of game data (dungeon loot, recipe metadata). Body: JSON as text.
ownerOnly.post("/api/import/loot", async (c) => {
  const data = JSON.parse(await c.req.text()) as LootImport;
  if (!Array.isArray(data?.dungeons) || !Array.isArray(data.items)) return c.text("Hibás import", 400);
  return c.json(await importLoot(c.env, data));
});
ownerOnly.post("/api/import/recipes", async (c) => {
  const data = JSON.parse(await c.req.text()) as RecipeImport;
  if (!Number.isInteger(data?.professionId) || !Array.isArray(data.recipes)) return c.text("Hibás import", 400);
  return c.json({ imported: await importRecipes(c.env, data) });
});

ownerOnly.post("/api/items/sync", async (c) =>
  c.json(await syncItems(c.env, Math.min(400, Number(c.req.query("limit")) || 40))),
);
ownerOnly.post("/api/prices/sync", async (c) => c.json(await syncPrices(c.env)));

// Which auction house is yours? Compare one item's price across houses with the in-game price.
ownerOnly.get("/api/ah/compare", async (c) => {
  const item = Number(c.req.query("item")) || 2319;
  const houses = (c.req.query("houses") ?? "113,114,115,120,124").split(",").map(Number).filter(Boolean);
  return c.json({ item, houses: await compareHouses(c.env, item, houses) });
});

ownerOnly.post("/share/remove", async (c) => {
  const form = await c.req.parseBody();
  await removeCharacter(c.env, String(form.slug ?? ""));
  return c.redirect("/character", 303);
});

// ====================================================================================
// Front door: authentication, uploads, shared links, then the character pages.
// ====================================================================================
const root = new Hono<{ Bindings: Env }>();
root.use("*", requireAccess);

/** Which character an upload token belongs to: the owner's secret, or a shared character's key. */
async function uploadTarget(env: Env, header: string | undefined): Promise<Env | null> {
  const token = header?.startsWith("Bearer ") ? header.slice(7) : "";
  if (env.UPLOAD_TOKEN ? token === env.UPLOAD_TOKEN : !token) return env; // owner (no token configured locally)
  const guest = token ? await findByKey(env, token) : null;
  return guest ? scopedEnv(env, guest.slug, `/u/${guest.share_key}`) : null;
}

// Upload targets for scripts/uploader.mjs: the addon's SavedVariables and the parsed combat log.
root.post("/api/addon", async (c) => {
  const env = await uploadTarget(c.env, c.req.header("Authorization"));
  if (!env) return c.text("Unauthorized", 401);
  return c.json(await importAddon(env, await c.req.json()));
});
root.post("/api/fights", async (c) => {
  const env = await uploadTarget(c.env, c.req.header("Authorization"));
  if (!env) return c.text("Unauthorized", 401);
  return c.json({ stored: await storeFights(env, await c.req.json()) });
});

// --- shared characters -----------------------------------------------------------
root.get("/u/join", async (c) => {
  const code = c.req.query("code") ?? "";
  return c.html(await joinPage({ code, valid: code === (await inviteCode(c.env)) }));
});
root.post("/u/join", async (c) => {
  const form = await c.req.parseBody();
  const code = String(form.code ?? "");
  const name = String(form.name ?? "");
  if (code !== (await inviteCode(c.env))) return c.html(await joinPage({ code, valid: false }), 403);
  const { character, error } = await createCharacter(c.env, name);
  if (!character) return c.html(await joinPage({ code, valid: true, error, name }), 400);
  const prefix = `/u/${character.share_key}`;
  if (!character.last_sync) await syncAll(scopedEnv(c.env, character.slug, prefix));
  return c.redirect(`${prefix}/`, 303);
});

// What a shared link may reach. Everything else stays owner-only.
const SHARED_GET = new Set(["/", "/character", "/gear", "/combat", "/professions"]);
const SHARED_POST = new Set(["/sync", "/manual/gold", "/gear/buffs", "/plan/refresh", "/professions/refresh"]);

root.all("/u/:key/*", async (c) => {
  const guest = await findByKey(c.env, c.req.param("key"));
  if (!guest) return c.text("Ez a link nem érvényes.", 404);
  const prefix = `/u/${guest.share_key}`;
  const url = new URL(c.req.url);
  const inner = url.pathname.slice(prefix.length) || "/";
  const allowed = c.req.method === "GET" ? SHARED_GET : c.req.method === "POST" ? SHARED_POST : null;
  if (!allowed?.has(inner)) return c.text("Ez az oldal megosztott linkről nem érhető el.", 404);

  url.pathname = inner;
  const res = await app.fetch(new Request(url, c.req.raw), scopedEnv(c.env, guest.slug, prefix), c.executionCtx);

  // The pages link to "/gear", "/sync"...: keep the visitor inside their own prefix.
  const location = res.headers.get("Location");
  if (location?.startsWith("/")) {
    const headers = new Headers(res.headers);
    headers.set("Location", prefix + location);
    return new Response(res.body, { status: res.status, headers });
  }
  if (!res.headers.get("Content-Type")?.includes("text/html")) return res;
  const rewrite = (attr: string) => ({
    element(el: Element) {
      const v = el.getAttribute(attr);
      if (v?.startsWith("/") && !v.startsWith("//")) el.setAttribute(attr, prefix + v);
    },
  });
  return new HTMLRewriter().on("a[href]", rewrite("href")).on("form[action]", rewrite("action")).transform(res);
});

root.route("/", ownerOnly);
root.route("/", app);

export default {
  fetch: root.fetch,
  async scheduled(event: ScheduledController, env: Env, ctx: ExecutionContext) {
    const minute = new Date(event.scheduledTime).getUTCMinutes();
    ctx.waitUntil(
      (async () => {
        // The owner every run; shared characters in turn, oldest sync first, a few per run so
        // the API calls of one run stay within the request limits.
        const all = await listCharacters(env);
        const guests = all
          .filter((ch) => !ch.is_owner && ch.share_key)
          .sort((a, b) => (a.last_sync ?? "").localeCompare(b.last_sync ?? ""))
          .slice(0, 5);
        await syncAll(env);
        for (const g of guests) await syncAll(scopedEnv(env, g.slug, `/u/${g.share_key}`));
      })().catch((err) => console.error("character sync failed", err)),
    );
    // Auction data refreshes about hourly, so only pull it on the full hour; in between,
    // look up item stats a few at a time.
    if (minute === 0) ctx.waitUntil(syncPrices(env).catch((err) => console.error("price sync failed", err)));
    else ctx.waitUntil(syncItems(env, 40).catch((err) => console.error("item sync failed", err)));
  },
} satisfies ExportedHandler<Env>;
