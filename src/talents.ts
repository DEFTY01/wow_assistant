import type { Env } from "./env";
import { type GearContext, gearContext } from "./gear";
import { stateGet, statePut } from "./state";
import { latestSnapshots } from "./sync";

type Obj = Record<string, any>;

// ---------------------------------------------------------------- data

export interface TalentDef {
  id: number;
  name: string;
  row: number;
  col: number;
  max: number;
  requiredPoints: number;
  requires: { id: number; qty: number }[];
  /** Description text per rank, index 0 = rank 1. */
  desc: string[];
}
export interface TalentTree {
  id: number;
  name: string;
  talents: TalentDef[];
}
export interface TalentData {
  trees: TalentTree[];
}

export async function importTalents(env: Env, classId: number, data: TalentData): Promise<number> {
  await env.DB.prepare(
    "INSERT INTO talent_data (class_id, json, updated_at) VALUES (?, ?, ?) " +
      "ON CONFLICT(class_id) DO UPDATE SET json = excluded.json, updated_at = excluded.updated_at",
  )
    .bind(classId, JSON.stringify(data), new Date().toISOString())
    .run();
  return data.trees.reduce((a, t) => a + t.talents.length, 0);
}

async function loadTalents(env: Env, classId: number): Promise<TalentData | null> {
  const row = await env.DB.prepare("SELECT json FROM talent_data WHERE class_id = ?").bind(classId).first<{ json: string }>();
  return row ? (JSON.parse(row.json) as TalentData) : null;
}

// ---------------------------------------------------------------- builds

/** Rank per talent id. */
type Build = Map<number, number>;

interface Index {
  /** Every talent in a fixed order, for cheap cache keys. */
  all: TalentDef[];
  /** Modelled talents: the number in their description for each rank (index 0 = not taken). */
  values: Map<string, { id: number; byRank: number[] }>;
  defs: Map<number, TalentDef>;
  treeOf: Map<number, TalentTree>;
  byName: Map<string, TalentDef>;
}
function index(data: TalentData): Index {
  const defs = new Map<number, TalentDef>();
  const treeOf = new Map<number, TalentTree>();
  const byName = new Map<string, TalentDef>();
  for (const tree of data.trees) {
    for (const t of tree.talents) {
      defs.set(t.id, t);
      treeOf.set(t.id, tree);
      byName.set(t.name, t);
    }
  }
  const values = new Map<string, { id: number; byRank: number[] }>();
  for (const [name, re] of Object.entries(READ)) {
    const t = byName.get(name);
    if (!t) continue;
    values.set(name, { id: t.id, byRank: [0, ...t.desc.map((d) => Number(re.exec(d)?.[1] ?? 0))] });
  }
  return { all: [...defs.values()], values, defs, treeOf, byName };
}
const spent = (b: Build) => {
  let n = 0;
  for (const r of b.values()) n += r;
  return n;
};
const below = (b: Build, tree: TalentTree, row: number) => {
  let n = 0;
  for (const t of tree.talents) if (t.row < row) n += b.get(t.id) ?? 0;
  return n;
};
function valid(b: Build, ix: Index): boolean {
  for (const [id, rank] of b) {
    if (!rank) continue;
    const t = ix.defs.get(id)!;
    if (rank > t.max) return false;
    if (below(b, ix.treeOf.get(id)!, t.row) < t.requiredPoints) return false;
    for (const req of t.requires) if ((b.get(req.id) ?? 0) < req.qty) return false;
  }
  return true;
}

// ---------------------------------------------------------------- effects

/** What a build changes in the damage model. Everything is absolute, so two builds can be compared. */
interface Effects {
  crit: number; // % crit, all attacks
  hit: number; // %
  ssCost: number; // energy off Sinister Strike
  evisCost: number;
  ssDmg: number; // +fraction
  evisDmg: number;
  ssCritBonus: number; // added to the 2x crit multiplier
  ssCritChance: number; // extra % crit on Sinister Strike only
  offhand: number; // +fraction off-hand damage
  expertise: number; // % off the target's dodge and parry, each
  hackRank: number; // Hack and Slash: effect depends on the weapon
  armorIgnore: number; // fraction
  poisonDmg: number;
  poisonChance: number; // added proc chance, absolute %
  ruthless: number; // chance of +1 combo point after a finisher
  sealFate: number; // chance of +1 combo point on a crit
  relentless: number; // chance per combo point to refund 25 energy
  sndDuration: number; // +fraction
  bladeFlurry: boolean;
  adrenalineRush: boolean;
  coldBlood: boolean;
}

