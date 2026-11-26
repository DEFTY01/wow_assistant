import type { Env } from "./env";
import { latestSnapshots } from "./sync";

type Obj = Record<string, any>;

interface AbilityStats {
  n: number;
  dmg: number;
  hit: number;
  crit: number;
  glance: number;
  miss: number;
  dodge: number;
  parry: number;
  block: number;
  other: number;
  max: number;
}

export interface Fight {
  start: number;
  dur: number;
  dmg: number;
  target?: string;
  targetLevel?: number;
  level?: number;
  ab: Record<string, AbilityStats>;
  casts: [number, string, number, number][];
  auras: Record<string, number>;
  capped: number;
  samples: number;
  /** Every Eviscerate with the state of the decision (scripts/combat-log.mjs, from 2.8.3). */
  evis?: EvisCast[];
}

export interface EvisCast {
  /** unset for an Eviscerate; "Ferocious Bite" for a druid's bite */
  spell?: string;
  t: number; // tenths of a second from the fight's start
  cp: number;
  target?: string;
  landed: boolean | null;
  dmg: number | null;
  crit: boolean | null;
  killed: boolean | null;
  hpBefore: number | null;
  blocked?: number;
  maxHp: number | null;
  lived: number; // seconds the target lived after it (at least, unless livedKnown)
  livedKnown: boolean;
}

// A low-point Eviscerate is a proven mistake only when the log shows all of it: it spent 1-2
// combo points, it hit and the target survived, no roll of it could have killed (more than 4x the
// hit's non-crit damage left: the highest roll is at most EVIS_SPREAD x the lowest, then a crit),
// and the target lived at least EVIS_ROOM more seconds - two Sinister Strikes' worth of energy.
// The same rule as the addon's WowAssistant/Combat.lua C.EvisMistake, which says where the bound
// comes from. true = proven, false = low points but justified by the log, null = not a low-point
// cast or the state is not known.
export const EVIS_ROOM = 8;
export const EVIS_SPREAD = 2;
export function evisMistake(e: EvisCast): boolean | null {
  if (!(e.cp >= 1 && e.cp <= 2) || e.landed === false) return null;
  if (e.killed) return false;
  if (e.hpBefore == null || e.dmg == null || e.lived == null) return null;
  const dmg = e.dmg + (e.blocked ?? 0);
  const killable = (e.crit ? dmg / 2 : dmg) * EVIS_SPREAD * 2;
  return e.hpBefore > killable && e.lived >= EVIS_ROOM;
}

export interface EvisEvidence {
  seen: number;
  proven: { start: number; e: EvisCast }[];
  justified: number;
  /** low-point casts the log cannot decide: no health known, or a fight stored without the data */
  unchecked: number;
}
export function evisEvidence(fights: Fight[]): EvisEvidence {
  const out: EvisEvidence = { seen: 0, proven: [], justified: 0, unchecked: 0 };
  for (const f of fights) {
    if (Array.isArray(f.evis)) {
      // Ferocious Bite records (spell set, from 2.11.0) are the addon's druid page's, not Eviscerates
      for (const e of f.evis.filter((x) => !x.spell)) {
        out.seen++;
        const x = evisMistake(e);
        if (x === true) out.proven.push({ start: f.start, e });
        else if (x === false) out.justified++;
        else if (e.cp >= 1 && e.cp <= 2 && e.landed !== false) out.unchecked++;
      }
    } else {
      for (const c of Array.isArray(f.casts) ? f.casts : []) if (c[1] === "Eviscerate" && c[3] >= 1 && c[3] <= 2) out.unchecked++;
    }
  }
  return out;
}

