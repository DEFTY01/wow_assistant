import { html, raw } from "hono/html";
import type { CombatReport } from "./combat";
import { CSS } from "./view";

const f1 = (n: number) => n.toFixed(1);
const LEVEL_LABEL = { fix: "Javítandó", tip: "Tipp", info: "Adat" } as const;

export function combatPage(r: CombatReport | null) {
  return html`<!doctype html>
<html lang="hu">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Harcelemzés</title>
<style>${raw(CSS)}</style>
</head>
<body>
<header><h1><a href="/" style="color:inherit;text-decoration:none">←</a> Harcelemzés</h1></header>
<main>
${r
  ? html`
  <section class="wide">
    <div class="stats">
      <div><span class="muted">Mért DPS</span><b>${f1(r.dps)}</b></div>
      <div><span class="muted">Harcok</span><b>${r.fights}</b></div>
      <div><span class="muted">Harcidő</span><b>${Math.round(r.seconds / 60)} perc</b></div>
      <div><span class="muted">Energia plafonon</span><b>${r.energyCappedPct == null ? "–" : f1(r.energyCappedPct) + "%"}</b></div>
      <div><span class="muted">Auto-attack miss</span><b>${f1(r.white.miss)}%</b></div>
      <div><span class="muted">Auto-attack crit</span><b>${f1(r.white.crit)}%</b></div>
    </div>
  </section>

  <section class="wide"><h2>Javaslatok</h2>
    ${r.advice.map(
      (a) => html`<div class="prof"><div><span class="tag">${LEVEL_LABEL[a.level]}</span> <strong>${a.title}</strong></div>
        <p class="muted" style="margin:4px 0 0">${a.text}</p></div>`,
    )}
  </section>

  <section class="wide"><h2>Képességek</h2>
    <table><thead><tr><th>Képesség</th><th>Sebzés</th><th>Arány</th><th>Db</th><th>Átlag</th><th>Max</th>
      <th>Crit</th><th>Glancing</th><th>Miss</th><th>Dodge</th><th>Parry</th></tr></thead><tbody>
    ${r.abilities.map(
      (a) => html`<tr><td>${a.name}</td><td>${a.dmg}</td><td>${f1(a.share)}%</td><td>${a.n}</td>
        <td>${Math.round(a.avg)}</td><td>${a.max}</td><td>${a.crit}</td><td>${a.glance}</td>
        <td>${a.miss}</td><td>${a.dodge}</td><td>${a.parry}</td></tr>`,
    )}
    </tbody></table>
  </section>

  <section><h2>Finisherek</h2>
    ${r.finishers.length
      ? html`<table><thead><tr><th>Képesség</th><th>Használat</th><th>Átlag combo pont</th></tr></thead><tbody>
          ${r.finishers.map((f) => html`<tr><td>${f.name}</td><td>${f.casts}</td><td>${f1(f.avgCp)}</td></tr>`)}
        </tbody></table>`
      : html`<p class="muted">Nincs rögzített finisher.</p>`}
  </section>

  <section><h2>Buffok fedettsége</h2>
    ${r.auras.length
      ? html`<table><tbody>${r.auras.map((a) => html`<tr><td>${a.name}</td><td>${f1(a.uptimePct)}%</td></tr>`)}</tbody></table>`
      : html`<p class="muted">Nincs rögzített buff.</p>`}
  </section>

  <section><h2>Célpont szintje szerint</h2>
    <table><thead><tr><th>Szintkülönbség</th><th>Harcok</th><th>DPS</th><th>Auto-attack miss</th></tr></thead><tbody>
    ${r.byLevel.map((l) => html`<tr><td>${l.diff > 0 ? "+" : ""}${l.diff}</td><td>${l.fights}</td><td>${f1(l.dps)}</td><td>${f1(l.missPct)}%</td></tr>`)}
    </tbody></table>
  </section>

  <section><h2>Legutóbbi harcok</h2>
    <table><thead><tr><th>Célpont</th><th>Idő</th><th>DPS</th></tr></thead><tbody>
    ${r.recent.map((f) => html`<tr><td>${f.target}${f.targetLevel ? html` <span class="muted">(${f.targetLevel})</span>` : ""}</td>
      <td>${f1(f.dur)} mp</td><td>${f1(f.dps)}</td></tr>`)}
    </tbody></table>
  </section>`
  : html`<section class="wide"><p class="muted">Még nincs rögzített harc. A játékban kapcsold be a harcnaplót
      (<code>/wa log</code>), harcolj; a feltöltő script a játék naplófájljából olvassa ki a harcokat.</p></section>`}
</main>
</body>
</html>`;
}