// Which number to read from each modelled talent's description.
const READ: Record<string, RegExp> = {
  Aggression: /by (\d+)%/,
  "Coup de Grace": /Eviscerate ability by (\d+)%/,
  Malice: /by (\d+)%/,
  Precision: /by (\d+)%/,
  "Efficient Strikes": /by (\d+)/,
  "Flawless Execution": /by (\d+)/,
  Lethality: /by (\d+)%/,
  "Remorseless Attacks": /a (\d+)% increased/,
  "Dual Wield Specialization": /by (\d+)%/,
  "Weapon Expertise": /by (\d+)%/,
  "Serrated Blades": /ignore (\d+)%/,
  "Vile Poisons": /poisons by (\d+)%/,
  "Improved Poisons": /by (\d+)%/,
  Ruthlessness: /a (\d+)% chance/,
  "Seal Fate": /a (\d+)% chance/,
  "Relentless Strikes": /a (\d+)% chance/,
  "Improved Slice and Dice": /by (\d+)%/,
};

/** Value of a modelled talent at the build's rank (0 when not taken), from a table built once. */
function num(ix: Index, b: Build, name: string): number {
  const entry = ix.values.get(name);
  return entry ? entry.byRank[b.get(entry.id) ?? 0] : 0;
}
const rankOf = (ix: Index, b: Build, name: string) => {
  const t = ix.byName.get(name);
  return t ? (b.get(t.id) ?? 0) : 0;
};
const has = (ix: Index, b: Build, name: string) => rankOf(ix, b, name) > 0;

function effects(ix: Index, b: Build, ssPerFight: number): Effects {
  const aggression = num(ix, b, "Aggression") / 100;
  const coup = num(ix, b, "Coup de Grace") / 100;
  return {
    crit: num(ix, b, "Malice"),
    hit: num(ix, b, "Precision"),
    ssCost: num(ix, b, "Efficient Strikes"),
    evisCost: num(ix, b, "Flawless Execution"),
    ssDmg: aggression,
    evisDmg: (1 + aggression) * (1 + coup) - 1,
    ssCritBonus: num(ix, b, "Lethality") / 100,
    // Remorseless Attacks: a crit bonus on the first strike after a kill, spread over a fight.
    ssCritChance: num(ix, b, "Remorseless Attacks") / Math.max(1, ssPerFight),
    offhand: num(ix, b, "Dual Wield Specialization") / 100,
    expertise: num(ix, b, "Weapon Expertise"),
    hackRank: rankOf(ix, b, "Hack and Slash"),
    armorIgnore: num(ix, b, "Serrated Blades") / 100,
    poisonDmg: num(ix, b, "Vile Poisons") / 100,
    poisonChance: num(ix, b, "Improved Poisons"),
    ruthless: num(ix, b, "Ruthlessness") / 100,
    sealFate: num(ix, b, "Seal Fate") / 100,
    relentless: num(ix, b, "Relentless Strikes") / 100,
    sndDuration: num(ix, b, "Improved Slice and Dice") / 100,
    bladeFlurry: has(ix, b, "Blade Flurry"),
    adrenalineRush: has(ix, b, "Adrenaline Rush"),
    coldBlood: has(ix, b, "Cold Blood"),
  };
}

