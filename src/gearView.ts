import { html } from "hono/html";
import { QUALITY_BY_INDEX as Q, page } from "./layout";
import type { ResolvedBuff } from "./buffs";
import type { GearReport, Upgrade } from "./gear";


function item(u: Upgrade) {
  return html`<b style="color:${Q[u.quality] ?? "inherit"}">${u.name}</b>${u.warning ? html` <span class="tag tag-fix">${u.warning}</span>` : ""}`;
}
function gain(u: { gain: number; gainPct: number }) {
  return html`<b style="color:var(--good)">+${u.gain.toFixed(1)}</b> <span class="muted">${u.gainPct.toFixed(1)}%</span>`;
}

function buffPicker(buffs: ResolvedBuff[]) {
  const group = (g: ResolvedBuff["group"]) =>
    buffs
      .filter((b) => b.group === g)
      .map(
        (b) => html`<label class="buff ${b.effect ? "" : "off"}">
          <input type="checkbox" name="buff" value="${b.id}" ${b.selected ? "checked" : ""} ${b.effect ? "" : "disabled"}>
          <span><b>${b.name}</b><small>${b.summary} · ${b.source}</small></span>
        </label>`,
      );
  return html`<form method="post" action="/gear/buffs">
    <h3 style="margin-top:0">Csapat</h3><div class="buffs">${group("party")}</div>
    <h3>Fogyóeszközök</h3><div class="buffs">${group("consumable")}</div>
    <p style="margin:14px 0 0"><button>Újraszámol</button></p>
  </form>`;
}

export function gearPage(r: GearReport | null) {
  return page({
    title: "Felszerelés",
    active: "gear",
    body: html`
${r
  ? html`
  <section class="wide"><h2>A modell</h2>
    <div class="stats" style="margin-bottom:14px">
      <div><span>Modellezett DPS</span><b>${r.baseline.toFixed(1)}</b></div>
      ${r.baseline !== r.unbuffed ? html`<div><span>Buffok nélkül</span><b>${r.unbuffed.toFixed(1)}</b></div>` : ""}
      <div><span>Mért DPS</span><b>${r.measuredDps != null ? r.measuredDps.toFixed(1) : "–"}</b></div>
      <div><span>Attack power</span><b>${r.sheet.ap}</b></div>
      <div><span>Crit</span><b>${r.sheet.crit.toFixed(1)}%</b></div>
      <div><span>Hit</span><b>${r.sheet.hit}%</b></div>
    </div>
    <p class="muted">Egyszerűsített modell: a tárgyak egymáshoz viszonyított sorrendjére jó, az abszolút szám nem a valós DPS-ed.</p>
    ${r.params.notes.map((n) => html`<p class="muted">• ${n}</p>`)}
  </section>

  <section class="wide"><h2>Buffok <span class="muted">amikkel a számolás történik</span></h2>
    ${buffPicker(r.buffs)}
    <p class="muted" style="margin:12px 0 0">A csapatbuffok azt a rankot használják, amit egy veled azonos szintű játékos tud.
      Az értékek a Wowhead Forever tooltipekből származnak; azt nem ellenőriztem, hogy melyek adódnak össze egymással.</p>
  </section>

  <section class="wide"><h2>Melyik dungeonbe érdemes menni</h2>
    <table><thead><tr><th>Dungeon</th><th>Szint</th><th>DPS nyereség</th><th>Legjobb dropok</th></tr></thead><tbody>
    ${r.dungeons.map(
      (d) => html`<tr><td><b>${d.name}</b></td><td class="muted">${d.levels}</td><td>${gain(d)}</td>
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
`,
  });
}
