import { html } from "hono/html";
import { type Html, QUALITY, money, page } from "./layout";
import type { Option, Plan, SkillAdvice } from "./plan";

const SOURCE: Record<Option["source"], [string, string]> = {
  ah: ["Aukció", "src-ah"],
  craft: ["Craft", "src-craft"],
  owned: ["Megvan", "src-owned"],
  trainer: ["Trainer", "src-trainer"],
};
const TIER: Record<SkillAdvice["tier"], [string, string]> = {
  dps: ["DPS", "tag-good"],
  core: ["Alap", ""],
  situational: ["Helyzetfüggő", "tag-info"],
  skip: ["Kihagyható", "tag-dim"],
};
const f1 = (n: number) => n.toFixed(1);

function row(o: Option, showCost = true): Html {
  const [label, cls] = SOURCE[o.source];
  const perGold = o.cost > 0 && o.gain > 0 ? o.gain / (o.cost / 10000) : null;
  return html`<li class="act">
    <span class="src ${cls}">${label}</span>
    <div class="act-main">
      <div class="act-title" style="${o.quality ? `color:${QUALITY[o.quality] ?? "inherit"}` : ""}">${o.title}
        ${o.warning ? html`<span class="tag tag-fix">${o.warning}</span>` : ""}</div>
      <div class="act-detail">${o.detail}</div>
    </div>
    <div class="act-num">
      ${o.gain > 0
        ? html`<b class="gain">+${o.gain.toFixed(2)} DPS${o.estimated ? html`<sup title="Becsült érték">~</sup>` : ""}</b>`
        : html`<b class="muted">alap skill</b>`}
      ${showCost ? html`<span>${o.cost > 0 ? money(o.cost) : "ingyen"}</span>` : ""}
      ${perGold != null ? html`<small>${f1(perGold)} DPS / gold</small>` : ""}
    </div>
  </li>`;
}

