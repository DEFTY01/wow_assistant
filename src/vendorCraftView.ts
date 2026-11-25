import { html } from "hono/html";
import { money, page } from "./layout";
import { PROFESSIONS, type VendorCraft, type VendorCraftFilter, type VendorCraftReport } from "./vendorCraft";

const SHOW = 150;

export function vendorCraftPage(rep: VendorCraftReport, f: VendorCraftFilter) {
  const when = rep.pricesAt ? new Date(rep.pricesAt).toLocaleString("hu-HU", { timeZone: "Europe/Budapest" }) : "még nincs letöltve";
  const profOpt = (v: string, label: string) => html`<option value="${v}" ${String(f.profession) === v ? "selected" : ""}>${label}</option>`;
  return page({
    title: "Vendorra gyártás",
    active: "vendor",
    toolbar: html`<form method="post" action="/professions/refresh"><button>Árak frissítése</button></form>`,
    body: html`
  <section class="wide">
    <h2>Mit érdemes legyártani, hogy vendornak eladd</h2>
    <p class="muted" style="margin-top:0">Azok a receptek, amelyeknél a vendor többet fizet a kész tárgyért, mint amennyibe az alapanyag
      kerül, ha az aukciósházból veszed meg (vagy kereskedőtől, ha ott olcsóbb). Árak: ${when}.</p>
    <form method="get" class="gold" style="margin:0;flex-wrap:wrap;gap:10px">
      <label>Szakma: <select name="prof">
        ${profOpt("mine", "A karakterem szakmái")}
        ${profOpt("all", "Mind")}
        ${Object.entries(PROFESSIONS).map(([id, n]) => profOpt(id, n))}
      </select></label>
      <label>Skill: <select name="skill">
        <option value="current" ${f.skill === "current" ? "selected" : ""}>Jelenlegi skillemig</option>
        <option value="max" ${f.skill === "max" ? "selected" : ""}>Minden recept (300-ig)</option>
      </select></label>
      <label><input type="checkbox" name="known" value="1" ${f.knownOnly ? "checked" : ""}> csak amit már ismerek</label>
      <button>Szűrés</button>
    </form>
    ${rep.mine.length
      ? html`<p class="muted" style="margin:8px 0 0">Szakmáid: ${rep.mine.map((m) => `${m.name} ${m.skill}`).join(" · ")}</p>`
      : html`<p class="muted" style="margin:8px 0 0">A szakmáidat még nem látom (Blizzard profil-szinkron kell hozzá).</p>`}
  </section>
  <section class="wide">
    ${rep.rows.length
      ? html`<table>
          <thead><tr><th>Recept</th><th>Termék · vendorár</th><th class="num">1. darab</th><th class="num">Átlagáron</th>
            <th class="num">Legjobb adag</th><th class="num">Befektetés</th><th class="num">Haszon</th></tr></thead>
          <tbody>${rep.rows.slice(0, SHOW).map(row)}</tbody>
        </table>
        ${rep.rows.length > SHOW ? html`<p class="muted">… és még ${rep.rows.length - SHOW} recept.</p>` : ""}`
      : html`<p class="muted">Ezzel a szűréssel most egy recept sem hoz hasznot vendornál.</p>`}
    <p class="muted" style="margin:12px 0 0">
      <b>1. darab</b>: a haszon az első gyártáson, a legolcsóbb kint lévő alapanyagokkal.
      <b>Átlagáron</b>: egy gyártás haszna a piaci átlagárral (a medián háromszorosánál drágább hirdetések nélkül).
      <b>Legjobb adag</b>: hány darabot éri meg legyártani. A számítás hirdetésről hirdetésre veszi az alapanyagot, a legolcsóbbtól
      felfelé, és ott áll meg, ahol a következő gyártás már veszteséges lenne. A nem osztható köteget egészben számolja.
      Cooldownos receptnél (transmute, Mooncloth) az adag egyetlen gyártás. A „+” jel azt mutatja, hogy a számítás elérte az
      1000 gyártást vagy a letárolt hirdetések végét, tehát akár többet is megérhet.
      A vendorárat a Blizzard tárgyadatbázisából veszem, és összevetem a Wowhead Forever adatával. Ha eltérnek, a kisebbel számolok,
      és jelzem. Kereskedőnél kapott hírnév-kedvezményt nem számolok, ezért az olcsóbb is lehet.
      ${rep.unpriced ? html`${rep.unpriced} recepthez most nincs elég alapanyag az aukciósházban, ezek kimaradtak.` : ""}
    </p>
  </section>`,
  });
}

