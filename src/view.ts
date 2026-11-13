import { html } from "hono/html";
import { type Html, QUALITY, money, page } from "./layout";
import type { Kind, LatestSnapshot } from "./sync";

export { CSS, formatMoney } from "./layout";

type Obj = Record<string, any>;

export interface DashboardData {
  slug: string;
  snapshots: Partial<Record<Kind, LatestSnapshot>>;
  log: { kind: string; status: number; changed: number; message: string | null; at: string }[];
  goldCopper: number | null;
  addon: {
    updatedAt: string;
    bagItems: number;
    bankItems: number | null;
    skills: { name: string; rank: number; max: number }[];
  } | null;
  trainerSkills: {
    name: string;
    rank: number | null;
    required_level: number | null;
    cost_copper: number | null;
    learned: number;
    state: string;
  }[];
}

// The Forever response shapes are not officially documented, so every reader
// below is defensive and falls back to the raw JSON block at the bottom.
function text(v: unknown): string {
  if (v == null) return "";
  if (typeof v === "string" || typeof v === "number") return String(v);
  if (typeof v === "object") {
    const o = v as Obj;
    return text(o.name ?? o.display_string ?? o.value ?? o.type ?? "");
  }
  return "";
}

function when(iso: string | undefined | null): string {
  if (!iso) return "–";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString("hu-HU", { timeZone: "Europe/Budapest", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

// ---------------------------------------------------------------- banner

function hero(p: Obj | undefined, d: DashboardData): Html {
  if (!p) {
    return html`<div class="frame hero"><div><h1>${d.slug}</h1>
      <p class="sub">Még nincs profil-pillanatkép. Nyomd meg a Szinkron gombot.</p></div></div>`;
  }
  const faction = String(p.faction?.type ?? "").toLowerCase();
  return html`<div class="frame hero">
    <div class="medal" title="Szint">${text(p.level)}</div>
    <div>
      <h1>${text(p.name)}${p.surname ? html`<small>${text(p.surname)}</small>` : ""}</h1>
      <p class="sub"><b>${text(p.race)} ${text(p.character_class)}</b>
        ${p.guild ? html` · &lt;${text(p.guild)}&gt;` : ""}
        ${p.ruleset ? html` · ${text(p.ruleset)}` : ""}
        ${faction ? html` · <span class="${faction}">${text(p.faction)}</span>` : ""}</p>
    </div>
    <div class="chips">
      <div class="chip"><span>Vagyon</span><b>${money(d.goldCopper)}</b></div>
      <div class="chip"><span>Item level</span><b>${text(p.equipped_item_level ?? p.average_item_level) || "–"}</b></div>
      <div class="chip"><span>Táskák</span><b>${d.addon ? `${d.addon.bagItems} féle` : "–"}</b></div>
    </div>
  </div>`;
}

// ---------------------------------------------------------------- paper doll

const LEFT = ["HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "SHIRT", "TABARD", "WRIST"];
const RIGHT = ["HANDS", "WAIST", "LEGS", "FEET", "FINGER_1", "FINGER_2", "TRINKET_1", "TRINKET_2"];
const WEAPONS = ["MAIN_HAND", "OFF_HAND", "RANGED"];
const SLOT_LABEL: Record<string, [string, string]> = {
  HEAD: ["Fej", "FEJ"], NECK: ["Nyak", "NYK"], SHOULDER: ["Váll", "VÁL"], BACK: ["Köpeny", "KÖP"], CHEST: ["Mellkas", "MEL"],
  SHIRT: ["Ing", "ING"], TABARD: ["Tabard", "TAB"], WRIST: ["Csukló", "CSU"], HANDS: ["Kéz", "KÉZ"], WAIST: ["Öv", "ÖV"],
  LEGS: ["Láb", "LÁB"], FEET: ["Lábfej", "CIP"], FINGER_1: ["Gyűrű", "GY1"], FINGER_2: ["Gyűrű", "GY2"],
  TRINKET_1: ["Trinket", "TR1"], TRINKET_2: ["Trinket", "TR2"], MAIN_HAND: ["Főkéz", "FŐK"], OFF_HAND: ["Balkéz", "BAL"],
  RANGED: ["Távolsági", "TÁV"],
};

function slot(type: string, it: Obj | undefined): Html {
  const [label, abbr] = SLOT_LABEL[type] ?? [type, type.slice(0, 3)];
  if (!it) {
    return html`<div class="slot empty"><div class="icon">${abbr}</div>
      <div><div class="name">${label}</div><div class="meta">üres</div></div></div>`;
  }
  const bits: string[] = [];
  if (it.level?.value) bits.push(`ilvl ${it.level.value}`);
  if (it.weapon?.damage) {
    bits.push(`${it.weapon.damage.min_value}–${it.weapon.damage.max_value} / ${(Number(it.weapon.attack_speed?.value) / 1000).toFixed(1)}`);
  }
  for (const s of (it.stats ?? []) as Obj[]) bits.push(`+${s.value} ${text(s.type)}`);
  const q = QUALITY[it.quality?.type] ?? QUALITY.COMMON;
  return html`<div class="slot" style="--q:${q}"><div class="icon">${abbr}</div>
    <div><div class="name" title="${text(it.name)}">${text(it.name)}</div>
    <div class="meta" title="${bits.join(" · ")}">${bits.join(" · ") || label}</div></div></div>`;
}

function num(v: unknown, digits = 0): string {
  let n: unknown = v;
  if (v && typeof v === "object") {
    const o = v as Obj;
    n = o.effective ?? o.value;
  }
  return typeof n === "number" ? n.toFixed(digits) : "–";
}

function sheet(s: Obj | undefined): Html {
  if (!s) return html`<div class="sheet"><p class="muted">Nincs statisztika-adat.</p></div>`;
  const row = (k: string, v: string) => html`<dt>${k}</dt><dd>${v}</dd>`;
  return html`<div class="sheet">
    <h3>Támadás</h3>
    <dl class="kv">
      ${row("Attack power", num(s.attack_power))}
      ${row("Crit", `${num(s.melee_crit, 2)}%`)}
      ${row("Hit", `${num(s.melee_hit, 1)}%`)}
      ${row("Főkéz", `${num(s.main_hand_damage_min)}–${num(s.main_hand_damage_max)} · ${num(s.main_hand_dps, 1)} dps`)}
      ${row("Balkéz", `${num(s.off_hand_damage_min)}–${num(s.off_hand_damage_max)} · ${num(s.off_hand_dps, 1)} dps`)}
    </dl>
    <h3>Alapértékek</h3>
    <dl class="kv">
      ${row("Agility", num(s.agility))}
      ${row("Strength", num(s.strength))}
      ${row("Stamina", num(s.stamina))}
      ${row("Életerő", num(s.health))}
    </dl>
    <h3>Védekezés</h3>
    <dl class="kv">
      ${row("Páncél", num(s.armor))}
      ${row("Dodge", `${num(s.dodge, 1)}%`)}
      ${row("Parry", `${num(s.parry, 1)}%`)}
    </dl>
  </div>`;
}

function doll(e: Obj | undefined, s: Obj | undefined): Html {
  const by = new Map<string, Obj>();
  for (const it of (e?.equipped_items ?? []) as Obj[]) by.set(it.slot?.type, it);
  // Tabard is rarely worn; leave it out unless there is one.
  const left = LEFT.filter((t) => t !== "TABARD" || by.has(t));
  return html`<div class="doll">
    <div class="col">${left.map((t) => slot(t, by.get(t)))}</div>
    ${sheet(s)}
    <div class="col right">${RIGHT.map((t) => slot(t, by.get(t)))}</div>
    <div class="weapons">${WEAPONS.map((t) => slot(t, by.get(t)))}</div>
  </div>`;
}

// ---------------------------------------------------------------- professions & talents

function professionList(p: Obj | undefined): Html {
  const groups: Obj[] = [...(p?.primaries ?? []), ...(p?.secondaries ?? [])];
  if (!groups.length) return html`<p class="muted">Nincs mesterség-adat.</p>`;
  return html`${groups.map((g) => {
    // Retail nests skill under tiers[]; Classic-style responses put it on the profession itself.
    const tiers: Obj[] = g.tiers?.length ? g.tiers : [g];
    return tiers.map((t) => {
      const cur = Number(t.skill_points ?? 0);
      const max = Number(t.max_skill_points ?? 0);
      const recipes: Obj[] = t.known_recipes ?? [];
      const prof = text(g.profession);
      const tier = g.tiers?.length ? text(t.tier) : "";
      const name = tier && tier !== prof ? `${prof} – ${tier}` : prof;
      const pct = max ? Math.min(100, (cur / max) * 100) : 0;
      return html`<div class="prof">
        <div class="prof-head"><strong>${name}</strong>
          <span class="muted">${recipes.length > 2 ? `${recipes.length} recept` : ""}</span></div>
        <div class="bar-track"><div class="bar-fill ${max && max - cur <= 15 ? "capped" : ""}" style="width:${pct}%"></div>
          <div class="bar-label">${cur}${max ? ` / ${max}` : ""}</div></div>
      </div>`;
    });
  })}
  <p style="margin:12px 0 0"><a href="/professions">Legolcsóbb szintezési útvonal →</a></p>`;
}

function talentTrees(s: Obj | undefined): Html {
  const groups: Obj[] = s?.specialization_groups ?? [];
  const active = groups.find((g) => g.is_active) ?? groups[0];
  const specs: Obj[] = active?.specializations ?? [];
  if (!specs.length) return html`<p class="muted">Nincs talent-adat.</p>`;
  return html`<div class="trees">${specs.map((sp) => {
    const pts = Number(sp.spent_points) || 0;
    return html`<div class="tree ${pts ? "" : "zero"}">
      <header><b>${text(sp.specialization_name ?? sp.specialization)}</b><span>${pts}</span></header>
      <ul>${((sp.talents ?? []) as Obj[]).map(
        (t) => html`<li title="${text(t.spell_tooltip?.description)}"><span>${text(t.talent)}</span><b>${text(t.talent_rank)}</b></li>`,
      )}</ul>
    </div>`;
  })}</div>`;
}

// ---------------------------------------------------------------- trainer, sources

function trainerTable(d: DashboardData): Html {
  if (!d.trainerSkills.length) {
    return html`<p class="muted">Még nincs rögzítve trainer skill. Nyisd meg a trainer ablakát a játékban
      (a Filter menüben minden pipával), aztán <code>/wa save</code>.</p>`;
  }
  const now = d.trainerSkills.filter((t) => t.state === "available");
  const later = d.trainerSkills.filter((t) => t.state === "unavailable");
  const sum = (list: typeof now) => list.reduce((a, t) => a + (t.cost_copper ?? 0), 0);
  return html`<p><b>${now.length}</b> skill tanulható meg most, összesen ${money(sum(now))}
      ${d.goldCopper != null ? html`<span class="muted">(nálad: ${money(d.goldCopper)})</span>` : ""}.
      Később: ${later.length} skill, ${money(sum(later))}.</p>
    <table><thead><tr><th>Skill</th><th>Rank</th><th class="num">Szint</th><th class="num">Ár</th><th></th></tr></thead><tbody>
    ${d.trainerSkills.map(
      (t) => html`<tr><td>${t.name}</td><td class="muted">${t.rank ? `Rank ${t.rank}` : ""}</td>
        <td class="num">${t.required_level ?? ""}</td><td class="num">${money(t.cost_copper)}</td>
        <td>${t.state === "used" ? html`<span class="tag tag-info">megvan</span>` : t.state === "available" ? html`<span class="tag">tanulható</span>` : html`<span class="muted">később</span>`}</td></tr>`,
    )}
    </tbody></table>`;
}

function sources(d: DashboardData): Html {
  const lastOk = d.log.find((l) => l.status === 200);
  // Only failures newer than the last success matter (the log is newest first).
  const upTo = lastOk ? d.log.indexOf(lastOk) : d.log.length;
  const failed = d.log.slice(0, upTo).filter((l) => l.status !== 200).slice(0, 3);
  return html`<dl class="kv">
      <dt>Blizzard API</dt><dd>${when(lastOk?.at)}</dd>
      <dt>Addon feltöltés</dt><dd>${when(d.addon?.updatedAt)}</dd>
      <dt>Bank</dt><dd>${d.addon?.bankItems == null ? "még nincs megnyitva" : `${d.addon.bankItems} féle tárgy`}</dd>
    </dl>
    ${failed.length
      ? html`<p class="err" style="margin-top:10px">Sikertelen lekérés: ${failed.map((l) => `${l.kind} (HTTP ${l.status})`).join(", ")}</p>`
      : ""}
    <form method="post" action="/manual/gold" class="gold" style="margin-top:14px">
      <label for="gold">Gold kézzel</label>
      <input id="gold" name="gold" type="number" min="0" step="0.0001" value="${d.goldCopper == null ? "" : d.goldCopper / 10000}">
      <button>Mentés</button>
    </form>`;
}

function rawBlock(title: string, snap: LatestSnapshot | undefined): Html {
  if (!snap) return html``;
  return html`<details><summary>${title} (utoljára változott: ${when(snap.fetched_at)})</summary>
    <pre>${JSON.stringify(snap.json, null, 2)}</pre></details>`;
}

// ---------------------------------------------------------------- page

export function dashboard(d: DashboardData, extra?: Html): Html {
  const s = d.snapshots;
  const profile = s.profile?.json as Obj | undefined;
  return page({
    title: text(profile?.name) || d.slug,
    active: "char",
    toolbar: html`<form method="post" action="/sync"><button>Szinkron</button></form>`,
    body: html`
  ${hero(profile, d)}
  <section class="wide"><h2>Felszerelés</h2>
    ${doll(s.equipment?.json as Obj | undefined, s.statistics?.json as Obj | undefined)}
    <p style="margin:16px 0 0"><a href="/gear">Mit érdemes lecserélni és melyik dungeonből →</a></p>
  </section>
  <section><h2>Talentek</h2>${talentTrees(s.specializations?.json as Obj | undefined)}</section>
  <section><h2>Mesterségek</h2>${professionList(s.professions?.json as Obj | undefined)}</section>
  <section><h2>Trainer skillek</h2>${trainerTable(d)}</section>
  <section><h2>Adatforrások</h2>${sources(d)}</section>
  ${extra ?? ""}
  <section class="wide"><h2>Műszaki adatok</h2>
    <details><summary>Szinkron napló</summary>
      <table><thead><tr><th>Idő</th><th>Végpont</th><th>HTTP</th><th>Változott</th><th>Üzenet</th></tr></thead><tbody>
      ${d.log.map(
        (l) => html`<tr class="${l.status === 200 ? "" : "err"}"><td>${when(l.at)}</td><td>${l.kind}</td>
          <td>${l.status}</td><td>${l.changed ? "igen" : ""}</td><td class="muted">${l.message ?? ""}</td></tr>`,
      )}
      </tbody></table>
    </details>
    ${rawBlock("Profil", s.profile)}${rawBlock("Felszerelés", s.equipment)}
    ${rawBlock("Mesterségek", s.professions)}${rawBlock("Talentek", s.specializations)}
    ${rawBlock("Statok", s.statistics)}
  </section>`,
  });
}
