import { html } from "hono/html";
import { money, page } from "./layout";
import type { Route } from "./professions";

export function professionsPage(routes: Route[], meta: { house: string; pricesAt: string | null; target: number }) {
  return page({
    title: "Mesterségek",
    active: "prof",
    toolbar: html`<form method="post" action="/professions/refresh"><button>Árak frissítése</button></form>`,
    body: html`
  <section class="wide">
    <form method="get" class="gold" style="margin:0">
      <label>Cél skill: <input name="target" type="number" min="1" max="300" value="${meta.target}"></label>
      <button>Számol</button>
      <span class="muted">Aukciósház #${meta.house} · árak: ${meta.pricesAt ? new Date(meta.pricesAt).toLocaleString("hu-HU", { timeZone: "Europe/Budapest" }) : "még nincs letöltve"}</span>
    </form>
  </section>
  ${routes.length
    ? routes.map((r) => routeSection(r))
    : html`<section class="wide"><p class="muted">Nincs számolható útvonal. Kell hozzá profession-pillanatkép és importált receptadat.</p></section>`}
`,
  });
}

function routeSection(r: Route) {
  const net = r.totalMats + r.totalTraining;
  return html`<section class="wide">
    <h2>${r.profession}: ${r.skill} → ${r.unreachableFrom ?? r.target}
      <span class="muted">(jelenlegi plafon: ${r.cap})</span></h2>
    <p><b>${money(Math.round(net))}</b> összesen
      <span class="muted">(alapanyag ${money(Math.round(r.totalMats))}, tanulás ${money(r.totalTraining)};
      a kész tárgyak vendornál kb. ${money(r.totalVendorBack)}-t érnek)</span></p>
    ${r.ownedValue > 0 ? html`<p>Ebből már megvan a táskádban/bankodban: <b>${money(Math.round(r.ownedValue))}</b> értékű alapanyag.</p>` : ""}
    ${r.notes.map((n) => html`<p class="muted">• ${n}</p>`)}
    ${r.unreachableFrom != null
      ? html`<p class="err">${r.unreachableFrom}-tól nincs beárazható recept, ami még skillt adna.</p>`
      : ""}
    ${r.steps.length
      ? html`<table>
          <thead><tr><th>Skill</th><th>Recept</th><th class="num">Kb. darab</th><th>Alapanyag</th><th class="num">Költség</th></tr></thead>
          <tbody>
            ${r.steps.map(
              (s) => html`<tr>
                <td>${s.from} → ${s.to}</td>
                <td>${s.recipe}${s.known ? "" : html` <span class="tag">megtanulni: ${money(s.trainingCost)}</span>`}</td>
                <td class="num">${s.crafts}</td>
                <td class="muted">${s.reagents.map((g) => `${g.qty}× ${g.name}`).join(", ")}</td>
                <td class="num">${money(Math.round(s.matsCost))}</td>
              </tr>`,
            )}
          </tbody>
        </table>
        <h3 style="margin-top:20px">Bevásárlólista</h3>
        <table>
          <thead><tr><th>Tárgy</th><th class="num">Darab</th><th class="num">Megvan</th><th class="num">Egységár</th><th>Forrás</th><th class="num">Összesen</th></tr></thead>
          <tbody>
            ${r.shopping.map(
              (g) => html`<tr><td>${g.name}</td><td class="num">${g.qty}</td><td class="num">${g.owned || ""}</td><td class="num">${money(g.unit)}</td>
                <td class="muted">${g.source}</td><td class="num">${money(Math.round(g.total))}</td></tr>`,
            )}
          </tbody>
        </table>`
      : ""}
  </section>`;
}