/** Talents that change damage but that this model cannot value: listed for the user, never chosen for value. */
const UNMODELLED: Record<string, string> = {
  Mutilate: "új támadás, a Sinister Strike helyére lépne; tőrös buildhez való",
  Hemorrhage: "új támadás, a Sinister Strike helyére lépne",
  "Ghostly Strike": "új támadás cooldownnal",
  "Death Mark": "új finisher, a sebzése a tárolt sebzéstől függ",
  Venom: "a Shank használatától függ",
  "Flash of Steel": "a Shank használatától függ",
  "Boot Knife": "a Shank használatától függ",
  Riposte: "csak akkor üt, ha te parryzol; szólóban ér valamit, csapatban alig",
  Composure: "a Poised csak harcon kívül, tele energiával hat",
  "Puncturing Wounds": "Backstab és Mutilate talent",
  Opportunity: "Backstab, Ambush, Garrote és Mutilate talent",
  "Improved Ambush": "nyitótámadás",
  Initiative: "nyitótámadás",
  Premeditation: "nyitás, 2 combo pont cooldownnal",
  "Improved Kidney Shot": "csak a stun ideje alatt hat",
  "Blood Splatter": "Rupture és Garrote időtartam",
  Vigor: "csak a harc elején ad 10 energiát, tartós DPS-t nem",
};

// When the tree demands points that add no modelled damage, prefer these: survival and control
// that helps while leveling. Higher is better; unlisted talents count as 0.
const FILLER: Record<string, number> = {
  "Lightning Reflexes": 5, Deflection: 5, Endurance: 4, "Improved Kick": 4, "Improved Sprint": 3, "Improved Gouge": 3,
  Vigor: 3, Elusiveness: 2, Camouflage: 2, "Master of Deception": 1, Setup: 1, "Heightened Senses": 1,
};

interface Weapons {
  mh: number | null; // item subclass id
  oh: number | null;
}
// Hack and Slash per weapon type: swords and axes proc extra attacks, daggers and fists crit, maces ignore armor.
const hack = (sub: number | null, rank: number) => ({
  extra: sub === 7 || sub === 0 ? rank / 100 : 0,
  crit: sub === 15 || sub === 13 ? rank : 0,
  armor: sub === 4 ? (3 * rank) / 100 : 0,
});

interface Calibration {
  sndUptime: number;
  poisonDps: number;
  restDps: number; // other damage that talents here do not touch
  ssPerFight: number;
}

