import { apiGet } from "./blizzard";
import type { Env } from "./env";
import { type ItemStats, equippedStats } from "./gear";

type Obj = Record<string, any>;

/** Blizzard inventory type -> equipment slots the item can go into. */
export const INV_SLOTS: Record<string, string[]> = {
  HEAD: ["HEAD"], NECK: ["NECK"], SHOULDER: ["SHOULDER"], CHEST: ["CHEST"], ROBE: ["CHEST"], WAIST: ["WAIST"],
  LEGS: ["LEGS"], FEET: ["FEET"], WRIST: ["WRIST"], HAND: ["HANDS"], FINGER: ["FINGER_1", "FINGER_2"],
  TRINKET: ["TRINKET_1", "TRINKET_2"], CLOAK: ["BACK"], WEAPON: ["MAIN_HAND", "OFF_HAND"],
  WEAPONMAINHAND: ["MAIN_HAND"], WEAPONOFFHAND: ["OFF_HAND"],
};
// Rogue: cloth/leather/misc armor; daggers, one-handed swords and maces, fist weapons.
const ARMOR_SUBS = new Set([0, 1, 2]);
const WEAPON_SUBS = new Set([4, 7, 13, 15]);
const ROGUE = 4;

export interface GearItem {
  itemId: number;
  name: string;
  slot: string;
  itemClass: number;
  subclass: number;
  reqLevel: number;
  itemLevel: number;
  quality: string;
  binding: string | null;
  stats: ItemStats;
}

interface ItemRow {
  item_id: number;
  name: string | null;
  slot: string | null;
  item_class: number | null;
  subclass: number | null;
  req_level: number | null;
  item_level: number | null;
  quality: string | null;
  binding: string | null;
  stats: string | null;
}

function toGear(r: ItemRow): GearItem | null {
  if (!r.slot || !INV_SLOTS[r.slot] || !r.stats) return null;
  const parsed = JSON.parse(r.stats) as ItemStats & { classes?: number[] };
  if (parsed.classes?.length && !parsed.classes.includes(ROGUE)) return null;
  if (r.item_class === 4 && !ARMOR_SUBS.has(r.subclass ?? -1)) return null;
  if (r.item_class === 2 && (!WEAPON_SUBS.has(r.subclass ?? -1) || !parsed.weapon)) return null;
  if (r.item_class !== 2 && r.item_class !== 4) return null;
  return {
    itemId: r.item_id,
    name: r.name ?? `Item #${r.item_id}`,
    slot: r.slot,
    itemClass: r.item_class,
    subclass: r.subclass ?? 0,
    reqLevel: r.req_level ?? 0,
    itemLevel: r.item_level ?? 0,
    quality: r.quality ?? "COMMON",
    binding: r.binding,
    stats: parsed,
  };
}

const GEAR_COLUMNS = "item_id, name, slot, item_class, subclass, req_level, item_level, quality, binding, stats";

/** Rogue-usable gear among the given item ids. */
export async function loadGear(env: Env, ids: number[]): Promise<Map<number, GearItem>> {
  const out = new Map<number, GearItem>();
  for (let i = 0; i < ids.length; i += 90) {
    const chunk = ids.slice(i, i + 90);
    const rows = await env.DB.prepare(
      `SELECT ${GEAR_COLUMNS} FROM items WHERE slot IS NOT NULL AND item_id IN (${chunk.map(() => "?").join(",")})`,
    )
      .bind(...chunk)
      .all<ItemRow>();
    for (const r of rows.results) {
      const g = toGear(r);
      if (g) out.set(g.itemId, g);
    }
  }
  return out;
}

/** Gear currently buyable on the auction house, with its cheapest buyout. */
export async function loadAuctionGear(env: Env): Promise<{ item: GearItem; price: number; listings: number }[]> {
  const rows = await env.DB.prepare(
    `SELECT i.${GEAR_COLUMNS.split(", ").join(", i.")}, a.min_buyout, a.listings FROM ah_gear a JOIN items i ON i.item_id = a.item_id`,
  ).all<ItemRow & { min_buyout: number; listings: number }>();
  const out: { item: GearItem; price: number; listings: number }[] = [];
  for (const r of rows.results) {
    const item = toGear(r);
    if (item) out.push({ item, price: r.min_buyout, listings: r.listings });
  }
  return out;
}

