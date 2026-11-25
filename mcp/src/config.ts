// Settings come from environment variables, then `.mcp.env`, then the uploader's `.uploader.env`
// (both KEY=VALUE files in the repository root, not committed).
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

function loadEnvFile(file: string): void {
  if (!existsSync(file)) return;
  for (const line of readFileSync(file, "utf8").split(/\r?\n/)) {
    const m = /^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2];
  }
}

export interface Config {
  wowDir: string; // flavor folder, e.g. F:/World of Warcraft/_forever_
  dataDir: string; // where the SQLite database and logs live
  dbPath: string;
  maskOtherPlayers: boolean;
  logGapSeconds: number;
}

export function loadConfig(): Config {
  loadEnvFile(join(REPO_ROOT, ".mcp.env"));
  loadEnvFile(join(REPO_ROOT, ".uploader.env"));
  const appData = process.env.APPDATA ?? join(homedir(), ".local", "share");
  const dataDir = resolve(
    (process.env.MCP_DATA_DIR ?? join(appData, "azeroth-mcp")).replace(/%APPDATA%/gi, appData),
  );
  return {
    wowDir: resolve(process.env.WOW_DIR ?? "F:/World of Warcraft/_forever_"),
    dataDir,
    dbPath: join(dataDir, "azeroth.sqlite"),
    maskOtherPlayers: process.env.MASK_OTHER_PLAYERS === "1",
    logGapSeconds: Number(process.env.LOG_GAP_SECONDS ?? 8),
  };
}

/** Throws unless `target` is inside one of the allowed roots (guards against path traversal). */
export function assertInside(target: string, ...roots: string[]): string {
  const full = resolve(target);
  const ok = roots.some((r) => {
    const rel = relative(resolve(r), full);
    return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
  });
  if (!ok) throw new Error(`Path outside the allowed folders: ${full}`);
  return full;
}
