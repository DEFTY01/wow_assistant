import { loadAddon, ownedItems } from "./addon";
import { apiGet } from "./blizzard";
import { CONSUMABLE_ITEM_IDS } from "./buffs";
import { discoverItems, queueUnknownItems, storeAuctionGear } from "./market";
import type { Env } from "./env";
import { latestSnapshots } from "./sync";

type Obj = Record<string, any>;

/** Units used for the "depth" price: average cost of the cheapest N units on the AH. */
const DEPTH = 40;

// Reagents sold by trade-goods vendors in unlimited supply (Classic item IDs).
// Assumption carried over from Classic; for these the vendor price beats the AH.
const VENDOR_REAGENTS = new Set([
  2320, 2321, 4291, 8343, 14341, // threads
  4289, // salt
  2604, 2605, 2325, 4340, 4341, 4342, 6260, 6261, 10290, // dyes
  159, 2678, 2692, 3713, 2894, 2596, 30817, // common cooking vendor goods
]);

// Profession rank caps and where the next rank is trained (Wowhead Forever data).
export const RANKS = [
  { name: "Apprentice", cap: 75, trainAt: 0, cost: 10 },
  { name: "Journeyman", cap: 150, trainAt: 50, cost: 500 },
  { name: "Expert", cap: 225, trainAt: 125, cost: 5000 },
  { name: "Artisan", cap: 300, trainAt: 200, cost: 50000 },
];

// ---------------------------------------------------------------- import

export interface RecipeImport {
  professionId: number;
  recipes: {
    id: number;
    name: string;
    colors: number[];
    creates?: number[];
    reagents?: number[][];
    trainingcost?: number;
    source?: number[];
  }[];
  items?: Record<string, string>;
}

export async function importRecipes(env: Env, data: RecipeImport): Promise<number> {
  const now = new Date().toISOString();
  const stmts: D1PreparedStatement[] = [];
  for (const r of data.recipes) {
    if (!Array.isArray(r.colors) || r.colors.length !== 4 || !r.reagents?.length) continue;
    const qty = r.creates ? (Number(r.creates[1]) + Number(r.creates[2] ?? r.creates[1])) / 2 : 1;
    stmts.push(
      env.DB.prepare(
        "INSERT OR REPLACE INTO recipe_meta (spell_id, profession_id, name, orange, yellow, green, grey, " +
          "creates_item, creates_qty, reagents, training_cost, from_trainer, updated_at) " +
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      ).bind(
        r.id,
        data.professionId,
        r.name,
        Math.max(1, r.colors[0]),
        r.colors[1],
        r.colors[2],
        r.colors[3],
        r.creates?.[0] ?? null,
        qty || 1,
        JSON.stringify(r.reagents),
        r.trainingcost ?? null,
        r.source?.includes(6) ? 1 : 0,
        now,
      ),
    );
  }
  for (const [id, name] of Object.entries(data.items ?? {})) {
    stmts.push(
      env.DB.prepare(
        "INSERT INTO items (item_id, name, updated_at) VALUES (?, ?, ?) " +
          "ON CONFLICT(item_id) DO UPDATE SET name = excluded.name",
      ).bind(Number(id), name, now),
    );
  }
  for (let i = 0; i < stmts.length; i += 80) await env.DB.batch(stmts.slice(i, i + 80));
  return data.recipes.length;
}

// ---------------------------------------------------------------- prices

interface Listing {
  price: number;
  qty: number;
}

/** `gear` collects the cheapest buyout of every fixed-stat (no random suffix) non-commodity item. */
async function fetchListings(
  env: Env,
  houseId: number,
  wanted: Set<number> | null,
  gear?: Map<number, { min: number; n: number }>,
) {
  const byItem = new Map<number, Listing[]>();
  for (const suffix of ["", "/commodities"]) {
    const { status, body } = await apiGet(
      env,
      `/data/wow/ruleset/${env.RULESET_ID}/auctions/${houseId}${suffix}`,
      "dynamic",
    );
    if (status !== 200) throw new Error(`Auction house ${houseId}${suffix}: HTTP ${status}`);
    for (const a of ((body as Obj).auctions ?? []) as Obj[]) {
      const id = a.item?.id as number;
      if (gear && suffix === "" && a.buyout > 0 && !a.item?.bonus_lists && !a.item?.modifiers) {
        const unit = Number(a.buyout) / (Number(a.quantity) || 1);
        const g = gear.get(id);
        if (!g) gear.set(id, { min: unit, n: 1 });
        else {
          g.n++;
          if (unit < g.min) g.min = unit;
        }
      }
      if (wanted && !wanted.has(id)) continue;
      const qty = Number(a.quantity) || 1;
      const price = a.unit_price != null ? Number(a.unit_price) : Number(a.buyout) / qty;
      if (!(price > 0)) continue; // bid-only auctions have no buyout
      let list = byItem.get(id);
      if (!list) byItem.set(id, (list = []));
      list.push({ price, qty });
    }
  }
  return byItem;
}