export function planPage(p: Plan | null): Html {
  if (!p) {
    return page({
      title: "Haditerv",
      active: "plan",
      body: html`<section class="wide"><h2>Haditerv</h2><p class="muted">Még nincs karakteradat. Nyomd meg a Szinkron gombot a Karakter oldalon.</p></section>`,
    });
  }
  const up = p.projected - p.baseline;
  const pct = p.gold ? Math.min(100, (p.spent / p.gold) * 100) : 0;
  return page({
    title: "Haditerv",
    active: "plan",
    toolbar: html`<form method="post" action="/plan/refresh"><button>Frissítés</button></form>`,
    body: html`
  ${p.warnings.length
    ? html`<div class="notice">${p.warnings.map((w) => html`<p>${w}</p>`)}</div>`
    : ""}

  <div class="frame verdict">
    <div class="verdict-now"><span>Most</span><b>${f1(p.baseline)}</b><small>modellezett DPS${p.measuredDps != null ? html` · mért ${f1(p.measuredDps)}` : ""}</small></div>
    <div class="verdict-arrow" aria-hidden="true"></div>
    <div class="verdict-then"><span>A terv után</span><b>${f1(p.projected)}</b>
      <small>${up > 0.05 ? html`<em>+${f1(up)} DPS · +${f1((up / p.baseline) * 100)}%</em>` : "nincs teendő"}</small></div>
    <div class="purse">
      <span>Arany</span>
      <b>${money(p.gold)}</b>
      ${p.gold != null
        ? html`<div class="bar-track"><div class="bar-fill capped" style="width:${pct}%"></div></div>
            <small>elköltve ${money(p.spent)} · marad ${money(p.left)}</small>`
        : html`<small>nincs adat</small>`}
    </div>
  </div>

  <section class="wide"><h2>Erre költsd a goldod <span class="muted">a legtöbb DPS a mostani pénzedből</span></h2>
    ${p.buy.length
      ? html`<ul class="acts">${p.buy.map((o) => row(o))}</ul>`
      : html`<p class="muted">${p.gold == null ? "Gold-adat nélkül nincs vásárlási terv." : "A mostani goldodból nincs megvehető fejlesztés."}</p>`}
  </section>

  <section><h2>Ingyen van</h2>
    ${p.free.length || p.combat.length
      ? html`<ul class="acts">${p.free.map((o) => row(o, false))}</ul>
          ${p.combat.length
            ? html`<div class="advice" style="margin-top:${p.free.length ? 12 : 0}px">${p.combat.map(
                (a) => html`<div class="${a.level}"><span class="tag tag-${a.level}">${a.level === "fix" ? "Rotáció" : "Tipp"}</span><strong>${a.title}</strong>
                  <p>${a.text}</p></div>`,
              )}</div>`
            : ""}`
      : html`<p class="muted">Nincs ingyenes fejlesztés: a táskádban és a bankodban nincs jobb tárgy, és a rotációd rendben van.</p>`}
  </section>

  <section><h2>Ha lesz több goldod</h2>
    ${p.wishlist.length
      ? html`<ul class="acts">${p.wishlist.map((o) => row(o))}</ul>`
      : html`<p class="muted">Minden megvehető fejlesztés belefért a keretbe.</p>`}
  </section>

  <section><h2>Trainer <span class="muted">mit tanulj meg most</span></h2>
    ${p.skills.length
      ? html`<table><tbody>${p.skills.map((s) => {
          const [label, cls] = TIER[s.tier];
          return html`<tr class="${s.tier === "skip" ? "dim" : ""}"><td><span class="tag ${cls}">${label}</span></td>
            <td><b>${s.name}</b><div class="act-detail">${s.why}</div></td><td class="num">${money(s.cost)}</td></tr>`;
        })}</tbody></table>`
      : html`<p class="muted">Nincs megtanulható skill, vagy még nincs trainer-adat.</p>`}
  </section>

  <section><h2>Hova menj <span class="muted">a legtöbbet érő dungeonök</span></h2>
    ${p.farm.length
      ? html`<table><tbody>${p.farm.map(
          (d) => html`<tr><td><b>${d.name}</b><div class="act-detail">${d.levels} szint</div></td>
            <td>${d.upgrades.slice(0, 3).map((u) => html`<div>${u.name} <span class="muted">${u.boss ?? "trash"}</span></div>`)}</td>
            <td class="num"><b class="gain">+${f1(d.gain)}</b></td></tr>`,
        )}</tbody></table>
        <p style="margin:12px 0 0"><a href="/gear">Minden slot és dungeon →</a></p>`
      : html`<p class="muted">Nincs dungeon-drop, ami javítana.</p>`}
  </section>

  <section><h2>Mesterségek <span class="muted">a következő lépés</span></h2>
    ${p.professions.length
      ? html`${p.professions.map((r) => {
          const w = r.cap ? Math.min(100, (r.skill / r.cap) * 100) : 0;
          return html`<div class="prof">
            <div class="prof-head"><strong>${r.name}</strong><span class="muted">${r.next ? money(r.cost) : ""}</span></div>
            <div class="bar-track"><div class="bar-fill ${r.cap - r.skill <= 15 ? "capped" : ""}" style="width:${w}%"></div>
              <div class="bar-label">${r.skill} / ${r.cap}</div></div>
            <div class="act-detail" style="margin-top:4px">${r.next ?? "nincs olcsó lépés"}${r.note ? html` · <span class="warn">${r.note}</span>` : ""}</div>
          </div>`;
        })}
        <p style="margin:12px 0 0"><a href="/professions">Teljes útvonal és bevásárlólista →</a></p>`
      : html`<p class="muted">Nincs mesterség-adat.</p>`}
  </section>

  <section><h2>A következő szintek <span class="muted">mire gyűjts</span></h2>
    ${p.roadmap.length
      ? html`<ol class="road">${p.roadmap.map(
          (r) => html`<li><span class="road-lvl">${r.level}</span>
            <div>${r.skills.length ? html`<div><b>${r.skills.join(", ")}</b> <span class="muted">a trainernél:</span> ${money(r.skillCost)}</div>` : ""}
              ${r.gear.map((g) => html`<div><span style="color:${QUALITY[g.quality ?? ""] ?? "inherit"}">${g.title}</span>
                <span class="muted">${g.where.toLowerCase()},</span> ${money(g.cost)} <b class="gain">+${f1(g.gain)}</b></div>`)}
            </div></li>`,
        )}</ol>`
      : html`<p class="muted">A következő szintekre nincs ismert tennivaló.</p>`}
  </section>`,
  });
}
