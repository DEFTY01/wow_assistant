// Packs the WowAssistant addon (public name: Waystone) into a zip for CurseForge and, with --upload, sends it there.
//
// The release runs from this machine, not from GitHub: Recipes.lua and GameData.lua are generated
// from local data (scripts/build-addon-recipes.mjs) and are not kept in git, so a CI runner could
// not build a complete addon.
//
//   node scripts/release-addon.mjs              zip only: dist/Waystone-<version>.zip
//   node scripts/release-addon.mjs --upload     zip, upload to CurseForge, tag wa-v<version> (local)
//   node scripts/release-addon.mjs --versions   list CurseForge's WoW game versions (to pick ids)
//
// The version comes from "## Version" in WowAssistant.toc. Its suffix sets the release type:
// 2.4.0 = release, 2.4.0-beta1 = beta, 2.4.0-alpha1 = alpha.
// The changelog is the first section of addon/WowAssistant/CHANGELOG.md, which must be this
// version's; without that file, the subjects of the commits touching addon/WowAssistant since
// the last wa-v* tag.
//
// Settings in .uploader.env (not committed) or the environment:
//   CF_API_KEY        CurseForge API token (authors.curseforge.com → My API Tokens)
//   CF_PROJECT_ID     the project's id (shown on the project page, "About Project")
//   CF_GAME_VERSIONS  comma-separated game version ids, from --versions
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";
import { crc32, deflateRawSync } from "node:zlib";

const root = join(import.meta.dirname, "..");
const src = join(root, "addon", "WowAssistant");
const API = "https://wow.curseforge.com/api";

const envFile = join(root, ".uploader.env");
if (existsSync(envFile)) {
  for (const line of readFileSync(envFile, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
}

// Files written on this machine only: the uploader's AH prices and fight log.
const PERSONAL = new Set(["Market.lua", "Fights.lua"]);
// Data the addon cannot work without; generated, so missing ones stop the release.
const REQUIRED = ["Recipes.lua", "GameData.lua", "Enchants.lua"];

function token() {
  const t = process.env.CF_API_KEY;
  if (!t) throw new Error("CF_API_KEY is missing (.uploader.env)");
  return t;
}

async function listVersions() {
  const headers = { "X-Api-Token": token() };
  const [types, versions] = await Promise.all([
    fetch(`${API}/game/version-types`, { headers }).then((r) => r.json()),
    fetch(`${API}/game/versions`, { headers }).then((r) => r.json()),
  ]);
  const typeName = new Map(types.map((t) => [t.id, t.name]));
  const rows = versions
    .map((v) => ({ id: v.id, name: v.name, type: typeName.get(v.gameVersionTypeID) ?? v.gameVersionTypeID }))
    .sort((a, b) => String(a.type).localeCompare(String(b.type)) || b.id - a.id);
  for (const r of rows) console.log(`${String(r.id).padStart(6)}  ${r.name.padEnd(12)} ${r.type}`);
  console.log("\nPut the ids of the versions this addon runs on into CF_GAME_VERSIONS (comma-separated).");
}

function files(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) out.push(...files(full));
    else out.push(full);
  }
  return out;
}

// A plain zip (deflate), with the addon folder at its root as the game and CurseForge expect.
function zip(entries) {
  const locals = [], centrals = [];
  let offset = 0;
  for (const { name, data } of entries) {
    const nameBuf = Buffer.from(name, "utf8");
    const packed = deflateRawSync(data, { level: 9 });
    const crc = crc32(data);
    const head = Buffer.alloc(30);
    head.writeUInt32LE(0x04034b50, 0);
    head.writeUInt16LE(20, 4);
    head.writeUInt16LE(0x0800, 6); // names are UTF-8
    head.writeUInt16LE(8, 8);
    head.writeUInt32LE(0x00210000, 10); // 1980-01-01, fixed so the same files give the same zip
    head.writeUInt32LE(crc, 14);
    head.writeUInt32LE(packed.length, 18);
    head.writeUInt32LE(data.length, 22);
    head.writeUInt16LE(nameBuf.length, 26);
    locals.push(head, nameBuf, packed);
    const cen = Buffer.alloc(46);
    cen.writeUInt32LE(0x02014b50, 0);
    cen.writeUInt16LE(20, 4);
    cen.writeUInt16LE(20, 6);
    cen.writeUInt16LE(0x0800, 8);
    cen.writeUInt16LE(8, 10);
    cen.writeUInt32LE(0x00210000, 12);
    cen.writeUInt32LE(crc, 16);
    cen.writeUInt32LE(packed.length, 20);
    cen.writeUInt32LE(data.length, 24);
    cen.writeUInt16LE(nameBuf.length, 28);
    cen.writeUInt32LE(offset, 42);
    centrals.push(cen, nameBuf);
    offset += head.length + nameBuf.length + packed.length;
  }
  const central = Buffer.concat(centrals);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(central.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, central, end]);
}

