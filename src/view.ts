import { html, raw } from "hono/html";
import type { HtmlEscapedString } from "hono/utils/html";
import type { Kind, LatestSnapshot } from "./sync";

type Html = HtmlEscapedString | Promise<HtmlEscapedString>;
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
  }[];
}

const QUALITY_COLORS: Record<string, string> = {
  POOR: "#9d9d9d",
  COMMON: "#e8e8e8",
  UNCOMMON: "#1eff00",
  RARE: "#3d9eff",
  EPIC: "#c26bff",
  LEGENDARY: "#ff8000",
};

export function formatMoney(copper: number | null): string {
  if (copper == null) return "–";
  const g = Math.floor(copper / 10000);
  const s = Math.floor((copper % 10000) / 100);
  const c = copper % 100;
  return `${g}g ${s}s ${c}c`;
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

function profileCard(p: Obj | undefined): Html {
  if (!p) return html`<p class="muted">Még nincs profil-pillanatkép.</p>`;
  const rows: [string, string][] = [
    ["Szint", text(p.level)],
    ["Kaszt", text(p.character_class)],
    ["Faj", text(p.race)],
    ["Frakció", text(p.faction)],
    ["Guild", text(p.guild)],
    ["Átlag ilvl", text(p.average_item_level)],
  ];
  return html`<dl class="kv">
    ${rows.filter(([, v]) => v).map(([k, v]) => html`<dt>${k}</dt><dd>${v}</dd>`)}
  </dl>`;
}

function equipmentTable(e: Obj | undefined): Html {
  const items: Obj[] = e?.equipped_items ?? [];
  if (!items.length) return html`<p class="muted">Nincs felszerelés-adat.</p>`;
  return html`<table>
    <thead><tr><th>Slot</th><th>Item</th><th>ilvl</th><th>Statok</th></tr></thead>
    <tbody>
      ${items.map((it) => {
        const color = QUALITY_COLORS[it.quality?.type] ?? "inherit";
        const stats = (it.stats ?? [])
          .map((s: Obj) => text(s.display?.display_string ?? `${s.value} ${text(s.type)}`))
          .join(", ");
        const weapon = it.weapon?.damage?.display_string
          ? `${it.weapon.damage.display_string}, ${text(it.weapon.attack_speed)}, ${text(it.weapon.dps)}`
          : "";
        return html`<tr>
          <td>${text(it.slot)}</td>
          <td style="color:${color}">${text(it.name)}</td>
          <td>${text(it.level)}</td>
          <td class="muted">${[weapon, stats].filter(Boolean).join(" · ")}</td>
        </tr>`;
      })}
    </tbody>
  </table>`;
}

function professionList(p: Obj | undefined): Html {
  const groups: Obj[] = [...(p?.primaries ?? []), ...(p?.secondaries ?? [])];
  if (!groups.length) return html`<p class="muted">Nincs profession-adat.</p>`;
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
      return html`<div class="prof">
        <div class="prof-head"><strong>${name}</strong><span>${cur}${max ? ` / ${max}` : ""}</span></div>
        ${max ? html`<progress value="${cur}" max="${max}"></progress>` : ""}
        ${recipes.length
          ? html`<details><summary>${recipes.length} ismert recept</summary>
              <p class="muted">${recipes.map((r) => text(r)).join(", ")}</p></details>`
          : ""}
      </div>`;
    });
  })}`;
}

function talentList(s: Obj | undefined): Html {
  const groups: Obj[] = s?.specialization_groups ?? [];
  const active = groups.find((g) => g.is_active) ?? groups[0];
  const specs: Obj[] = active?.specializations ?? [];
  if (!specs.length) return html`<p class="muted">Nincs talent-adat.</p>`;
  return html`${specs.map(
    (sp) => html`<div class="prof">
      <div class="prof-head"><strong>${text(sp.specialization_name ?? sp.specialization)}</strong>
        <span>${text(sp.spent_points)} pont</span></div>
      <p class="muted">${(sp.talents ?? [])
        .map((t: Obj) => `${text(t.talent)} ${text(t.talent_rank)}`)
        .join(" · ")}</p>
    </div>`,
  )}`;
}

function statsGrid(s: Obj | undefined): Html {
  if (!s) return html`<p class="muted">Nincs statisztika-adat.</p>`;
  const cells: [string, string][] = [];
  for (const [key, v] of Object.entries(s)) {
    if (key.startsWith("_") || key === "character") continue;
    let val: unknown = v;
    if (v && typeof v === "object") {
      const o = v as Obj;
      val = o.effective ?? o.value ?? o.rating_normalized ?? o.rating;
    }
    if (typeof val !== "number") continue;
    cells.push([key.replace(/_/g, " "), Number.isInteger(val) ? String(val) : val.toFixed(2)]);
  }
  return html`<div class="stats">
    ${cells.map(([k, v]) => html`<div><span class="muted">${k}</span><b>${v}</b></div>`)}
  </div>`;
}

function rawBlock(title: string, snap: LatestSnapshot | undefined): Html {
  if (!snap) return html``;
  return html`<details><summary>${title} – nyers JSON (utoljára változott: ${snap.fetched_at})</summary>
    <pre>${JSON.stringify(snap.json, null, 2)}</pre></details>`;
}

export function dashboard(d: DashboardData): Html {
  const s = d.snapshots;
  const profile = s.profile?.json as Obj | undefined;
  const title = text(profile?.name) || d.slug;
  return html`<!doctype html>