function summarize(list: Listing[]) {
  list.sort((a, b) => a.price - b.price);
  let need = DEPTH;
  let cost = 0;
  let total = 0;
  for (const l of list) {
    total += l.qty;
    const take = Math.min(need, l.qty);
    cost += take * l.price;
    need -= take;
  }
  const bought = DEPTH - need;
  return {
    min: Math.round(list[0].price),
    depth: Math.round(cost / bought),
    quantity: total,
  };
}

async function reagentIds(env: Env): Promise<Set<number>> {
  const rows = await env.DB.prepare("SELECT reagents, creates_item FROM recipe_meta").all<{
    reagents: string;
    creates_item: number | null;
  }>();
  const ids = new Set<number>();
  for (const r of rows.results) {
    for (const [id] of JSON.parse(r.reagents) as number[][]) ids.add(id);
    if (r.creates_item) ids.add(r.creates_item);
  }
  return ids;
}

export async function syncPrices(env: Env): Promise<{ items: number; house: number; gear: number; queued: number }> {
  const house = Number(env.AUCTION_HOUSE_ID);
  const wanted = await reagentIds(env);
  for (const id of CONSUMABLE_ITEM_IDS) wanted.add(id);
  const gearListings = new Map<number, { min: number; n: number }>();
  const listings = await fetchListings(env, house, wanted, gearListings);
  const now = new Date().toISOString();
  const stmts = [env.DB.prepare("DELETE FROM prices")];
  for (const [id, list] of listings) {
    const s = summarize(list);
    stmts.push(
      env.DB.prepare(
        "INSERT INTO prices (item_id, house_id, min_price, depth_price, quantity, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
      ).bind(id, house, s.min, s.depth, s.quantity, now),
    );
  }
  for (let i = 0; i < stmts.length; i += 80) await env.DB.batch(stmts.slice(i, i + 80));
  const level = Number(((await latestSnapshots(env)).profile?.json as Obj | undefined)?.level) || 60;
  const gear = await storeAuctionGear(env, gearListings, level);
  return { items: listings.size, house, ...gear };
}

/** Price of one item in several auction houses, to find out which house is yours. */
export async function compareHouses(env: Env, itemId: number, houses: number[]) {
  const out: { house: number; min?: number; depth?: number; quantity?: number; error?: string }[] = [];
  for (const house of houses) {
    try {
      const list = (await fetchListings(env, house, new Set([itemId]))).get(itemId);
      out.push(list ? { house, ...summarize(list) } : { house, quantity: 0 });
    } catch (err) {
      out.push({ house, error: String(err) });
    }
  }
  return out;
}

/** Look up vendor prices / names for items we have not asked the Blizzard API about yet. */
export async function syncItems(env: Env, limit = 40): Promise<{ fetched: number; remaining: number }> {
  // Reagents and crafted items join the same queue as auction house and bag items.
  await queueUnknownItems(env, await reagentIds(env));
  return discoverItems(env, limit);
}

// ---------------------------------------------------------------- optimizer

interface Recipe {
  spell_id: number;
  name: string;
  orange: number;
  yellow: number;
  green: number;
  grey: number;
  creates_item: number | null;
  creates_qty: number;
  reagents: [number, number][];
  training_cost: number | null;
  from_trainer: number;
  known: boolean;
}

export interface RouteStep {
  from: number;
  to: number;
  recipe: string;
  known: boolean;
  trainingCost: number;
  crafts: number;
  matsCost: number;
  vendorBack: number;
  reagents: { itemId: number; name: string; qty: number; unit: number | null; source: string }[];
}

export interface Route {
  profession: string;
  professionId: number;
  skill: number;
  cap: number;
  target: number;
  steps: RouteStep[];
  shopping: { itemId: number; name: string; qty: number; unit: number | null; source: string; total: number; owned: number }[];
  /** Value of the reagents already in bags/bank (only known when the addon has uploaded). */
  ownedValue: number;
  totalMats: number;
  totalTraining: number;
  totalVendorBack: number;
  notes: string[];
  unreachableFrom: number | null;
}

/** Classic skill-up chance: 100% while orange, falling linearly from yellow to 0 at grey. */
function skillUpChance(r: Recipe, skill: number): number {
  if (skill < r.orange || skill >= r.grey) return 0;
  if (skill < r.yellow) return 1;
  return (r.grey - skill) / (r.grey - r.yellow);
}

