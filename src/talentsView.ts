import { html } from "hono/html";
import { type Html, page } from "./layout";
import type { BuildView, RotationResult, TalentReport, TreeView } from "./talents";

const f1 = (n: number) => n.toFixed(1);
const signed = (n: number) => `${n >= 0 ? "+" : ""}${f1(n)}%`;
const PART_HU: Record<string, string> = { ss: "Sinister Strike", hemo: "Hemorrhage", backstab: "Backstab", mutilate: "Mutilate", pvp: "PvP build" };

/** `reasons`: show each talent's note as a line of text (PvP) instead of a footnote star (damage builds). */
function trees(list: TreeView[], reasons = false): Html {
  return html`<div class="trees">${list.map(
    (t) => html`<div class="tree ${t.points ? "" : "zero"}">
      <header><b>${t.name}</b><span>${t.points}</span></header>
      <ul>${t.talents.map((x) => {
        const diff = x.rank - x.was;
        return html`<li title="${x.note ?? ""}"><span>${x.name}${x.note && !reasons ? html`<sup>*</sup>` : ""}
            ${reasons && x.note && x.rank ? html`<small class="why">${x.note}</small>` : ""}</span>
          <b class="${x.rank ? "" : "gone"}">${x.rank}/${x.max}${diff ? html`<small class="${diff > 0 ? "up" : "down"}">${diff > 0 ? "+" : ""}${diff}</small>` : ""}</b></li>`;
      })}</ul>
    </div>`,
  )}</div>`;
}

const cell = (b: BuildView | null, blocked: string | null) =>
  b
    ? html`<b>${b.split}</b> <span class="${b.gainPct >= 0 ? "gain" : "err"}">${signed(b.gainPct)}</span>`
    : html`<span class="muted">${blocked ?? "–"}</span>`;

function rotationDetails(r: RotationResult): Html {
  if (!r.now && !r.final) return html``;
  return html`<details><summary>${r.label}: a buildek részletesen</summary>
    ${r.now ? html`<h3>Most (${r.now.split}, ${signed(r.now.gainPct)})</h3>${trees(r.now.trees)}` : ""}
    ${r.final ? html`<h3>60-as szinten (${r.final.split}, ${signed(r.final.gainPct)})</h3>${trees(r.final.trees)}` : ""}
  </details>`;
}