function git(...args) {
  return execFileSync("git", args, { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
}

function changelog(version) {
  const own = join(src, "CHANGELOG.md");
  if (existsSync(own)) {
    const text = readFileSync(own, "utf8");
    const first = text.split(/\n(?=## )/).find((s) => s.startsWith("## "));
    const title = first ? first.split("\n")[0] : "";
    if (first && !title.includes(version)) {
      throw new Error(`CHANGELOG.md starts with "${title}", not ${version}: add this version's section`);
    }
    if (first) return first.trim();
  }
  let since = "";
  try { since = git("describe", "--tags", "--abbrev=0", "--match", "wa-v*"); } catch {}
  const range = since ? [`${since}..HEAD`] : ["-n", "20"];
  const subjects = git("log", ...range, "--format=%s", "--", "addon/WowAssistant")
    .split("\n").filter(Boolean)
    .map((s) => s.replace(/^WowAssistant[^:]*:\s*/, ""));
  return `## Waystone ${version}\n\n` + (subjects.length ? subjects.map((s) => `- ${s}`).join("\n") : "- maintenance");
}

async function upload(file, name, version, log) {
  const project = process.env.CF_PROJECT_ID;
  const versions = (process.env.CF_GAME_VERSIONS ?? "").split(",").map((s) => Number(s.trim())).filter(Boolean);
  if (!project) throw new Error("CF_PROJECT_ID is missing (.uploader.env)");
  if (!versions.length) throw new Error("CF_GAME_VERSIONS is missing: run with --versions and pick the ids");
  const releaseType = /alpha/i.test(version) ? "alpha" : /beta/i.test(version) ? "beta" : "release";
  const form = new FormData();
  form.append("metadata", JSON.stringify({
    changelog: log, changelogType: "markdown", displayName: `Waystone ${version}`,
    gameVersions: versions, releaseType,
  }));
  form.append("file", new Blob([readFileSync(file)], { type: "application/zip" }), name);
  const res = await fetch(`${API}/projects/${project}/upload-file`, {
    method: "POST", headers: { "X-Api-Token": token() }, body: form,
  });
  const body = await res.text();
  if (!res.ok) throw new Error(`CurseForge refused the upload (${res.status}): ${body}`);
  console.log(`Uploaded as ${releaseType}: file id ${JSON.parse(body).id}`);
}

async function main() {
  const args = new Set(process.argv.slice(2));
  if (args.has("--versions")) return listVersions();

  const toc = readFileSync(join(src, "WowAssistant.toc"), "utf8");
  const version = toc.match(/^## Version:\s*(\S+)/m)?.[1];
  if (!version) throw new Error("no ## Version in WowAssistant.toc");
  for (const f of REQUIRED) {
    if (!existsSync(join(src, f))) throw new Error(`${f} is missing: run npm run addon:recipes first`);
  }
  if (args.has("--upload") && git("status", "--porcelain", "--", "addon/WowAssistant")) {
    throw new Error("addon/WowAssistant has uncommitted changes: commit them before a release");
  }

  const entries = files(src)
    .map((full) => ({ rel: relative(src, full).split("\\").join("/"), full }))
    .filter(({ rel }) => !PERSONAL.has(rel))
    .sort((a, b) => a.rel.localeCompare(b.rel))
    .map(({ rel, full }) => ({ name: `WowAssistant/${rel}`, data: readFileSync(full) }));

  mkdirSync(join(root, "dist"), { recursive: true });
  const name = `Waystone-${version}.zip`; // the folder inside stays WowAssistant (saved data, uploader)
  const file = join(root, "dist", name);
  writeFileSync(file, zip(entries));
  const log = changelog(version);
  console.log(`${relative(root, file)}: ${entries.length} files, ${(statSync(file).size / 1024).toFixed(0)} KB`);
  console.log(log);

  if (!args.has("--upload")) {
    console.log("\nZip only. Run with --upload to send it to CurseForge.");
    return;
  }
  await upload(file, name, version, log);
  try {
    git("tag", `wa-v${version}`);
    console.log(`Tagged wa-v${version} (push it with: git push origin wa-v${version})`);
  } catch {
    console.log(`Tag wa-v${version} already exists; not tagged again.`);
  }
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