export interface PriceBook {
  unit(itemId: number): { price: number; source: string } | null;
  vendorSell(itemId: number | null): number;
  name(itemId: number): string;
}

export async function loadPriceBook(env: Env): Promise<PriceBook> {
  const [prices, items] = await Promise.all([
    env.DB.prepare("SELECT item_id, depth_price FROM prices").all<{ item_id: number; depth_price: number }>(),
    env.DB.prepare("SELECT item_id, name, vendor_buy, vendor_sell FROM items").all<{
      item_id: number;
      name: string | null;
      vendor_buy: number | null;
      vendor_sell: number | null;
    }>(),
  ]);
  const ah = new Map(prices.results.map((p) => [p.item_id, p.depth_price]));
  const it = new Map(items.results.map((i) => [i.item_id, i]));
  return {
    unit(id) {
      const vendor = VENDOR_REAGENTS.has(id) ? it.get(id)?.vendor_buy : null;
      const auction = ah.get(id);
      if (vendor && (!auction || vendor <= auction)) return { price: vendor, source: "vendor" };
      if (auction) return { price: auction, source: "AH" };
      return null;
    },
    vendorSell: (id) => (id ? (it.get(id)?.vendor_sell ?? 0) : 0),
    name: (id) => it.get(id)?.name ?? `Item #${id}`,
  };
}

function craftCost(r: Recipe, book: PriceBook): number | null {
  let cost = 0;
  for (const [id, qty] of r.reagents) {
    const u = book.unit(id);
    if (!u) return null;
    cost += u.price * qty;
  }
  return cost;
}

interface Plan {
  perPoint: { recipe: Recipe; crafts: number; net: number }[];
  total: number;
  stuckAt: number | null;
}

function greedy(recipes: { r: Recipe; cost: number; net: number }[], skill: number, target: number): Plan {
  const perPoint: Plan["perPoint"] = [];
  let total = 0;
  for (let s = skill; s < target; s++) {
    let best: { recipe: Recipe; crafts: number; net: number } | null = null;
    for (const { r, net } of recipes) {
      const p = skillUpChance(r, s);
      if (p <= 0) continue;
      const crafts = 1 / p;
      const expected = crafts * net;
      if (!best || expected < best.crafts * best.net) best = { recipe: r, crafts, net };
    }
    if (!best) return { perPoint, total, stuckAt: s };
    perPoint.push(best);
    total += best.crafts * best.net;
  }
  return { perPoint, total, stuckAt: null };
}