export function talentsPage(r: TalentReport | null, info: { rogue: boolean; hasData: boolean }): Html {
  if (!r) {
    return page({
      title: "Talentek",
      active: "talents",
      body: html`<section class="wide"><h2>Talentek</h2>
        ${!info.rogue
          ? html`<p>A talent-optimalizáló egyelőre csak <b>rogue</b> karakterre készült el.</p>`
          : !info.hasData
            ? html`<p class="muted">A talentfa adatai még nincsenek importálva.</p>`
            : html`<p class="muted">Még nincs elég karakteradat a számoláshoz.</p>`}
      </section>`,
    });
  }
  const free = r.points - r.spent;
  const bestNow = r.rotations.filter((x) => x.now).sort((a, b) => b.now!.gainPct - a.now!.gainPct)[0];
  const bestFinal = r.rotations.filter((x) => x.final).sort((a, b) => b.final!.gainPct - a.final!.gainPct)[0];
  const nowGain = bestNow?.now?.gainPct ?? 0;
  const respecWorth = nowGain >= 3;
  return page({
    title: "Talentek",
    active: "talents",
    body: html`
  ${r.pending.length
    ? html`<div class="notice"><p>Még számolom: ${r.pending.map((p) => PART_HU[p] ?? p).join(", ")}.
        Az oldal magától frissül, amíg minden el nem készül.</p></div>
      <script>setTimeout(() => location.reload(), 7000);</script>`
    : ""}

  <div class="frame verdict">
    <div class="verdict-now"><span>A mostani builded</span><b>${r.current.split}</b>
      <small>${f1(r.current.dps)} modellezett DPS · ${r.spent} pont${free > 0 ? html` · <em>${free} elköltetlen</em>` : ""}</small></div>
    <div class="verdict-arrow" aria-hidden="true"></div>
    <div class="verdict-then"><span>A legjobb ugyanennyi pontból</span><b>${bestNow?.now?.split ?? "–"}</b>
      <small>${nowGain > 0.05 ? html`<em>${signed(nowGain)} DPS</em> · ${bestNow.label}` : "a mostani a legjobb"}</small></div>
    <div class="purse"><span>Respec</span>
      <b>${respecWorth ? "megéri" : "nem sürgős"}</b>
      <small>${respecWorth ? "A mostani pontjaid átrendezése érezhetően többet ad." : "A különbség kicsi; folytasd a lenti sorrendben."}</small>
    </div>
  </div>

  <section class="wide"><h2>Rotációk összehasonlítása <span class="muted">a mostani buildedhez és fegyvereidhez mérve</span></h2>
    <table class="wrap"><thead><tr><th>Rotáció</th><th>A legjobb build most</th><th>A legjobb build 60-on</th></tr></thead><tbody>
    ${r.rotations.map(
      (x) => html`<tr><td><b>${x.label}</b>${x === bestFinal ? html` <span class="tag tag-good">60-on a legjobb</span>` : ""}
          <div class="act-detail">${x.note}</div></td>
        <td>${cell(x.now, x.blocked)}</td><td>${cell(x.final, x.blocked)}</td></tr>`,
    )}
    </tbody></table>
    ${r.rotations.map(rotationDetails)}
  </section>

  <section><h2>A következő pontjaid <span class="muted">Sinister Strike, respec nélkül</span></h2>
    ${r.steps.length
      ? html`<ol class="road">${r.steps.map(
          (s) => html`<li><span class="road-lvl">${s.level}</span>
            <div><b>${s.talent}</b> <span class="muted">${s.rank}/${s.max} · ${s.tree}</span>
              <b class="gain" style="float:right">${signed(s.gainPct)}</b>
              <div class="act-detail">${s.why}</div></div></li>`,
        )}</ol>
        <p class="muted" style="margin:10px 0 0">A százalék az addig összegyűlt nyereség a mostani buildedhez képest.
          Így folytatva 60-as szinten ${r.continued.split} lesz a builded (${signed(r.continued.gainPct)}).</p>`
      : html`<p class="muted">Nincs több elkölthető pont.</p>`}
  </section>

  <section><h2>PvP build <span class="muted">ítélet alapján, nem számolt</span></h2>
    ${r.pvp
      ? html`<p class="muted">A PvP nem a tartós sebzésről szól, hanem a burstről, a kontrollról és a menekülésről, ezért ezt nem a
          sebzésmodell rakja össze: minden talent kapott egy pontszámot aszerint, mennyit ér párbajban és battlegroundon,
          és a kereső a fa szabályai szerint a legtöbb pontot gyűjti össze. Az indok minden talent alatt ott van.</p>
        <h3>60-as szinten: ${r.pvp.finalSplit}</h3>${trees(r.pvp.final, true)}
        <details><summary>A mostani ${r.points} pontodból: ${r.pvp.nowSplit}</summary>${trees(r.pvp.now, true)}</details>`
      : html`<p class="muted">Még számolom.</p>`}
  </section>

  <section><h2>A számolásról</h2>
    ${r.notes.map((n) => html`<p class="muted">• ${n}</p>`)}
  </section>

  <section><h2>Amit a modell nem tud értékelni</h2>
    <p class="muted">Ezek hatnak a sebzésre, de helyzettől vagy külön képességtől függenek, ezért a kereső sosem választja őket
      az értékük miatt, legfeljebb tölteléknek. A sebzés-buildekben csillag jelöli őket.</p>
    <table><tbody>${r.unmodelled.map(
      (u) => html`<tr><td><b>${u.name}</b><div class="act-detail">${u.tree}</div></td><td class="muted">${u.why}</td></tr>`,
    )}</tbody></table>
  </section>`,
  });
}
