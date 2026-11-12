import { html, raw } from "hono/html";
import type { GearReport, Upgrade } from "./gear";
import { CSS } from "./view";

const Q = ["#9d9d9d", "#e8e8e8", "#1eff00", "#3d9eff", "#c26bff", "#ff8000"];

function item(u: Upgrade) {
  return html`<span style="color:${Q[u.quality] ?? "inherit"}">${u.name}</span>${u.warning ? html` <span class="tag">${u.warning}</span>` : ""}`;
}
function gain(u: { gain: number; gainPct: number }) {
  return html`<b>+${u.gain.toFixed(1)}</b> <span class="muted">(${u.gainPct.toFixed(1)}%)</span>`;
}

export function gearPage(r: GearReport | null) {
  return html`<!doctype html>
<html lang="hu">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Gear és dungeonök</title>
<style>${raw(CSS)}</style>
</head>
<body>
<header><h1><a href="/" style="color:inherit;text-decoration:none">←</a> Gear és dungeonök</h1></header>
<main>
${r
  ? html`
  <section class="wide">
    <p>Modellezett DPS most: <b>${r.baseline.toFixed(1)}</b>${r.measuredDps != null ? html` · mért DPS a rögzített harcokban: <b>${r.measuredDps.toFixed(1)}</b>` : ""}
      <span class="muted">(${r.sheet.ap} AP, ${r.sheet.crit.toFixed(1)}% crit, ${r.sheet.hit}% hit)</span></p>
    <p class="muted">Egyszerűsített modell: a tárgyak egymáshoz viszonyított sorrendjére jó, az abszolút szám nem a valós DPS-ed.</p>
    ${r.params.notes.map((n) => html`<p class="muted">• ${n}</p>`)}
  </section>

  <section class="wide"><h2>Melyik dungeonbe érdemes menni</h2>
    <table><thead><tr><th>Dungeon</th><th>Szint</th><th>Össz. nyereség</th><th>Legjobb dropok</th></tr></thead><tbody>
    ${r.dungeons.map(
      (d) => html`<tr><td>${d.name}</td><td>${d.levels}</td><td>${gain(d)}</td>
        <td>${d.upgrades.slice(0, 4).map((u, i) => html`${i ? ", " : ""}${item(u)} <span class="muted">(${u.boss ?? "trash drop"}, +${u.gain.toFixed(1)})</span>`)}</td></tr>`,
    )}
    </tbody></table>
  </section>

  <section class="wide"><h2>Legjobb csere slotonként</h2>
    <table><thead><tr><th>Slot</th><th>Most</th><th>Tárgy</th><th>Statok</th><th>Honnan</th><th>DPS</th></tr></thead><tbody>
    ${r.bySlot.map((s) =>
      s.best.map(
        (u, i) => html`<tr><td>${i ? "" : s.slot}</td><td class="muted">${i ? "" : (s.current ?? "üres")}</td>
          <td>${item(u)}</td><td class="muted">${u.detail}</td>
          <td>${u.dungeon} <span class="muted">· ${u.boss ?? "trash drop"}</span></td><td>${gain(u)}</td></tr>`,
      ),
    )}
    </tbody></table>
  </section>

  ${r.later.length
    ? html`<section class="wide"><h2>Hamarosan felvehető</h2>
      <table><thead><tr><th>Szint</th><th>Tárgy</th><th>Slot</th><th>Statok</th><th>Honnan</th><th>DPS</th></tr></thead><tbody>
      ${r.later.map(
        (u) => html`<tr><td>${u.reqLevel}</td><td>${item(u)}</td><td>${u.slot}</td><td class="muted">${u.detail}</td>
          <td>${u.dungeon} <span class="muted">· ${u.boss ?? "trash drop"}</span></td><td>${gain(u)}</td></tr>`,
      )}
      </tbody></table></section>`
    : ""}`
  : html`<section class="wide"><p class="muted">Nincs elég adat: kell profil-, stat- és felszerelés-pillanatkép.</p></section>`}
</main>
</body>
</html>`;
}