/** DPS of a build, using the character's gear, measured hit table and measured rotation. */
function evaluate(ctx: GearContext, e: Effects, now: Effects, w: Weapons, cal: Calibration): number {
  const p = ctx.params;
  const sh = ctx.sheet;
  if (!sh.mh) return 0;
  const lvl = p.level;

  // Armor: Classic formula with an assumed mob armor, only used for the "ignore armor" talents.
  const armor = 35 * lvl;
  const taken = (ignore: number) => 1 - (armor * (1 - ignore)) / (armor * (1 - ignore) + 400 + 85 * lvl);
  const hMh = hack(w.mh, e.hackRank);
  const hOh = hack(w.oh, e.hackRank);
  const hMhNow = hack(w.mh, now.hackRank);
  const hOhNow = hack(w.oh, now.hackRank);
  const pfMh = taken(Math.min(0.9, e.armorIgnore + hMh.armor)) / taken(Math.min(0.9, now.armorIgnore + hMhNow.armor));
  const pfOh = taken(Math.min(0.9, e.armorIgnore + hOh.armor)) / taken(Math.min(0.9, now.armorIgnore + hOhNow.armor));

  const critBase = sh.crit + (e.crit - now.crit);
  const critMh = Math.min(100, critBase + hMh.crit - hMhNow.crit) / 100;
  const critOh = Math.min(100, critBase + hOh.crit - hOhNow.crit) / 100;
  const hit = sh.hit + (e.hit - now.hit);
  const dExp = e.expertise - now.expertise;
  const avoid = (Math.max(0, p.dodge - dExp) + Math.max(0, p.parry - dExp)) / 100;
  const glance = p.glance / 100;
  const whiteMiss = Math.max(0, p.whiteMissBase - hit) / 100;
  const yellowMiss = Math.max(0, p.yellowMissBase - hit) / 100;
  const white = (crit: number) => Math.max(0, 1 - whiteMiss - avoid - glance - crit) + glance * 0.7 + crit * 2;
  const landed = Math.max(0, 1 - yellowMiss - avoid);

  // Attack speed: Slice and Dice (+20%) by uptime, Blade Flurry (+20% for 15 s every 2 min).
  const snd = (dur: number) => Math.min(1, cal.sndUptime * (1 + dur));
  const haste =
    ((1 + 0.2 * snd(e.sndDuration)) / (1 + 0.2 * snd(now.sndDuration))) *
    ((1 + (e.bladeFlurry ? 0.2 * (15 / 120) : 0)) / (1 + (now.bladeFlurry ? 0.2 * (15 / 120) : 0)));

  // Energy: how many Sinister Strikes a 5-point finisher cycle takes, and how long it lasts.
  const cycle = (x: Effects, crit: number) => {
    const regen = 10 * (1 + (x.adrenalineRush ? 15 / 300 : 0));
    const strikes = Math.max(1, (5 - x.ruthless) / (1 + x.sealFate * crit));
    const energy = strikes * (45 - x.ssCost) + (35 - x.evisCost) - 25 * Math.min(1, x.relentless * 5);
    const seconds = Math.max(1, energy) / regen;
    return { ss: strikes / seconds, fin: 1 / seconds };
  };
  const critNowMh = Math.min(100, sh.crit) / 100;
  const cNew = cycle(e, critMh + e.ssCritChance / 100);
  const cNow = cycle(now, critNowMh + now.ssCritChance / 100);
  const ssRate = p.ssPerSec * (cNew.ss / cNow.ss);
  const evisRate = p.evisPerSec * (cNew.fin / cNow.fin);

  const avg = (wpn: { min: number; max: number; speed: number }) => (wpn.min + wpn.max) / 2 + (sh.ap / 14) * wpn.speed;
  const mhHit = avg(sh.mh);
  let total = cal.restDps;

  // Auto-attacks; extra attacks from Hack and Slash are extra main-hand swings.
  const mhWhite = p.swingRate * haste * (mhHit / sh.mh.speed) * white(critMh) * pfMh;
  total += mhWhite * (1 + hMh.extra) + hMh.extra * ssRate * landed * mhHit * pfMh;
  if (sh.oh) {
    const ohMult = (1 + e.offhand) / (1 + now.offhand);
    total += p.swingRate * haste * ((avg(sh.oh) * 0.5) / sh.oh.speed) * white(critOh) * pfOh * ohMult * (1 + hOh.extra);
  }

  // Sinister Strike and Eviscerate.
  const ssCrit = Math.min(1, critMh + e.ssCritChance / 100);
  total += ssRate * (mhHit + p.ssBonus) * ((1 + e.ssDmg) / (1 + now.ssDmg)) * pfMh * landed * (1 + ssCrit * (1 + e.ssCritBonus));
  const evis = p.evisDamage * ((1 + e.evisDmg) / (1 + now.evisDmg));
  total += evisRate * evis * landed * (1 + critMh);
  // Cold Blood: one guaranteed crit on an Eviscerate every 3 minutes.
  if (e.coldBlood) total += ((1 - critMh) * evis * landed) / 180;

  // Poisons: damage and proc chance (assumed 20% base chance to apply).
  const poison = (x: Effects) => (1 + x.poisonDmg) * (1 + x.poisonChance / 20);
  total += cal.poisonDps * (poison(e) / poison(now)) * haste;
  return total;
}

// ---------------------------------------------------------------- search

/** Bring a talent to a rank, spending the fewest points on what the tree demands first. */
function reach(b: Build, ix: Index, id: number, rank: number, score: (x: Build) => number): Build | null {
  let cur = new Map(b);
  const t = ix.defs.get(id)!;
  if (rank > t.max) return null;
  for (const req of t.requires) {
    if ((cur.get(req.id) ?? 0) >= req.qty) continue;
    const next = reach(cur, ix, req.id, req.qty, score);
    if (!next) return null;
    cur = next;
  }
  const tree = ix.treeOf.get(id)!;
  // Fill the rows above with whatever is worth the most there.
  for (let guard = 0; below(cur, tree, t.row) < t.requiredPoints; guard++) {
    if (guard > 60) return null;
    let best: Build | null = null;
    let bestScore = -Infinity;
    for (const f of tree.talents) {
      if (f.row >= t.row || (cur.get(f.id) ?? 0) >= f.max) continue;
      if (below(cur, tree, f.row) < f.requiredPoints) continue;
      if (f.requires.some((r) => (cur.get(r.id) ?? 0) < r.qty)) continue;
      const trial = new Map(cur).set(f.id, (cur.get(f.id) ?? 0) + 1);
      // Among equally worthless fillers prefer the lowest row, then tree order.
      const s = score(trial) - f.row * 1e-6;
      if (s > bestScore) {
        bestScore = s;
        best = trial;
      }
    }
    if (!best) return null;
    cur = best;
  }
  cur.set(id, Math.max(cur.get(id) ?? 0, rank));
  return valid(cur, ix) ? cur : null;
}

