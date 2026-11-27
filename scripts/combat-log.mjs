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
//
// Damage is counted as effective damage: the amount minus the overkill (the part beyond the
// target's remaining health; -1 when there is none). Absorbed damage is not in the amount.
// A fight runs from our first to our last damaging or hostile action (no gap over FIGHT_GAP);
// a pet counts only when the log's own flags say it is ours (affiliation "mine", pet/guardian).
// Each fight says so in its `basis`, which the addon shows next to the numbers.
//
// Every Eviscerate and Ferocious Bite is kept with the state of the decision (fight.evis; a
// Ferocious Bite carries spell: "Ferocious Bite", an Eviscerate no spell field): the combo points it
// spent (the cast's power cost "energy|combo points"), the target's health before the hit (the
// damage event's advanced block describes the target: health after the hit + the damage), the
// damage, whether it killed, and how long the target lived after it (its death, or at least
// until our last hit on it). The addon decides from these whether a low-point finisher was a
// mistake.
//
// Every Life Tap during a fight is kept (fight.taps): the mana it gave and the part over the
// maximum, which the energize event states itself (its overEnergize field). That part was paid for
// with health and lost. Mana potions and mana gems ("Restore Mana", "Replenish Mana") are kept the
// same way (fight.gems): the part over the maximum is lost. Rage events of ours (fight.rage: Bloodrage,
// Charge, Shield Specialization, Unbridled Wrath...) too, a tick marked: rage over 100 is lost.
//
// The aura timeline (fight.auraLog, WA-005): when each of our buffs and each of our debuffs on the
// enemies went on and off, on the casts' clock (tenths of a second from the pull):
// [t, name, 1 on / 0 off, "b" buff on us / "d" our debuff on an enemy]. A buff running at the pull
// is on at 0. A debuff is on while it sits on at least one enemy; an enemy's death takes ours off it.
// At most MAX_AURA_EVENTS a fight; past that fight.auraLogCut says from when the timeline is missing.

// Everything lives inside the function on purpose: the web app serves this function's own
// source to the browser (Function.prototype.toString), so it must not lean on module scope.
/**
 * @param {string} text  whole log file
 * @param {string} character  first name of the character, e.g. "Defty"
 * @param {{ includeOpen?: boolean }} [opts]  includeOpen: also return a fight that may still be going on
 */
