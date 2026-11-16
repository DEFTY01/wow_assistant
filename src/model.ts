import type { Env } from "./env";

type Obj = Record<string, any>;

/**
 * Remember what the model said for the current gear and talents. One row per distinct pair
 * of equipment and talent snapshots, so a row marks the moment something changed.
 */
export async function logModel(env: Env, modelDps: number, level: number): Promise<void> {
  const ids = await env.DB.prepare(
    "SELECT (SELECT MAX(id) FROM snapshots WHERE slug = ?1 AND kind = 'equipment') AS eq, " +
      "(SELECT MAX(id) FROM snapshots WHERE slug = ?1 AND kind = 'specializations') AS tal",
  )
    .bind(env.CHARACTER_SLUG)
    .first<{ eq: number | null; tal: number | null }>();
  if (!ids?.eq) return;
  await env.DB.prepare(
    "INSERT OR IGNORE INTO model_log (slug, at, equipment_snap, talents_snap, model_dps, level) VALUES (?, ?, ?, ?, ?, ?)",
  )
    .bind(env.CHARACTER_SLUG, new Date().toISOString(), ids.eq, ids.tal ?? 0, modelDps, level)
    .run();
}

export interface ModelPeriod {
  from: string;
  to: string | null;
  level: number | null;
  /** What changed at the start of this period. */
  change: string;
  modelDps: number;
  measuredDps: number | null;
  fights: number;
  minutes: number;
  /** Change the model predicted over the previous period, and what the fights showed. */
  predictedPct: number | null;
  measuredPct: number | null;
}
export interface ModelReport {
  periods: ModelPeriod[];
  /** Typical gap between model and measurement over periods with enough fights, in percent. */
  typicalErrorPct: number | null;
  verdict: string;
}

const MIN_SECONDS = 180; // a period needs this much fighting to count

function gearNames(json: string | undefined): Map<string, string> {
  const out = new Map<string, string>();
  if (!json) return out;
  for (const it of ((JSON.parse(json) as Obj).equipped_items ?? []) as Obj[]) out.set(String(it.slot?.type), String(it.name));
  return out;
}
function talentPoints(json: string | undefined): string {
  if (!json) return "";
  const groups = ((JSON.parse(json) as Obj).specialization_groups ?? []) as Obj[];
  const active = groups.find((g) => g.is_active) ?? groups[0];
  return ((active?.specializations ?? []) as Obj[]).map((s) => `${s.specialization_name}:${s.spent_points}`).join(" ");
}

export async function modelReport(env: Env): Promise<ModelReport | null> {
  const log = await env.DB.prepare(
    "SELECT m.at, m.model_dps, m.level, e.json AS eq, t.json AS tal FROM model_log m " +
      "LEFT JOIN snapshots e ON e.id = m.equipment_snap LEFT JOIN snapshots t ON t.id = m.talents_snap " +
      "WHERE m.slug = ? ORDER BY m.id",
  )
    .bind(env.CHARACTER_SLUG)
    .all<{ at: string; model_dps: number; level: number | null; eq: string | null; tal: string | null }>();
  if (!log.results.length) return null;
  const fights = await env.DB.prepare("SELECT start, duration, damage FROM fights WHERE slug = ? ORDER BY start")
    .bind(env.CHARACTER_SLUG)
    .all<{ start: number; duration: number; damage: number }>();

  const periods: ModelPeriod[] = [];
  log.results.forEach((row, i) => {
    const next = log.results[i + 1];
    const from = new Date(row.at).getTime() / 1000;
    const to = next ? new Date(next.at).getTime() / 1000 : Infinity;
    // The first row has no "before": it also covers the fights recorded earlier.
    const inPeriod = fights.results.filter((f) => (i === 0 ? f.start < to : f.start >= from && f.start < to));
    const secs = inPeriod.reduce((a, f) => a + f.duration, 0);
    const dmg = inPeriod.reduce((a, f) => a + f.damage, 0);

    let change = "kiinduló állapot";
    const prev = log.results[i - 1];
    if (prev) {
      const before = gearNames(prev.eq ?? undefined);
      const after = gearNames(row.eq ?? undefined);
      const bits: string[] = [];
      for (const [slot, name] of after) if (before.get(slot) !== name) bits.push(name);
      const tb = talentPoints(prev.tal ?? undefined);
      const ta = talentPoints(row.tal ?? undefined);
      if (tb !== ta) bits.push(`talentek: ${ta}`);
      if (prev.level != null && row.level != null && row.level !== prev.level) bits.push(`${row.level}. szint`);
      change = bits.length ? bits.slice(0, 4).join(", ") + (bits.length > 4 ? ` és még ${bits.length - 4}` : "") : "kisebb változás";
    }
    periods.push({
      from: row.at,
      to: next?.at ?? null,
      level: row.level,
      change,
      modelDps: row.model_dps,
      measuredDps: secs >= MIN_SECONDS ? dmg / secs : null,
      fights: inPeriod.length,
      minutes: secs / 60,
      predictedPct: null,
      measuredPct: null,
    });
  });
  for (let i = 1; i < periods.length; i++) {
    const a = periods[i - 1];
    const b = periods[i];
    b.predictedPct = ((b.modelDps - a.modelDps) / a.modelDps) * 100;
    if (a.measuredDps && b.measuredDps) b.measuredPct = ((b.measuredDps - a.measuredDps) / a.measuredDps) * 100;
  }

  const gaps = periods.filter((p) => p.measuredDps).map((p) => Math.abs((p.modelDps - p.measuredDps!) / p.measuredDps!) * 100);
  const typical = gaps.length ? gaps.sort((a, b) => a - b)[Math.floor(gaps.length / 2)] : null;
  const both = periods.filter((p) => p.predictedPct != null && p.measuredPct != null);
  const sameWay = both.filter((p) => Math.sign(p.predictedPct!) === Math.sign(p.measuredPct!) || Math.abs(p.predictedPct!) < 1).length;
  const verdict =
    typical == null
      ? "Még nincs elég rögzített harc ahhoz, hogy a modellt a valósághoz mérjem."
      : `A modell és a mért sebzés közti tipikus eltérés ${typical.toFixed(0)}%.` +
        (both.length
          ? ` ${both.length} változásból ${sameWay} esetben a mért sebzés abba az irányba mozdult, amerre a modell jósolta.`
          : " Változás előtti és utáni mérés még nincs, ezért az előrejelzések iránya még nem ellenőrizhető.");
  return { periods: periods.reverse(), typicalErrorPct: typical, verdict };
}
