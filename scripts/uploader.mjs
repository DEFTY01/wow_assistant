// Watches the addon's SavedVariables file and uploads it to the web app whenever the
// game rewrites it (on logout or /reload).
//
//   node scripts/uploader.mjs            watch and upload on every change
//   node scripts/uploader.mjs --once     upload once and exit
//   node scripts/uploader.mjs --install  copy the addon into the game folder
//
// Settings (environment variables):
//   WOW_DIR       game flavor folder, default "F:/World of Warcraft/_forever_"
//   APP_URL       web app, default "http://127.0.0.1:8787"
//   WOW_CHARACTER character first name in the combat log, default "Defty"
//   (the same keys can be put in a .uploader.env file in the project folder)
//   UPLOAD_TOKEN  must match the worker's UPLOAD_TOKEN secret when that is set
import { cpSync, existsSync, readFileSync, readdirSync, renameSync, statSync, watchFile, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parseCombatLog } from "./combat-log.mjs";
import { parseSavedVariables } from "./lua-table.mjs";

// Optional settings file next to package.json (.uploader.env, KEY=VALUE per line, not committed),
// so the scheduled task needs no environment variables of its own.
{
  const envFile = join(dirname(fileURLToPath(import.meta.url)), "..", ".uploader.env");
  if (existsSync(envFile)) {
    for (const line of readFileSync(envFile, "utf8").split(/\r?\n/)) {
      const m = /^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/.exec(line);
      if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2];
    }
  }
}

const WOW_DIR = process.env.WOW_DIR ?? "F:/World of Warcraft/_forever_";
const APP_URL = (process.env.APP_URL ?? "http://127.0.0.1:8787").replace(/\/$/, "");
const TOKEN = process.env.UPLOAD_TOKEN ?? "";
const CHARACTER = process.env.WOW_CHARACTER ?? "Defty";
const ADDON = "WowAssistant";
const root = join(dirname(fileURLToPath(import.meta.url)), "..");

function install() {
  const target = join(WOW_DIR, "Interface", "AddOns", ADDON);
  if (!existsSync(join(WOW_DIR, "Interface", "AddOns"))) {
    throw new Error(`Nem találom az AddOns mappát itt: ${WOW_DIR} (állítsd be a WOW_DIR változót)`);
  }
  cpSync(join(root, "addon", ADDON), target, { recursive: true });
  console.log(`Addon telepítve: ${target}`);
  // SessionBar and AzerothChronicle are part of WowAssistant since 2.0. Their folders get a shim
  // that only keeps the old SavedVariables loaded, so the first login copies them over.
  for (const old of ["SessionBar", "AzerothChronicle"]) {
    const dir = join(WOW_DIR, "Interface", "AddOns", old);
    cpSync(join(root, "addon", old), dir, { recursive: true });
    console.log(`Átköltöztető shim: ${dir} (minden karakter első belépése után törölhető)`);
  }
}