/** Spend points up to the budget, always taking the step with the best gain per point. */
function grow(start: Build, ix: Index, budget: number, score: (x: Build) => number): { build: Build; order: number[] } {
  let cur = new Map(start);
  const order: number[] = [];
  while (spent(cur) < budget) {
    const base = score(cur);
    const left = budget - spent(cur);
    let best: Build | null = null;
    let bestRatio = -Infinity;
    for (const t of ix.defs.values()) {
      const rank = cur.get(t.id) ?? 0;
      if (rank >= t.max) continue;
      // Look at most two rows ahead: deeper talents come into view as the rows fill up, and
      // trying every deep talent at every step is what makes the search expensive.
      if (t.requiredPoints - below(cur, ix.treeOf.get(t.id)!, t.row) > 10) continue;
      const next = reach(cur, ix, t.id, rank + 1, score);
      if (!next) continue;
      const cost = spent(next) - spent(cur);
      if (cost <= 0 || cost > left) continue;
      // Tiny bias towards cheap, shallow talents so worthless points are spent sensibly.
      const ratio = (score(next) - base) / cost - cost * 1e-7 - t.row * 1e-8;
      if (ratio > bestRatio) {
        bestRatio = ratio;
        best = next;
      }
    }
    if (!best) break;
    // Record the individual points in the order they have to be taken (shallow rows first).
    const added: number[] = [];
    for (const [id, r] of best) for (let k = cur.get(id) ?? 0; k < r; k++) added.push(id);
    added.sort((a, b) => ix.defs.get(a)!.row - ix.defs.get(b)!.row);
    order.push(...added);
    cur = best;
  }
  return { build: cur, order };
}

/** Local improvement: move one point at a time while that helps. */
function polish(start: Build, ix: Index, score: (x: Build) => number): Build {
  let cur = new Map(start);
  let curScore = score(cur);
  for (let pass = 0; pass < 4; pass++) {
    let improved = false;
    for (const from of ix.defs.values()) {
      const r = cur.get(from.id) ?? 0;
      if (!r) continue;
      const removed = new Map(cur).set(from.id, r - 1);
      if (!valid(removed, ix)) continue;
      for (const to of ix.defs.values()) {
        if (to.id === from.id || (removed.get(to.id) ?? 0) >= to.max) continue;
        const trial = new Map(removed).set(to.id, (removed.get(to.id) ?? 0) + 1);
        if (!valid(trial, ix)) continue;
        const s = score(trial);
        if (s > curScore + 1e-6) {
          cur = trial;
          curScore = s;
          improved = true;
          break;
        }
      }
    }
    if (!improved) break;
  }
  return cur;
}

// ---------------------------------------------------------------- report

export interface TreeView {
  name: string;
  points: number;
  talents: { name: string; rank: number; max: number; was: number; note: string | null }[];
}
export interface TalentStep {
  level: number;
  talent: string;
  tree: string;
  rank: number;
  max: number;
  gainPct: number; // cumulative, over the current build
  why: string;
}
export interface TalentReport {
  level: number;
  points: number; // talent points at this level
  spent: number;
  current: { dps: number; split: string };
  /** Best build with the points you have now (needs a respec). */
  ideal: { dps: number; gainPct: number; split: string; trees: TreeView[] };
  /** Best build at level 60. */
  final: { split: string; gainPct: number; trees: TreeView[] };
  /** Next points without a respec, in the order to take them. */
  steps: TalentStep[];
  /** Level 60 build reached by continuing without a respec, vs. the best one from scratch. */
  continued: { split: string; gainPct: number };
  unmodelled: { name: string; why: string; tree: string }[];
  notes: string[];
}

const TREE_HU: Record<string, string> = { RogueAssassination: "Assassination", RogueCombat: "Combat", RogueSubtlety: "Subtlety" };

