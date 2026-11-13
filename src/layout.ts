import { html, raw } from "hono/html";
import type { HtmlEscapedString } from "hono/utils/html";

export type Html = HtmlEscapedString | Promise<HtmlEscapedString>;

export const QUALITY: Record<string, string> = {
  POOR: "#9d9d9d",
  COMMON: "#f2efe6",
  UNCOMMON: "#1eff00",
  RARE: "#2f8dff",
  EPIC: "#b048f8",
  LEGENDARY: "#ff8000",
};
export const QUALITY_BY_INDEX = [QUALITY.POOR, QUALITY.COMMON, QUALITY.UNCOMMON, QUALITY.RARE, QUALITY.EPIC, QUALITY.LEGENDARY];

/** Plain-text money, for places that cannot hold markup. */
export function formatMoney(copper: number | null): string {
  if (copper == null) return "–";
  const g = Math.floor(copper / 10000);
  const s = Math.floor((copper % 10000) / 100);
  const c = Math.round(copper % 100);
  return `${g}g ${s}s ${c}c`;
}

/** Money as gold / silver / copper coins. */
export function money(copper: number | null | undefined): Html {
  if (copper == null) return html`<span class="muted">–</span>`;
  const v = Math.round(copper);
  const g = Math.floor(v / 10000);
  const s = Math.floor((v % 10000) / 100);
  const c = v % 100;
  return html`<span class="money">${g > 0 ? html`<span class="coin g">${g.toLocaleString("hu-HU")}</span>` : ""}${
    g > 0 || s > 0 ? html`<span class="coin s">${s}</span>` : ""
  }<span class="coin c">${c}</span></span>`;
}

const TABS = [
  { id: "plan", href: "/", label: "Haditerv" },
  { id: "char", href: "/character", label: "Karakter" },
  { id: "combat", href: "/combat", label: "Harc" },
  { id: "gear", href: "/gear", label: "Felszerelés" },
  { id: "prof", href: "/professions", label: "Mesterségek" },
] as const;
export type TabId = (typeof TABS)[number]["id"];

export function page(opts: { title: string; active: TabId | null; body: Html; toolbar?: Html }): Html {
  return html`<!doctype html>
<html lang="hu">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${opts.title} · WoW Assistant</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Cinzel:wght@500;700&family=Alegreya+Sans:wght@400;500;700&display=swap" rel="stylesheet">
<style>${raw(CSS)}</style>
</head>
<body>
<header class="bar">
  <a class="brand" href="/"><span class="sigil" aria-hidden="true"></span><span>WoW Assistant</span></a>
  ${opts.active
    ? html`<nav class="tabs">
    ${TABS.map((t) => html`<a href="${t.href}" class="${t.id === opts.active ? "on" : ""}">${t.label}</a>`)}
  </nav>`
    : ""}
  <div class="tools">${opts.toolbar ?? ""}</div>
</header>
<main>
${opts.body}
</main>
<footer>Blizzard API · Wowhead adatbázis · saját addon és harcnapló</footer>
</body>
</html>`;
}

// Corner brackets are drawn with eight tiny gradients so panels need no extra markup.
const CORNERS = ["top left", "top right", "bottom left", "bottom right"]
  .flatMap((pos) => [`linear-gradient(var(--gold),var(--gold)) ${pos}/14px 1px no-repeat`, `linear-gradient(var(--gold),var(--gold)) ${pos}/1px 14px no-repeat`])
  .join(",");

