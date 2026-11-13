import { loadAddon, ownedItems } from "./addon";
import type { Env } from "./env";
import { type GearContext, type GearReport, gearContext, gearReport } from "./gear";
import { INV_SLOTS, type GearItem, loadAuctionGear, loadGear } from "./market";
import { loadPriceBook, planRoutes } from "./professions";
import { latestSnapshots } from "./sync";

type Obj = Record<string, any>;

export type Source = "ah" | "craft" | "owned" | "trainer";

export interface Option {
  source: Source;
  /** Purchases that exclude each other share a group (one item per equipment slot). */
  group: string;
  title: string;
  quality: string | null;
  detail: string;
  where: string;
  cost: number; // copper
  gain: number; // DPS
  gainPct: number;
  estimated: boolean;
  warning: string | null;
}

export interface SkillAdvice {
  name: string;
  level: number;
  cost: number;
  tier: "dps" | "core" | "situational" | "skip";
  why: string;
  gain: number;
}

export interface Plan {
  name: string;
  level: number;
  gold: number | null;
  baseline: number;
  measuredDps: number | null;
  projected: number;
  buy: Option[];
  spent: number;
  left: number | null;
  wishlist: Option[];
  free: Option[];
  combat: { level: string; title: string; text: string }[];
  skills: SkillAdvice[];
  farm: GearReport["dungeons"];
  professions: { name: string; skill: number; cap: number; next: string | null; cost: number; note: string | null }[];
  roadmap: { level: number; skillCost: number; skills: string[]; gear: Option[] }[];
  warnings: string[];
}

// ---------------------------------------------------------------- trainer skills

// What a rogue's trainer abilities are worth when leveling and running dungeons. These are
// judgements about the kit, not values read from the game.
const CORE: Record<string, string> = {
  Kick: "megszakítás; dungeonben a caster mobok és bossok ellen alap",
  Sap: "tömegkontroll a húzásoknál, egy mobot kivesz a harcból",
  Feint: "csökkenti az aggródat, ha dungeonben átveszed a tanktól",
  Vanish: "vészkijárat és aggro-törlés",
  Evasion: "túlélés, ha rád fordul valami",
  Sprint: "mobilitás, menekülés",
  Gouge: "megszakítás és helyezkedés a mob mögé",
  "Kidney Shot": "stun, megszakításnak is jó",
  Blind: "második tömegkontroll",
  "Slice and Dice": "az auto-attack a sebzésed nagyja, ez gyorsítja",
  Stealth: "gyorsabb mozgás lopakodva",
  "Cheap Shot": "nyitó stun",
};
const SITUATIONAL: Record<string, string> = {
  Backstab: "tőr kell hozzá a főkézbe és a célpont háta; Sinister Strike buildben nem használod",
  Ambush: "tőrös nyitás lopakodásból",
  Garrote: "nyitó vérzés, hosszabb harcokra",
  Rupture: "vérzés; csak hosszú harcban (boss) éri meg az Eviscerate helyett",
  "Expose Armor": "páncélcsökkentés; csak akkor, ha nincs warrior a csapatban",
  Distract: "járőröző mobok kikerülése",
  "Deadly Poison": "hosszú harcokra jobb, rövid mobokra az Instant Poison erősebb",
  "Wound Poison": "gyógyításcsökkentés, inkább PvP",
};
const SKIP: Record<string, string> = {
  "Detect Traps": "szinte soha nem számít",
  "Disarm Trap": "szinte soha nem számít",
  "Pick Pocket": "aprópénz, DPS-t nem ad",
  "Pick Lock": "kényelmi skill",
  "Safe Fall": "kényelmi skill",
  "Mind-numbing Poison": "csak casterek ellen, főleg PvP",
  "Crippling Poison": "lassítás, főleg PvP",
};
// Basics worth buying before any DPS purchase: without them a dungeon run goes badly.
const MUST = new Set(["Kick", "Slice and Dice", "Evasion", "Sprint", "Vanish"]);
const baseName = (n: string) => n.replace(/\s+[IVX]+$/, "");

