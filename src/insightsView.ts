import { html } from "hono/html";
import type { CoachReport } from "./coach";
import { type Html, money } from "./layout";
import type { ModelReport } from "./model";
import type { CraftProfit } from "./profit";
import type { XpReport } from "./scan";

const f1 = (n: number) => n.toFixed(1);
const int = (n: number) => Math.round(n).toLocaleString("hu-HU");
const when = (iso: string) =>
  new Date(iso).toLocaleString("hu-HU", { timeZone: "Europe/Budapest", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
const signed = (n: number) => `${n >= 0 ? "+" : ""}${f1(n)}%`;
const LEVEL = { fix: "Javítandó", tip: "Tipp", info: "Adat" } as const;
const SHORT: Record<string, string> = {
  "Sinister Strike": "SS", Eviscerate: "Evis", "Slice and Dice": "SnD", Backstab: "BS", Hemorrhage: "Hemo", Mutilate: "Mut",
  Riposte: "Rip", Gouge: "Gouge", Kick: "Kick", Shank: "Shank", Throw: "Throw", Rupture: "Rupt", "Kidney Shot": "KS",
};

export function coachSection(c: CoachReport | null): Html {
  if (!c) {
    return html`<section class="wide"><h2>Rotáció-edző</h2>
      <p class="muted">Legalább 5 hosszabb rögzített harc kell hozzá. Kapcsold be a harcnaplót: <code>/wa log</code>.</p></section>`;
  }
  const evisTotal = c.evisByCp.reduce((a, b) => a + b, 0);
  return html`<section class="wide"><h2>Rotáció-edző <span class="muted">${c.fights} harc alapján</span></h2>
    <div class="stats" style="margin-bottom:14px">
      <div><span>Képesség / perc</span><b>${f1(c.perMinute)}</b></div>
      <div><span>Energia ütéskor</span><b>${Math.round(c.builderEnergy)}</b></div>
      <div><span>90+ energiával</span><b>${f1(c.builderHighPct)}%</b></div>
      <div><span>SnD nélküli hosszú harc</span><b>${f1(c.sndFightsWithout)}%</b></div>
      <div><span>Első SnD</span><b>${c.sndLateSec == null ? "–" : f1(c.sndLateSec) + " mp"}</b></div>
    </div>
    <div class="advice">${c.tips.map(
      (t) => html`<div class="${t.level}"><span class="tag tag-${t.level}">${LEVEL[t.level]}</span><strong>${t.title}</strong><p>${t.text}</p></div>`,
    )}</div>

    <h3 style="margin-top:18px">A legjobb és a leggyengébb harcaid</h3>
    <table><thead><tr><th></th><th class="num">Legjobb negyed</th><th class="num">Leggyengébb negyed</th></tr></thead><tbody>
      ${c.compare.map((r) => html`<tr><td>${r.label}</td><td class="num"><b>${r.best}</b></td><td class="num">${r.worst}</td></tr>`)}
    </tbody></table>

    ${evisTotal
      ? html`<h3 style="margin-top:18px">Eviscerate combo pont szerint</h3>
          <div class="cpbars">${[1, 2, 3, 4, 5].map(
            (cp) => html`<div><i style="height:${Math.max(3, (c.evisByCp[cp] / evisTotal) * 70)}px"></i><b>${c.evisByCp[cp]}</b><span>${cp} pont</span></div>`,
          )}</div>`
      : ""}

    <h3 style="margin-top:18px">A legutóbbi harcok képességről képességre</h3>
    <p class="muted">A felső szám az energia a gomb megnyomásakor (finishernél a napló nem adja meg), az alsó a combo pont.</p>
    ${c.recent.map(
      (f) => html`<div class="tl">
        <div class="tl-head"><b>${f.target}</b>${f.targetLevel ? html` <span class="muted">(${f.targetLevel})</span>` : ""}
          <span class="muted"> · ${f1(f.dur)} mp · ${f1(f.dps)} DPS · SnD ${Math.round(f.sndPct)}%</span></div>
        <div class="tl-row">${f.casts.map(
          (x) => html`<span class="cast ${x.name === "Eviscerate" || x.name === "Slice and Dice" ? "fin" : ""} ${x.energy >= 95 ? "full" : ""}"
            title="${x.name} · ${f1(x.t)} mp"><small>${x.energy >= 0 ? x.energy : "–"}</small><b>${SHORT[x.name] ?? x.name.slice(0, 5)}</b><small>${x.cp}</small></span>`,
        )}</div>
      </div>`,
    )}
  </section>`;
}

export function xpSection(x: XpReport | null): Html {
  if (!x) {
    return html`<section class="wide"><h2>Szintezés</h2>
      <p class="muted">Még nincs XP-adat. Az addon új verziója rögzíti; játssz vele egy keveset, aztán <code>/wa save</code>.</p></section>`;
  }
  return html`<section class="wide"><h2>Szintezés <span class="muted">XP/óra és farmhelyek</span></h2>
    <div class="stats" style="margin-bottom:14px">
      <div><span>Mostani tempó</span><b>${int(x.recentPerHour)} XP/óra</b></div>
      <div><span>A következő szintig</span><b>${int(x.toLevel)} XP</b></div>
      <div><span>Ennyi idő</span><b>${x.hoursToLevel == null ? "–" : x.hoursToLevel < 1 ? `${Math.round(x.hoursToLevel * 60)} perc` : `${f1(x.hoursToLevel)} óra`}</b></div>
    </div>
    ${x.notes.map((n) => html`<p>${n}</p>`)}
    ${x.zones.length
      ? html`<table><thead><tr><th>Zóna</th><th class="num">XP/óra</th><th class="num">Ölés/óra</th><th class="num">Átlag harc</th>
          <th class="num">Harccal töltött idő</th><th class="num">Mobok szintje</th><th class="num">Játékidő</th></tr></thead><tbody>
          ${x.zones.map(
            (z) => html`<tr><td><b>${z.zone}</b></td><td class="num"><b class="gain">${int(z.perHour)}</b></td>
              <td class="num">${z.killsPerHour ? f1(z.killsPerHour) : "–"}</td><td class="num">${z.avgFight ? f1(z.avgFight) + " mp" : "–"}</td>
              <td class="num">${z.killsPerHour ? f1(z.fightShare) + "%" : "–"}</td><td class="num">${z.mobLevel ? f1(z.mobLevel) : "–"}</td>
              <td class="num muted">${f1(z.hours)} óra</td></tr>`,
          )}
        </tbody></table>`
      : html`<p class="muted">Zónánkénti bontáshoz legalább 10 perc játék kell egy helyen.</p>`}
    ${x.sessions.length
      ? html`<details><summary>A legutóbbi játékalkalmak</summary>
          <table><tbody>${x.sessions.map(
            (s) => html`<tr><td>${when(new Date(s.start * 1000).toISOString())}</td><td>${s.zone || "?"}</td>
              <td class="num">${f1(s.hours)} óra</td><td class="num">${int(s.xp)} XP</td><td class="num"><b>${int(s.perHour)}</b> XP/óra</td></tr>`,
          )}</tbody></table></details>`
      : ""}
  </section>`;
}

export function modelSection(m: ModelReport | null): Html {
  if (!m) return html``;
  return html`<section class="wide"><h2>Modell kontra valóság <span class="muted">mennyire lehet hinni a százalékoknak</span></h2>
    <p>${m.verdict}</p>
    <table><thead><tr><th>Mikortól</th><th>Mi változott</th><th class="num">Modell DPS</th><th class="num">Mért DPS</th>
      <th class="num">Jósolt változás</th><th class="num">Mért változás</th><th class="num">Harcok</th></tr></thead><tbody>
      ${m.periods.map(
        (p) => html`<tr><td>${when(p.from)}</td><td class="wrapcell">${p.change}</td><td class="num">${f1(p.modelDps)}</td>
          <td class="num">${p.measuredDps == null ? html`<span class="muted">kevés adat</span>` : html`<b>${f1(p.measuredDps)}</b>`}</td>
          <td class="num">${p.predictedPct == null ? "" : signed(p.predictedPct)}</td>
          <td class="num">${p.measuredPct == null ? "" : html`<b>${signed(p.measuredPct)}</b>`}</td>
          <td class="num muted">${p.fights} · ${Math.round(p.minutes)} perc</td></tr>`,
      )}
    </tbody></table>
    <p class="muted" style="margin:10px 0 0">Egy sor akkor jön létre, amikor a Blizzard API új felszerelést vagy talentet lát, ami csak
      kijelentkezés után történik meg; a váltás körüli harcok ezért a rossz oldalra kerülhetnek. A mért DPS a mobok szintjétől és a
      buffoktól is függ, tehát néhány harc alapján ne vonj le következtetést.</p>
  </section>`;
}

export function profitSection(list: CraftProfit[]): Html {
  return html`<section class="wide"><h2>Mit éri meg gyártani eladásra <span class="muted">a mostani árakon</span></h2>
    ${list.length
      ? html`<table><thead><tr><th>Recept</th><th>Alapanyag</th><th class="num">Költség</th><th class="num">Eladás</th>
          <th class="num">Haszon</th><th class="num">Már kint van</th><th class="num">Készletből</th></tr></thead><tbody>
          ${list.map(
            (p) => html`<tr><td><b>${p.recipe}</b>${p.known ? "" : html` <span class="tag">megtanulni: ${money(p.trainingCost)}</span>`}
                <div class="act-detail">${p.profession}</div></td>
              <td class="wrapcell muted">${p.matsText}</td><td class="num">${money(p.mats)}</td>
              <td class="num">${money(p.sale)}<div class="act-detail">${p.channel === "ah" ? "aukció, 5% levonva" : "vendor"}</div></td>
              <td class="num"><b class="gain">${money(p.profit)}</b><div class="act-detail">${Math.round(p.marginPct)}%</div></td>
              <td class="num ${p.channel === "ah" && p.listed > 30 ? "warn" : "muted"}">${p.channel === "ah" ? `${p.listed} db` : "–"}</td>
              <td class="num">${p.fromStock > 0 ? html`<b>${p.fromStock}×</b>` : ""}</td></tr>`,
          )}
        </tbody></table>
        <p class="muted" style="margin:10px 0 0">A haszon egy darabra szól, a legolcsóbb 40 kint lévő darab átlagárával számolva. Azt nem látom,
          milyen gyorsan fogy egy tárgy: ahol már sok van kint (sárgával jelölve), ott lassan megy el, és az ár is lejjebb mehet.
          A „Készletből" azt mutatja, hányat tudsz most legyártani abból, ami a táskádban és a bankodban van.</p>`
      : html`<p class="muted">A mostani árakon egyik recepted sem hoz hasznot az alapanyagok megvételével. A magad skinnelt bőrt
          ilyenkor nyersen érdemes eladni.</p>`}
  </section>`;
}
