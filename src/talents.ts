import type { Env } from "./env";
import { type GearContext, gearContext, instantWeaponDamage, normalizedSpeed } from "./gear";
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
  for (const [key, [name, re]] of Object.entries(READ_MORE)) {
    const t = byName.get(name);
    if (t) values.set(key, { id: t.id, byRank: [0, ...t.desc.map((d) => Number(re.exec(d)?.[1] ?? 0))] });
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
  opportunity: number; // +fraction Backstab and Mutilate damage
  backstabCrit: number; // extra % crit
  mutilateCrit: number;
  backstabCombo: number; // chance of an extra combo point from Backstab
  hemorrhage: boolean;
  mutilate: boolean;
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
  Opportunity: /by (\d+)%/,
};
// Talents with more than one number: key -> [talent, pattern].
const READ_MORE: Record<string, [string, RegExp]> = {
  "pw.backstab": ["Puncturing Wounds", /Backstab by (\d+)%/],
  "pw.mutilate": ["Puncturing Wounds", /Mutilate by (\d+)%/],
  "pw.combo": ["Puncturing Wounds", /a (\d+)% chance to add/],
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
    opportunity: num(ix, b, "Opportunity") / 100,
    backstabCrit: num(ix, b, "pw.backstab"),
    mutilateCrit: num(ix, b, "pw.mutilate"),
    backstabCombo: num(ix, b, "pw.combo") / 100,
    hemorrhage: has(ix, b, "Hemorrhage"),
    mutilate: has(ix, b, "Mutilate"),
  };
}

