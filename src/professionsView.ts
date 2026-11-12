import { html, raw } from "hono/html";
import type { Route } from "./professions";
import { CSS, formatMoney } from "./view";

export function professionsPage(routes: Route[], meta: { house: string; pricesAt: string | null; target: number }) {
  return html`<!doctype html>
<html lang="hu">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Profession útvonal</title>
<style>${raw(CSS)}</style>
</head>
<body>
<header>
  <h1><a href="/" style="color:inherit;text-decoration:none">←</a> Profession útvonal</h1>
  <form method="post" action="/professions/refresh"><button>Árak frissítése</button></form>
</header>
<main>
  <section class="wide">
    <form method="get" class="gold" style="margin:0">
      <label>Cél skill: <input name="target" type="number" min="1" max="300" value="${meta.target}"></label>
      <button>Számol</button>
      <span class="muted">Aukciósház: #${meta.house} · árak: ${meta.pricesAt ?? "még nincs letöltve"}</span>
    </form>
  </section>
  ${routes.length
    ? routes.map((r) => routeSection(r))
    : html`<section class="wide"><p class="muted">Nincs számolható útvonal. Kell hozzá profession-pillanatkép és importált receptadat.</p></section>`}
</main>
</body>
</html>`;
}

function routeSection(r: Route) {
  const net = r.totalMats + r.totalTraining;
  return html`<section class="wide">
    <h2>${r.profession}: ${r.skill} → ${r.unreachableFrom ?? r.target}
      <span class="muted">(jelenlegi plafon: ${r.cap})</span></h2>
    <p><b>${formatMoney(Math.round(net))}</b> összesen
      <span class="muted">(alapanyag ${formatMoney(Math.round(r.totalMats))}, tanulás ${formatMoney(r.totalTraining)};
      a kész tárgyak vendornál kb. ${formatMoney(r.totalVendorBack)}-t érnek)</span></p>
    ${r.ownedValue > 0 ? html`<p>Ebből már megvan a táskádban/bankodban: <b>${formatMoney(Math.round(r.ownedValue))}</b> értékű alapanyag.</p>` : ""}
    ${r.notes.map((n) => html`<p class="muted">• ${n}</p>`)}
    ${r.unreachableFrom != null
      ? html`<p class="err">${r.unreachableFrom}-tól nincs beárazható recept, ami még skillt adna.</p>`
      : ""}
    ${r.steps.length
      ? html`<table>
          <thead><tr><th>Skill</th><th>Recept</th><th>Kb. darab</th><th>Alapanyag</th><th>Költség</th></tr></thead>
          <tbody>
            ${r.steps.map(
              (s) => html`<tr>
                <td>${s.from} → ${s.to}</td>
                <td>${s.recipe}${s.known ? "" : html` <span class="tag">megtanulni: ${formatMoney(s.trainingCost)}</span>`}</td>
                <td>${s.crafts}</td>
                <td class="muted">${s.reagents.map((g) => `${g.qty}× ${g.name}`).join(", ")}</td>
                <td>${formatMoney(Math.round(s.matsCost))}</td>
              </tr>`,
            )}
          </tbody>
        </table>
        <h2 style="margin-top:16px">Bevásárlólista</h2>
        <table>
          <thead><tr><th>Tárgy</th><th>Darab</th><th>Megvan</th><th>Egységár</th><th>Forrás</th><th>Összesen</th></tr></thead>
          <tbody>
            ${r.shopping.map(
              (g) => html`<tr><td>${g.name}</td><td>${g.qty}</td><td>${g.owned || ""}</td><td>${formatMoney(g.unit)}</td>
                <td>${g.source}</td><td>${formatMoney(Math.round(g.total))}</td></tr>`,
            )}
          </tbody>
        </table>`
      : ""}
  </section>`;
}