function views(data: TalentData, b: Build, was: Build): TreeView[] {
  return data.trees.map((tree) => ({
    name: TREE_HU[tree.name] ?? tree.name,
    points: tree.talents.reduce((a, t) => a + (b.get(t.id) ?? 0), 0),
    talents: tree.talents
      .filter((t) => (b.get(t.id) ?? 0) > 0 || (was.get(t.id) ?? 0) > 0)
      .sort((x, y) => x.row - y.row || x.col - y.col)
      .map((t) => ({ name: t.name, rank: b.get(t.id) ?? 0, max: t.max, was: was.get(t.id) ?? 0, note: UNMODELLED[t.name] ?? null })),
  }));
}
const split = (data: TalentData, b: Build) =>
  data.trees.map((tree) => tree.talents.reduce((a, t) => a + (b.get(t.id) ?? 0), 0)).join(" / ");

export async function talentReport(env: Env): Promise<TalentReport | null> {
  const ctx = await gearContext(env);
  if (!ctx) return null;
  const data = await loadTalents(env, 4);
  if (!data) return null;
  const ix = index(data);
  const snaps = await latestSnapshots(env);
  const specs = snaps.specializations?.json as Obj | undefined;
  const equip = snaps.equipment?.json as Obj | undefined;

  // The build you have now, matched to the tree data by talent name.
  const current: Build = new Map();
  const groups = (specs?.specialization_groups ?? []) as Obj[];
  const active = groups.find((g) => g.is_active) ?? groups[0];
  for (const sp of (active?.specializations ?? []) as Obj[]) {
    for (const t of (sp.talents ?? []) as Obj[]) {
      const def = ix.byName.get(String(t.talent?.name));
      if (def) current.set(def.id, Math.min(def.max, Number(t.talent_rank) || 0));
    }
  }
  const sub = (slot: string) => {
    const it = ((equip?.equipped_items ?? []) as Obj[]).find((i) => i.slot?.type === slot);
    return it ? Number(it.item_subclass?.id) : null;
  };
  const weapons: Weapons = { mh: sub("MAIN_HAND"), oh: sub("OFF_HAND") };

  const combat = ctx.combat;
  const poisonDmg = combat ? combat.abilities.filter((a) => /poison/i.test(a.name)).reduce((s, a) => s + a.dmg, 0) : 0;
  const otherDmg = combat
    ? combat.abilities.filter((a) => !["Melee", "Sinister Strike", "Eviscerate"].includes(a.name)).reduce((s, a) => s + a.dmg, 0)
    : 0;
  const poisonDps = otherDmg > 0 ? ctx.params.otherDps * (poisonDmg / otherDmg) : 0;
  const ss = combat?.abilities.find((a) => a.name === "Sinister Strike");
  const cal: Calibration = {
    sndUptime: (combat?.auras.find((a) => a.name === "Slice and Dice")?.uptimePct ?? 50) / 100,
    poisonDps,
    restDps: ctx.params.otherDps - poisonDps,
    ssPerFight: combat && ss ? Math.max(1, ss.n / combat.fights) : 6,
  };

  const now = effects(ix, current, cal.ssPerFight);
  const cache = new Map<string, number>();
  const score = (b: Build): number => {
    let key = "";
    let utility = 0;
    for (const t of ix.all) {
      const r = b.get(t.id) ?? 0;
      key += r;
      if (r) utility += r * (FILLER[t.name] ?? 0);
    }
    let v = cache.get(key);
    if (v == null) {
      // The utility term is far below any real DPS difference: it only breaks ties between fillers.
      v = evaluate(ctx, effects(ix, b, cal.ssPerFight), now, weapons, cal) + utility * 1e-4;
      cache.set(key, v);
    }
    return v;
  };

  const level = ctx.level;
  const points = Math.max(0, level - 9);
  const base = score(current);
  const pct = (b: Build) => ((score(b) - base) / base) * 100;

  const ideal = polish(grow(new Map(), ix, Math.max(points, spent(current)), score).build, ix, score);
  const final = polish(grow(new Map(), ix, 51, score).build, ix, score);
  const cont = grow(current, ix, 51, score);

  // Name each next point with the level it becomes available at.
  const steps: TalentStep[] = [];
  const walk = new Map(current);
  let n = spent(current);
  for (const id of cont.order.slice(0, 14)) {
    const def = ix.defs.get(id)!;
    const before = score(walk);
    walk.set(id, (walk.get(id) ?? 0) + 1);
    n++;
    const after = score(walk);
    steps.push({
      level: Math.max(level, n + 9),
      talent: def.name,
      tree: TREE_HU[ix.treeOf.get(id)!.name] ?? ix.treeOf.get(id)!.name,
      rank: walk.get(id)!,
      max: def.max,
      gainPct: ((after - base) / base) * 100,
      why: after - before > base * 0.0005 ? (def.desc[walk.get(id)! - 1] ?? "") : "töltelék pont: a fa következő sorához kell",
    });
  }

  const notes: string[] = [
    "A keresés a mostani felszereléseddel, a mért találati arányaiddal és a mért rotációddal számol, Sinister Strike-ra épülő buildet feltételezve.",
    `Hack and Slash: a főkezed ${weapons.mh === 4 ? "buzogány (páncéláttörés)" : weapons.mh === 7 || weapons.mh === 0 ? "kard vagy balta (extra támadás)" : "tőr vagy ökölfegyver (crit)"}; fegyverváltáskor az értéke változik.`,
    "Feltevések: a mobok páncélja 35 × szint; a mérgek alap esélye 20%; Blade Flurry és Adrenaline Rush cooldownra használva.",
  ];
  if (!combat) notes.push("Nincs rögzített harc, ezért a rotáció és a Slice and Dice fedettség tankönyvi érték.");

  const unmodelled: TalentReport["unmodelled"] = [];
  for (const tree of data.trees) {
    for (const t of tree.talents) {
      if (UNMODELLED[t.name]) unmodelled.push({ name: t.name, why: UNMODELLED[t.name], tree: TREE_HU[tree.name] ?? tree.name });
    }
  }

  return {
    level,
    points,
    spent: spent(current),
    current: { dps: base, split: split(data, current) },
    ideal: { dps: score(ideal), gainPct: pct(ideal), split: split(data, ideal), trees: views(data, ideal, current) },
    final: { split: split(data, final), gainPct: pct(final), trees: views(data, final, current) },
    steps,
    continued: { split: split(data, cont.build), gainPct: pct(cont.build) },
    unmodelled,
    notes,
  };
}

