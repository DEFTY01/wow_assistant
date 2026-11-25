// Crafting to sell to a vendor: which recipes make something a vendor pays more for than the
// reagents cost, buying the reagents on the auction house (or from a vendor when that is cheaper).
//
// Costs come from the stored order book, not an average: the first craft uses the cheapest units
// listed, the next one the next cheapest, and so on. A batch stops at the craft where buying more
// reagents would cost more than the vendor pays. Listings that are not commodities can only be
// bought as a whole stack; the extra units are counted as spent and carried into the next crafts.
import type { Env } from "./env";
import { latestSnapshots } from "./sync";

type Obj = Record<string, any>;

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
const COOLDOWN: Record<number, number> = {
  11479: 3600, // Transmute: Iron to Gold
  11480: 3600, // Transmute: Mithril to Truesilver
  17187: 169171, // Transmute: Arcanite (1.958 days)
  17559: 82800, 17560: 82800, 17561: 82800, 17562: 82800, // elemental transmutes, 23 hours
  17563: 82800, 17564: 82800, 17565: 82800, 17566: 82800,
  25146: 600, // Transmute: Elemental Fire
  18560: 341971, // Mooncloth (3.958 days)
};

const MAX_CRAFTS = 1000;
const GIVE_UP_AFTER = 25; // consecutive crafts at a loss before the batch is considered finished

const SOURCE: Record<number, string> = { 2: "drop", 4: "quest", 5: "receptárus", 6: "tréner", 7: "felfedezés", 16: "horgászat" };

export interface VendorCraftFilter {
  /** "mine": your professions; "all": every profession; or one profession id. */
  profession: "mine" | "all" | number;
  /** "current": up to your current skill (your professions only); "max": every recipe up to 300. */
  skill: "current" | "max";
  /** Only recipes you already know. */
  knownOnly: boolean;
}

export interface ShoppingLine {
  itemId: number;
  name: string;
  units: number;
  ahUnits: number;
  ahCost: number;
  /** Most expensive unit price paid on the auction house: do not pay more than this. */
  ahMaxUnit: number | null;
  vendorUnits: number;
  vendorCost: number;
  /** Units bought because a stack could not be split, left over after the batch. */
  leftover: number;
  minPrice: number | null;
  avgPrice: number | null;
}

export interface VendorCraft {
  spellId: number;
  recipe: string;
  professionId: number;
  profession: string;
  orange: number;
  status: "known" | "trainer" | "recipe" | "skill";
  learnText: string;
  productId: number;
  product: string;
  /** Pieces made per craft: exact when min === max. */
  makesMin: number;
  makesMax: number;
  /** Vendor price of one piece, copper. */
  vendorEach: number;
  vendorCheck: "both" | "blizzard" | "wowhead" | "mismatch";
  vendorOther: number | null;
  /** First craft at the cheapest listed reagents. */
  firstCost: number;
  firstProfit: number;
  /** One craft at average market prices. */
  avgCost: number | null;
  avgProfit: number | null;
  /** Cooldown between crafts in seconds, if any: the batch is then a single craft. */
  cooldown: number | null;
  /** Best batch: as many crafts as stay profitable. */
  crafts: number;
  /** The batch reached the most crafts that are worked out (or the end of the stored listings). */
  capped: boolean;
  cost: number;
  income: number;
  profit: number;
  roiPct: number;
  shopping: ShoppingLine[];
}

export interface VendorCraftReport {
  pricesAt: string | null;
  mine: { id: number; name: string; skill: number }[];
  rows: VendorCraft[];
  /** Recipes that make something a vendor buys but could not be priced (reagent never listed). */
  unpriced: number;
}

interface Supply {
  tiers: [number, number, number][];
  vendor: number | null;
}

/** Buys reagent units from the cheapest source, keeping track of what is left. */
class Buyer {
  private idx = 0;
  private left: number;
  held = 0;
  ahUnits = 0;
  ahCost = 0;
  ahMaxUnit: number | null = null;
  vendorUnits = 0;
  vendorCost = 0;

  constructor(private s: Supply) {
    this.left = s.tiers[0]?.[1] ?? 0;
  }

  /** Cost of the next `units`, or null when they cannot be bought. */
  take(units: number): number | null {
    let cost = 0;
    const fromHeld = Math.min(this.held, units);
    this.held -= fromHeld;
    units -= fromHeld;
    while (units > 0) {
      const t = this.s.tiers[this.idx];
      if (this.s.vendor != null && (!t || this.s.vendor <= t[0])) {
        cost += this.s.vendor * units;
        this.vendorUnits += units;
        this.vendorCost += this.s.vendor * units;
        return cost;
      }
      if (!t) return null;
      const [price, , whole] = t;
      const n = whole ? this.left : Math.min(this.left, units);
      cost += price * n;
      this.ahUnits += n;
      this.ahCost += price * n;
      this.ahMaxUnit = Math.max(this.ahMaxUnit ?? 0, price);
      this.left -= n;
      if (n > units) this.held += n - units;
      units -= Math.min(n, units);
      if (this.left === 0) {
        this.idx++;
        this.left = this.s.tiers[this.idx]?.[1] ?? 0;
      }
    }
    return cost;
  }
}