function row(r: VendorCraft) {
  const makes = r.makesMin === r.makesMax ? (r.makesMin > 1 ? `${r.makesMin} db` : "") : `${r.makesMin}–${r.makesMax} db`;
  const check =
    r.vendorCheck === "mismatch"
      ? html` <span class="tag warn" title="A másik forrás szerint ${r.vendorOther}">eltérő vendorár</span>`
      : r.vendorCheck === "both"
        ? ""
        : html` <span class="muted">(${r.vendorCheck === "blizzard" ? "csak Blizzard" : "csak Wowhead"})</span>`;
  return html`<tr>
    <td><b>${r.recipe}</b>
      <div class="act-detail">${r.profession} ${r.orange} · ${r.status === "known" ? html`<span class="gain">ismered</span>` : r.learnText}</div>
      ${r.shopping.length
        ? html`<details><summary class="muted">bevásárlólista</summary>${shopping(r)}</details>`
        : ""}</td>
    <td>${r.product} ${makes ? html`<span class="muted">×${makes}</span>` : ""}
      <div class="act-detail">${money(r.vendorEach)} / db${check}</div></td>
    <td class="num">${signedMoney(r.firstProfit)}<div class="act-detail">költség ${money(r.firstCost)}</div></td>
    <td class="num">${r.avgProfit == null ? html`<span class="muted">–</span>` : signedMoney(r.avgProfit)}
      <div class="act-detail">${r.avgCost == null ? "" : html`költség ${money(r.avgCost)}`}</div></td>
    <td class="num">${r.crafts ? html`<b>${r.crafts}${r.capped ? "+" : ""}×</b>` : html`<span class="muted">–</span>`}
      ${r.cooldown ? html`<div class="act-detail">cooldown: ${duration(r.cooldown)}</div>` : ""}</td>
    <td class="num">${r.crafts ? money(r.cost) : ""}<div class="act-detail">${r.crafts ? html`vendor ad: ${money(r.income)}` : ""}</div></td>
    <td class="num">${r.crafts ? html`<b class="gain">${money(r.profit)}</b><div class="act-detail">${Math.round(r.roiPct)}%</div>` : html`<span class="muted">–</span>`}</td>
  </tr>`;
}

function shopping(r: VendorCraft) {
  return html`<table style="margin:6px 0">
    <thead><tr><th>Alapanyag</th><th class="num">Kell</th><th class="num">AH-ról</th><th class="num">Max. egységár</th>
      <th class="num">Kereskedőtől</th><th class="num">Legolcsóbb / átlag</th></tr></thead>
    <tbody>${r.shopping.map(
      (s) => html`<tr><td>${s.name}</td><td class="num">${s.units}</td>
        <td class="num">${s.ahUnits ? html`${s.ahUnits} db · ${money(s.ahCost)}` : ""}${s.leftover ? html`<div class="act-detail">${s.leftover} marad</div>` : ""}</td>
        <td class="num">${s.ahMaxUnit == null ? "" : money(s.ahMaxUnit)}</td>
        <td class="num">${s.vendorUnits ? html`${s.vendorUnits} db · ${money(s.vendorCost)}` : ""}</td>
        <td class="num muted">${money(s.minPrice)} / ${money(s.avgPrice)}</td></tr>`,
    )}</tbody>
  </table>`;
}

function duration(sec: number) {
  if (sec < 3600) return `${Math.round(sec / 60)} perc`;
  if (sec < 86400) return `${Math.round(sec / 3600)} óra`;
  return `${(sec / 86400).toFixed(1).replace(".", ",")} nap`;
}

function signedMoney(v: number) {
  return v >= 0 ? html`<span class="gain">+${money(v)}</span>` : html`<span class="err">−${money(-v)}</span>`;
}