// The search is too heavy to repeat on every page view: reuse the result until the inputs change.
const TALENT_VERSION = 3;
/**
 * With `defer`, an out-of-date result is returned at once and the fresh one is computed after the
 * response (a page view should never have to wait for, or pay for, the search).
 */
export async function cachedTalentReport(
  env: Env,
  defer?: (work: Promise<unknown>) => void,
): Promise<TalentReport | null> {
  const row = await env.DB.prepare(
    "SELECT (SELECT MAX(id) FROM snapshots WHERE slug = ?1) || '|' || " +
      "(SELECT COUNT(*) || ':' || COALESCE(MAX(start), 0) FROM fights WHERE slug = ?1) || '|' || " +
      "COALESCE((SELECT updated_at FROM manual_state WHERE key = ?1 || ':buffs'), '') || '|' || " +
      "COALESCE((SELECT updated_at FROM talent_data WHERE class_id = 4), '') AS stamp",
  )
    .bind(env.CHARACTER_SLUG)
    .first<{ stamp: string }>();
  const stamp = `${TALENT_VERSION}|${row?.stamp ?? ""}`;
  const hit = await stateGet(env, "talent_cache");
  if (hit) {
    try {
      const cached = JSON.parse(hit.value) as { stamp: string; report: TalentReport | null };
      if (cached.stamp === stamp) return cached.report;
      if (defer && cached.report) {
        defer(
          talentReport(env)
            .then((fresh) => statePut(env, "talent_cache", JSON.stringify({ stamp, report: fresh })))
            .catch(() => null),
        );
        return cached.report;
      }
    } catch {
      // rebuild
    }
  }
  const report = await talentReport(env);
  await statePut(env, "talent_cache", JSON.stringify({ stamp, report }));
  return report;
}
