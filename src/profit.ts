import { loadAddon, ownedItems } from "./addon";
import type { Env } from "./env";
import { loadPriceBook } from "./professions";
import { latestSnapshots } from "./sync";

type Obj = Record<string, any>;

const AH_CUT = 0.05; // the auction house keeps 5% of a sale

export interface CraftProfit {
  profession: string;
  recipe: string;
  known: boolean;
  trainingCost: number;
  mats: number; // copper per craft at auction house / vendor prices
  matsText: string;
  sale: number; // what one craft sells for after the cut
  channel: "ah" | "vendor";
  listed: number; // units of the product already on the auction house
  profit: number;
  marginPct: number;
  /** Crafts you could make right now from what is in your bags and bank. */
  fromStock: number;
}

/** What is worth crafting to sell, at current prices, with the recipes you have or can train. */
export async function craftProfits(env: Env): Promise<CraftProfit[]> {
  const snaps = await latestSnapshots(env);
  const prof = snaps.professions?.json as Obj | undefined;
  if (!prof) return [];
  const book = await loadPriceBook(env);
  const owned = ownedItems((await loadAddon(env))?.state);
  const priceRows = await env.DB.prepare("SELECT item_id, depth_price, quantity FROM prices").all<{
    item_id: number;
    depth_price: number;
    quantity: number;
  }>();
  const market = new Map(priceRows.results.map((p) => [p.item_id, p]));

  const out: CraftProfit[] = [];
  for (const g of [...(prof.primaries ?? []), ...(prof.secondaries ?? [])] as Obj[]) {
    const tier = g.tiers?.[0] ?? g;
    const skill = Number(tier.skill_points ?? 0);
    const known = new Set<string>((tier.known_recipes ?? []).map((r: Obj) => String(r.name)));
    const recipes = await env.DB.prepare(
      "SELECT name, creates_item, creates_qty, reagents, training_cost, from_trainer FROM recipe_meta " +
        "WHERE profession_id = ? AND creates_item IS NOT NULL AND orange <= ?",
    )
      .bind(Number(g.profession?.id), skill)
      .all<Obj>();
    for (const r of recipes.results) {
      const isKnown = known.has(String(r.name));
      if (!isKnown && !(r.from_trainer && r.training_cost != null)) continue;
      const reagents = JSON.parse(r.reagents) as [number, number][];
      let mats = 0;
      let priced = true;
      let fromStock = Infinity;
      const text: string[] = [];
      for (const [id, qty] of reagents) {
        const u = book.unit(id);
        if (!u) {
          priced = false;
          break;
        }
        mats += u.price * qty;
        text.push(`${qty}× ${book.name(id)}`);
        fromStock = Math.min(fromStock, Math.floor((owned.get(id) ?? 0) / qty));
      }
      if (!priced || !reagents.length) continue;
      const qty = Number(r.creates_qty) || 1;
      const m = market.get(Number(r.creates_item));
      const ahNet = m ? m.depth_price * qty * (1 - AH_CUT) : 0;
      const vendor = book.vendorSell(Number(r.creates_item)) * qty;
      const sale = Math.max(ahNet, vendor);
      const profit = sale - mats;
      if (profit <= 0) continue;
      out.push({
        profession: String(g.profession?.name),
        recipe: String(r.name),
        known: isKnown,
        trainingCost: isKnown ? 0 : Number(r.training_cost),
        mats: Math.round(mats),
        matsText: text.join(", "),
        sale: Math.round(sale),
        channel: ahNet >= vendor ? "ah" : "vendor",
        listed: m?.quantity ?? 0,
        profit: Math.round(profit),
        marginPct: mats > 0 ? (profit / mats) * 100 : 0,
        fromStock: Number.isFinite(fromStock) ? fromStock : 0,
      });
    }
  }
  return out.sort((a, b) => b.profit - a.profit).slice(0, 25);
}