function rankSkills(
  rows: { name: string; required_level: number; cost_copper: number; state: string; tradeskill: number }[],
  ctx: GearContext,
): SkillAdvice[] {
  const shares = new Map<string, number>();
  for (const a of ctx.combat?.abilities ?? []) {
    const key = baseName(a.name.replace(/ \(dot\)$/, ""));
    shares.set(key, (shares.get(key) ?? 0) + a.share);
  }
  const out: SkillAdvice[] = [];
  for (const r of rows) {
    if (r.state !== "available" || r.tradeskill) continue;
    const base = baseName(r.name);
    const share = shares.get(base) ?? 0;
    let tier: SkillAdvice["tier"] = "situational";
    let why = "új képesség, a mostani rotációdban nincs szerepe";
    let gain = 0;
    if (share >= 2) {
      // A new rank of something you already deal damage with. The exact rank values are not
      // in the data, so assume a rank adds about a tenth to that ability.
      tier = "dps";
      gain = (share / 100) * 0.1 * ctx.baseline;
      why = `új rank: ez a képesség most a sebzésed ${share.toFixed(1)}%-a`;
    } else if (CORE[base]) {
      tier = "core";
      why = CORE[base];
    } else if (SKIP[base]) {
      tier = "skip";
      why = SKIP[base];
    } else if (SITUATIONAL[base]) {
      why = SITUATIONAL[base];
    }
    out.push({ name: r.name, level: r.required_level, cost: r.cost_copper, tier, why, gain });
  }
  const order = { dps: 0, core: 1, situational: 2, skip: 3 };
  return out.sort((a, b) => order[a.tier] - order[b.tier] || b.gain - a.gain || a.cost - b.cost);
}

// ---------------------------------------------------------------- budget

/**
 * Multiple-choice knapsack: at most one option per group, total cost within the budget,
 * maximum total DPS. Costs are bucketed so the table stays small.
 */
function allocate(options: Option[], budget: number): Option[] {
  if (budget <= 0) return [];
  const unit = Math.max(100, Math.ceil(budget / 4000)); // 1 silver, or coarser for big purses
  const cap = Math.floor(budget / unit);
  const groups = new Map<string, Option[]>();
  for (const o of options) {
    if (o.cost > budget || o.gain <= 0) continue;
    const list = groups.get(o.group) ?? [];
    list.push(o);
    groups.set(o.group, list);
  }
  let best = new Float64Array(cap + 1);
  const picks: Int16Array[] = [];
  const lists = [...groups.values()];
  for (const list of lists) {
    const next = Float64Array.from(best);
    const pick = new Int16Array(cap + 1).fill(-1);
    list.forEach((o, idx) => {
      const c = Math.ceil(o.cost / unit);
      for (let b = cap; b >= c; b--) {
        const v = best[b - c] + o.gain;
        if (v > next[b] + 1e-9) {
          next[b] = v;
          pick[b] = idx;
        }
      }
    });
    best = next;
    picks.push(pick);
  }
  const chosen: Option[] = [];
  let b = cap;
  for (let g = lists.length - 1; g >= 0; g--) {
    const idx = picks[g][b];
    if (idx >= 0) {
      const o = lists[g][idx];
      chosen.push(o);
      b -= Math.ceil(o.cost / unit);
    }
  }
  return chosen.sort((x, y) => y.gain - x.gain);
}

// ---------------------------------------------------------------- plan

const SLOT_HU: Record<string, string> = {
  HEAD: "fej", NECK: "nyak", SHOULDER: "váll", BACK: "köpeny", CHEST: "mellkas", WRIST: "csukló", HANDS: "kéz",
  WAIST: "öv", LEGS: "láb", FEET: "lábfej", FINGER_1: "gyűrű", FINGER_2: "gyűrű", TRINKET_1: "trinket",
  TRINKET_2: "trinket", MAIN_HAND: "főkéz", OFF_HAND: "balkéz",
};