<html lang="hu">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WoW Assistant – ${title}</title>
<style>${raw(CSS)}</style>
</head>
<body>
<header>
  <h1>${title}</h1>
  <nav style="display:flex;gap:12px;align-items:center"><a href="/combat">Harcelemzés</a><a href="/gear">Gear és dungeonök</a><a href="/professions">Profession útvonal</a><form method="post" action="/sync"><button>Szinkron most</button></form></nav>
</header>
<main>
  <section><h2>Karakter</h2>${profileCard(profile)}
    <form method="post" action="/manual/gold" class="gold">
      <label>Gold: <input name="gold" type="number" min="0" step="0.0001"
        value="${d.goldCopper == null ? "" : d.goldCopper / 10000}"></label>
      <button>Mentés</button>
      <span class="muted">${formatMoney(d.goldCopper)}</span>
    </form>
  </section>
  <section><h2>Addon adatok</h2>
    ${d.addon
      ? html`<p class="muted">Utolsó feltöltés: ${d.addon.updatedAt}</p>
          <dl class="kv"><dt>Táskák</dt><dd>${d.addon.bagItems} féle tárgy</dd>
          <dt>Bank</dt><dd>${d.addon.bankItems == null ? "még nincs (nyisd meg a bankot a játékban)" : `${d.addon.bankItems} féle tárgy`}</dd></dl>
          <p class="muted" style="margin-bottom:0">${d.addon.skills.map((s) => `${s.name} ${s.rank}/${s.max}`).join(" · ")}</p>`
      : html`<p class="muted">Még nem jött adat az addontól. Telepítés: <code>npm run addon:install</code>,
          a játékban <code>/wa save</code>, majd <code>npm run addon:upload</code>.</p>`}
  </section>
  <section><h2>Professionök</h2>${professionList(s.professions?.json as Obj | undefined)}</section>
  <section><h2>Talentek</h2>${talentList(s.specializations?.json as Obj | undefined)}</section>
  <section class="wide"><h2>Felszerelés</h2>${equipmentTable(s.equipment?.json as Obj | undefined)}</section>
  <section class="wide"><h2>Statok</h2>${statsGrid(s.statistics?.json as Obj | undefined)}</section>
  <section class="wide"><h2>Trainer skillek</h2>
    ${d.trainerSkills.length
      ? html`<table><thead><tr><th>Skill</th><th>Rank</th><th>Szint</th><th>Ár</th><th>Megvan</th></tr></thead><tbody>
          ${d.trainerSkills.map((t) => html`<tr><td>${t.name}</td><td>${t.rank ?? ""}</td>
            <td>${t.required_level ?? ""}</td><td>${formatMoney(t.cost_copper)}</td>
            <td>${t.learned ? "✓" : ""}</td></tr>`)}
        </tbody></table>`
      : html`<p class="muted">Még nincs rögzítve trainer skill.</p>`}
  </section>
  <section class="wide"><h2>Szinkron napló</h2>
    <table><thead><tr><th>Idő</th><th>Végpont</th><th>HTTP</th><th>Változott</th><th>Üzenet</th></tr></thead><tbody>
      ${d.log.map((l) => html`<tr class="${l.status === 200 ? "" : "err"}"><td>${l.at}</td><td>${l.kind}</td>
        <td>${l.status}</td><td>${l.changed ? "igen" : ""}</td><td class="muted">${l.message ?? ""}</td></tr>`)}
    </tbody></table>
  </section>
  <section class="wide"><h2>Nyers adatok</h2>
    ${rawBlock("Profil", s.profile)}${rawBlock("Felszerelés", s.equipment)}
    ${rawBlock("Professionök", s.professions)}${rawBlock("Talentek", s.specializations)}
    ${rawBlock("Statok", s.statistics)}
  </section>
</main>
</body>
</html>`;
}

export const CSS = `
:root{color-scheme:dark;--bg:#12141a;--panel:#1b1e27;--line:#2c313d;--text:#e6e8ee;--muted:#8d94a5;--accent:#f0c040}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 system-ui,sans-serif}
header{display:flex;justify-content:space-between;align-items:center;gap:16px;padding:16px;border-bottom:1px solid var(--line)}
h1{margin:0;font-size:22px;color:var(--accent)}
h2{margin:0 0 12px;font-size:16px}
main{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:16px;padding:16px;max-width:1200px;margin:0 auto}
section{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:16px;min-width:0;overflow-x:auto}
.wide{grid-column:1/-1}
.muted{color:var(--muted)}
.kv{display:grid;grid-template-columns:max-content 1fr;gap:4px 16px;margin:0}
.kv dt{color:var(--muted)} .kv dd{margin:0}
table{width:100%;border-collapse:collapse;font-size:14px}
th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--muted);font-weight:500}
tr.err td{color:#ff7b7b}
.prof{margin-bottom:12px}
.prof-head{display:flex;justify-content:space-between}
progress{width:100%;height:8px;accent-color:var(--accent)}
.stats{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:8px}
.stats div{display:flex;flex-direction:column;border:1px solid var(--line);border-radius:6px;padding:8px;text-transform:capitalize}
.gold{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-top:16px}
input,button{font:inherit;background:var(--bg);color:var(--text);border:1px solid var(--line);border-radius:6px;padding:6px 10px}
button{cursor:pointer;border-color:var(--accent);color:var(--accent)}
input{width:120px}
.tag{font-size:12px;border:1px solid var(--accent);color:var(--accent);border-radius:4px;padding:1px 6px;white-space:nowrap}
.err{color:#ff7b7b}
a{color:var(--accent)}
pre{overflow:auto;max-height:400px;font-size:12px;background:var(--bg);padding:12px;border-radius:6px}
summary{cursor:pointer}
`;
