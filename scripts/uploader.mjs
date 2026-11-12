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
//   UPLOAD_TOKEN  must match the worker's UPLOAD_TOKEN secret when that is set
import { cpSync, existsSync, readFileSync, readdirSync, statSync, watchFile } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parseCombatLog } from "./combat-log.mjs";
import { parseSavedVariables } from "./lua-table.mjs";

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
  const res = await fetch(`${APP_URL}/api/addon`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(TOKEN ? { Authorization: `Bearer ${TOKEN}` } : {}) },
    body: JSON.stringify(db),
  });
  console.log(`${new Date().toLocaleTimeString()} feltöltve → HTTP ${res.status} ${await res.text()}`);
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

let lastLogKey = "";
async function uploadFights(final = false) {
  const file = findCombatLog();
  if (!file) return;
  const st = statSync(file);
  const key = `${file}:${st.size}`;
  if (key === lastLogKey) return;
  lastLogKey = key;
  // A file that has not grown for a while cannot contain a fight still in progress.
  const idle = Date.now() - st.mtimeMs > 15000;
  const fights = parseCombatLog(readFileSync(file, "utf8"), CHARACTER, { includeOpen: final || idle });
  if (!fights.length) return;
  const res = await fetch(`${APP_URL}/api/fights`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(TOKEN ? { Authorization: `Bearer ${TOKEN}` } : {}) },
    body: JSON.stringify(fights),
  });
  console.log(`${new Date().toLocaleTimeString()} harcnapló: ${fights.length} harc → HTTP ${res.status} ${await res.text()}`);
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
  if (!process.argv.includes("--once")) {
    // The game appends to the combat log continuously; look at it every 20 seconds.
    setInterval(() => uploadFights().catch((e) => console.error("Harcnapló feltöltés sikertelen:", e.message)), 20000);
    watchFile(file, { interval: 2000 }, (cur, prev) => {
      if (cur.mtimeMs !== prev.mtimeMs) upload(file).catch((e) => console.error("Feltöltés sikertelen:", e.message));
    });
    console.log("Várakozás változásra (Ctrl+C a kilépéshez)…");
  }
}
