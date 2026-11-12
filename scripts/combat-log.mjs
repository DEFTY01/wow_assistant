// Parses the game's own combat log (Logs/WoWCombatLog-*.txt, COMBAT_LOG_VERSION 22 with
// advanced logging) into per-fight summaries for one character.
//
// Field layout after the timestamp (0-based):
//   0 event, 1 srcGUID, 2 srcName, 3-4 flags, 5 dstGUID, 6 dstName, 7-8 flags, then the payload.
//   SWING_*  payload starts at 9, SPELL_* payload has spellId/name/school at 9-11 first.
//   Damage events carry a 19-field "advanced" block (unit GUID, owner, hp, maxHp, attack power,
//   spell power, armor, absorb, 2 unknown, power type, power, max power, cost, x, y, map, facing,
//   level) followed by amount, base amount, overkill, school, resisted, blocked, absorbed,
//   critical, glancing, crushing.

const FIGHT_GAP = 8; // seconds without any action of ours ends a fight
const MAX_CASTS = 150;
const FINISHERS = new Set(["Eviscerate", "Slice and Dice", "Rupture", "Kidney Shot", "Expose Armor"]);
const COMBO_POINTS = "4";

function splitCsv(line) {
  const out = [];
  let cur = "";
  let quoted = false;
  for (const ch of line) {
    if (ch === '"') quoted = !quoted;
    else if (ch === "," && !quoted) {
      out.push(cur);
      cur = "";
    } else cur += ch;
  }
  out.push(cur);
  return out;
}

// "11/12/2026 18:12:44.2981" -> seconds (local time). The 4th fraction digit is not milliseconds.
function parseTime(stamp) {
  const m = /^(\d+)\/(\d+)\/(\d+) (\d+):(\d+):(\d+)\.(\d{3})/.exec(stamp);
  if (!m) return null;
  return new Date(+m[3], +m[1] - 1, +m[2], +m[4], +m[5], +m[6], +m[7]).getTime() / 1000;
}

const newAbility = () => ({ n: 0, dmg: 0, hit: 0, crit: 0, glance: 0, miss: 0, dodge: 0, parry: 0, block: 0, other: 0, max: 0 });
const MISS = { MISS: "miss", DODGE: "dodge", PARRY: "parry", BLOCK: "block" };
const round1 = (n) => Math.round(n * 10) / 10;

/**
 * @param {string} text  whole log file
 * @param {string} character  first name of the character, e.g. "Defty"
 * @param {{ includeOpen?: boolean }} [opts]  includeOpen: also return a fight that may still be going on
 */