interface RecipeRow {
  spell_id: number;
  profession_id: number;
  name: string;
  orange: number;
  creates_item: number;
  creates_qty: number;
  creates_min: number | null;
  creates_max: number | null;
  reagents: string;
  training_cost: number | null;
  from_trainer: number;
  sources: string | null;
}

/** Runs `crafts` crafts (or until the reagents run out / stop paying). */
function simulate(reagents: [number, number][], supplies: Map<number, Supply>, incomeEach: number, crafts: number, stopWhenLosing: boolean) {
  const buyers = reagents.map(([id]) => new Buyer(supplies.get(id)!));
  let cum = 0;
  let best = { n: 0, profit: 0, cost: 0 };
  let spent = 0;
  let losing = 0;
  let first: number | null = null;
  for (let n = 1; n <= crafts; n++) {
    let c = 0;
    for (let i = 0; i < reagents.length; i++) {
      const x = buyers[i].take(reagents[i][1]);
      if (x == null) return { best, first, buyers };
      c += x;
    }
    if (first == null) first = c;
    spent += c;
    cum += incomeEach - c;
    if (cum > best.profit) {
      best = { n, profit: cum, cost: spent };
      losing = 0;
    } else if (stopWhenLosing && ++losing >= GIVE_UP_AFTER) break;
  }
  return { best, first, buyers };
}

