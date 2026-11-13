import { loadAddon } from "./addon";
import { loadSelectedBuffs, resolveBuffs, type ResolvedBuff } from "./buffs";
import { combatReport } from "./combat";
import type { Env } from "./env";
import { latestSnapshots } from "./sync";

type Obj = Record<string, any>;

// ---------------------------------------------------------------- import

export interface LootImport {
  dungeons: { id: number; name: string; min: number; max: number; req: number }[];
  items: {
    id: number;
    name: string;
    q: number;
    ilvl: number;
    req: number;
    slot: number;
    cls: number;
    sub: number;
    zone: number;
    boss: string | null;
    st: Record<string, number>;
  }[];
}

export async function importLoot(env: Env, data: LootImport) {
  const stmts: D1PreparedStatement[] = [
    env.DB.prepare("DELETE FROM loot"),
    env.DB.prepare("DELETE FROM dungeons"),
  ];
  for (const d of data.dungeons) {
    stmts.push(
      env.DB.prepare(
        "INSERT OR REPLACE INTO dungeons (zone_id, name, min_level, max_level, req_level) VALUES (?, ?, ?, ?, ?)",
      ).bind(d.id, d.name, d.min || 0, d.max || 0, d.req || 0),
    );
  }
  for (const i of data.items) {
    stmts.push(
      env.DB.prepare(
        "INSERT OR REPLACE INTO loot (item_id, zone_id, name, quality, item_level, req_level, slot, item_class, " +
          "subclass, boss, stats) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      ).bind(i.id, i.zone, i.name, i.q, i.ilvl, i.req || 0, i.slot, i.cls, i.sub, i.boss, JSON.stringify(i.st)),
    );
  }
  for (let k = 0; k < stmts.length; k += 80) await env.DB.batch(stmts.slice(k, k + 80));
  return { dungeons: data.dungeons.length, items: data.items.length };
}

// ---------------------------------------------------------------- stat model

/** The gear-dependent numbers the DPS model needs. */
interface Sheet {
  ap: number;
  crit: number; // %
  hit: number; // %
  mh: Weapon | null;
  oh: Weapon | null;
}
interface Weapon {
  min: number;
  max: number;
  speed: number;
}
/** What one item contributes. */
export interface ItemStats {
  agi: number;
  str: number;
  ap: number;
  crit: number;
  hit: number;
  weapon: Weapon | null;
}

export interface ModelParams {
  level: number;
  agiPerCrit: number;
  /** Chance for a white / yellow attack to miss before +hit is applied, in %. */
  whiteMissBase: number;
  yellowMissBase: number;
  dodge: number; // %
  parry: number; // %
  glance: number; // % of white swings
  /** Real swings per second relative to the weapon speeds (Slice and Dice up, running down). */
  swingRate: number;
  ssPerSec: number;
  evisPerSec: number;
  ssBonus: number;
  evisDamage: number;
  /** Damage the model does not scale with gear (poison, procs, racials). */
  otherDps: number;
  /** Multiplier on Agility and Strength from percent buffs (Blessing of Kings). */
  statMult: number;
  notes: string[];
}

const ZERO: ItemStats = { agi: 0, str: 0, ap: 0, crit: 0, hit: 0, weapon: null };

/** Stats of an equipped item as the Blizzard equipment endpoint reports them. */
export function equippedStats(it: Obj | undefined): ItemStats {
  if (!it) return ZERO;
  const s: ItemStats = { ...ZERO };
  for (const st of (it.stats ?? []) as Obj[]) {
    const v = Number(st.value) || 0;
    if (st.type?.type === "AGILITY") s.agi += v;
    if (st.type?.type === "STRENGTH") s.str += v;
  }
  for (const sp of (it.spells ?? []) as Obj[]) {
    const d = String(sp.description ?? "");
    let m: RegExpMatchArray | null;
    if ((m = d.match(/\+(\d+) (?:Melee )?Attack Power/i))) s.ap += Number(m[1]);
    if ((m = d.match(/critical strike by (\d+)%/i))) s.crit += Number(m[1]);
    if ((m = d.match(/chance to hit by (\d+)%/i))) s.hit += Number(m[1]);
  }
  const w = it.weapon;
  if (w?.damage) {
    s.weapon = {
      min: Number(w.damage.min_value),
      max: Number(w.damage.max_value),
      speed: Number(w.attack_speed?.value) / 1000,
    };
  }
  return s;
}

/** Stats of a loot item from Wowhead's jsonequip. In the Classic-era data the "rtng" keys hold percentages. */
function lootStats(st: Record<string, number>): ItemStats {
  return {
    agi: st.agi ?? 0,
    str: st.str ?? 0,
    ap: st.atkpwr ?? 0,
    crit: st.critstrkrtng ?? 0,
    hit: (st.hitrtng ?? 0) + (st.mlehitpct ?? 0),
    weapon: st.mlespeed ? { min: st.mledmgmin, max: st.mledmgmax, speed: st.mlespeed } : null,
  };
}

/**
 * Simplified sustained single-target DPS for a Sinister Strike / Eviscerate rogue.
 * Only the parts that react to gear are modelled; poisons, armor and glancing blows
 * are left out because they scale (almost) the same for every candidate item.
 */
export function dps(sh: Sheet, p: ModelParams): number {
  const crit = Math.min(sh.crit, 100) / 100;
  const avoid = (p.dodge + p.parry) / 100;
  const glance = p.glance / 100;
  const whiteMiss = Math.max(0, p.whiteMissBase - sh.hit) / 100;
  const yellowMiss = Math.max(0, p.yellowMissBase - sh.hit) / 100;
  // One-roll table: plain hits take whatever is left; glancing blows do ~70%, crits 200%.
  const plain = Math.max(0, 1 - whiteMiss - avoid - glance - crit);
  const whiteFactor = plain + glance * 0.7 + crit * 2;
  const yellowFactor = Math.max(0, 1 - yellowMiss - avoid) * (1 + crit);

  const avg = (w: Weapon) => (w.min + w.max) / 2 + (sh.ap / 14) * w.speed;
  let total = p.otherDps;
  if (sh.mh) total += p.swingRate * (avg(sh.mh) / sh.mh.speed) * whiteFactor;
  if (sh.oh) total += p.swingRate * ((avg(sh.oh) * 0.5) / sh.oh.speed) * whiteFactor;
  if (sh.mh) {
    total += p.ssPerSec * (avg(sh.mh) + p.ssBonus) * yellowFactor;
    total += p.evisPerSec * p.evisDamage * yellowFactor;
  }
  return total;
}

function apply(sh: Sheet, remove: ItemStats, add: ItemStats, p: ModelParams): Sheet {
  const dAgi = (add.agi - remove.agi) * p.statMult;
  const dStr = (add.str - remove.str) * p.statMult;
  return {
    ...sh,
    ap: sh.ap + (add.ap - remove.ap) + dStr + dAgi,
    crit: sh.crit + (add.crit - remove.crit) + dAgi / p.agiPerCrit,
    hit: sh.hit + (add.hit - remove.hit),
  };
}

// ---------------------------------------------------------------- recommendations

// Wowhead inventory type -> Blizzard equipment slots it can go into.
const SLOT_MAP: Record<number, string[]> = {
  1: ["HEAD"], 2: ["NECK"], 3: ["SHOULDER"], 5: ["CHEST"], 20: ["CHEST"], 6: ["WAIST"], 7: ["LEGS"],
  8: ["FEET"], 9: ["WRIST"], 10: ["HANDS"], 11: ["FINGER_1", "FINGER_2"], 12: ["TRINKET_1", "TRINKET_2"],
  16: ["BACK"], 13: ["MAIN_HAND", "OFF_HAND"], 21: ["MAIN_HAND"], 22: ["OFF_HAND"],
};
// Rogue: cloth/leather/misc armor, daggers, one-handed swords and maces, fist weapons.
const ARMOR_SUBS = new Set([0, 1, 2]);
const WEAPON_SUBS = new Set([4, 7, 13, 15]);
const WEAPON_NAMES: Record<number, string> = { 4: "Mace", 7: "Sword", 13: "Fist", 15: "Dagger" };
// Skill line names as the game client reports them (English client).
const WEAPON_SKILLS: Record<number, string> = { 4: "Maces", 7: "Swords", 13: "Fist Weapons", 15: "Daggers" };

export interface Upgrade {
  itemId: number;
  name: string;
  quality: number;
  itemLevel: number;
  reqLevel: number;
  slot: string;
  replaces: string | null;
  boss: string | null;
  dungeon: string;
  zoneId: number;
  gain: number; // DPS
  gainPct: number;
  usableNow: boolean;
  detail: string;
  /** Weapon skill problem, known only when the addon has uploaded skill lines. */
  warning: string | null;
}

export interface DungeonScore {
  zoneId: number;
  name: string;
  levels: string;
  gain: number;
  gainPct: number;
  upgrades: Upgrade[];
}

export interface GearReport {
  baseline: number;
  /** DPS measured in recorded fights, when there are any. */
  measuredDps: number | null;
  /** Model DPS without the selected buffs. */
  unbuffed: number;
  buffs: ResolvedBuff[];
  params: ModelParams;
  sheet: Sheet;
  dungeons: DungeonScore[];
  bySlot: { slot: string; current: string | null; best: Upgrade[] }[];
  later: Upgrade[];
}

function talentRank(specs: Obj | undefined, name: string): { rank: number; desc: string } {
  for (const g of (specs?.specialization_groups ?? []) as Obj[]) {
    if (g.is_active === false) continue;
    for (const sp of (g.specializations ?? []) as Obj[]) {
      for (const t of (sp.talents ?? []) as Obj[]) {
        if (t.talent?.name === name) {
          return { rank: Number(t.talent_rank) || 0, desc: String(t.spell_tooltip?.description ?? "") };
        }
      }
    }
  }
  return { rank: 0, desc: "" };
}

/** Everything needed to score a piece of gear against what is equipped now. */
export async function gearContext(env: Env) {
  const snaps = await latestSnapshots(env);
  const profile = snaps.profile?.json as Obj | undefined;
  const stats = snaps.statistics?.json as Obj | undefined;
  const equip = snaps.equipment?.json as Obj | undefined;
  const specs = snaps.specializations?.json as Obj | undefined;
  if (!profile || !stats || !equip) return null;

  const level = Number(profile.level);
  const equipped = new Map<string, Obj>();
  for (const it of (equip.equipped_items ?? []) as Obj[]) equipped.set(it.slot?.type, it);

  // Calibrate from the character's own sheet where possible.
  const notes: string[] = [];
  const malice = talentRank(specs, "Malice");
  const maliceCrit = Number(malice.desc.match(/by (\d+)%/)?.[1] ?? 0);
  const agi = Number(stats.agility?.effective ?? 0);
  const critNow = Number(stats.melee_crit?.value ?? 0);
  let agiPerCrit = agi / Math.max(0.1, critNow - maliceCrit);
  if (!(agiPerCrit > 3 && agiPerCrit < 60)) agiPerCrit = 2.2 + (26.8 * (level - 1)) / 59;
  notes.push(`1% crit ≈ ${agiPerCrit.toFixed(1)} agility (a saját statjaidból visszaszámolva).`);

  const eff = talentRank(specs, "Efficient Strikes");
  const ssCost = 45 - Number(eff.desc.match(/by (\d+)/)?.[1] ?? 0);
  const coup = talentRank(specs, "Coup de Grace");
  const evisBonus = 1 + Number(coup.desc.match(/Eviscerate ability by (\d+)%/)?.[1] ?? 0) / 100;
  const mhNow = equippedStats(equipped.get("MAIN_HAND"));
  const ohNow = equippedStats(equipped.get("OFF_HAND"));
  const sheet: Sheet = {
    ap: Number(stats.attack_power ?? 0),
    crit: critNow,
    hit: Number(stats.melee_hit?.value ?? 0),
    mh: mhNow.weapon,
    oh: ohNow.weapon,
  };

  // Textbook defaults: five Sinister Strikes then one 35-energy Eviscerate at 10 energy/sec,
  // dual-wield miss 24%, 5% dodge, attacking from behind.
  const cycleSeconds = (5 * ssCost + 35) / 10;
  const params: ModelParams = {
    level,
    agiPerCrit,
    whiteMissBase: sheet.oh ? 24 : 5,
    yellowMissBase: 5,
    dodge: 5,
    parry: 0,
    glance: 0,
    swingRate: 1,
    ssPerSec: 5 / cycleSeconds,
    evisPerSec: 1 / cycleSeconds,
    ssBonus: Math.round(level / 2),
    evisDamage: Math.round(12 * level * evisBonus),
    otherDps: 0,
    statMult: 1,
    notes,
  };

  // Pull every default towards what the recorded fights show. The weight grows with the
  // sample size, so a handful of fights only nudges the numbers.
  const combat = await combatReport(env);
  const mix = (prior: number, measured: number, n: number, half: number) => {
    const w = n / (n + half);
    return prior * (1 - w) + measured * w;
  };
  if (combat && combat.seconds > 0) {
    const secs = combat.seconds;
    const wn = combat.white.n;
    params.whiteMissBase = mix(params.whiteMissBase, combat.white.miss + sheet.hit, wn, 100);
    params.dodge = mix(params.dodge, combat.white.dodge, wn, 100);
    params.parry = mix(params.parry, combat.white.parry, wn, 100);
    params.glance = mix(params.glance, combat.white.glance, wn, 100);
    params.yellowMissBase = mix(params.yellowMissBase, combat.yellow.miss + sheet.hit, combat.yellow.n, 100);
    if (sheet.mh) {
      const expected = 1 / sheet.mh.speed + (sheet.oh ? 1 / sheet.oh.speed : 0);
      params.swingRate = mix(1, wn / secs / expected, secs, 120);
    }
    const ss = combat.abilities.find((a) => a.name === "Sinister Strike");
    const evis = combat.abilities.find((a) => a.name === "Eviscerate");
    params.ssPerSec = mix(params.ssPerSec, (ss?.n ?? 0) / secs, secs, 120);
    params.evisPerSec = mix(params.evisPerSec, (evis?.n ?? 0) / secs, secs, 120);
    if (ss && sheet.mh && ss.hit + ss.crit > 0) {
      // Normal-hit average with crits counted double, minus what the weapon and attack power explain.
      const normal = ss.dmg / (ss.hit + 2 * ss.crit);
      const weapon = (sheet.mh.min + sheet.mh.max) / 2 + (sheet.ap / 14) * sheet.mh.speed;
      params.ssBonus = mix(params.ssBonus, Math.max(0, normal - weapon), ss.hit + ss.crit, 20);
    }
    if (evis && evis.hit + evis.crit > 0) {
      params.evisDamage = mix(params.evisDamage, evis.dmg / (evis.hit + 2 * evis.crit), evis.hit + evis.crit, 3);
    }
    const modelled = new Set(["Melee", "Sinister Strike", "Eviscerate"]);
    const other = combat.abilities.filter((a) => !modelled.has(a.name)).reduce((s, a) => s + a.dmg, 0);
    params.otherDps = mix(0, other / secs, secs, 120);
    const weight = Math.round((wn / (wn + 100)) * 100);
    notes.push(
      `Kalibrálva ${combat.fights} rögzített harcból (${Math.round(secs)} mp, ${wn} auto-attack): a mért értékek ` +
        `súlya most kb. ${weight}%, és a mintával együtt nő.`,
    );
    notes.push(
      `Auto-attack: ${params.whiteMissBase.toFixed(1)}% alap miss, ${params.dodge.toFixed(1)}% dodge, ` +
        `${params.parry.toFixed(1)}% parry, ${params.glance.toFixed(1)}% glancing. ` +
        `Sinister Strike ${(params.ssPerSec * 60).toFixed(1)}/perc (+${params.ssBonus.toFixed(0)} bónusz), ` +
        `Eviscerate ${(params.evisPerSec * 60).toFixed(1)}/perc (${params.evisDamage.toFixed(0)} sebzés), ` +
        `egyéb források ${params.otherDps.toFixed(1)} DPS.`,
    );
  } else {
    notes.push(
      "Nincs rögzített harc, ezért tankönyvi értékekkel számol: 24% dual-wield miss, 5% dodge, hátulról ütve, " +
        "5 Sinister Strike után Eviscerate. Kapcsold be a harcnaplót (/wa log) a kalibráláshoz.",
    );
  }
  // Selected buffs change the character sheet every candidate item is compared against.
  const unbuffed = dps(sheet, params);
  const buffs = resolveBuffs(level, await loadSelectedBuffs(env));
  let bAgi = 0;
  let bStr = 0;
  let bAp = 0;
  let bCrit = 0;
  let pct = 0;
  for (const b of buffs) {
    if (!b.selected || !b.effect) continue;
    bAgi += b.effect.agi ?? 0;
    bStr += b.effect.str ?? 0;
    bAp += b.effect.ap ?? 0;
    bCrit += b.effect.crit ?? 0;
    pct += b.effect.statPct ?? 0;
  }
  if (pct > 0) {
    // The percent bonus also applies to what you already have and to the flat buffs.
    bAgi += pct * (agi + bAgi);
    bStr += pct * (Number(stats.strength?.effective ?? 0) + bStr);
    params.statMult = 1 + pct;
  }
  sheet.ap += bAgi + bStr + bAp;
  sheet.crit += bCrit + bAgi / agiPerCrit;
  const baseline = dps(sheet, params);
  const skills = (await loadAddon(env))?.state.skills;
  const equippedIds = new Set([...equipped.values()].map((it) => Number(it.item?.id)));

  /** Best slot for an item and the DPS it adds there; null when it is not an upgrade. */
  const score = (add: ItemStats, slots: string[]): { slot: string; gain: number } | null => {
    let best: { slot: string; gain: number } | null = null;
    for (const slot of slots) {
      let sh = apply(sheet, equippedStats(equipped.get(slot)), add, params);
      if (slot === "MAIN_HAND") sh = { ...sh, mh: add.weapon };
      if (slot === "OFF_HAND") sh = { ...sh, oh: add.weapon };
      const gain = dps(sh, params) - baseline;
      if (!best || gain > best.gain) best = { slot, gain };
    }
    return best && best.gain > 0.05 ? best : null;
  };
  const describe = (add: ItemStats, weaponSub?: number): string => {
    const bits: string[] = [];
    if (add.weapon) {
      const w = add.weapon;
      bits.push(`${WEAPON_NAMES[weaponSub ?? -1] ?? "Weapon"} ${w.min}–${w.max} / ${w.speed.toFixed(1)}`);
    }
    if (add.agi) bits.push(`+${add.agi} agi`);
    if (add.str) bits.push(`+${add.str} str`);
    if (add.ap) bits.push(`+${add.ap} AP`);
    if (add.crit) bits.push(`+${add.crit}% crit`);
    if (add.hit) bits.push(`+${add.hit}% hit`);
    return bits.join(", ");
  };
  const weaponWarning = (itemClass: number, sub: number): string | null => {
    if (itemClass !== 2 || !skills || !Object.keys(skills).length) return null;
    const line = WEAPON_SKILLS[sub];
    const s = skills[line];
    if (!s) return `${line} nincs kitanulva`;
    return s.rank < s.max - 15 ? `${line} skill ${s.rank}/${s.max}` : null;
  };

  return {
    level, baseline, unbuffed, buffs, params, sheet, equipped, equippedIds, combat,
    gold: null as number | null,
    score, describe, weaponWarning,
  };
}
export type GearContext = NonNullable<Awaited<ReturnType<typeof gearContext>>>;

export async function gearReport(env: Env, lookahead = 3, given?: GearContext): Promise<GearReport | null> {
  const ctx = given ?? (await gearContext(env));
  if (!ctx) return null;
  const { level, baseline, unbuffed, buffs, params, sheet, equipped, equippedIds, combat } = ctx;

  const rows = await env.DB.prepare(
    "SELECT l.*, d.name AS dungeon, d.min_level, d.max_level FROM loot l JOIN dungeons d ON d.zone_id = l.zone_id " +
      "WHERE l.req_level <= ?",
  )
    .bind(level + lookahead)
    .all<Obj>();

  const upgrades: Upgrade[] = [];
  for (const r of rows.results) {
    if (equippedIds.has(r.item_id)) continue;
    if (r.item_class === 4 && !ARMOR_SUBS.has(r.subclass)) continue;
    if (r.item_class === 2 && !WEAPON_SUBS.has(r.subclass)) continue;
    const slots = SLOT_MAP[r.slot];
    if (!slots) continue;
    const add = lootStats(JSON.parse(r.stats));
    if (r.item_class === 2 && !add.weapon) continue;

    const best = ctx.score(add, slots);
    if (!best) continue;

    upgrades.push({
      itemId: r.item_id,
      name: r.name,
      quality: r.quality,
      itemLevel: r.item_level,
      reqLevel: r.req_level,
      slot: best.slot,
      replaces: equipped.get(best.slot)?.name ?? null,
      boss: r.boss,
      dungeon: r.dungeon,
      zoneId: r.zone_id,
      gain: best.gain,
      gainPct: (best.gain / baseline) * 100,
      usableNow: r.req_level <= level,
      detail: ctx.describe(add, r.subclass),
      warning: ctx.weaponWarning(r.item_class, r.subclass),
    });
  }
  upgrades.sort((a, b) => b.gain - a.gain);

  // Rings and trinkets have two slots, weapons two hands: fold FINGER_2 into FINGER_1 etc. for display.
  const group = (s: string) => s.replace(/_[12]$/, "");
  const usable = upgrades.filter((u) => u.usableNow);

  // Per dungeon: the best usable upgrade for each slot group, summed.
  const dMeta = new Map(rows.results.map((r) => [r.zone_id as number, r]));
  const byDungeon = new Map<number, Map<string, Upgrade>>();
  for (const u of usable) {
    const slots = byDungeon.get(u.zoneId) ?? new Map<string, Upgrade>();
    if (!slots.has(u.slot)) slots.set(u.slot, u);
    byDungeon.set(u.zoneId, slots);
  }
  const dungeons: DungeonScore[] = [...byDungeon.entries()]
    .map(([zoneId, slots]) => {
      const ups = [...slots.values()].sort((a, b) => b.gain - a.gain);
      const gain = ups.reduce((a, u) => a + u.gain, 0);
      const m = dMeta.get(zoneId)!;
      return {
        zoneId,
        name: String(m.dungeon),
        levels: m.min_level ? `${m.min_level}–${m.max_level}` : "?",
        gain,
        gainPct: (gain / baseline) * 100,
        upgrades: ups,
      };
    })
    .sort((a, b) => b.gain - a.gain);

  const slotOrder = ["MAIN_HAND", "OFF_HAND", "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET"];
  const bySlot = slotOrder
    .map((slot) => ({
      slot,
      current:
        [...equipped.entries()]
          .filter(([k]) => group(k) === slot)
          .map(([, v]) => String(v.name))
          .join(" + ") || null,
      best: usable.filter((u) => group(u.slot) === slot).slice(0, 3),
    }))
    .filter((s) => s.best.length);

  return {
    baseline,
    measuredDps: combat ? combat.dps : null,
    unbuffed,
    buffs,
    params,
    sheet,
    dungeons,
    bySlot,
    later: upgrades.filter((u) => !u.usableNow).slice(0, 10),
  };
}
