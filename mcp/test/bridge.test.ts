// End-to-end tests on a generated fake WoW folder: ingest, MCP tools over an in-memory transport,
// write-back safety. Run: npm test (in mcp/).
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, describe, it } from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import type { Config } from "../src/config.ts";
import { assertInside } from "../src/config.ts";
import { openDb } from "../src/db.ts";
import { ingestAll } from "../src/ingest/index.ts";
import { splitCsv } from "../src/ingest/combatLog.ts";
import { parseSavedVariables, toLua } from "../src/lua.ts";
import { createServer, weekKey, weekStart } from "../src/server.ts";

const root = mkdtempSync(join(tmpdir(), "azeroth-test-"));
const wow = join(root, "_forever_");
const cfg: Config = { wowDir: wow, dataDir: join(root, "data"), dbPath: join(root, "data", "t.sqlite"), maskOtherPlayers: false, logGapSeconds: 8 };
const now = Math.floor(Date.now() / 1000);
const wk = weekKey(now);
const ws = weekStart(wk);

// --- combat log line builders (COMBAT_LOG_VERSION 22 layout) ---
const stamp = (d: Date) =>
  `${d.getMonth() + 1}/${d.getDate()}/${d.getFullYear()} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}:${String(d.getSeconds()).padStart(2, "0")}.0001`;
const ME = ["Player-1-0001", '"Testy-Realm-Normal-EU"', "0x511", "0x0"];
const MOB = ["Creature-0-1-2-3-4-5", '"Angry Boar"', "0xa48", "0x0"];
const adv = Array(19).fill("0");
const line = (t: Date, fields: string[]) => `${stamp(t)}  ${fields.join(",")}`;
function spellDamage(t: Date, src: string[], dst: string[], spell: string, amount: number) {
  return line(t, ["SPELL_DAMAGE", ...src, ...dst, "1752", `"${spell}"`, "0x1", ...adv, String(amount), String(amount), "-1", "1", "0", "0", "0", "nil", "nil", "nil"]);
}

before(() => {
  const acc = join(wow, "WTF", "Account", "ACC");
  mkdirSync(join(acc, "SavedVariables"), { recursive: true });
  mkdirSync(join(acc, "93", "Testy-Realm", "SavedVariables"), { recursive: true });
  mkdirSync(join(wow, "Logs"), { recursive: true });
  mkdirSync(join(wow, "Interface", "AddOns", "AzerothMCP_Data"), { recursive: true });
  writeFileSync(join(wow, "Interface", "AddOns", "AzerothMCP_Data", "AzerothMCP_Data.toc"), "## Interface: 16001\n## Title: Inbox\n");
  mkdirSync(join(wow, "Interface", "AddOns", "OldAddon"), { recursive: true });
  writeFileSync(join(wow, "Interface", "AddOns", "OldAddon", "OldAddon.toc"), "## Interface: 11507\n## Title: Old\n");

  const snap = (ts: number, level: number, cxp: number, money: number, quests: number) => ({ ts, level, xp: 10, xpMax: 1000, money, cxp, deaths: 0, quests, skills: 100, zone: "Elwynn" });
  writeFileSync(join(acc, "SavedVariables", "AzerothChronicle.lua"), "AzerothChronicleDB = " + toLua({
    version: 1, share: true,
    chars: { "Testy-Realm": { class: "ROGUE", guild: "Test Guild", counters: { xp: 5000, deaths: 0, quests: 7 },
      snapshots: [snap(ws - 86400, 10, 1000, 5000, 2), snap(ws + 3600, 11, 3000, 9000, 5), snap(now, 12, 5000, 15000, 7)] } },
    guild: { "Test Guild": { [String(wk)]: {
      "Testy-Realm": { ts: now, class: "ROGUE", level: 12, xp: 4000, money: 10000, levels: 2, skills: 0, quests: 5, deaths: 0 },
      "Other-Realm": { ts: now, class: "MAGE", level: 20, xp: 9000, money: -500, levels: 1, skills: 3, quests: 9, deaths: 2 },
    } } },
  }) + "\n");
  writeFileSync(join(acc, "93", "Testy-Realm", "SavedVariables", "SessionBar.lua"), "SessionBarCharDB = " + toLua({
    history: [{ start: now - 7200, duration: 3600, xp: 1200, levels: 0, income: { loot: 500 }, expense: { repair: 100 } }],
    current: { start: now - 600, last: now, xp: 300, levels: 0, income: { quest: 50 }, expense: {} },
  }) + "\n");

  const t0 = new Date(Date.now() - 3600_000);
  const at = (s: number) => new Date(t0.getTime() + s * 1000);
  const lines = [
    line(at(0), ["COMBAT_LOG_VERSION", "22", "ADVANCED_LOG_ENABLED", "1", "BUILD_VERSION", "1.60.1", "PROJECT_ID", "18"]),
    line(at(0), ["ZONE_CHANGE", "1", '"Elwynn Forest"', "0"]),
    spellDamage(at(1), ME, MOB, "Sinister Strike", 120),
    spellDamage(at(3), MOB, ME, "Gore", 300),
    spellDamage(at(5), ME, MOB, "Eviscerate", 400),
    // 30 s later: a new fight that kills the player
    spellDamage(at(40), MOB, ME, "Gore", 500),
    spellDamage(at(42), MOB, ME, "Gore", 600),
    line(at(43), ["UNIT_DIED", "0000000000000000", "nil", "0x80000000", "0x80000000", ...ME, "0"]),
    line(at(60), ["ENCOUNTER_START", "2748", '"Rethilgore"', "1", "5", "33"]),
    spellDamage(at(61), ME, MOB, "Backstab", 900),
    line(at(70), ["ENCOUNTER_END", "2748", '"Rethilgore"', "1", "5", "1", "9000"]),
    line(at(200), ["ZONE_CHANGE", "2", '"Stormwind"', "0"]),
  ];
  writeFileSync(join(wow, "Logs", "WoWCombatLog-112526_100000.txt"), lines.join("\n") + "\n");
});