export async function vendorCraftReport(env: Env, f: VendorCraftFilter): Promise<VendorCraftReport> {
  const [recipeRows, priceRows, itemRows, at, snaps] = await Promise.all([
    env.DB.prepare(
      "SELECT spell_id, profession_id, name, orange, creates_item, creates_qty, creates_min, creates_max, reagents, " +
        "training_cost, from_trainer, sources FROM recipe_meta WHERE creates_item IS NOT NULL",
    ).all<RecipeRow>(),
    env.DB.prepare("SELECT item_id, min_price, avg_price, book FROM prices").all<{
      item_id: number;
      min_price: number;
      avg_price: number | null;
      book: string | null;
    }>(),
    env.DB.prepare("SELECT item_id, name, vendor_buy, vendor_sell, wh_sell, api_status FROM items").all<{
      item_id: number;
      name: string | null;
      vendor_buy: number | null;
      vendor_sell: number | null;
      wh_sell: number | null;
      api_status: number | null;
    }>(),
    env.DB.prepare(
      "SELECT COALESCE((SELECT value FROM manual_state WHERE key = 'prices_synced'), (SELECT MAX(updated_at) FROM prices)) AS at",
    ).first<{ at: string | null }>(),
    latestSnapshots(env),
  ]);

  // Your professions, skill and known recipes (Blizzard profile).
  const mine = new Map<number, { name: string; skill: number; known: Set<string> }>();
  const prof = snaps.professions?.json as Obj | undefined;
  for (const g of [...(prof?.primaries ?? []), ...(prof?.secondaries ?? [])] as Obj[]) {
    const tier = g.tiers?.[0] ?? g;
    mine.set(Number(g.profession?.id), {
      name: String(g.profession?.name),
      skill: Number(tier.skill_points ?? 0),
      known: new Set<string>((tier.known_recipes ?? []).map((r: Obj) => String(r.name))),
    });
  }

  const items = new Map(itemRows.results.map((i) => [i.item_id, i]));
  const market = new Map(priceRows.results.map((p) => [p.item_id, p]));
  const supplies = new Map<number, Supply>();
  const supply = (id: number): Supply => {
    let s = supplies.get(id);
    if (!s) {
      const m = market.get(id);
      const vendor = VENDOR_SOLD.has(id) ? (items.get(id)?.vendor_buy ?? null) : null;
      s = { tiers: m?.book ? (JSON.parse(m.book) as [number, number, number][]) : [], vendor: vendor && vendor > 0 ? vendor : null };
      supplies.set(id, s);
    }
    return s;
  };
  const name = (id: number) => items.get(id)?.name ?? `Item #${id}`;

  const rows: VendorCraft[] = [];
  let unpriced = 0;
  for (const r of recipeRows.results) {
    const pid = r.profession_id;
    const my = mine.get(pid);
    if (f.profession === "mine" && !my) continue;
    if (typeof f.profession === "number" && f.profession !== pid) continue;
    if (f.skill === "current" && (!my || r.orange > my.skill)) continue;
    const known = !!my?.known.has(r.name);
    if (f.knownOnly && !known) continue;

    // Vendor price of the product: the Blizzard item API, checked against Wowhead.
    const it = items.get(r.creates_item);
    const bz = it?.api_status === 200 ? (it.vendor_sell ?? 0) : null;
    const wh = it?.wh_sell ?? null;
    const vendorEach = bz != null && wh != null ? Math.min(bz, wh) : (bz ?? wh ?? 0);
    if (!(vendorEach > 0)) continue;
    const vendorCheck: VendorCraft["vendorCheck"] =
      bz != null && wh != null ? (bz === wh ? "both" : "mismatch") : bz != null ? "blizzard" : "wowhead";

    const makesMin = r.creates_min ?? Math.floor(r.creates_qty) ?? 1;
    const makesMax = r.creates_max ?? makesMin;
    const incomeEach = vendorEach * makesMin;
    const reagents = JSON.parse(r.reagents) as [number, number][];
    for (const [id] of reagents) supply(id);

    const first = simulate(reagents, supplies, incomeEach, 1, false);
    if (first.first == null) {
      unpriced++;
      continue;
    }
    const cooldown = COOLDOWN[r.spell_id] ?? null;
    const run = simulate(reagents, supplies, incomeEach, cooldown ? 1 : MAX_CRAFTS, true);

    // One craft at average prices (vendor price when the reagent is sold by a vendor and cheaper).
    let avgCost: number | null = 0;
    for (const [id, q] of reagents) {
      const s = supplies.get(id)!;
      const avg = market.get(id)?.avg_price ?? null;
      const unit = s.vendor != null && (avg == null || s.vendor <= avg) ? s.vendor : avg;
      if (unit == null) {
        avgCost = null;
        break;
      }
      avgCost! += unit * q;
    }
    const avgIncome = vendorEach * ((makesMin + makesMax) / 2);

    const status: VendorCraft["status"] = known
      ? "known"
      : my && r.orange > my.skill
        ? "skill"
        : r.from_trainer && r.training_cost != null
          ? "trainer"
          : "recipe";
    const srcs = (r.sources ? (JSON.parse(r.sources) as number[]) : []).map((s) => SOURCE[s]).filter(Boolean);
    const learnText =
      status === "known"
        ? "ismered"
        : status === "trainer"
          ? `trénertől tanulható`
          : status === "skill"
            ? `${r.orange} skill kell`
            : srcs.length
              ? `recept: ${srcs.join(", ")}`
              : "recept kell";

    // Shopping list for the best batch.
    const best = run.best;
    let shopping: ShoppingLine[] = [];
    if (best.n > 0) {
      const again = simulate(reagents, supplies, incomeEach, best.n, false);
      shopping = reagents.map(([id, q], i) => {
        const b = again.buyers[i];
        return {
          itemId: id,
          name: name(id),
          units: q * best.n,
          ahUnits: b.ahUnits,
          ahCost: Math.round(b.ahCost),
          ahMaxUnit: b.ahMaxUnit,
          vendorUnits: b.vendorUnits,
          vendorCost: b.vendorCost,
          leftover: b.held,
          minPrice: market.get(id)?.min_price ?? null,
          avgPrice: market.get(id)?.avg_price ?? null,
        };
      });
    }

    // Worth showing only when it pays at the cheapest listings or at average prices.
    if (best.n === 0 && !(avgCost != null && avgIncome - avgCost > 0)) continue;
    rows.push({
      spellId: r.spell_id,
      recipe: r.name,
      professionId: pid,
      profession: PROFESSIONS[pid] ?? my?.name ?? String(pid),
      orange: r.orange,
      status,
      learnText,
      productId: r.creates_item,
      product: name(r.creates_item),
      makesMin,
      makesMax,
      vendorEach,
      vendorCheck,
      vendorOther: vendorCheck === "mismatch" ? Math.max(bz!, wh!) : null,
      firstCost: Math.round(first.first),
      firstProfit: Math.round(incomeEach - first.first),
      avgCost: avgCost == null ? null : Math.round(avgCost),
      avgProfit: avgCost == null ? null : Math.round(avgIncome - avgCost),
      cooldown,
      crafts: best.n,
      capped: !cooldown && best.n >= MAX_CRAFTS,
      cost: Math.round(best.cost),
      income: incomeEach * best.n,
      profit: Math.round(best.profit),
      roiPct: best.cost > 0 ? (best.profit / best.cost) * 100 : 0,
      shopping,
    });
  }
  rows.sort((a, b) => b.profit - a.profit || b.firstProfit - a.firstProfit);
  return {
    pricesAt: at?.at ?? null,
    mine: [...mine].map(([id, m]) => ({ id, name: PROFESSIONS[id] ?? m.name, skill: m.skill })),
    rows,
    unpriced,
  };
}