const clock = (start: number, tenths: number) =>
  new Date((start + tenths / 10) * 1000).toLocaleString("hu-HU", { timeZone: "Europe/Budapest", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" });

/** The Eviscerate finding from the log's evidence, or null when the log has no Eviscerate data. */
export function evisAdvice(ev: EvisEvidence, avgCp: number | null): Advice | null {
  if (ev.proven.length) {
    const lines = ev.proven.slice(0, 3).map(({ start, e }) =>
      `${clock(start, e.t)}, ${e.target ?? "?"}: ${e.cp} pont, életereje előtte ${e.hpBefore} / ${e.maxHp ?? "?"}, ` +
      `a sebzés ${e.dmg}${e.crit ? " (krit)" : ""}, utána még ${e.livedKnown ? "" : "legalább "}${e.lived.toFixed(1)} mp-ig élt`);
    return {
      level: "fix",
      title: "Kevés combo pontos Eviscerate",
      text: `${ev.proven.length} Eviscerate ment 1–2 combo ponttal úgy, hogy a célpont nem halt meg tőle, több mint négyszer annyi ` +
        `életereje maradt, mint az ütés normál sebzése (a legnagyobb dobás krittel sem ölt volna), és utána még legalább ${EVIS_ROOM} mp-ig élt (harcnapló): ` +
        lines.join("; ") + (ev.proven.length > 3 ? `; és még ${ev.proven.length - 3}` : "") +
        ". Ilyenkor építs még 1–2 pontot: az ára ugyanaz a 35 energia, a sebzése pontonként nő." +
        (ev.unchecked ? ` További ${ev.unchecked} kevés pontosnál a célpont élete nem látszik.` : ""),
    };
  }
  if (ev.justified && !ev.unchecked && avgCp != null && avgCp < 4) {
    return {
      level: "info",
      title: "Kevés pontos Eviscerate, de indokolt",
      text: `Az Eviscerate-jeid átlagosan ${avgCp.toFixed(1)} combo ponttal mentek. Mind a ${ev.justified} darab 1–2 pontos ` +
        "ellenőrizhető volt a harcnaplóban, és egyik sem volt hiba: ölt, kevés életerejű célpontra ment, vagy a célpont hamar meghalt.",
    };
  }
  if (avgCp != null && avgCp < 4 && (ev.justified || ev.unchecked)) {
    return {
      level: "tip",
      title: "Kevés combo pontos Eviscerate (nem megállapítható)",
      text: `Az Eviscerate-jeid átlagosan ${avgCp.toFixed(1)} combo ponttal mennek. Az 1–2 pontosak közül ${ev.justified} a harcnapló ` +
        `szerint indokolt volt, ${ev.unchecked}-nál/-nél nem látszik a célpont életereje, így ott nem dönthető el, hiba volt-e. ` +
        "4–5 ponttal több sebzés jut egy energiára, kivéve ha a mob 1–2 ponttal is meghal.",
    };
  }
  return null;
}

export async function storeFights(env: Env, fights: unknown): Promise<number> {
  const list = (Array.isArray(fights) ? fights : []) as Fight[];
  // The combat log does not contain the player's level; take it from the latest profile.
  const level = Number(((await latestSnapshots(env)).profile?.json as Obj | undefined)?.level) || undefined;
  for (const f of list) if (f && !f.level) f.level = level;
  const valid = list.filter((f) => f && Number(f.start) > 0 && Number(f.dur) > 0);
  if (!valid.length) return 0;
  // The uploader re-sends the whole log every time: skip the fights that are already stored as they are.
  const oldest = Math.min(...valid.map((f) => f.start));
  const have = await env.DB.prepare(
    "SELECT start, duration, damage, instr(json, '\"evis\"') > 0 AS evis FROM fights WHERE slug = ? AND start >= ?",
  )
    .bind(env.CHARACTER_SLUG, oldest)
    .all<{ start: number; duration: number; damage: number; evis: number }>();
  const stored = new Map(have.results.map((r) => [r.start, r]));
  const stmts = valid
    .filter((f) => {
      const s = stored.get(f.start);
      // a fight stored before the parser kept the Eviscerates is stored again once it has them
      return !s || s.duration !== f.dur || s.damage !== Math.round(f.dmg) || (!s.evis && Array.isArray(f.evis) && f.evis.length > 0);
    })
    .map((f) =>
      env.DB.prepare("INSERT OR REPLACE INTO fights (slug, start, duration, damage, json) VALUES (?, ?, ?, ?, ?)").bind(
        env.CHARACTER_SLUG,
        f.start,
        f.dur,
        Math.round(f.dmg),
        JSON.stringify(f),
      ),
    );
  for (let i = 0; i < stmts.length; i += 50) await env.DB.batch(stmts.slice(i, i + 50));
  return stmts.length;
}

const EMPTY: AbilityStats = { n: 0, dmg: 0, hit: 0, crit: 0, glance: 0, miss: 0, dodge: 0, parry: 0, block: 0, other: 0, max: 0 };
const FINISHERS = new Set(["Eviscerate", "Slice and Dice", "Rupture", "Kidney Shot", "Expose Armor"]);
// The log only tells the hand for misses, so all auto-attacks are one "Melee" row; the
// off-hand misses are kept as an extra row that must not be double counted.
const OFFHAND_MISS = "Melee (off hand miss)";
const WHITE = (name: string) => name === "Melee";
const DOT = (name: string) => name.endsWith(" (dot)");

export interface AbilityRow extends AbilityStats {
  name: string;
  share: number;
  avg: number;
}

export interface Advice {
  level: "fix" | "tip" | "info";
  title: string;
  text: string;
}

export interface CombatReport {
  fights: number;
  seconds: number;
  damage: number;
  dps: number;
  abilities: AbilityRow[];
  white: { landed: number; n: number; miss: number; dodge: number; parry: number; glance: number; crit: number };
  yellow: { n: number; miss: number; dodge: number; parry: number; crit: number };
  energyCappedPct: number | null;
  /** Share of failed auto-attacks (miss/dodge/parry) that were off-hand swings. */
  offhandMissSharePct: number | null;
  finishers: { name: string; casts: number; avgCp: number }[];
  auras: { name: string; uptimePct: number }[];
  byLevel: { diff: number; fights: number; dps: number; missPct: number }[];
  recent: { start: number; dur: number; dps: number; target: string; targetLevel: number | null }[];
  advice: Advice[];
}

function add(into: AbilityStats, a: Partial<AbilityStats>) {
  for (const k of Object.keys(EMPTY) as (keyof AbilityStats)[]) {
    if (k === "max") into.max = Math.max(into.max, Number(a.max) || 0);
    else into[k] += Number(a[k]) || 0;
  }
}
const pct = (part: number, whole: number) => (whole > 0 ? (part / whole) * 100 : 0);

export async function combatReport(env: Env, limit = 200): Promise<CombatReport | null> {
  const rows = await env.DB.prepare("SELECT json FROM fights WHERE slug = ? ORDER BY start DESC LIMIT ?").bind(env.CHARACTER_SLUG, limit).all<{ json: string }>();
  const fights = rows.results.map((r) => JSON.parse(r.json) as Fight);
  if (!fights.length) return null;

  const abilities = new Map<string, AbilityStats>();
  const white = { ...EMPTY };
  const yellow = { ...EMPTY };
  const cp = new Map<string, { casts: number; cp: number }>();
  const auraSecs = new Map<string, number>();
  const byLevel = new Map<number, { fights: number; dmg: number; dur: number; n: number; miss: number }>();
  let seconds = 0;
  let damage = 0;
  let capped = 0;
  let samples = 0;
  let offhandMiss = 0;

  for (const f of fights) {
    seconds += f.dur;
    damage += f.dmg;
    capped += f.capped || 0;
    samples += f.samples || 0;
    let fn = 0;
    let fmiss = 0;
    for (const [name, a] of Object.entries(f.ab ?? {})) {
      if (name === OFFHAND_MISS) {
        offhandMiss += Number(a.n) || 0;
        continue;
      }
      const into = abilities.get(name) ?? { ...EMPTY };
      add(into, a);
      abilities.set(name, into);
      if (WHITE(name)) add(white, a);
      else if (!DOT(name)) add(yellow, a);
      if (WHITE(name)) {
        fn += a.n;
        fmiss += a.miss;
      }
    }
    for (const c of Array.isArray(f.casts) ? f.casts : []) {
      const name = c[1];
      if (!FINISHERS.has(name)) continue;
      const e = cp.get(name) ?? { casts: 0, cp: 0 };
      e.casts++;
      e.cp += Number(c[3]) || 0;
      cp.set(name, e);
    }
    for (const [name, secs] of Object.entries(f.auras ?? {})) auraSecs.set(name, (auraSecs.get(name) ?? 0) + Number(secs));
    if (f.targetLevel && f.level && f.targetLevel > 0) {
      const diff = f.targetLevel - f.level;
      const e = byLevel.get(diff) ?? { fights: 0, dmg: 0, dur: 0, n: 0, miss: 0 };
      e.fights++;
      e.dmg += f.dmg;
      e.dur += f.dur;
      e.n += fn;
      e.miss += fmiss;
      byLevel.set(diff, e);
    }
  }

  const rowsOut: AbilityRow[] = [...abilities.entries()]
    .map(([name, a]) => ({
      name,
      ...a,
      share: pct(a.dmg, damage),
      avg: a.hit + a.crit + a.glance > 0 ? a.dmg / (a.hit + a.crit + a.glance) : 0,
    }))
    .sort((a, b) => b.dmg - a.dmg);

  const landed = (a: AbilityStats) => a.hit + a.crit + a.glance;
  const report: CombatReport = {
    fights: fights.length,
    seconds,
    damage,
    dps: damage / seconds,
    abilities: rowsOut,
    white: {
      landed: landed(white),
      n: white.n,
      miss: pct(white.miss, white.n),
      dodge: pct(white.dodge, white.n),
      parry: pct(white.parry, white.n),
      glance: pct(white.glance, white.n),
      crit: pct(white.crit, white.n),
    },
    yellow: {
      n: yellow.n,
      miss: pct(yellow.miss, yellow.n),
      dodge: pct(yellow.dodge, yellow.n),
      parry: pct(yellow.parry, yellow.n),
      crit: pct(yellow.crit, landed(yellow)),
    },
    energyCappedPct: samples > 0 ? pct(capped, samples) : null,
    offhandMissSharePct: white.n - landed(white) > 0 ? pct(offhandMiss, white.n - landed(white)) : null,
    finishers: [...cp.entries()].map(([name, e]) => ({ name, casts: e.casts, avgCp: e.cp / e.casts })),
    auras: [...auraSecs.entries()]
      .map(([name, secs]) => ({ name, uptimePct: Math.min(100, pct(secs, seconds)) }))
      .sort((a, b) => b.uptimePct - a.uptimePct)
      .slice(0, 12),
    byLevel: [...byLevel.entries()]
      .map(([diff, e]) => ({ diff, fights: e.fights, dps: e.dmg / e.dur, missPct: pct(e.miss, e.n) }))
      .sort((a, b) => a.diff - b.diff),
    recent: fights.slice(0, 15).map((f) => ({
      start: f.start,
      dur: f.dur,
      dps: f.dmg / f.dur,
      target: f.target ?? "?",
      targetLevel: f.targetLevel ?? null,
    })),
    advice: [],
  };
  report.advice = advise(report, fights);
  return report;
}

function advise(r: CombatReport, fights: Fight[]): Advice[] {
  const out: Advice[] = [];
  const f1 = (n: number) => n.toFixed(1);

  if (r.seconds < 300 || r.white.n < 150) {
    out.push({
      level: "info",
      title: "Kevés még az adat",
      text: `Eddig ${r.fights} harc, ${Math.round(r.seconds)} másodperc és ${r.white.n} auto-attack van rögzítve. ` +
        "Az arányok kb. 10 perc harc után kezdenek megbízhatóak lenni.",
    });
  }

  if (r.energyCappedPct != null && r.energyCappedPct > 8) {
    out.push({
      level: "fix",
      title: "Energia megy kárba",
      text: `A harcidő ${f1(r.energyCappedPct)}%-ában tele energiával állsz. Minden másodperc a plafonon 10 elveszett energia, ` +
        "vagyis kb. negyed Sinister Strike. Harc elején azonnal üss, és ne tartogasd az energiát 80 fölött.",
    });
  }

  const evis = r.finishers.find((f) => f.name === "Eviscerate");
  const ev = evisEvidence(fights);
  const fromLog = ev.seen ? evisAdvice(ev, evis?.avgCp ?? null) : null;
  if (fromLog) out.push(fromLog);
  else if (!ev.seen && evis && evis.casts >= 5 && evis.avgCp < 4) {
    out.push({
      level: "tip",
      title: "Kevés combo pontos Eviscerate (nem megállapítható)",
      text: `Az Eviscerate-jeid átlagosan ${f1(evis.avgCp)} combo ponttal mennek (${evis.casts} használat). ` +
        "A sebzése combo pontonként nő, az energiaára viszont fix, ezért 4–5 ponttal éri meg, " +
        "kivéve ha a mob 1–2 ponttal is meghal tőle. Hogy hiba volt-e, nem látszik: ezekben a harcokban " +
        "nincs meg a célpont életereje (a harcnapló újraolvasása után lesz).",
    });
  }

  const avgFight = r.seconds / r.fights;
  const snd = r.auras.find((a) => a.name === "Slice and Dice");
  if (avgFight >= 12 && (!snd || snd.uptimePct < 50)) {
    out.push({
      level: "fix",
      title: "Slice and Dice alig van fent",
      text: `A Slice and Dice a harcidő ${snd ? f1(snd.uptimePct) : "0"}%-ában aktív, miközben a sebzésed ` +
        `${f1(r.abilities.filter((a) => WHITE(a.name)).reduce((s, a) => s + a.share, 0))}%-a auto-attack. ` +
        "Az átlagos harcod elég hosszú ahhoz, hogy az első 1–2 combo pontot Slice and Dice-ra költsd, és utána gyűjts Eviscerate-re.",
    });
  }

  const parry = pct(
    r.abilities.reduce((s, a) => s + a.parry, 0),
    r.abilities.filter((a) => !DOT(a.name)).reduce((s, a) => s + a.n, 0),
  );
  if (parry > 2) {
    out.push({
      level: "tip",
      title: "Sok ütésedet hárítják",
      text: `Az ütéseid ${f1(parry)}%-át parryzik. A mobok csak szemből tudnak parryzni és blokkolni, ` +
        "tehát csapatban (dungeonben) állj a célpont mögé. Szólóban ez nem kerülhető el, de egy Gouge utáni helyezkedés segít.",
    });
  }

  if (r.white.n >= 150) {
    out.push({
      level: "info",
      title: "Mért találati arányok",
      text: `Auto-attack: ${f1(r.white.miss)}% miss, ${f1(r.white.dodge)}% dodge, ${f1(r.white.glance)}% glancing, ` +
        `${f1(r.white.crit)}% crit. Képességek: ${f1(r.yellow.miss)}% miss, ${f1(r.yellow.crit)}% crit. ` +
        (r.white.miss > 15
          ? "A fehér ütések ötöde-hatoda elvész, ezért a +hit tárgyak neked sokat érnek."
          : "A miss arány rendben van."),
    });
  }
  if (r.white.glance > 20) {
    out.push({
      level: "tip",
      title: "Sok a glancing ütés",
      text: `Az auto-attackjeid ${f1(r.white.glance)}%-a glancing. Ez nálad magasabb szintű mobokon és alacsony fegyverskillnél jön elő: ` +
        "ha nemrég váltottál fegyvertípust, a skill felhúzása ingyen DPS.",
    });
  }

  const hasPoison = r.abilities.some((a) => /poison/i.test(a.name));
  const level = fights[0]?.level ?? 0;
  if (!hasPoison && level >= 20 && r.seconds >= 120) {
    out.push({
      level: "tip",
      title: "Nincs méreg a fegyvereiden",
      text: "A rögzített harcokban egyetlen méreg-sebzés sincs. Classic alapján 20-as szinttől elérhető az Instant Poison " +
        "(a Forever-beli feltételt nem ellenőriztem); ha megvan, mindkét fegyverre tedd fel, a gyors balkezes fegyveren ér a legtöbbet.",
    });
  }

  const ss = r.abilities.find((a) => a.name === "Sinister Strike");
  const melee = r.abilities.find((a) => a.name === "Melee");
  if (ss && melee) {
    out.push({
      level: "info",
      title: "Sebzésmegoszlás",
      text: `Sinister Strike ${f1(ss.share)}% (átlag ${Math.round(ss.avg)}), auto-attack ${f1(melee.share)}% (átlag ${Math.round(melee.avg)}). ` +
        "A Sinister Strike a főkezes fegyver sebzéséből számol, ezért oda a lassú, nagy sebzésű fegyver való, a balkézbe a gyors.",
    });
  }
  return out;
}