async function post(path, body) {
  const res = await fetch(`${APP_URL}${path}`, {
    method: "POST",
    redirect: "manual",
    headers: { "Content-Type": "application/json", ...(TOKEN ? { Authorization: `Bearer ${TOKEN}` } : {}) },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (res.status >= 300 && res.status < 400) {
    throw new Error(`HTTP ${res.status}: átirányítás a bejelentkező oldalra (a Cloudflare Access nem engedi át a ${path} útvonalat)`);
  }
  if (res.status === 401) throw new Error("HTTP 401: hibás vagy hiányzó UPLOAD_TOKEN");
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 200)}`);
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`A válasz nem az apptól jött: ${text.slice(0, 80).replace(/\s+/g, " ")}`);
  }
}

function findSavedVariables() {
  const accounts = join(WOW_DIR, "WTF", "Account");
  if (!existsSync(accounts)) return [];
  return readdirSync(accounts)
    .map((a) => join(accounts, a, "SavedVariables", `${ADDON}.lua`))
    .filter((f) => existsSync(f))
    .sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
}

async function upload(file) {
  const db = parseSavedVariables(readFileSync(file, "utf8")).WowAssistantDB;
  if (!db?.chars) {
    console.log("A fájlban még nincs adat.");
    return;
  }
  // Only the exporter data goes to the web app: the session bar, Chronicle and market tables
  // (also in WowAssistantDB since addon 2.0) are read in game and by the Azeroth MCP bridge.
  const r = await post("/api/addon", { version: db.version, last: db.last, chars: db.chars });
  console.log(
    `${new Date().toLocaleTimeString()} feltöltve → ${APP_URL}: ${r.money ?? "?"} copper, ${r.bagItems} féle tárgy a táskákban, ` +
      `${r.bankItems} a bankban, ${r.trainerSkills} trainer skill`,
  );
}

// Newest combat log file written by the game (/wa log or /combatlog turns logging on).
function findCombatLog() {
  const dir = join(WOW_DIR, "Logs");
  if (!existsSync(dir)) return null;
  const files = readdirSync(dir)
    .filter((f) => /^WoWCombatLog.*.txt$/i.test(f))
    .map((f) => join(dir, f))
    .sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
  return files[0] ?? null;
}

// ------------------------------------------------------------------ fights for the game
// Addons cannot read the combat log in this client, so the fights parsed here are also written
// into the addon folder (WowAssistant/Fights.lua). The game reads that file at login or /reload,
// and the in-game Combat and Plan windows then work from the same fights as the web app.
const FIGHTS_KEEP = 200;
const luaStr = (s) => '"' + String(s).replace(/[\\"]/g, (c) => "\\" + c).replace(/\r?\n/g, "\\n") + '"';
const luaVal = (v) =>
  v == null ? "nil"
    : typeof v === "number" ? (Number.isFinite(v) ? String(v) : "nil")
    : typeof v === "boolean" ? String(v)
    : typeof v === "string" ? luaStr(v)
    : Array.isArray(v) ? "{" + v.map(luaVal).join(",") + "}"
    : "{" + Object.entries(v).filter(([, x]) => x != null).map(([k, x]) => `[${luaStr(k)}]=${luaVal(x)}`).join(",") + "}";
// The web app's Fight -> the addon's shape (ordered lists instead of name-keyed objects).
const forGame = (f, level) => ({
  start: f.start, dur: f.dur, dmg: f.dmg, target: f.target, targetLevel: f.targetLevel, level: f.level ?? level,
  capped: f.capped, samples: f.samples, source: "log",
  ab: Object.entries(f.ab ?? {}).map(([name, a]) => ({ name, ...a })),
  casts: f.casts ?? [],
  auras: Object.entries(f.auras ?? {}).map(([name, secs]) => [name, secs]),
  // where the numbers come from, and every Eviscerate with the target's health (2.8.0+)
  pet: f.pet, overkill: f.overkill, basis: f.basis, evis: f.evis, taps: f.taps, gems: f.gems, rage: f.rage,
  // when each buff and debuff of ours went on and off (WA-005; at most 200 changes a fight)
  auraLog: f.auraLog, auraLogCut: f.auraLogCut,
});

function writeGameFights(text, includeOpen) {
  const dir = join(WOW_DIR, "Interface", "AddOns", ADDON);
  const sv = findSavedVariables()[0];
  if (!existsSync(dir) || !sv) return;
  const chars = parseSavedVariables(readFileSync(sv, "utf8")).WowAssistantDB?.chars ?? {};
  const target = join(dir, "Fights.lua");
  let old = {};
  try {
    if (existsSync(target)) old = parseSavedVariables(readFileSync(target, "utf8")).WowAssistantFights ?? {};
  } catch {
    old = {};
  }
  const out = {};
  let added = 0;
  // Only "Name-Realm" keys: the log names players that way, so same-name alts stay apart.
  for (const [key, c] of Object.entries(chars)) {
    if (!key.includes("-")) continue;
    const byStart = new Map();
    for (const f of Array.isArray(old[key]) ? old[key] : Object.values(old[key] ?? {})) byStart.set(f.start, f);
    for (const f of parseCombatLog(text, key, { includeOpen })) {
      if (!byStart.has(f.start)) added++;
      byStart.set(f.start, forGame(f, c.level));
    }
    if (byStart.size) out[key] = [...byStart.values()].sort((a, b) => b.start - a.start).slice(0, FIGHTS_KEEP);
  }
  if (!Object.keys(out).length) return;
  const body = [
    "-- Written by scripts/uploader.mjs from the game's combat log; read by the addon at login or /reload.",
    "WowAssistantFights = {",
    ...Object.entries(out).map(([k, list]) => [`  [${luaStr(k)}] = {`, ...list.map((f) => `    ${luaVal(f)},`), "  },"].join("\n")),
    "}",
    "",
  ].join("\n");
  writeFileSync(target + ".tmp", body);
  renameSync(target + ".tmp", target);
  if (added) console.log(`${new Date().toLocaleTimeString()} harcnapló a játéknak: ${added} új harc (${target})`);
}

// ------------------------------------------------------------------ prices for the game
// The web app keeps every auction house listing of the crafting reagents (hourly download). The
// addon's vendor crafting window gets them as WowAssistant/Market.lua, read at login or /reload,
// so it knows what crafting costs without an in-game scan. A newer in-game scan or a live
// auction house search still takes precedence.
let lastMarketAt = null;
async function writeGameMarket() {
  const dir = join(WOW_DIR, "Interface", "AddOns", ADDON);
  if (!existsSync(dir)) return;
  const res = await fetch(`${APP_URL}/api/market`, {
    redirect: "manual",
    headers: TOKEN ? { Authorization: `Bearer ${TOKEN}` } : {},
  });
  if (res.status === 404) return; // an older web app without the endpoint
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const m = await res.json();
  if (!m.at || m.at === lastMarketAt) return;
  const target = join(dir, "Market.lua");
  const lines = Object.entries(m.books ?? {}).map(([id, book]) =>
    `    [${Number(id)}] = {${book.map(([u, q, w]) => `${+u},${+q},${w ? 1 : 0}`).join(",")}},`);
  const body = [
    "-- Written by scripts/uploader.mjs from the web app's auction house data; read by the addon at login or /reload.",
    "-- books[item] = { unit price, quantity, whole stack (1) or not (0), ... }, cheapest first",
    "WowAssistantMarketFile = {",
    `  at = ${m.at},`,
    "  books = {",
    ...lines,
    "  },",
    "  -- average unit price over every listing (the book above stops at 5000 units)",
    "  avg = {",
    ...Object.entries(m.avg ?? {}).map(([id, p]) => `    [${Number(id)}] = ${+p},`),
    "  },",
    "}",
    "",
  ].join("\n");
  writeFileSync(target + ".tmp", body);
  renameSync(target + ".tmp", target);
  lastMarketAt = m.at;
  console.log(`${new Date().toLocaleTimeString()} AH-árak a játéknak: ${lines.length} alapanyag, ${new Date(m.at * 1000).toLocaleTimeString()}-i adat (${target})`);
}

let lastLogKey = "";
async function uploadFights(final = false) {
  const file = findCombatLog();
  if (!file) return;
  const st = statSync(file);
  const key = `${file}:${st.size}`;
  if (key === lastLogKey) return;
  // A file that has not grown for a while cannot contain a fight still in progress.
  const idle = Date.now() - st.mtimeMs > 15000;
  const text = readFileSync(file, "utf8");
  try {
    writeGameFights(text, final || idle);
  } catch (e) {
    console.error("Harcnapló a játéknak sikertelen:", e.message);
  }
  const fights = parseCombatLog(text, CHARACTER, { includeOpen: final || idle });
  if (!fights.length) return;
  const r = await post("/api/fights", fights);
  lastLogKey = key;
  console.log(`${new Date().toLocaleTimeString()} harcnapló: ${r.stored} harc feltöltve`);
}

if (process.argv.includes("--install")) {
  install();
} else {
  const files = findSavedVariables();
  if (!files.length) {
    console.log(
      `Még nincs ${ADDON}.lua a WTF mappában (${WOW_DIR}). Lépj be a játékba az addonnal, ` +
        "írd be: /wa save, aztán indítsd újra ezt a scriptet.",
    );
    process.exit(1);
  }
  const file = files[0];
  console.log(`Figyelt fájl: ${file}`);
  await upload(file).catch((e) => console.error("Feltöltés sikertelen:", e.message));
  await uploadFights(true).catch((e) => console.error("Harcnapló feltöltés sikertelen:", e.message));
  await writeGameMarket().catch((e) => console.error("AH-árak a játéknak sikertelen:", e.message));
  if (!process.argv.includes("--once")) {
    // The game appends to the combat log continuously; look at it every 20 seconds.
    setInterval(() => uploadFights().catch((e) => console.error("Harcnapló feltöltés sikertelen:", e.message)), 20000);
    // The web app downloads prices hourly; checking every 5 minutes picks a new download up soon.
    setInterval(() => writeGameMarket().catch((e) => console.error("AH-árak a játéknak sikertelen:", e.message)), 300000);
    watchFile(file, { interval: 2000 }, (cur, prev) => {
      if (cur.mtimeMs !== prev.mtimeMs) upload(file).catch((e) => console.error("Feltöltés sikertelen:", e.message));
    });
    console.log("Várakozás változásra (Ctrl+C a kilépéshez)…");
  }
}