const openDbs: { close(): void }[] = [];
after(() => {
  for (const d of openDbs) d.close();
  rmSync(root, { recursive: true, force: true });
});

describe("lua", () => {
  it("round-trips values through toLua and the repository parser", () => {
    const v = { a: 1, b: "x\"y\\z\nő", list: [1, 2, { c: true }], "weird key": -2.5 };
    assert.deepEqual(parseSavedVariables("X = " + toLua(v)).X, v);
  });
});

describe("combat log", () => {
  it("keeps quoted commas and bracket groups in one field", () => {
    assert.deepEqual(splitCsv('A,"b,c",[1,(2,3)],d'), ["A", "b,c", "[1,(2,3)]", "d"]);
  });
});

describe("paths", () => {
  it("rejects paths outside the allowed root", () => {
    assert.throws(() => assertInside(join(root, "..", "evil.lua"), root));
    assert.equal(assertInside(join(root, "a", "b.lua"), root), join(root, "a", "b.lua"));
  });
});

describe("ingest + MCP tools", () => {
  let client: Client;
  const call = async (name: string, args: Record<string, unknown> = {}) => {
    const r = (await client.callTool({ name, arguments: args })) as { content: { text: string }[]; isError?: boolean };
    return { error: !!r.isError, text: r.content[0].text, json: () => JSON.parse(r.content[0].text) };
  };

  before(async () => {
    const db = openDb(cfg.dbPath);
    openDbs.push(db);
    const r = ingestAll(db, cfg, { final: true });
    assert.equal(r.savedVariables.errors.length, 0, r.savedVariables.errors.join("\n"));
    assert.equal(r.combatLogs.errors.length, 0, r.combatLogs.errors.join("\n"));
    const server = createServer(db, cfg);
    const [a, b] = InMemoryTransport.createLinkedPair();
    client = new Client({ name: "test", version: "1" });
    await Promise.all([server.connect(a), client.connect(b)]);
  });

  it("is idempotent", () => {
    const db = openDb(cfg.dbPath);
    const r = ingestAll(db, cfg, { final: true });
    db.close();
    assert.equal(r.savedVariables.files, 0);
    assert.equal(r.combatLogs.segments, 0);
  });

  it("lists characters with level", async () => {
    const chars = (await call("list_characters")).json();
    const t = chars.find((c: { key: string }) => c.key === "Testy-Realm");
    assert.equal(t.level, 12);
    assert.equal(t.guild, "Test Guild");
  });

  it("computes weekly gains from snapshots", async () => {
    const w = (await call("get_week_summary", { weeks_ago: 0 })).json();
    const t = w.characters.find((c: { character: string }) => c.character === "Testy-Realm");
    assert.equal(t.xp, 4000); // 5000 now - 1000 at week start
    assert.equal(t.money, 10000);
    assert.equal(t.quests, 5);
  });

  it("builds a timeline with total gain", async () => {
    const r = (await call("get_progress_timeline", { metric: "level", character: "Testy", from: ws - 2 * 86400 })).json();
    assert.equal(r.totalGain, 2);
    assert.ok(r.series.length >= 2);
  });

  it("reads sessions with per-hour rates", async () => {
    const s = (await call("list_sessions", { character: "Testy-Realm" })).json();
    assert.equal(s.length, 2);
    const hist = s.find((x: { is_current: number }) => x.is_current === 0);
    assert.equal(hist.xp_per_hour, 1200);
    assert.equal(hist.income_by_category.loot, 500);
  });

  it("splits fights and records the death recap", async () => {
    const segs = (await call("list_combat_segments")).json();
    assert.equal(segs.length, 3);
    const boss = segs.find((s: { kind: string }) => s.kind === "encounter");
    assert.equal(boss.name, "Rethilgore");
    assert.equal(boss.success, 1);
    const deaths = (await call("get_deaths", { player: "Testy" })).json();
    assert.equal(deaths.length, 1);
    assert.equal(deaths[0].killer, "Angry Boar: Gore");
    assert.equal(deaths[0].recap.length, 2);
    const sum = (await call("get_segment_summary", { segment_id: segs[segs.length - 1].id })).json();
    assert.equal(sum.units[0].name, "Testy-Realm");
    assert.equal(sum.units[0].damage_done, 520);
  });

  it("ranks the guild leaderboard", async () => {
    const xp = (await call("get_guild_leaderboard", { category: "xp" })).json();
    assert.equal(xp.standings[0].member, "Other-Realm");
    const survivor = (await call("get_guild_leaderboard", { category: "survivor" })).json();
    assert.deepEqual(survivor.standings.map((s: { member: string }) => s.member), ["Testy-Realm"]);
  });

  it("only allows read-only SQL", async () => {
    assert.equal((await call("query_sql", { sql: "SELECT COUNT(*) AS n FROM segments" })).json().rows[0].n, 3);
    assert.ok((await call("query_sql", { sql: "DELETE FROM segments" })).error);
    assert.ok((await call("query_sql", { sql: "SELECT 1; DROP TABLE segments" })).error);
    assert.ok((await call("query_sql", { sql: "WITH x AS (SELECT 1) INSERT INTO deaths(segment_id) SELECT 1" })).error);
  });

  it("reads SavedVariables subtrees", async () => {
    const r = (await call("read_saved_variables", { addon: "AzerothChronicle", path: "AzerothChronicleDB.chars.Testy-Realm.counters" })).json();
    assert.deepEqual(r.value, { xp: 5000, deaths: 0, quests: 7 });
    assert.ok((await call("read_saved_variables", { addon: "../../evil" })).error);
  });

  it("flags out-of-date addons", async () => {
    const r = (await call("list_addons")).json();
    assert.equal(r.addons.find((a: { folder: string }) => a.folder === "OldAddon").outOfDate, true);
    assert.equal(r.addons.find((a: { folder: string }) => a.folder === "AzerothMCP_Data").outOfDate, false);
  });

  it("writes only the inbox file, as Lua literals", async () => {
    const r = await call("write_ingame_inbox", { goals: [{ title: "Szint 20", text: 'Érd el a "20"-as szintet' }] });
    assert.ok(!r.error, r.text);
    const src = readFileSync(join(wow, "Interface", "AddOns", "AzerothMCP_Data", "Data.lua"), "utf8");
    const inbox = parseSavedVariables(src).AzerothMCP_Inbox as { goals: { text: string }[] };
    assert.equal(inbox.goals[0].text, 'Érd el a "20"-as szintet');
  });

  it("serves the schema resource and prompts", async () => {
    const res = await client.readResource({ uri: "wow://schema" });
    assert.match(String((res.contents[0] as { text: string }).text), /CREATE TABLE segments/);
    const prompts = await client.listPrompts();
    assert.ok(prompts.prompts.some((p) => p.name === "guild_chronicle"));
  });
});
