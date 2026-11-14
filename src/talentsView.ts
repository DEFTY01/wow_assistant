import { html } from "hono/html";
import { type Html, page } from "./layout";
import type { TalentReport, TreeView } from "./talents";

const f1 = (n: number) => n.toFixed(1);
const signed = (n: number) => `${n >= 0 ? "+" : ""}${f1(n)}%`;

function trees(list: TreeView[]): Html {
  return html`<div class="trees">${list.map(
    (t) => html`<div class="tree ${t.points ? "" : "zero"}">
      <header><b>${t.name}</b><span>${t.points}</span></header>
      <ul>${t.talents.map((x) => {
        const diff = x.rank - x.was;
        return html`<li title="${x.note ?? ""}"><span>${x.name}${x.note ? html`<sup title="${x.note}">*</sup>` : ""}</span>
          <b class="${x.rank ? "" : "gone"}">${x.rank}/${x.max}${diff ? html`<small class="${diff > 0 ? "up" : "down"}">${diff > 0 ? "+" : ""}${diff}</small>` : ""}</b></li>`;
      })}</ul>
    </div>`,
  )}</div>`;
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
  const respecWorth = r.ideal.gainPct >= 3;
  const finalBetter = r.final.gainPct - r.continued.gainPct;
  return page({
    title: "Talentek",
    active: "talents",
    body: html`
  <div class="frame verdict">
    <div class="verdict-now"><span>A mostani builded</span><b>${r.current.split}</b>
      <small>${f1(r.current.dps)} modellezett DPS · ${r.spent} pont${free > 0 ? html` · <em>${free} elköltetlen</em>` : ""}</small></div>
    <div class="verdict-arrow" aria-hidden="true"></div>
    <div class="verdict-then"><span>A legjobb ugyanennyi pontból</span><b>${r.ideal.split}</b>
      <small>${r.ideal.gainPct > 0.05 ? html`<em>${signed(r.ideal.gainPct)} DPS</em>` : "a mostani a legjobb"}</small></div>
    <div class="purse"><span>Respec</span>
      <b>${respecWorth ? "megéri" : "nem sürgős"}</b>
      <small>${respecWorth
        ? "A mostani pontjaid átrendezése érezhetően többet ad."
        : "A különbség kicsi; folytasd a lenti sorrendben."}</small>
    </div>
  </div>

  <section><h2>A következő pontjaid <span class="muted">respec nélkül, sorrendben</span></h2>
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

  <section><h2>A legjobb build most <span class="muted">${r.points} pontból, respec után</span></h2>
    ${trees(r.ideal.trees)}
    <p class="muted" style="margin:10px 0 0">A kis szám azt mutatja, mennyivel tér el a mostanitól.</p>
  </section>

  <section class="wide"><h2>A legjobb build 60-as szinten <span class="muted">${r.final.split} · ${signed(r.final.gainPct)} a mostanihoz képest</span></h2>
    ${trees(r.final.trees)}
    ${finalBetter > 2
      ? html`<p style="margin:12px 0 0">Ez <b>${f1(finalBetter)} százalékponttal</b> jobb annál, ahová respec nélkül jutnál:
          egy respec valamikor útközben megéri.</p>`
      : html`<p class="muted" style="margin:12px 0 0">Respec nélkül folytatva is majdnem ugyanide jutsz.</p>`}
  </section>

  <section><h2>A számolásról</h2>
    ${r.notes.map((n) => html`<p class="muted">• ${n}</p>`)}
  </section>

  <section><h2>Amit a modell nem tud értékelni</h2>
    <p class="muted">Ezek hatnak a sebzésre, de más rotációt vagy helyzetet igényelnek, ezért a kereső sosem választja őket
      az értékük miatt, legfeljebb tölteléknek. A buildekben csillag jelöli őket.</p>
    <table><tbody>${r.unmodelled.map(
      (u) => html`<tr><td><b>${u.name}</b><div class="act-detail">${u.tree}</div></td><td class="muted">${u.why}</td></tr>`,
    )}</tbody></table>
  </section>`,
  });
}
