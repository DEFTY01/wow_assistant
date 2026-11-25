// Runs the whole app on this computer, with no Cloudflare account involved:
//   - the worker with a local D1 database (wrangler dev, data in .wrangler/state),
//   - the uploader, which sends the addon data and the combat log to it,
//   - the 30-minute sync that the online cron trigger used to do.
//
//   npm run local          (open http://127.0.0.1:8787)
//
// Only 127.0.0.1 is bound, so nothing is reachable from the network. Ctrl+C stops everything.
import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = process.env.LOCAL_PORT ?? "8787";
const URL = `http://127.0.0.1:${PORT}`;
const children = [];

function run(name, args, env = {}) {
  const child = spawn(process.execPath, args, { cwd: root, env: { ...process.env, ...env }, stdio: ["ignore", "pipe", "pipe"] });
  const prefix = (line) => line && console.log(`[${name}] ${line}`);
  child.stdout.on("data", (d) => String(d).split(/\r?\n/).forEach(prefix));
  child.stderr.on("data", (d) => String(d).split(/\r?\n/).forEach(prefix));
  child.on("exit", (code) => console.log(`[${name}] leállt (${code})`));
  children.push(child);
  return child;
}

function stopAll() {
  for (const c of children) if (c.exitCode === null) c.kill();
  process.exit(0);
}
process.on("SIGINT", stopAll);
process.on("SIGTERM", stopAll);

async function waitForServer() {
  for (let i = 0; i < 120; i++) {
    try {
      await fetch(URL, { redirect: "manual" });
      return true;
    } catch {
      await new Promise((r) => setTimeout(r, 1000));
    }
  }
  return false;
}

// Same work as the online "*/30 * * * *" trigger; prices are pulled on the full hour.
async function scheduled() {
  const now = new Date();
  now.setSeconds(0, 0);
  try {
    const res = await fetch(`${URL}/__scheduled?cron=${encodeURIComponent("*/30 * * * *")}&time=${now.getTime()}`);
    console.log(`[sync] ${now.toLocaleTimeString()} ütemezett frissítés: HTTP ${res.status}`);
  } catch (e) {
    console.log(`[sync] sikertelen: ${e.message}`);
  }
}

function scheduleEvery30() {
  const now = new Date();
  const next = new Date(now);
  next.setMinutes(now.getMinutes() < 30 ? 30 : 60, 0, 0);
  setTimeout(() => {
    scheduled();
    scheduleEvery30();
  }, next.getTime() - now.getTime());
}

run("app", [
  join(root, "node_modules", "wrangler", "bin", "wrangler.js"),
  "dev", "--ip", "127.0.0.1", "--port", PORT, "--test-scheduled", "--var", "LOCAL_DEV:1",
]);

if (!(await waitForServer())) {
  console.log("A helyi szerver nem indult el 2 perc alatt.");
  stopAll();
}
console.log(`\nWoW Assistant fut: ${URL}\n`);

// Locally the worker has no UPLOAD_TOKEN, so the uploader must not send one.
run("feltöltő", [join(root, "scripts", "uploader.mjs")], { APP_URL: URL, UPLOAD_TOKEN: "" });

await scheduled();
scheduleEvery30();