export function parseCombatLog(text, character, opts = {}) {
  const FIGHT_GAP = 8; // seconds without any action of ours ends a fight
  const MAX_CASTS = 150;
  const MAX_AURA_EVENTS = 200;
  const FINISHERS = new Set(["Eviscerate", "Slice and Dice", "Rupture", "Kidney Shot", "Expose Armor", "Rip", "Ferocious Bite"]);
  // direct-damage finishers whose decision is kept in fight.evis
  const PROVABLE = new Set(["Eviscerate", "Ferocious Bite"]);
  const COMBO_POINTS = "4";
  const ENERGY = "3";
  const MANA = "0";
  const RAGE = "1";
  // Things done between fights: they must neither start a fight nor glue two fights together.
  const NOT_COMBAT = /^(Skinning|Stealth|Mining|Herb Gathering|Fishing|Pick Pocket|Pick Lock|Disarm Trap|Detect Traps|Find \w+|.*Bandage.*|.*Poison.*)$/;

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
  // amount minus overkill; the overkill is added to the fight's total separately
  const effective = (amountField, overkillField) => {
    const amount = Number(amountField) || 0;
    const over = Math.max(0, Number(overkillField) || 0);
    if (fight) fight.overkill += Math.min(amount, over);
    return Math.max(0, amount - over);
  };

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
    let pet = 0;
    for (const [name, a] of Object.entries(f.ab)) {
      dmg += a.dmg;
      if (name.startsWith("Pet: ")) pet += a.dmg;
    }
    if (dur < 3 || dmg <= 0) return;
    for (const [name, since] of Object.entries(f.auraOn)) f.auras[name] = (f.auras[name] ?? 0) + Math.max(0, f.last - since);
    for (const name of Object.keys(f.auras)) f.auras[name] = round1(Math.min(f.auras[name], dur));
    const target = Object.entries(f.targets).sort((a, b) => b[1] - a[1])[0]?.[0];
    // how long each Eviscerate's target lived after it: its death, else at least until our last hit
    const evis = f.evis.map((e) => {
      const died = deaths[e.guid];
      const end = died != null && died >= e.at ? died : Math.max(lastHit[e.guid] ?? e.at, e.at);
      const out = { spell: e.spell, t: e.t, cp: e.cp, target: e.target, landed: e.landed ?? null, dmg: e.dmg ?? null, crit: e.crit ?? null,
        blocked: e.blocked || undefined,
        killed: e.killed ?? null, hpBefore: e.hpBefore ?? null, maxHp: e.maxHp ?? null,
        lived: round1(end - e.at), livedKnown: died != null && died >= e.at };
      return out;
    });
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
      pet,
      overkill: f.overkill,
      evis: evis.length ? evis : undefined,
      taps: f.taps.length ? f.taps : undefined,
      gems: f.gems.length ? f.gems : undefined,
      rage: f.rage.length ? f.rage : undefined,
      auraLog: f.auraLog.length ? f.auraLog : undefined,
      auraLogCut: f.auraLogCut ?? undefined,
      basis: { dmg: "effective", dur: "own-events", pet: "owner-flags" },
    });
  };

  const touch = (t) => {
    if (fight && t - fight.last > FIGHT_GAP) close();
    if (!fight) {
      fight = { t0: t, last: t, ab: {}, casts: [], targets: {}, levels: {}, auras: {}, auraOn: {}, capped: 0, samples: 0, energyAt: null, overkill: 0,
        evis: [], evisPending: null, taps: [], gems: [], rage: [], auraLog: [], auraLogCut: null, debuffOn: {} };
      // Buffs that were already running when the fight began.
      for (const name of activeAuras) {
        fight.auraOn[name] = t;
        auraEvent(t, name, 1, "b");
      }
      cp = 0; // combo points sit on the target, so a new fight starts from zero
    }
    fight.last = t;
  };
  const ability = (name) => (fight.ab[name] ??= newAbility());
  // one change on the aura timeline (the fight must be open)
  function auraEvent(t, name, on, kind) {
    if (fight.auraLogCut != null) return;
    const at = Math.max(0, Math.round((t - fight.t0) * 10));
    if (fight.auraLog.length >= MAX_AURA_EVENTS) {
      fight.auraLogCut = at;
      return;
    }
    fight.auraLog.push([at, name, on, kind]);
  }
  // our debuff off an enemy (removed, or the enemy died): off the timeline when no enemy has it
  const debuffOff = (t, name, guid) => {
    const on = fight?.debuffOn[name];
    if (!on || !on.has(guid)) return;
    on.delete(guid);
    if (on.size === 0) auraEvent(t, name, 0, "d");
  };

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
  const deaths = {}; // unit GUID -> time it died
  const lastHit = {}; // unit GUID -> time of our (or our pet's) last damage on it
  // the power cost of a cast for one power type ("3|4" and "35|3": 35 energy, 3 combo points)
  const costOf = (types, costs, type) => {
    const t = String(types ?? "").split("|");
    const c = String(costs ?? "").split("|");
    const i = t.indexOf(type);
    return i >= 0 ? Number(c[i]) : NaN;
  };

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
        if (fight && t - fight.last <= FIGHT_GAP && fight.auraOn[name] == null) {
          fight.auraOn[name] = t;
          auraEvent(t, name, 1, "b");
        }
      } else {
        activeAuras.delete(name);
        if (fight && fight.auraOn[name] != null) {
          fight.auras[name] = (fight.auras[name] ?? 0) + Math.max(0, Math.min(t, fight.last) - fight.auraOn[name]);
          delete fight.auraOn[name];
          auraEvent(Math.min(t, fight.last), name, 0, "b");
        }
      }
      continue;
    }
    // our debuff on an enemy (DoTs, Sunder Armor, Faerie Fire...): on the timeline (WA-005)
    if ((ev === "SPELL_AURA_APPLIED" || ev === "SPELL_AURA_REMOVED") && mine && !toMe && f[12] === "DEBUFF") {
      const name = f[10];
      const guid = f[5];
      if (ev === "SPELL_AURA_APPLIED") {
        if (fight && t - fight.last <= FIGHT_GAP) {
          const on = (fight.debuffOn[name] ??= new Set());
          if (on.size === 0) auraEvent(t, name, 1, "d");
          on.add(guid);
        }
      } else if (fight) debuffOff(Math.min(t, fight.last + FIGHT_GAP), name, guid);
      continue;
    }
    if (ev === "UNIT_DIED") {
      deaths[f[5]] = t;
      if (fight) for (const name of Object.keys(fight.debuffOn)) debuffOff(t, name, f[5]);
      continue;
    }
    // Our pet (a hunter's beast): source flags say "mine" (0x1) and pet or guardian (0x3000).
    // Its damage is ours, as on raid logging sites, under "Pet: <ability>".
    const srcFlags = parseInt(f[3], 16) || 0;
    if (!mine && (srcFlags & 0x1) && (srcFlags & 0x3000)) {
      const swing = ev.startsWith("SWING_");
      if (ev === "SWING_DAMAGE" || ev === "SPELL_DAMAGE" || ev === "SPELL_PERIODIC_DAMAGE") {
        touch(t);
        const amount = swing ? effective(f[28], f[30]) : effective(f[31], f[33]);
        const a = ability(swing ? "Pet: Melee" : `Pet: ${f[10]}${ev === "SPELL_PERIODIC_DAMAGE" ? " (dot)" : ""}`);
        a.n++;
        a.dmg += amount;
        if (f[swing ? 35 : 38] === "1") a.crit++;
        else if (f[swing ? 36 : 39] === "1") a.glance++;
        else a.hit++;
        a.max = Math.max(a.max, amount);
        fight.targets[f[6]] = (fight.targets[f[6]] ?? 0) + amount;
        lastHit[f[5]] = t;
      } else if ((ev === "SWING_MISSED" || ev === "SPELL_MISSED") && fight && t - fight.last <= FIGHT_GAP) {
        const a = ability(swing ? "Pet: Melee" : `Pet: ${f[10]}`);
        a.n++;
        a[MISS[f[swing ? 9 : 12]] ?? "other"]++;
      }
      continue;
    }
    if (!mine) continue;

    const hostile = f[5]?.startsWith("Creature-") || f[5]?.startsWith("Vehicle-") || (f[5]?.startsWith("Player-") && !toMe);

    if (ev === "SWING_DAMAGE") {
      touch(t);
      const amount = effective(f[28], f[30]);
      const a = ability("Melee");
      a.n++;
      a.dmg += amount;
      if (f[35] === "1") a.crit++;
      else if (f[36] === "1") a.glance++;
      else a.hit++;
      a.max = Math.max(a.max, amount);
      fight.targets[f[6]] = (fight.targets[f[6]] ?? 0) + amount;
      lastHit[f[5]] = t;
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
      const amount = effective(f[31], f[33]);
      const a = ability(ev === "SPELL_PERIODIC_DAMAGE" ? `${f[10]} (dot)` : f[10]);
      a.n++;
      a.dmg += amount;
      if (f[38] === "1") a.crit++;
      else if (f[39] === "1") a.glance++;
      else a.hit++;
      a.max = Math.max(a.max, amount);
      fight.targets[f[6]] = (fight.targets[f[6]] ?? 0) + amount;
      lastHit[f[5]] = t;
      if (f[12] === f[5]) fight.levels[f[6]] = Number(f[30]) || fight.levels[f[6]];
      // the Eviscerate just cast: the target's health and what the hit did
      const e = fight.evisPending;
      if (ev === "SPELL_DAMAGE" && e && f[10] === e.name && e.guid === f[5] && t - e.at <= 1.5) {
        fight.evisPending = null;
        const hpAfter = f[12] === f[5] ? Number(f[14]) : NaN;
        e.rec.landed = true;
        e.rec.dmg = amount;
        e.rec.crit = f[38] === "1";
        e.rec.blocked = Number(f[36]) || 0;
        e.rec.killed = Number(f[33]) >= 0 || hpAfter === 0;
        if (Number.isFinite(hpAfter)) {
          e.rec.hpBefore = hpAfter + amount;
          e.rec.maxHp = Number(f[15]) || null;
        }
      }
    } else if (ev === "SPELL_MISSED") {
      touch(t);
      const a = ability(f[10]);
      a.n++;
      a[MISS[f[12]] ?? "other"]++;
      if (fight.evisPending && f[10] === fight.evisPending.name && fight.evisPending.guid === f[5]) {
        fight.evisPending.rec.landed = false;
        fight.evisPending = null;
      }
    } else if ((ev === "SPELL_ENERGIZE" || ev === "SPELL_PERIODIC_ENERGIZE") && f[33] === RAGE) {
      // a rage event of ours during a fight: the rage it gave and the part over the maximum
      if (mine && fight && t - fight.last <= FIGHT_GAP) {
        const rec = { t: Math.round((t - fight.t0) * 10), spell: f[10], gain: Math.round(Number(f[31]) || 0), over: Math.round(Number(f[32]) || 0) };
        if (ev === "SPELL_PERIODIC_ENERGIZE") rec.tick = true;
        fight.rage.push(rec);
      }
    } else if (ev === "SPELL_ENERGIZE") {
      if (f[33] === COMBO_POINTS) cp = Math.min(Number(f[34]) || 5, cp + (Number(f[31]) || 0));
      // a Life Tap of ours during a fight: the mana it gave and the part over the maximum
      if (mine && f[10] === "Life Tap" && f[33] === MANA && fight && t - fight.last <= FIGHT_GAP) {
        const gain = Number(f[31]) || 0;
        const over = Number(f[32]) || 0;
        fight.taps.push({ t: Math.round((t - fight.t0) * 10), gain: Math.round(gain), over: Math.round(over), max: Number(f[34]) || null });
      }
      // a mana potion or gem of ours during a fight, the same way
      if (mine && (f[10] === "Restore Mana" || f[10] === "Replenish Mana") && f[33] === MANA && fight && t - fight.last <= FIGHT_GAP) {
        fight.gems.push({ t: Math.round((t - fight.t0) * 10), gain: Math.round(Number(f[31]) || 0), over: Math.round(Number(f[32]) || 0), max: Number(f[34]) || null });
      }
    } else if (ev === "SPELL_CAST_SUCCESS") {
      const name = f[10];
      if (NOT_COMBAT.test(name)) continue;
      // Only casts on enemies (or finishers/buffs used mid-fight) belong to a fight.
      if (hostile || (fight && t - fight.last <= FIGHT_GAP)) {
        if (hostile) touch(t);
        else fight.last = Math.max(fight.last, t);
        // Finishers report combo points in the power fields, not energy: -1 marks "unknown".
        const isEnergy = f[22] === ENERGY;
        const energy = isEnergy ? Number(f[23]) : -1;
        // a finisher's combo points: from the cast's own cost when the log lists them, else counted
        const spentCp = FINISHERS.has(name) ? costOf(f[22], f[25], COMBO_POINTS) : NaN;
        const castCp = Number.isFinite(spentCp) && spentCp > 0 ? spentCp : cp;
        if (fight.casts.length < MAX_CASTS) {
          fight.casts.push([Math.round((t - fight.t0) * 10), name, Number.isFinite(energy) ? energy : -1, castCp]);
        }
        if (isEnergy && f[12] === f[1]) sampleEnergy(t, energy, Number(f[24]));
        if (PROVABLE.has(name)) {
          // combo points from the cast's own cost, else from what we counted
          const spent = costOf(f[22], f[25], COMBO_POINTS);
          const rec = { t: Math.round((t - fight.t0) * 10), cp: Number.isFinite(spent) && spent > 0 ? spent : cp, target: f[6] };
          if (name !== "Eviscerate") rec.spell = name;
          fight.evis.push(rec);
          fight.evisPending = { guid: f[5], at: t, rec, name };
          rec.guid = f[5];
          rec.at = t;
        }
      }
      if (FINISHERS.has(name)) cp = 0;
    }
  }

  // The last fight is only final once the log has moved on (or the caller says so).
  if (fight && (opts.includeOpen || lastTime - fight.last > FIGHT_GAP)) close();
  return fights;
}