export const CSS = `
:root{
  color-scheme:dark;
  --ink:#0a0907; --stone:#12100c; --panel:#17140f; --panel2:#1e1a13; --edge:#4a3a1e; --hair:#2b2418;
  --gold:#c9a24a; --gold-hi:#f3d58a; --text:#dcd0b6; --muted:#8c806a; --dim:#5f5646;
  --class:#fff468; --good:#6fd36f; --bad:#ff6a55; --info:#7fb2d9;
  --display:"Cinzel","Trajan Pro",Georgia,serif; --body:"Alegreya Sans","Segoe UI",system-ui,sans-serif;
}
*{box-sizing:border-box}
html{background:var(--ink)}
body{margin:0;min-height:100vh;color:var(--text);font:16px/1.45 var(--body);
  background:
    radial-gradient(1200px 500px at 50% -120px,rgba(201,162,74,.13),transparent 70%),
    repeating-linear-gradient(135deg,rgba(255,255,255,.012) 0 2px,transparent 2px 6px),
    var(--ink)}
a{color:var(--gold-hi);text-decoration:none}
a:hover{text-decoration:underline}
code{font:13px ui-monospace,Consolas,monospace;background:#0d0b08;border:1px solid var(--hair);padding:1px 5px;color:var(--gold-hi)}
.muted{color:var(--muted)}
.err{color:var(--bad)}

/* top bar */
.bar{position:sticky;top:0;z-index:5;display:flex;align-items:center;gap:20px;padding:0 20px;height:56px;
  background:linear-gradient(#1c1811,#100e0a);border-bottom:1px solid var(--edge);
  box-shadow:0 1px 0 #000,0 6px 18px rgba(0,0,0,.55)}
.brand{display:flex;align-items:center;gap:10px;font:700 15px var(--display);letter-spacing:.14em;text-transform:uppercase;color:var(--gold-hi)}
.brand:hover{text-decoration:none}
.sigil{width:14px;height:14px;transform:rotate(45deg);border:1px solid var(--gold-hi);
  background:linear-gradient(135deg,var(--gold-hi),#7a5a1c);box-shadow:0 0 8px rgba(243,213,138,.45)}
.tabs{display:flex;align-self:stretch;margin-left:8px}
.tabs a{display:flex;align-items:center;padding:0 16px;font:500 13px var(--display);letter-spacing:.1em;text-transform:uppercase;
  color:var(--muted);border-bottom:2px solid transparent;margin-bottom:-1px}
.tabs a:hover{color:var(--text);text-decoration:none}
.tabs a.on{color:var(--gold-hi);border-bottom-color:var(--gold-hi);background:linear-gradient(transparent,rgba(201,162,74,.10))}
.tools{margin-left:auto;display:flex;align-items:center;gap:10px}
.tools form{margin:0}

/* layout */
main{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:18px;max-width:1240px;margin:0 auto;padding:22px 20px 40px}
main>*{grid-column:span 12;min-width:0}
main>.half{grid-column:span 6}
main>.third{grid-column:span 4}
main>section:not(.wide):not(.half):not(.third){grid-column:span 6}
footer{text-align:center;color:var(--dim);font-size:13px;padding:0 20px 28px;letter-spacing:.04em}

/* framed panel */
section,.frame{position:relative;padding:18px 20px 20px;overflow-x:auto;
  border:1px solid var(--edge);
  background:${CORNERS},linear-gradient(180deg,var(--panel2),var(--panel) 120px);
  box-shadow:0 0 0 1px #000,inset 0 1px 0 rgba(255,235,190,.05),0 10px 26px rgba(0,0,0,.45)}
h1,h2,h3{font-family:var(--display);font-weight:700;margin:0}
h2{display:flex;align-items:center;gap:12px;margin-bottom:14px;font-size:13px;letter-spacing:.16em;text-transform:uppercase;color:var(--gold-hi)}
h2::after{content:"";flex:1;height:1px;background:linear-gradient(90deg,var(--edge),transparent)}
h2 .muted{font:400 14px var(--body);letter-spacing:0;text-transform:none}
h3{font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);margin:14px 0 6px}
p{margin:0 0 8px}

/* tables */
table{width:100%;border-collapse:collapse;font-size:15px;font-variant-numeric:tabular-nums}
th{text-align:left;padding:6px 10px;font:500 11px var(--display);letter-spacing:.12em;text-transform:uppercase;color:var(--muted);
  border-bottom:1px solid var(--edge);white-space:nowrap}
td{padding:7px 10px;border-bottom:1px solid var(--hair);vertical-align:top}
td:first-child{white-space:nowrap}
tbody tr:last-child td{border-bottom:0}
tbody tr:hover td{background:rgba(243,213,138,.035)}
tr.err td{color:var(--bad)}
td.num,th.num{text-align:right}

/* buttons and inputs */
button,.btn{font:700 12px var(--display);letter-spacing:.1em;text-transform:uppercase;cursor:pointer;padding:8px 14px;color:#ffd978;
  border:1px solid #9c7a2f;background:linear-gradient(#7d1a12,#4a0d08);
  box-shadow:inset 0 1px 0 rgba(255,190,150,.25),0 0 0 1px #000}
button:hover,.btn:hover{background:linear-gradient(#96241a,#5a120b);color:#fff0c0}
button:active{transform:translateY(1px)}
input{font:15px var(--body);width:120px;padding:7px 9px;color:var(--text);background:#0c0a07;border:1px solid var(--edge);
  box-shadow:inset 0 2px 5px rgba(0,0,0,.6)}
input:focus,button:focus-visible,a:focus-visible{outline:1px solid var(--gold-hi);outline-offset:2px}
.gold{display:flex;flex-wrap:wrap;gap:10px;align-items:center;margin:0}
label{color:var(--muted)}

/* money */
.money{white-space:nowrap;font-variant-numeric:tabular-nums}
.coin{margin-right:5px}
.coin::after{content:"";display:inline-block;width:.62em;height:.62em;margin-left:3px;border-radius:50%;vertical-align:.02em;
  box-shadow:inset 0 0 0 1px rgba(0,0,0,.35),inset 0 -2px 2px rgba(0,0,0,.3)}
.coin.g::after{background:#ffd100}.coin.s::after{background:#c9ccd4}.coin.c::after{background:#d98a4e}

/* tags */
.tag{display:inline-block;font:500 10px var(--display);letter-spacing:.1em;text-transform:uppercase;padding:2px 7px;white-space:nowrap;
  color:var(--gold-hi);border:1px solid var(--edge);background:rgba(201,162,74,.08)}
.tag-fix{color:#ffb0a3;border-color:#7d2a20;background:rgba(255,106,85,.10)}
.tag-info{color:#b8d6ee;border-color:#2f4a60;background:rgba(127,178,217,.09)}

/* stat plaques */
.stats{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}
.stats>div{display:flex;flex-direction:column;gap:2px;padding:10px 12px;border:1px solid var(--hair);background:#100e0a;
  box-shadow:inset 0 2px 6px rgba(0,0,0,.5)}
.stats span{font:500 10px var(--display);letter-spacing:.12em;text-transform:uppercase;color:var(--muted)}
.stats b{font:700 22px var(--display);color:var(--gold-hi);font-variant-numeric:tabular-nums}

/* key/value lists */
.kv{display:grid;grid-template-columns:max-content 1fr;gap:5px 18px;margin:0}
.kv dt{color:var(--muted)}.kv dd{margin:0;text-align:right;font-variant-numeric:tabular-nums}

/* skill bars */
.prof{margin-bottom:14px}
.prof:last-child{margin-bottom:0}
.prof-head{display:flex;justify-content:space-between;align-items:baseline;gap:10px;margin-bottom:4px}
.prof-head strong{font-weight:700}
.bar-track{position:relative;height:18px;border:1px solid var(--edge);background:#0b0906;box-shadow:inset 0 2px 5px rgba(0,0,0,.7)}
.bar-fill{position:absolute;inset:0 auto 0 0;background:linear-gradient(#3f78c9,#1c3f7d);box-shadow:inset 0 1px 0 rgba(255,255,255,.25)}
.bar-fill.capped{background:linear-gradient(#c9a24a,#7a5a1c)}
.bar-label{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:700;
  color:#fff;text-shadow:0 1px 2px #000;font-variant-numeric:tabular-nums}
details{margin-top:6px}
summary{cursor:pointer;color:var(--muted);font-size:14px}
summary:hover{color:var(--text)}
pre{overflow:auto;max-height:380px;font:12px ui-monospace,Consolas,monospace;background:#0b0906;border:1px solid var(--hair);padding:12px;color:#b9ad92}

/* character banner */
.hero{display:flex;align-items:center;gap:22px;flex-wrap:wrap;padding:22px 24px}
.medal{flex:none;width:76px;height:76px;border-radius:50%;display:grid;place-items:center;
  font:700 30px var(--display);color:var(--gold-hi);
  border:2px solid var(--gold);background:radial-gradient(circle at 50% 35%,#3a2f18,#0d0b07 72%);
  box-shadow:0 0 0 1px #000,0 0 0 4px #1a160f,0 0 0 5px var(--edge),0 0 22px rgba(201,162,74,.25)}
.hero h1{font-size:34px;letter-spacing:.04em;line-height:1.1;color:var(--class);text-shadow:0 2px 0 #000,0 0 18px rgba(255,244,104,.18)}
.hero h1 small{font-size:.62em;color:var(--text);font-weight:500;margin-left:.3em}
.hero .sub{color:var(--muted);margin-top:4px}
.hero .sub b{color:var(--text);font-weight:500}
.chips{margin-left:auto;display:flex;gap:10px;flex-wrap:wrap}
.chip{min-width:104px;padding:8px 12px;border:1px solid var(--hair);background:#100e0a;box-shadow:inset 0 2px 6px rgba(0,0,0,.5)}
.chip>span{display:block;font:500 10px var(--display);letter-spacing:.12em;text-transform:uppercase;color:var(--muted)}
.chip b{font-size:18px;font-weight:700;color:var(--text)}
.horde{color:#e0553f}.alliance{color:#5b8fe0}

/* paper doll */
.doll{display:grid;grid-template-columns:minmax(0,1fr) minmax(220px,300px) minmax(0,1fr);gap:16px 22px}
.doll .col{display:flex;flex-direction:column;gap:8px}
.doll .weapons{grid-column:1/-1;display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px 22px;padding-top:14px;border-top:1px solid var(--hair)}
.slot{display:flex;gap:10px;align-items:center;min-width:0}
.col.right .slot{flex-direction:row-reverse;text-align:right}
.icon{flex:none;width:42px;height:42px;display:grid;place-items:center;font:700 11px var(--display);letter-spacing:.05em;color:var(--q,var(--dim));
  border:1px solid var(--q,var(--hair));background:linear-gradient(135deg,#1d1a14,#0b0906);
  box-shadow:inset 0 0 0 1px #000,inset 0 0 10px color-mix(in srgb,var(--q,#000) 28%,transparent)}
.slot .name{font-weight:700;color:var(--q,var(--dim));white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.slot .meta{font-size:13px;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.slot>div:last-child{min-width:0}
.slot.empty .name{font-weight:400;font-style:italic}
.sheet{align-self:start;padding:14px 16px;border:1px solid var(--hair);background:#100e0a;box-shadow:inset 0 2px 8px rgba(0,0,0,.55)}
.sheet h3:first-child{margin-top:0}

/* talent trees */
.trees{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:14px}
.tree{padding:12px 14px;border:1px solid var(--hair);background:#100e0a}
.tree header{display:flex;justify-content:space-between;align-items:baseline;margin-bottom:8px}
.tree header b{font:700 13px var(--display);letter-spacing:.1em;text-transform:uppercase;color:var(--text)}
.tree header span{font:700 20px var(--display);color:var(--gold-hi)}
.tree ul{list-style:none;margin:0;padding:0;font-size:14px}
.tree li{display:flex;justify-content:space-between;gap:8px;padding:2px 0;color:var(--muted)}
.tree li b{color:var(--good);font-weight:700}
.tree.zero{opacity:.45}

/* battle plan */
.notice{padding:10px 14px;border:1px solid #6a4a1c;border-left:3px solid var(--gold);background:rgba(201,162,74,.07);color:#d8c59a;font-size:15px}
.notice p{margin:2px 0}
.verdict{display:grid;grid-template-columns:auto auto auto 1fr;align-items:center;gap:8px 26px;padding:22px 26px}
.verdict>div{display:flex;flex-direction:column}
.verdict>div>span{font:500 11px var(--display);letter-spacing:.14em;text-transform:uppercase;color:var(--muted)}
.verdict>div>b{font:700 44px/1.05 var(--display);color:var(--text);font-variant-numeric:tabular-nums}
.verdict>div>small{color:var(--muted);font-size:14px}
.verdict-then b{color:var(--gold-hi);text-shadow:0 0 22px rgba(243,213,138,.25)}
.verdict-then em{font-style:normal;color:var(--good);font-weight:700}
.verdict-arrow{width:44px;height:2px;background:linear-gradient(90deg,var(--edge),var(--gold-hi));position:relative;align-self:center}
.verdict-arrow::after{content:"";position:absolute;right:-1px;top:-5px;border:6px solid transparent;border-left-color:var(--gold-hi);border-right:0}
.purse{justify-self:end;min-width:240px;padding:12px 16px;border:1px solid var(--hair);background:#100e0a;box-shadow:inset 0 2px 8px rgba(0,0,0,.55)}
.verdict>.purse>b{font:700 24px var(--body);margin:2px 0 8px;color:var(--text)}
.purse .bar-track{height:8px;margin-bottom:6px}
.acts{list-style:none;margin:0;padding:0}
.act{display:grid;grid-template-columns:76px minmax(0,1fr) auto;gap:14px;align-items:center;padding:11px 0;border-bottom:1px solid var(--hair)}
.act:last-child{border-bottom:0;padding-bottom:0}
.act:first-child{padding-top:2px}
.src{justify-self:start;font:700 10px var(--display);letter-spacing:.1em;text-transform:uppercase;padding:4px 0;width:76px;text-align:center;border:1px solid var(--edge);color:var(--gold-hi);background:rgba(201,162,74,.08)}
.src-craft{color:#9fd6a0;border-color:#2f5a35;background:rgba(111,211,111,.08)}
.src-owned{color:#b8d6ee;border-color:#2f4a60;background:rgba(127,178,217,.09)}
.src-trainer{color:#e2b8f2;border-color:#553066;background:rgba(176,72,248,.09)}
.act-title{font-weight:700;font-size:17px}
.act-detail{color:var(--muted);font-size:14px;line-height:1.35}
.act-num{display:flex;flex-direction:column;align-items:flex-end;gap:1px;white-space:nowrap;font-variant-numeric:tabular-nums}
.act-num small{color:var(--dim);font-size:12px}
.gain{color:var(--good);font-weight:700}
.gain sup{color:var(--muted);margin-left:1px}
.warn{color:#e8b25a}
.tag-good{color:#a9e6aa;border-color:#2f5a35;background:rgba(111,211,111,.09)}
.tag-dim{color:var(--dim);border-color:var(--hair);background:none}
tr.dim td{opacity:.55}
.road{list-style:none;margin:0;padding:0;position:relative}
.road::before{content:"";position:absolute;left:17px;top:6px;bottom:6px;width:1px;background:var(--edge)}
.road li{display:grid;grid-template-columns:36px 1fr;gap:14px;padding:6px 0;position:relative}
.road-lvl{width:36px;height:36px;border-radius:50%;display:grid;place-items:center;font:700 14px var(--display);color:var(--gold-hi);
  border:1px solid var(--gold);background:#14110c;box-shadow:0 0 0 3px var(--panel)}
.road li>div{align-self:center;font-size:15px}

/* buff picker */
.buffs{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:8px}
.buff{display:flex;gap:10px;align-items:center;padding:8px 10px;cursor:pointer;color:var(--text);border:1px solid var(--hair);background:#100e0a}
.buff:hover{border-color:var(--edge)}
.buff:has(input:checked){border-color:var(--gold);background:rgba(201,162,74,.10);box-shadow:inset 0 0 12px rgba(201,162,74,.10)}
.buff input{width:16px;height:16px;padding:0;margin:0;accent-color:var(--gold);box-shadow:none;flex:none}
.buff span{display:flex;flex-direction:column;min-width:0}
.buff b{font-weight:700}
.buff small{font-size:13px;color:var(--muted)}
.buff.off{cursor:default;opacity:.45}

/* advice */
.advice{display:grid;gap:10px}
.advice>div{padding:12px 14px;border:1px solid var(--hair);border-left:3px solid var(--gold);background:#100e0a}
.advice>div.fix{border-left-color:var(--bad)}
.advice>div.info{border-left-color:var(--info)}
.advice strong{margin-left:8px}
.advice p{margin:6px 0 0;color:#b9ad92}

@media (max-width:900px){
  main>.half,main>.third,main>section:not(.wide):not(.half):not(.third){grid-column:span 12}
  .doll{grid-template-columns:1fr}
  .doll .weapons{grid-template-columns:1fr}
  .col.right .slot{flex-direction:row;text-align:left}
  .bar{flex-wrap:wrap;height:auto;padding:8px 14px;gap:8px 14px;position:static}
  .tabs{order:3;width:100%;margin:0;overflow-x:auto}
  .tabs a{padding:8px 12px}
  .chips{margin-left:0}
  .verdict{grid-template-columns:1fr auto 1fr;padding:18px 16px;gap:14px}
  .verdict>div>b{font-size:34px}
  .purse{grid-column:1/-1;justify-self:stretch}
  .act{grid-template-columns:1fr auto}
  .src{grid-column:1/-1}
  main{padding:14px 12px 30px;gap:14px}
}
`;
