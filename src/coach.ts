import type { Fight } from "./combat";
import type { Env } from "./env";

const FINISHERS = new Set(["Eviscerate", "Slice and Dice", "Rupture", "Kidney Shot", "Expose Armor"]);
const BUILDERS = new Set(["Sinister Strike", "Backstab", "Hemorrhage", "Mutilate"]);

export interface FightLine {
  start: number;
  target: string;
  targetLevel: number | null;
  dur: number;
  dps: number;
  sndPct: number;
  cappedPct: number;
  casts: { t: number; name: string; energy: number; cp: number }[];
}
export interface CoachReport {
  fights: number;
  perMinute: number; // abilities per minute of fighting
  builderEnergy: number; // average energy when a builder is pressed
  builderHighPct: number; // builders pressed at 90+ energy
  evisByCp: number[]; // index = combo points, value = how many Eviscerates
  sndFightsWithout: number; // % of longer fights with no Slice and Dice at all
  sndLateSec: number | null; // average time until the first Slice and Dice in longer fights
  compare: { label: string; best: string; worst: string }[];
  tips: { level: "fix" | "tip" | "info"; title: string; text: string }[];
  recent: FightLine[];
}

const avg = (xs: number[]) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0);

export async function coachReport(env: Env, limit = 150): Promise<CoachReport | null> {
  const rows = await env.DB.prepare("SELECT json FROM fights WHERE slug = ? ORDER BY start DESC LIMIT ?")
    .bind(env.CHARACTER_SLUG, limit)
    .all<{ json: string }>();
  const fights = rows.results.map((r) => JSON.parse(r.json) as Fight).filter((f) => f.dur >= 6 && Array.isArray(f.casts));
  if (fights.length < 5) return null;

  const line = (f: Fight): FightLine => ({
    start: f.start,
    target: f.target ?? "?",
    targetLevel: f.targetLevel ?? null,
    dur: f.dur,
    dps: f.dmg / f.dur,
    sndPct: Math.min(100, ((f.auras?.["Slice and Dice"] ?? 0) / f.dur) * 100),
    cappedPct: f.samples > 0 ? (f.capped / f.samples) * 100 : 0,
    casts: f.casts.map((c) => ({ t: c[0] / 10, name: c[1], energy: c[2], cp: c[3] })),
  });
  const lines = fights.map(line);

  const builders = lines.flatMap((l) => l.casts.filter((c) => BUILDERS.has(c.name)));
  const evisByCp = [0, 0, 0, 0, 0, 0];
  for (const l of lines) for (const c of l.casts) if (c.name === "Eviscerate") evisByCp[Math.min(5, Math.max(0, c.cp))]++;
  const long = lines.filter((l) => l.dur >= 12);
  const firstSnd = long.map((l) => l.casts.find((c) => c.name === "Slice and Dice")?.t).filter((t): t is number => t != null);
  const perMinute = avg(lines.map((l) => (l.casts.length / l.dur) * 60));
  const withEnergy = builders.filter((c) => c.energy >= 0);
  const builderEnergy = avg(withEnergy.map((c) => c.energy));
  const builderHighPct = withEnergy.length ? (withEnergy.filter((c) => c.energy >= 90).length / withEnergy.length) * 100 : 0;
  const sndFightsWithout = long.length ? (long.filter((l) => !l.casts.some((c) => c.name === "Slice and Dice")).length / long.length) * 100 : 0;
  const sndLateSec = firstSnd.length ? avg(firstSnd) : null;

  // Your best quarter of fights against your worst, on mobs of a similar level.
  const sorted = [...lines].sort((a, b) => b.dps - a.dps);
  const q = Math.max(2, Math.floor(sorted.length / 4));
  const best = sorted.slice(0, q);
  const worst = sorted.slice(-q);
  const cpm = (l: FightLine) => (l.casts.length / l.dur) * 60;
  const finCp = (l: FightLine) => avg(l.casts.filter((c) => c.name === "Eviscerate").map((c) => c.cp));
  const lvl = (ls: FightLine[]) => avg(ls.map((l) => l.targetLevel ?? 0).filter((x) => x > 0));
  const f1 = (n: number) => n.toFixed(1);
  const compare = [
    { label: "DPS", best: f1(avg(best.map((l) => l.dps))), worst: f1(avg(worst.map((l) => l.dps))) },
    { label: "Célpont szintje", best: f1(lvl(best)), worst: f1(lvl(worst)) },
    { label: "Harc hossza", best: `${f1(avg(best.map((l) => l.dur)))} mp`, worst: `${f1(avg(worst.map((l) => l.dur)))} mp` },
    { label: "Slice and Dice fedettség", best: `${f1(avg(best.map((l) => l.sndPct)))}%`, worst: `${f1(avg(worst.map((l) => l.sndPct)))}%` },
    { label: "Idő tele energiával", best: `${f1(avg(best.map((l) => l.cappedPct)))}%`, worst: `${f1(avg(worst.map((l) => l.cappedPct)))}%` },
    { label: "Képesség / perc", best: f1(avg(best.map(cpm))), worst: f1(avg(worst.map(cpm))) },
    { label: "Eviscerate combo pont", best: f1(avg(best.map(finCp).filter((x) => x > 0))), worst: f1(avg(worst.map(finCp).filter((x) => x > 0))) },
  ];

  const tips: CoachReport["tips"] = [];
  if (builderHighPct > 25) {
    tips.push({
      level: "fix",
      title: "Tele energiával ütsz",
      text: `A combo pont gyűjtőid ${f1(builderHighPct)}%-át 90 fölötti energiával nyomod. Ami 100 fölé menne, elvész: üss korábban, ne várd meg a plafont.`,
    });
  }
  const evisTotal = evisByCp.reduce((a, b) => a + b, 0);
  const evisLow = evisByCp[1] + evisByCp[2];
  if (evisTotal >= 8 && evisLow / evisTotal > 0.3) {
    tips.push({
      level: "tip",
      title: "Sok az alacsony combo pontos Eviscerate",
      text: `${evisTotal} Eviscerate-ből ${evisLow} ment 1–2 combo ponttal. Ha a mob úgyis meghal tőle, rendben; különben az a pont Slice and Dice-ban többet ér.`,
    });
  }
  if (long.length >= 5 && sndFightsWithout > 40) {
    tips.push({
      level: "fix",
      title: "A hosszabb harcok felében nincs Slice and Dice",
      text: `A 12 másodpercnél hosszabb harcaid ${f1(sndFightsWithout)}%-ában egyszer sem használod. Az auto-attack a sebzésed legnagyobb része, a +20% sebesség azonnal megtérül.`,
    });
  } else if (sndLateSec != null && sndLateSec > 6) {
    tips.push({
      level: "tip",
      title: "Későn megy fel a Slice and Dice",
      text: `Átlagosan ${f1(sndLateSec)} másodperc telik el az elsőig. Az első 1–2 combo pontból rakd fel, utána gyűjts Eviscerate-re.`,
    });
  }
  const bestSnd = avg(best.map((l) => l.sndPct));
  const worstSnd = avg(worst.map((l) => l.sndPct));
  if (bestSnd - worstSnd > 20) {
    tips.push({
      level: "info",
      title: "A jó harcaidban több a Slice and Dice",
      text: `A legjobb negyedben ${f1(bestSnd)}%, a leggyengébben ${f1(worstSnd)}% a fedettség. A mobok szintje is számít (lásd a táblázatot), de ez a te kezedben van.`,
    });
  }
  if (!tips.length) {
    tips.push({ level: "info", title: "Nincs feltűnő hiba", text: "A nyitásod, az energiahasználatod és a finishereid rendben vannak a rögzített harcokban." });
  }

  return {
    fights: lines.length,
    perMinute,
    builderEnergy,
    builderHighPct,
    evisByCp,
    sndFightsWithout,
    sndLateSec,
    compare,
    tips,
    recent: lines.slice(0, 6),
  };
}