/** Ask the Blizzard API about items and store name, vendor prices and (for gear) stats. */
export async function fetchItems(env: Env, ids: number[]): Promise<number> {
  const now = new Date().toISOString();
  const stmts: D1PreparedStatement[] = [];
  // A few at a time keeps a batch fast without hammering the API.
  for (let i = 0; i < ids.length; i += 5) {
    const results = await Promise.all(
      ids.slice(i, i + 5).map(async (id) => ({ id, ...(await apiGet(env, `/data/wow/item/${id}`, "static")) })),
    );
    for (const { id, status, body } of results) {
      const b = (status === 200 ? body : {}) as Obj;
      const p = (b.preview_item ?? {}) as Obj;
      const slot = b.inventory_type?.type as string | undefined;
      const equippable = !!slot && !!INV_SLOTS[slot];
      const stats = equippable
        ? JSON.stringify({
            ...equippedStats(p),
            classes: (p.requirements?.playable_classes?.links ?? []).map((c: Obj) => Number(c.id)),
          })
        : null;
      stmts.push(
        env.DB.prepare(
          "INSERT INTO items (item_id, name, vendor_buy, vendor_sell, api_status, updated_at, slot, item_class, subclass, " +
            "req_level, item_level, quality, binding, stats) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) " +
            "ON CONFLICT(item_id) DO UPDATE SET name = COALESCE(excluded.name, items.name), vendor_buy = excluded.vendor_buy, " +
            "vendor_sell = excluded.vendor_sell, api_status = excluded.api_status, updated_at = excluded.updated_at, " +
            "slot = excluded.slot, item_class = excluded.item_class, subclass = excluded.subclass, req_level = excluded.req_level, " +
            "item_level = excluded.item_level, quality = excluded.quality, binding = excluded.binding, stats = excluded.stats",
        ).bind(
          id,
          b.name ?? null,
          b.purchase_price ?? null,
          b.sell_price ?? null,
          status === 429 ? null : status, // rate limited: leave it marked as not fetched yet
          now,
          equippable ? slot : null,
          b.item_class?.id ?? null,
          b.item_subclass?.id ?? null,
          b.required_level ?? null,
          b.level ?? null,
          b.quality?.type ?? null,
          p.binding?.type ?? null,
          stats,
        ),
      );
    }
  }
  for (let i = 0; i < stmts.length; i += 50) await env.DB.batch(stmts.slice(i, i + 50));
  return ids.length;
}

const UNKNOWN_KEY = "items_todo";

/** Item ids seen somewhere (auction house, bags) that the items table knows nothing about yet. */
export async function queueUnknownItems(env: Env, ids: Iterable<number>): Promise<number> {
  const all = [...new Set(ids)].filter((id) => Number.isInteger(id) && id > 0);
  const known = new Set<number>();
  const rows = await env.DB.prepare("SELECT item_id FROM items WHERE api_status IS NOT NULL").all<{ item_id: number }>();
  for (const r of rows.results) known.add(r.item_id);
  const prev = await env.DB.prepare("SELECT value FROM manual_state WHERE key = ?").bind(UNKNOWN_KEY).first<{ value: string }>();
  const todo = new Set<number>(prev ? (JSON.parse(prev.value) as number[]) : []);
  for (const id of all) if (!known.has(id)) todo.add(id);
  for (const id of todo) if (known.has(id)) todo.delete(id);
  const list = [...todo].slice(0, 8000);
  await env.DB.prepare(
    "INSERT INTO manual_state (key, value, updated_at) VALUES (?, ?, ?) " +
      "ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
  )
    .bind(UNKNOWN_KEY, JSON.stringify(list), new Date().toISOString())
    .run();
  return list.length;
}

/** Fetch the next batch of queued items. Returns how many are still waiting. */
export async function discoverItems(env: Env, limit = 40): Promise<{ fetched: number; remaining: number }> {
  const stale = await env.DB.prepare("SELECT item_id FROM items WHERE api_status IS NULL LIMIT ?").bind(limit).all<{ item_id: number }>();
  let ids = stale.results.map((r) => r.item_id);
  let queue: number[] = [];
  if (ids.length < limit) {
    const prev = await env.DB.prepare("SELECT value FROM manual_state WHERE key = ?").bind(UNKNOWN_KEY).first<{ value: string }>();
    queue = prev ? (JSON.parse(prev.value) as number[]) : [];
    const take = queue.slice(0, limit - ids.length);
    queue = queue.slice(take.length);
    ids = ids.concat(take);
    await env.DB.prepare(
      "INSERT INTO manual_state (key, value, updated_at) VALUES (?, ?, ?) " +
        "ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
    )
      .bind(UNKNOWN_KEY, JSON.stringify(queue), new Date().toISOString())
      .run();
  }
  if (ids.length) await fetchItems(env, ids);
  const left = await env.DB.prepare("SELECT COUNT(*) AS n FROM items WHERE api_status IS NULL").first<{ n: number }>();
  return { fetched: ids.length, remaining: queue.length + (left?.n ?? 0) };
}

/**
 * Store the cheapest buyout of every fixed-stat item a rogue around this level could wear,
 * and queue ids we have never looked up. `listings` comes from the hourly auction download.
 */
export async function storeAuctionGear(
  env: Env,
  listings: Map<number, { min: number; n: number }>,
  level: number,
): Promise<{ gear: number; queued: number }> {
  const ids = [...listings.keys()];
  const gear = await loadGear(env, ids);
  const now = new Date().toISOString();
  const stmts = [env.DB.prepare("DELETE FROM ah_gear")];
  for (const g of gear.values()) {
    if (g.reqLevel > level + 5) continue;
    const l = listings.get(g.itemId)!;
    stmts.push(
      env.DB.prepare("INSERT INTO ah_gear (item_id, min_buyout, listings, updated_at) VALUES (?, ?, ?, ?)").bind(
        g.itemId,
        Math.round(l.min),
        l.n,
        now,
      ),
    );
  }
  for (let i = 0; i < stmts.length; i += 80) await env.DB.batch(stmts.slice(i, i + 80));
  const queued = await queueUnknownItems(env, ids);
  return { gear: stmts.length - 1, queued };
}