/** Talents that change damage but that this model cannot value: listed for the user, never chosen for value. */
const UNMODELLED: Record<string, string> = {
  "Ghostly Strike": "új támadás cooldownnal",
  "Death Mark": "új finisher, a sebzése a tárolt sebzéstől függ",
  Venom: "a Shank használatától függ",
  "Flash of Steel": "a Shank használatától függ",
  "Boot Knife": "a Shank használatától függ",
  Riposte: "csak akkor üt, ha te parryzol; szólóban ér valamit, csapatban alig",
  Composure: "a Poised csak harcon kívül, tele energiával hat",
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

interface Weapon {
  min: number;
  max: number;
  speed: number;
}
/** The weapons a rotation is evaluated with (a dagger rotation may swap the hands). */
interface Loadout {
  mh: Weapon | null;
  oh: Weapon | null;
  mhSub: number | null; // item subclass id: 15 dagger, 7 sword, 4 mace, 13 fist, 0 axe
  ohSub: number | null;
}

export type Rotation = "ss" | "hemo" | "backstab" | "mutilate";

// Ability values from the Wowhead Forever tooltips: [level learned, bonus damage].
const BACKSTAB_BONUS: [number, number][] = [[4, 10], [12, 20], [20, 32], [28, 46], [36, 60], [44, 90], [52, 110], [60, 150]];
const MUTILATE_BONUS: [number, number][] = [[40, 40], [50, 57], [60, 79]];
const atLevel = (table: [number, number][], level: number) =>
  [...table].reverse().find(([l]) => l <= level)?.[1] ?? table[0][1];
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
function evaluate(
  ctx: GearContext,
  e: Effects,
  now: Effects,
  w: Loadout,
  home: Loadout, // the weapons as worn today, which the measured numbers belong to
  cal: Calibration,
  rotation: Rotation,
): number {
  const p = ctx.params;
  const sh = { ...ctx.sheet, mh: w.mh, oh: w.oh };
  if (!sh.mh || !home.mh) return 0;
  const lvl = p.level;

  // Armor: Classic formula with an assumed mob armor, only used for the "ignore armor" talents.
  const armor = 35 * lvl;
  const taken = (ignore: number) => 1 - (armor * (1 - ignore)) / (armor * (1 - ignore) + 400 + 85 * lvl);
  const hMh = hack(w.mhSub, e.hackRank);
  const hOh = hack(w.ohSub, e.hackRank);
  const hMhNow = hack(home.mhSub, now.hackRank);
  const hOhNow = hack(home.ohSub, now.hackRank);
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

  const avg = (wpn: Weapon) => (wpn.min + wpn.max) / 2 + (sh.ap / 14) * wpn.speed;
  const mhHit = avg(sh.mh);
  const dagger = w.mhSub === 15;

  // The combo point builder of this rotation: energy cost, combo points, damage and crit.
  const builder = (() => {
    if (rotation === "hemo") {
      return { cost: 35 - e.ssCost, cp: 1, crit: 0, dmg: mhHit * (dagger ? 1.45 : 1) };
    }
    if (rotation === "backstab") {
      return {
        cost: 60,
        cp: 1 + e.backstabCombo,
        crit: e.backstabCrit,
        dmg: (1.5 * mhHit + atLevel(BACKSTAB_BONUS, lvl)) * (1 + e.opportunity),
      };
    }
    if (rotation === "mutilate") {
      const bonus = atLevel(MUTILATE_BONUS, lvl);
      // Both weapons, +20% against a poisoned target (poisons are assumed to be on).
      const hit = 0.9 * mhHit + bonus + (sh.oh ? (0.9 * avg(sh.oh) + bonus) * 0.5 * (1 + e.offhand) : 0);
      return { cost: 60, cp: 2, crit: e.mutilateCrit, dmg: hit * 1.2 * (1 + e.opportunity) };
    }
    // Sinister Strike: the bonus damage is the one measured in your fights.
    // Sinister Strike uses the normalized speed (instantWeaponDamage in gear.ts)
    const ssHit = instantWeaponDamage({ ...sh.mh, norm: normalizedSpeed(w.mhSub) }, sh.ap);
    return { cost: 45 - e.ssCost, cp: 1, crit: e.ssCritChance, dmg: (ssHit + p.ssBonus) * ((1 + e.ssDmg) / (1 + now.ssDmg)) };
  })();

  // Energy: how many builders a 5-point finisher cycle takes, and how long the cycle lasts.
  const cycle = (x: Effects, cost: number, cp: number, crit: number) => {
    const regen = 10 * (1 + (x.adrenalineRush ? 15 / 300 : 0));
    const strikes = Math.max(1, (5 - x.ruthless) / (cp + x.sealFate * crit));
    const energy = strikes * cost + (35 - x.evisCost) - 25 * Math.min(1, x.relentless * 5);
    const seconds = Math.max(1, energy) / regen;
    return { builders: strikes / seconds, fin: 1 / seconds };
  };
  // The measured Sinister Strike and Eviscerate rates say how much of the theoretical energy
  // you really turn into attacks; the same share is assumed for every rotation.
  const critHome = Math.min(100, ctx.sheet.crit) / 100;
  const theoryNow = cycle(now, 45 - now.ssCost, 1, critHome + now.ssCritChance / 100);
  const builderCrit = Math.min(1, critMh + builder.crit / 100);
  const theory = cycle(e, builder.cost, builder.cp, builderCrit);
  const ssRate = p.ssPerSec * (theory.builders / theoryNow.builders);
  const evisRate = p.evisPerSec * (theory.fin / theoryNow.fin);

  let total = cal.restDps;

  // Auto-attacks; extra attacks from Hack and Slash are extra main-hand swings.
  const mhWhite = p.swingRate * haste * (mhHit / sh.mh.speed) * white(critMh) * pfMh;
  total += mhWhite * (1 + hMh.extra) + hMh.extra * ssRate * landed * mhHit * pfMh;
  if (sh.oh) {
    const ohMult = (1 + e.offhand) / (1 + now.offhand);
    total += p.swingRate * haste * ((avg(sh.oh) * 0.5) / sh.oh.speed) * white(critOh) * pfOh * ohMult * (1 + hOh.extra);
  }

  // Builder and Eviscerate. Lethality raises the crit multiplier of every builder here.
  total += ssRate * builder.dmg * pfMh * landed * (1 + builderCrit * (1 + e.ssCritBonus));
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

// ---------------------------------------------------------------- PvP

// A PvP build cannot be computed from a damage model: it is about burst, control and getting
// away. These weights are a judgement of each talent's worth in duels and battlegrounds
// (0-10 for the fully ranked talent), with the reason shown to the user.
const PVP: Record<string, [number, string]> = {
  Preparation: [10, "minden cooldown újra: második Vanish, Sprint, Evasion"],
  "Cold Blood": [9, "garantált crit a nyitásra vagy az Eviscerate-re"],
  Malice: [8, "crit: a burst alapja"],
  Lethality: [8, "nagyobb critek"],
  "Seal Fate": [8, "crit után extra combo pont: gyorsabb Kidney Shot és Eviscerate"],
  Initiative: [8, "nyitásból rögtön 2-3 combo pont"],
  Premeditation: [8, "2 ingyen combo pont a harc elején"],
  Elusiveness: [8, "rövidebb Vanish és Blind cooldown"],
  Riposte: [8, "lefegyverzés: melee ellen harcot dönt el"],
  "Improved Kick": [8, "némítás: casterek ellen kulcs"],
  "Improved Kidney Shot": [7, "a stun alatt több sebzést kap a célpont"],
  "Improved Sprint": [7, "kiszabadít a lassításból és a gyökerekből"],
  Camouflage: [7, "gyorsabb lopakodás, rövidebb Stealth cooldown"],
  Opportunity: [7, "nagyobb Ambush és Backstab"],
  "Improved Ambush": [7, "szinte biztos Ambush crit"],
  Hemorrhage: [7, "olcsó combo pont gyűjtő"],
  "Improved Gouge": [6, "hosszabb Gouge: több idő kötözni vagy újranyitni"],
  "Master of Deception": [6, "nehezebben vesznek észre lopakodva"],
  "Dirty Deeds": [6, "olcsóbb Cheap Shot és Garrote"],
  "Ghostly Strike": [6, "ütés és dodge egyben"],
  "Relentless Strikes": [6, "energia vissza a finisherekből"],
  "Adrenaline Rush": [6, "dupla energia 15 másodpercig: burst ablak"],
  Mutilate: [6, "nagy, gyors combo pont gyűjtő"],
  Vigor: [5, "több energia a nyitáshoz"],
  Ruthlessness: [5, "extra combo pont a finisher után"],
  "Improved Poisons": [5, "megbízhatóbb mérgek (Crippling, Mind-numbing)"],
  "Lightning Reflexes": [5, "dodge melee ellen"],
  Deflection: [5, "parry, és a Riposte előfeltétele"],
  Endurance: [5, "rövidebb Sprint és Evasion cooldown"],
  "Puncturing Wounds": [5, "Backstab crit és extra combo pont"],
  "Dirty Tricks": [5, "olcsóbb Sap és Blind"],
  "Heightened Senses": [5, "észreveszed a lopakodókat, kevesebb varázslat talál"],
  "Death Mark": [5, "tárolt sebzés egyben: burst"],
  Setup: [4, "combo pont dodge után"],
  "Vile Poisons": [4, "erősebb mérgek"],
  "Coup de Grace": [4, "nagyobb Eviscerate"],
  Precision: [4, "kevesebb mellé ment ütés"],
  "Serrated Blades": [4, "páncéláttörés plate ellen"],
  "Blade Flurry": [4, "burst cooldown"],
  "Remorseless Attacks": [3, "crit a következő ütésre kill után"],
  "Efficient Strikes": [3, "olcsóbb Sinister Strike és Hemorrhage"],
  "Flawless Execution": [3, "olcsóbb Eviscerate"],
  "Weapon Expertise": [3, "kevesebb dodge és parry ellened"],
  Aggression: [3, "nagyobb Sinister Strike és Eviscerate"],
  "Dual Wield Specialization": [3, "balkezes sebzés"],
  "Hack and Slash": [3, "fegyverfüggő bónusz"],
  Venom: [3, "méregsebzés a Shank után"],
  "Blood Splatter": [2, "hosszabb Rupture és Garrote"],
  "Quick Getaway": [2, "második Sap célpont"],
  "Boot Knife": [2, "combo pont a Shankből"],
  "Improved Expose Armor": [1, "ritkán használt"],
  "Improved Slice and Dice": [1, "PvP-ben nincs idő fenntartani"],
  Composure: [1, "csak harcon kívül hat"],
  "Flash of Steel": [1, "a Shank ritka PvP-ben"],
};

// ---------------------------------------------------------------- report

export interface TreeView {
  name: string;
  points: number;
  talents: { name: string; rank: number; max: number; was: number; note: string | null }[];
}
export interface BuildView {
  split: string;
  gainPct: number;
  trees: TreeView[];
}
export interface RotationResult {
  key: Rotation;
  label: string;
  /** What the rotation needs or assumes, shown under its name. */
  note: string;
  /** Why there is no result (missing weapon, level), or null. */
  blocked: string | null;
  now: BuildView | null;
  final: BuildView | null;
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
  points: number;
  spent: number;
  current: { dps: number; split: string };
  steps: TalentStep[];
  continued: { split: string; gainPct: number };
  rotations: RotationResult[];
  pvp: { now: TreeView[]; nowSplit: string; final: TreeView[]; finalSplit: string } | null;
  /** Parts still being computed in the background. */
  pending: string[];
  unmodelled: { name: string; why: string; tree: string }[];
  notes: string[];
}

const TREE_HU: Record<string, string> = { RogueAssassination: "Assassination", RogueCombat: "Combat", RogueSubtlety: "Subtlety" };
const ROTATIONS: { key: Rotation; label: string; talent?: string; minLevel?: number }[] = [
  { key: "ss", label: "Sinister Strike" },
  { key: "hemo", label: "Hemorrhage", talent: "Hemorrhage", minLevel: 30 },
  { key: "backstab", label: "Backstab (tőr)" },
  { key: "mutilate", label: "Mutilate", talent: "Mutilate", minLevel: 40 },
];
const PARTS = ["ss", "hemo", "backstab", "mutilate", "pvp"] as const;
type Part = (typeof PARTS)[number];

function views(data: TalentData, b: Build, was: Build, notes: (name: string) => string | null): TreeView[] {
  return data.trees.map((tree) => ({
    name: TREE_HU[tree.name] ?? tree.name,
    points: tree.talents.reduce((a, t) => a + (b.get(t.id) ?? 0), 0),
    talents: tree.talents
      .filter((t) => (b.get(t.id) ?? 0) > 0 || (was.get(t.id) ?? 0) > 0)
      .sort((x, y) => x.row - y.row || x.col - y.col)
      .map((t) => ({ name: t.name, rank: b.get(t.id) ?? 0, max: t.max, was: was.get(t.id) ?? 0, note: notes(t.name) })),
  }));
}
const split = (data: TalentData, b: Build) =>
  data.trees.map((tree) => tree.talents.reduce((a, t) => a + (b.get(t.id) ?? 0), 0)).join(" / ");

/** Everything the parts share: tree data, the current build, weapons and the measured calibration. */
async function prepare(env: Env) {
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
  const home: Loadout = { mh: ctx.sheet.mh, oh: ctx.sheet.oh, mhSub: sub("MAIN_HAND"), ohSub: sub("OFF_HAND") };
  // Dagger rotations need the dagger in the main hand: swap the hands if it is in the off hand.
  const daggerLoadout: Loadout | null =
    home.mhSub === 15 ? home : home.ohSub === 15 ? { mh: home.oh, oh: home.mh, mhSub: home.ohSub, ohSub: home.mhSub } : null;

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

  /** A scoring function for one rotation; a build without the rotation's key talent scores nothing. */
  const scorer = (rotation: Rotation, loadout: Loadout, must?: string) => {
    const cache = new Map<string, number>();
    const mustId = must ? ix.byName.get(must)?.id : undefined;
    return (b: Build): number => {
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
        v =
          mustId != null && !(b.get(mustId) ?? 0)
            ? -1e6
            : evaluate(ctx, effects(ix, b, cal.ssPerFight), now, loadout, home, cal, rotation) + utility * 1e-4;
        cache.set(key, v);
      }
      return v;
    };
  };

  const level = ctx.level;
  const base = scorer("ss", home)(current);
  return { ctx, data, ix, current, home, daggerLoadout, combat, scorer, level, points: Math.max(0, level - 9), base };
}
type Prepared = NonNullable<Awaited<ReturnType<typeof prepare>>>;

const dpsNote = (name: string) => UNMODELLED[name] ?? null;

function rotationPart(p: Prepared, key: Rotation): RotationResult {
  const def = ROTATIONS.find((r) => r.key === key)!;
  const { ix, data, current, base, level, points } = p;
  const dagger = key === "backstab";
  const loadout = dagger ? p.daggerLoadout : p.home;
  const swapped = dagger && loadout !== p.home;
  const note =
    key === "ss"
      ? "a mostani rotációd; a mért adataidból számol"
      : key === "hemo"
        ? "35 energiás gyűjtő; tőrrel a főkézben 145% fegyversebzés"
        : key === "backstab"
          ? `csak a célpont háta mögül megy, ezért csapatban reális${swapped ? "; a tőrödet a főkézbe, a mostani főkezest a balkézbe téve számol" : ""}`
          : "mindkét fegyverrel üt, 2 combo pontot ad; 40-es szinttől";
  if (!loadout) return { key, label: def.label, note, blocked: "Nincs tőröd: ehhez tőr kell a főkézbe.", now: null, final: null };

  const score = p.scorer(key, loadout, def.talent);
  const pct = (b: Build) => ((score(b) - base) / base) * 100;
  const build = (budget: number): Build | null => {
    let start: Build = new Map();
    if (def.talent) {
      const seed = reach(start, ix, ix.byName.get(def.talent)!.id, 1, score);
      if (!seed || spent(seed) > budget) return null;
      start = seed;
    }
    return polish(grow(start, ix, budget, score).build, ix, score);
  };
  const view = (b: Build | null): BuildView | null =>
    b ? { split: split(data, b), gainPct: pct(b), trees: views(data, b, current, dpsNote) } : null;

  const tooLow = def.minLevel != null && level < def.minLevel;
  const nowBuild = tooLow ? null : build(Math.max(points, spent(current)));
  return {
    key,
    label: def.label,
    note,
    blocked: tooLow ? `${def.minLevel}-es szinttől érhető el.` : !nowBuild && def.talent ? "A mostani pontjaidból még nem érhető el." : null,
    now: view(nowBuild),
    final: view(build(51)),
  };
}

/** The current rotation also yields the "what to take next" list. */
function stepsPart(p: Prepared) {
  const { ix, data, current, base, level } = p;
  const score = p.scorer("ss", p.home);
  const cont = grow(current, ix, 51, score);
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
  return { steps, continued: { split: split(data, cont.build), gainPct: ((score(cont.build) - base) / base) * 100 } };
}

function pvpPart(p: Prepared): NonNullable<TalentReport["pvp"]> {
  const { ix, data, current, points } = p;
  const score = (b: Build) => {
    let v = 0;
    for (const t of ix.all) {
      const r = b.get(t.id) ?? 0;
      if (r) v += ((PVP[t.name]?.[0] ?? 0) * r) / t.max;
    }
    return v;
  };
  const note = (name: string) => PVP[name]?.[1] ?? null;
  const build = (budget: number) => polish(grow(new Map(), ix, budget, score).build, ix, score);
  const now = build(Math.max(points, spent(current)));
  const final = build(51);
  return {
    now: views(data, now, current, note),
    nowSplit: split(data, now),
    final: views(data, final, current, note),
    finalSplit: split(data, final),
  };
}

// ---------------------------------------------------------------- cache, built one part at a time

// The searches are too heavy to run together inside one request. Each call computes at most
// one missing part and stores it; the page shows what is ready and the rest fills in over the
// next page views and scheduled runs.
const TALENT_VERSION = 5;

async function talentStamp(env: Env): Promise<string> {
  const row = await env.DB.prepare(
    "SELECT (SELECT MAX(id) FROM snapshots WHERE slug = ?1) || '|' || " +
      "(SELECT COUNT(*) || ':' || COALESCE(MAX(start), 0) FROM fights WHERE slug = ?1) || '|' || " +
      "COALESCE((SELECT updated_at FROM manual_state WHERE key = ?1 || ':buffs'), '') || '|' || " +
      "COALESCE((SELECT updated_at FROM talent_data WHERE class_id = 4), '') AS stamp",
  )
    .bind(env.CHARACTER_SLUG)
    .first<{ stamp: string }>();
  return `${TALENT_VERSION}|${row?.stamp ?? ""}`;
}

interface TalentCache {
  stamp: string;
  parts: Partial<Record<Part, unknown>>;
  head?: Pick<TalentReport, "level" | "points" | "spent" | "current" | "unmodelled" | "notes">;
}

async function readCache(env: Env): Promise<TalentCache | null> {
  const hit = await stateGet(env, "talent_cache");
  if (!hit) return null;
  try {
    const c = JSON.parse(hit.value) as TalentCache;
    return c && typeof c === "object" && c.parts ? c : null;
  } catch {
    return null;
  }
}

function assemble(c: TalentCache): TalentReport | null {
  if (!c.head || !c.parts.ss) return null;
  const ss = c.parts.ss as { rotation: RotationResult; steps: TalentStep[]; continued: TalentReport["continued"] };
  const rotations = [ss.rotation];
  for (const key of ["hemo", "backstab", "mutilate"] as const) if (c.parts[key]) rotations.push(c.parts[key] as RotationResult);
  return {
    ...c.head,
    steps: ss.steps,
    continued: ss.continued,
    rotations,
    pvp: (c.parts.pvp as TalentReport["pvp"]) ?? null,
    pending: PARTS.filter((part) => !c.parts[part]),
  };
}

/** Compute the next missing part. Returns true when there was something to do. */
export async function advanceTalents(env: Env): Promise<boolean> {
  const stamp = await talentStamp(env);
  let cache = await readCache(env);
  if (!cache || cache.stamp !== stamp) cache = { stamp, parts: {} };
  const next = PARTS.find((part) => !cache!.parts[part]);
  if (!next) return false;
  const p = await prepare(env);
  if (!p) return false;

  if (next === "ss") {
    const unmodelled: TalentReport["unmodelled"] = [];
    for (const tree of p.data.trees) {
      for (const t of tree.talents) {
        if (UNMODELLED[t.name]) unmodelled.push({ name: t.name, why: UNMODELLED[t.name], tree: TREE_HU[tree.name] ?? tree.name });
      }
    }
    const mh = p.home.mhSub;
    const notes = [
      "Minden rotáció a mostani felszereléseddel, a mért találati arányaiddal és a mostani szinted képességeivel számol.",
      "A Sinister Strike a mért rotációdból indul; a többi rotációnál azt feltételezi, hogy az energiádat ugyanolyan arányban váltod támadásra.",
      `Hack and Slash: a főkezed ${mh === 4 ? "buzogány (páncéláttörés)" : mh === 7 || mh === 0 ? "kard vagy balta (extra támadás)" : "tőr vagy ökölfegyver (crit)"}; fegyverváltáskor az értéke változik.`,
      "Feltevések: a mobok páncélja 35 × szint; a mérgek alap esélye 20%; a célpont mérgezett; a cooldownokat használod.",
    ];
    if (!p.combat) notes.push("Nincs rögzített harc, ezért a rotáció és a Slice and Dice fedettség tankönyvi érték.");
    cache.head = {
      level: p.level,
      points: p.points,
      spent: spent(p.current),
      current: { dps: p.base, split: split(p.data, p.current) },
      unmodelled,
      notes,
    };
    cache.parts.ss = { rotation: rotationPart(p, "ss"), ...stepsPart(p) };
  } else if (next === "pvp") {
    cache.parts.pvp = pvpPart(p);
  } else {
    cache.parts[next] = rotationPart(p, next);
  }
  await statePut(env, "talent_cache", JSON.stringify(cache));
  return true;
}

/**
 * What is ready of the talent report. With `defer`, one more missing part is computed after
 * the response, so a page view never pays for more than the first part.
 */
export async function cachedTalentReport(env: Env, defer?: (work: Promise<unknown>) => void): Promise<TalentReport | null> {
  const stamp = await talentStamp(env);
  let cache = await readCache(env);
  const fresh = !!cache && cache.stamp === stamp;
  if (!fresh && cache && assemble(cache) && defer) {
    // Out of date: show the previous result now and start over in the background.
    defer(advanceTalents(env).catch(() => null));
    return assemble(cache);
  }
  if (!fresh || !cache?.parts.ss) {
    await advanceTalents(env);
    cache = await readCache(env);
  }
  if (!cache) return null;
  const report = assemble(cache);
  if (report?.pending.length && defer) defer(advanceTalents(env).catch(() => null));
  return report;
}