export function parseCombatLog(text, character, opts = {}) {
  const prefix = `${character}-`;
  const fights = [];
  let fight = null;
  let lastTime = 0;
  let cp = 0;

  const close = () => {
    const f = fight;
    fight = null;
    if (!f) return;
    const dur = f.last - f.t0;
    let dmg = 0;
    for (const a of Object.values(f.ab)) dmg += a.dmg;
    if (dur < 3 || dmg <= 0) return;
    for (const [name, since] of Object.entries(f.auraOn)) f.auras[name] = (f.auras[name] ?? 0) + Math.max(0, f.last - since);
    for (const name of Object.keys(f.auras)) f.auras[name] = round1(Math.min(f.auras[name], dur));
    const target = Object.entries(f.targets).sort((a, b) => b[1] - a[1])[0]?.[0];
    fights.push({
      start: Math.round(f.t0),
      dur: round1(dur),
      dmg,
      target,
      targetLevel: target ? (f.levels[target] ?? null) : null,
      level: null, // the log only has the player's item level; the server fills this in
      ab: f.ab,
      casts: f.casts,
      auras: f.auras,
      capped: round1(f.capped),
      samples: round1(f.samples),
    });
  };

  const touch = (t) => {
    if (fight && t - fight.last > FIGHT_GAP) close();
    if (!fight) {
      fight = { t0: t, last: t, ab: {}, casts: [], targets: {}, levels: {}, auras: {}, auraOn: {}, capped: 0, samples: 0, energyAt: null };
      // Buffs that were already running when the fight began.
      for (const name of activeAuras) fight.auraOn[name] = t;
      cp = 0; // combo points sit on the target, so a new fight starts from zero
    }
    fight.last = t;
  };
  const ability = (name) => (fight.ab[name] ??= newAbility());

  // Time at the energy cap, estimated from the energy value attached to our own events.
  const sampleEnergy = (t, power, max) => {
    if (!(max > 0)) return;
    const prev = fight.energyAt;
    if (prev && t > prev.t) {
      fight.samples += t - prev.t;
      if (prev.full && power >= max) fight.capped += t - prev.t;
    }
    fight.energyAt = { t, full: power >= max };
  };

  const activeAuras = new Set();

  for (const line of text.split(/\r?\n/)) {
    const sep = line.indexOf("  ");
    if (sep < 0) continue;
    const t = parseTime(line.slice(0, sep));
    if (t == null) continue;
    lastTime = t;
    const f = splitCsv(line.slice(sep + 2));
    const ev = f[0];
    const mine = f[2]?.startsWith(prefix);
    const toMe = f[6]?.startsWith(prefix);

    if ((ev === "SPELL_AURA_APPLIED" || ev === "SPELL_AURA_REMOVED") && toMe && f[12] === "BUFF") {
      const name = f[10];
      if (ev === "SPELL_AURA_APPLIED") {
        activeAuras.add(name);
        if (fight && t - fight.last <= FIGHT_GAP) fight.auraOn[name] ??= t;
      } else {
        activeAuras.delete(name);
        if (fight && fight.auraOn[name] != null) {
          fight.auras[name] = (fight.auras[name] ?? 0) + Math.max(0, Math.min(t, fight.last) - fight.auraOn[name]);
          delete fight.auraOn[name];
        }
      }
      continue;
    }
    if (!mine) continue;

    const hostile = f[5]?.startsWith("Creature-") || f[5]?.startsWith("Vehicle-") || (f[5]?.startsWith("Player-") && !toMe);

    if (ev === "SWING_DAMAGE") {
      touch(t);
      const amount = Number(f[28]) || 0;
      const a = ability("Melee");
      a.n++;
      a.dmg += amount;
      if (f[35] === "1") a.crit++;
      else if (f[36] === "1") a.glance++;
      else a.hit++;
      a.max = Math.max(a.max, amount);
      fight.targets[f[6]] = (fight.targets[f[6]] ?? 0) + amount;
      sampleEnergy(t, Number(f[20]), Number(f[21]));
    } else if (ev === "SWING_DAMAGE_LANDED") {
      if (fight && f[9] === f[5]) fight.levels[f[6]] = Number(f[27]) || fight.levels[f[6]];
    } else if (ev === "SWING_MISSED") {
      touch(t);
      const a = ability(f[10] === "1" ? "Melee (off hand miss)" : "Melee");
      // Misses are the only swing events that say which hand it was; count them all under Melee
      // and keep the off-hand share separately.
      const all = ability("Melee");
      all.n++;
      all[MISS[f[9]] ?? "other"]++;
      if (a !== all) {
        a.n++;
        a[MISS[f[9]] ?? "other"]++;
      }
    } else if (ev === "SPELL_DAMAGE" || ev === "RANGE_DAMAGE" || ev === "SPELL_PERIODIC_DAMAGE" || ev === "DAMAGE_SHIELD") {
      touch(t);
      const amount = Number(f[31]) || 0;
      const a = ability(ev === "SPELL_PERIODIC_DAMAGE" ? `${f[10]} (dot)` : f[10]);
      a.n++;
      a.dmg += amount;
      if (f[38] === "1") a.crit++;
      else if (f[39] === "1") a.glance++;
      else a.hit++;
      a.max = Math.max(a.max, amount);
      fight.targets[f[6]] = (fight.targets[f[6]] ?? 0) + amount;
      if (f[12] === f[5]) fight.levels[f[6]] = Number(f[30]) || fight.levels[f[6]];
    } else if (ev === "SPELL_MISSED") {
      touch(t);
      const a = ability(f[10]);
      a.n++;
      a[MISS[f[12]] ?? "other"]++;
    } else if (ev === "SPELL_ENERGIZE") {
      if (f[33] === COMBO_POINTS) cp = Math.min(Number(f[34]) || 5, cp + (Number(f[31]) || 0));
    } else if (ev === "SPELL_CAST_SUCCESS") {
      const name = f[10];
      // Only casts on enemies (or finishers/buffs used mid-fight) belong to a fight.
      if (hostile || (fight && t - fight.last <= FIGHT_GAP)) {
        if (hostile) touch(t);
        else fight.last = Math.max(fight.last, t);
        const energy = Number(f[23]);
        if (fight.casts.length < MAX_CASTS) {
          fight.casts.push([Math.round((t - fight.t0) * 10), name, Number.isFinite(energy) ? energy : 0, cp]);
        }
        if (f[12] === f[1]) sampleEnergy(t, energy, Number(f[24]));
      }
      if (FINISHERS.has(name)) cp = 0;
    }
  }

  // The last fight is only final once the log has moved on (or the caller says so).
  if (fight && (opts.includeOpen || lastTime - fight.last > FIGHT_GAP)) close();
  return fights;
}