export async function buildPlan(env: Env): Promise<Plan | null> {
  const ctx = await gearContext(env);
  if (!ctx) return null;
  const snaps = await latestSnapshots(env);
  const profile = snaps.profile?.json as Obj;
  const profSnap = snaps.professions?.json as Obj | undefined;
  const addon = await loadAddon(env);
  const owned = ownedItems(addon?.state);
  const goldRow = await env.DB.prepare("SELECT value FROM manual_state WHERE key = 'gold_copper'").first<{ value: string }>();
  const gold = goldRow ? Number(goldRow.value) : null;
  const { level, baseline } = ctx;

  const option = (item: GearItem, source: Source, cost: number, where: string, extra?: string): Option | null => {
    if (ctx.equippedIds.has(item.itemId)) return null;
    const s = ctx.score(item.stats, INV_SLOTS[item.slot]);
    if (!s) return null;
    const replaces = ctx.equipped.get(s.slot)?.name;
    return {
      source,
      group: s.slot,
      title: item.name,
      quality: item.quality,
      detail: [ctx.describe(item.stats, item.subclass), `${SLOT_HU[s.slot] ?? s.slot}${replaces ? `, a ${replaces} helyére` : ""}`, extra]
        .filter(Boolean)
        .join(" · "),
      where,
      cost,
      gain: s.gain,
      gainPct: (s.gain / baseline) * 100,
      estimated: false,
      warning: ctx.weaponWarning(item.itemClass, item.subclass),
    };
  };

  // --- auction house
  const all: Option[] = [];
  const soon: (Option & { req: number })[] = [];
  for (const { item, price, listings } of await loadAuctionGear(env)) {
    const o = option(item, "ah", price, "Aukciósház", `${listings} db kint`);
    if (!o) continue;
    if (item.reqLevel <= level) all.push(o);
    else if (item.reqLevel <= level + 4) soon.push({ ...o, req: item.reqLevel });
  }

  // --- already in bags or bank
  const free: Option[] = [];
  const ownedGear = await loadGear(env, [...owned.keys()]);
  for (const item of ownedGear.values()) {
    if (item.reqLevel > level) continue;
    const o = option(item, "owned", 0, "A táskádban vagy a bankodban van");
    if (o) free.push(o);
  }

  // --- things you can craft yourself
  const book = await loadPriceBook(env);
  for (const g of [...(profSnap?.primaries ?? []), ...(profSnap?.secondaries ?? [])] as Obj[]) {
    const tier = g.tiers?.[0] ?? g;
    const skill = Number(tier.skill_points ?? 0);
    const known = new Set<string>((tier.known_recipes ?? []).map((r: Obj) => String(r.name)));
    const recipes = await env.DB.prepare(
      "SELECT name, orange, creates_item, reagents, training_cost, from_trainer FROM recipe_meta " +
        "WHERE profession_id = ? AND creates_item IS NOT NULL AND orange <= ?",
    )
      .bind(Number(g.profession?.id), skill)
      .all<Obj>();
    const gear = await loadGear(env, recipes.results.map((r) => Number(r.creates_item)));
    for (const r of recipes.results) {
      const item = gear.get(Number(r.creates_item));
      if (!item || item.reqLevel > level) continue;
      const isKnown = known.has(String(r.name));
      if (!isKnown && !(r.from_trainer && r.training_cost != null)) continue; // pattern drops are not plannable
      let mats = 0;
      let priced = true;
      const need: string[] = [];
      for (const [id, qty] of JSON.parse(r.reagents) as [number, number][]) {
        const have = Math.min(qty, owned.get(id) ?? 0);
        const u = book.unit(id);
        if (qty - have > 0) {
          if (!u) priced = false;
          else mats += u.price * (qty - have);
          need.push(`${qty - have}× ${book.name(id)}`);
        }
      }
      if (!priced) continue;
      const cost = Math.round(mats + (isKnown ? 0 : Number(r.training_cost)));
      const o = option(
        item,
        "craft",
        cost,
        `Saját ${String(g.profession?.name)}`,
        (need.length ? `venni kell: ${need.join(", ")}` : "minden alapanyag megvan") + (isKnown ? "" : " · a receptet meg kell tanulni"),
      );
      if (!o) continue;
      if (cost === 0) free.push({ ...o, source: "craft" });
      else all.push(o);
    }
  }

  // --- trainer skills
  const trainerRows = await env.DB.prepare(
    "SELECT name, required_level, cost_copper, state, tradeskill FROM trainer_skills",
  ).all<{ name: string; required_level: number; cost_copper: number; state: string; tradeskill: number }>();
  const skills = rankSkills(trainerRows.results, ctx);
  for (const s of skills) {
    if (s.tier !== "dps" || s.cost <= 0) continue;
    all.push({
      source: "trainer",
      group: `skill:${s.name}`,
      title: s.name,
      quality: null,
      detail: s.why,
      where: "Rogue trainer",
      cost: s.cost,
      gain: s.gain,
      gainPct: (s.gain / baseline) * 100,
      estimated: true,
      warning: null,
    });
  }

  // The same item can be both on the AH and craftable: keep the cheaper way.
  const cheapest = new Map<string, Option>();
  for (const o of all) {
    const key = `${o.group}|${o.title}`;
    const cur = cheapest.get(key);
    if (!cur || o.cost < cur.cost) cheapest.set(key, o);
  }
  const options = [...cheapest.values()];

  // Free upgrades come first: they change what is worth buying for that slot.
  const bestFree = new Map<string, Option>();
  for (const o of free.sort((a, b) => b.gain - a.gain)) if (!bestFree.has(o.group)) bestFree.set(o.group, o);
  const freeList = [...bestFree.values()];
  const payable = options
    .map((o) => {
      const f = bestFree.get(o.group);
      return f ? { ...o, gain: o.gain - f.gain, gainPct: ((o.gain - f.gain) / baseline) * 100 } : o;
    })
    .filter((o) => o.gain > 0.05);

  // Reserve the basics first, cheapest first, then spend the rest on damage.
  const reserved: Option[] = [];
  let budget = gold ?? 0;
  for (const s of skills.filter((x) => x.tier === "core" && MUST.has(baseName(x.name))).sort((a, b) => a.cost - b.cost)) {
    if (s.cost > budget) continue;
    budget -= s.cost;
    reserved.push({
      source: "trainer",
      group: `skill:${s.name}`,
      title: s.name,
      quality: null,
      detail: `alap képesség: ${s.why}`,
      where: "Rogue trainer",
      cost: s.cost,
      gain: 0,
      gainPct: 0,
      estimated: false,
      warning: null,
    });
  }
  const buy = gold != null ? [...reserved, ...allocate(payable, budget)] : [];
  const spent = buy.reduce((a, o) => a + o.cost, 0);
  const taken = new Set(buy.map((o) => o.group));

  // What you would buy next with more gold: the best option per group you have not covered.
  const wishBest = new Map<string, Option>();
  for (const o of payable.sort((a, b) => b.gain - a.gain)) {
    if (taken.has(o.group) || (gold != null && o.cost <= gold - spent)) continue;
    if (!wishBest.has(o.group)) wishBest.set(o.group, o);
  }
  const wishlist = [...wishBest.values()].sort((a, b) => b.gain / b.cost - a.gain / a.cost).slice(0, 6);

  // --- dungeons, professions
  const report = await gearReport(env, 3, ctx);
  const routes = await planRoutes(env, 300);
  const professions = routes.map((r) => {
    const reachable = r.steps.filter((s) => s.from < r.cap);
    const first = reachable[0];
    return {
      name: r.profession,
      skill: r.skill,
      cap: r.cap,
      next: first ? `${first.recipe} ×${first.crafts} (${first.from} → ${Math.min(first.to, r.cap)})` : null,
      cost: first ? Math.round(first.matsCost + first.trainingCost) : 0,
      note: r.cap - r.skill <= 25 && r.cap < 300 ? `${r.cap}-nél megállsz: tanuld meg a következő rangot a trainernél` : null,
    };
  });

  // --- what the next levels bring
  const roadmap: Plan["roadmap"] = [];
  for (let l = level + 1; l <= level + 4; l++) {
    const rows = trainerRows.results.filter((r) => r.state === "unavailable" && !r.tradeskill && r.required_level === l);
    const gear = soon.filter((o) => o.req === l).sort((a, b) => b.gain - a.gain).slice(0, 2);
    if (!rows.length && !gear.length) continue;
    roadmap.push({
      level: l,
      skillCost: rows.reduce((a, r) => a + r.cost_copper, 0),
      skills: rows.map((r) => r.name),
      gear,
    });
  }

  // --- data quality
  const warnings: string[] = [];
  const hours = (iso?: string | null) => (iso ? (Date.now() - new Date(iso).getTime()) / 3600_000 : Infinity);
  if (gold == null) warnings.push("Nincs gold-adat: telepítsd az addont, vagy add meg kézzel a Karakter oldalon. Enélkül nincs vásárlási terv.");
  if (!addon) warnings.push("Az addon még nem töltött fel semmit, ezért a táska, a bank és a trainer adatai hiányoznak.");
  else if (hours(addon.updatedAt) > 24) warnings.push("Az addon adata több mint egy napos: /wa save a játékban.");
  if (addon && !addon.state.bankAt) warnings.push("A bank tartalma ismeretlen: nyisd meg egyszer a bankot, aztán /wa save.");
  if (!trainerRows.results.length) warnings.push("Nincs trainer-adat: nyisd meg a rogue trainer ablakát minden szűrővel, aztán /wa save.");
  const priceAt = await env.DB.prepare("SELECT MAX(updated_at) AS at FROM ah_gear").first<{ at: string | null }>();
  if (hours(priceAt?.at) > 6) warnings.push("Az aukciós árak több mint 6 órásak, a vásárlási javaslatok elavultak lehetnek.");
  if (!ctx.combat) warnings.push("Nincs rögzített harc: a modell tankönyvi értékekkel számol. /wa log a játékban.");
  if (hours(snaps.profile?.last_seen_at) > 12) warnings.push("A Blizzard API adata régi: a profil csak kijelentkezés után frissül.");

  return {
    name: String(profile?.name ?? ""),
    level,
    gold,
    baseline,
    measuredDps: ctx.combat ? ctx.combat.dps : null,
    projected: baseline + buy.reduce((a, o) => a + o.gain, 0) + freeList.reduce((a, o) => a + o.gain, 0),
    buy,
    spent,
    left: gold != null ? gold - spent : null,
    wishlist,
    free: freeList,
    combat: (ctx.combat?.advice ?? []).filter((a) => a.level !== "info").map((a) => ({ level: a.level, title: a.title, text: a.text })),
    skills,
    farm: (report?.dungeons ?? []).slice(0, 3),
    professions,
    roadmap,
    warnings,
  };
}