export async function planRoutes(env: Env, targetOverride?: number): Promise<Route[]> {
  const snaps = await latestSnapshots(env);
  const prof = snaps.professions?.json as Obj | undefined;
  const level = Number((snaps.profile?.json as Obj | undefined)?.level ?? 0);
  if (!prof) return [];
  const book = await loadPriceBook(env);
  // Shared across professions so the same stack is not counted twice.
  const owned = ownedItems((await loadAddon(env))?.state);
  const routes: Route[] = [];

  for (const g of [...(prof.primaries ?? []), ...(prof.secondaries ?? [])] as Obj[]) {
    const tier = g.tiers?.[0] ?? g;
    const professionId = Number(g.profession?.id);
    const skill = Number(tier.skill_points ?? 0);
    const cap = Number(tier.max_skill_points ?? 0);
    const knownNames = new Set<string>((tier.known_recipes ?? []).map((r: Obj) => String(r.name)));

    const rows = await env.DB.prepare("SELECT * FROM recipe_meta WHERE profession_id = ?")
      .bind(professionId)
      .all<Obj>();
    if (!rows.results.length) continue;

    const target = Math.min(targetOverride ?? 300, 300);
    const notes: string[] = [];
    for (const rank of RANKS) {
      if (rank.cap > cap && rank.cap - 75 < target) {
        notes.push(
          `${rank.name} rang (${rank.cap}-ig): ${rank.trainAt}-es skilltől tanulható, ` +
            `${(rank.cost / 10000).toFixed(2)}g a trainernél.` +
            (rank.name === "Artisan" && level < 35 ? " Classic alapján 35-ös szint kell hozzá (nem ellenőrzött)." : ""),
        );
      }
    }

    const all: Recipe[] = rows.results.map((r) => ({
      ...(r as any),
      reagents: JSON.parse(r.reagents),
      known: knownNames.has(r.name),
    }));
    const priced = (list: Recipe[]) =>
      list.flatMap((r) => {
        const cost = craftCost(r, book);
        if (cost == null) return [];
        // Crafted gear can at least be vendored; that lowers the real cost of the step.
        const back = book.vendorSell(r.creates_item) * r.creates_qty;
        return [{ r, cost, net: Math.max(cost - back, cost * 0.02) }];
      });

    const known = priced(all.filter((r) => r.known));
    const trainable = priced(all.filter((r) => !r.known && r.from_trainer && r.training_cost != null));
    const unpricedKnown = all.filter((r) => r.known && r.grey > skill && craftCost(r, book) == null);
    if (unpricedKnown.length) {
      notes.push(
        `Ár nélküli (ezért kihagyott) ismert receptek: ${unpricedKnown.map((r) => r.name).slice(0, 8).join(", ")}` +
          (unpricedKnown.length > 8 ? ` és még ${unpricedKnown.length - 8}` : "") + ".",
      );
    }

    // Start from known recipes, then buy a trainer recipe whenever it pays for itself.
    const chosen = [...known];
    const bought: Recipe[] = [];
    let plan = greedy(chosen, skill, target);
    // A plan that gets stuck earlier is always worse than one that reaches further.
    const score = (p: Plan) => (target - skill - p.perPoint.length) * 1e12 + p.total;
    for (;;) {
      let bestGain = 0;
      let bestIdx = -1;
      let bestPlan: Plan | null = null;
      for (let i = 0; i < trainable.length; i++) {
        const cand = trainable[i];
        if (bought.includes(cand.r)) continue;
        const p = greedy([...chosen, cand], skill, target);
        const gain = score(plan) - (score(p) + (cand.r.training_cost ?? 0));
        if (gain > bestGain) {
          bestGain = gain;
          bestIdx = i;
          bestPlan = p;
        }
      }
      if (bestIdx < 0 || !bestPlan) break;
      chosen.push(trainable[bestIdx]);
      bought.push(trainable[bestIdx].r);
      plan = bestPlan;
    }

    // Collapse consecutive points on the same recipe into steps.
    const steps: RouteStep[] = [];
    const charged = new Set<number>();
    plan.perPoint.forEach((pt, i) => {
      const s = skill + i;
      let step = steps[steps.length - 1];
      if (!step || step.recipe !== pt.recipe.name) {
        const firstUse = !pt.recipe.known && !charged.has(pt.recipe.spell_id);
        charged.add(pt.recipe.spell_id);
        step = {
          from: s,
          to: s,
          recipe: pt.recipe.name,
          known: pt.recipe.known,
          trainingCost: firstUse ? (pt.recipe.training_cost ?? 0) : 0,
          crafts: 0,
          matsCost: 0,
          vendorBack: 0,
          reagents: pt.recipe.reagents.map(([itemId, qty]) => {
            const u = book.unit(itemId);
            return { itemId, name: book.name(itemId), qty: 0, unit: u?.price ?? null, source: u?.source ?? "?", per: qty } as any;
          }),
        };
        steps.push(step);
      }
      step.to = s + 1;
      step.crafts += pt.crafts;
    });
    for (const step of steps) {
      const r = all.find((x) => x.name === step.recipe)!;
      step.crafts = Math.ceil(step.crafts);
      for (const rg of step.reagents as any[]) {
        rg.qty = rg.per * step.crafts;
        step.matsCost += (rg.unit ?? 0) * rg.qty;
        delete rg.per;
      }
      step.vendorBack = Math.round(book.vendorSell(r.creates_item) * r.creates_qty * step.crafts);
    }

    const shop = new Map<number, Route["shopping"][number]>();
    for (const step of steps) {
      for (const rg of step.reagents) {
        const row = shop.get(rg.itemId) ?? { ...rg, qty: 0, total: 0, owned: 0 };
        row.qty += rg.qty;
        row.total += (rg.unit ?? 0) * rg.qty;
        shop.set(rg.itemId, row);
      }
    }

    let ownedValue = 0;
    for (const row of shop.values()) {
      const have = Math.min(row.qty, owned.get(row.itemId) ?? 0);
      if (!have) continue;
      row.owned = have;
      owned.set(row.itemId, (owned.get(row.itemId) ?? 0) - have);
      ownedValue += have * (row.unit ?? 0);
    }

    routes.push({
      ownedValue,
      profession: String(g.profession?.name),
      professionId,
      skill,
      cap,
      target,
      steps,
      shopping: [...shop.values()].sort((a, b) => b.total - a.total),
      totalMats: steps.reduce((a, s) => a + s.matsCost, 0),
      totalTraining: steps.reduce((a, s) => a + s.trainingCost, 0),
      totalVendorBack: steps.reduce((a, s) => a + s.vendorBack, 0),
      notes,
      unreachableFrom: plan.stuckAt,
    });
  }
  return routes;
}
