#!/usr/bin/env node
// azeroth-mcp serve | ingest [--full] | doctor | install [--yes]
// stdout belongs to the MCP protocol in `serve`; everything human-readable goes to stderr there.
import { cpSync, existsSync, mkdirSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { loadConfig, REPO_ROOT } from "./config.ts";
import { openDb } from "./db.ts";
import { ingestAll, startWatcher } from "./ingest/index.ts";
import { accountDirs, addonsDir, characterDirs, combatLogFiles } from "./paths.ts";
import { createServer } from "./server.ts";

const ADDONS = ["WowAssistant", "SessionBar", "AzerothChronicle", "AzerothMCP_Data"];
const cmd = process.argv[2] ?? "help";
const cfg = loadConfig();
const err = (msg: string) => process.stderr.write(msg + "\n");

async function serve() {
  const db = openDb(cfg.dbPath);
  try {
    const r = ingestAll(db, cfg);
    err(`azeroth-mcp: initial ingest ${r.savedVariables.files} files, ${r.combatLogs.segments} fights in ${r.ms} ms`);
  } catch (e) {
    err(`azeroth-mcp: initial ingest failed: ${(e as Error).message}`);
  }
  const stop = startWatcher(db, cfg, (m) => err(`azeroth-mcp: ${m}`));
  const server = createServer(db, cfg);
  await server.connect(new StdioServerTransport());
  const shutdown = () => {
    stop();
    db.close();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
  process.stdin.on("close", shutdown);
}

function ingest() {
  const db = openDb(cfg.dbPath);
  const r = ingestAll(db, cfg, { force: process.argv.includes("--full"), final: process.argv.includes("--final") });
  console.log(JSON.stringify(r, null, 2));
  db.close();
}

function doctor() {
  const ok = (b: boolean) => (b ? "OK " : "-- ");
  console.log(`WoW mappa:      ${cfg.wowDir} ${existsSync(cfg.wowDir) ? "" : "(NEM LÉTEZIK)"}`);
  console.log(`Adatbázis:      ${cfg.dbPath}`);
  const accounts = accountDirs(cfg.wowDir);
  console.log(`Fiókok:         ${accounts.map((a) => a.account).join(", ") || "nincs"}`);
  for (const c of characterDirs(cfg.wowDir)) console.log(`  karakter:     ${c.key} (${c.account})`);
  const logs = combatLogFiles(cfg.wowDir);
  console.log(`Combat logok:   ${logs.length} fájl${logs.length ? `, legújabb: ${logs[logs.length - 1]}` : " (játékban: /wa log)"}`);
  const dir = addonsDir(cfg.wowDir);
  for (const a of ADDONS) console.log(`  ${ok(existsSync(join(dir, a)))}addon ${a}`);
  const db = openDb(cfg.dbPath);
  const r = ingestAll(db, cfg);
  console.log(`Beolvasás:      ${r.savedVariables.files} SavedVariables fájl, ${r.combatLogs.segments} új harc, ${r.ms} ms`);
  for (const e of [...r.savedVariables.errors, ...r.combatLogs.errors]) console.log(`  HIBA: ${e}`);
  const unknown = Object.entries(r.combatLogs.unknown);
  if (unknown.length) console.log(`  Ismeretlen log-események: ${unknown.map(([k, v]) => `${k}×${v}`).join(", ")}`);
  const count = (t: string) => (db.prepare(`SELECT COUNT(*) AS n FROM ${t}`).get() as { n: number }).n;
  for (const t of ["characters", "snapshots", "xp_samples", "sessions", "segments", "deaths", "guild_standings"]) console.log(`  ${t.padEnd(16)} ${count(t)}`);
  db.close();
}

function install() {
  const dir = addonsDir(cfg.wowDir);
  if (!existsSync(dir)) throw new Error(`Nincs AddOns mappa: ${dir}`);
  const yes = process.argv.includes("--yes");
  const existing = ADDONS.filter((a) => existsSync(join(dir, a)));
  if (existing.length && !yes) {
    console.log(`Ezeket felülírnám: ${existing.join(", ")}. Zárd be a játékot, és futtasd újra --yes kapcsolóval.`);
    return;
  }
  for (const a of ADDONS) {
    const src = join(REPO_ROOT, "addon", a);
    if (!existsSync(src)) continue;
    const dst = join(dir, a);
    mkdirSync(dst, { recursive: true });
    for (const f of readdirSync(src)) {
      // The inbox the bridge wrote must survive a reinstall.
      if (a === "AzerothMCP_Data" && f === "Data.lua" && existsSync(join(dst, f))) continue;
      cpSync(join(src, f), join(dst, f), { recursive: true });
    }
    console.log(`telepítve: ${dst}`);
  }
}

try {
  if (cmd === "serve") await serve();
  else if (cmd === "ingest") ingest();
  else if (cmd === "doctor") doctor();
  else if (cmd === "install") install();
  else console.log("használat: azeroth-mcp serve | ingest [--full] [--final] | doctor | install [--yes]");
} catch (e) {
  err(`azeroth-mcp: ${(e as Error).message}`);
  process.exit(1);
}
