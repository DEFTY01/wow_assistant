import { watch, type FSWatcher } from "node:fs";
import { join } from "node:path";
import type { DatabaseSync } from "node:sqlite";
import type { Config } from "../config.ts";
import { ingestCombatLogs, type LogIngestResult } from "./combatLog.ts";
import { ingestSavedVariables, type SvIngestResult } from "./savedVariables.ts";

export interface IngestResult { savedVariables: SvIngestResult; combatLogs: LogIngestResult; ms: number }

export function ingestAll(db: DatabaseSync, cfg: Config, opts: { force?: boolean; final?: boolean } = {}): IngestResult {
  const t0 = Date.now();
  const savedVariables = ingestSavedVariables(db, cfg, opts.force);
  const combatLogs = ingestCombatLogs(db, cfg, { final: opts.final });
  return { savedVariables, combatLogs, ms: Date.now() - t0 };
}

/** Re-ingests 2 s after the game writes WTF or Logs, and every 2 minutes as a fallback. */
export function startWatcher(db: DatabaseSync, cfg: Config, log: (msg: string) => void): () => void {
  let timer: NodeJS.Timeout | null = null;
  const schedule = () => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => {
      timer = null;
      try {
        const r = ingestAll(db, cfg);
        if (r.savedVariables.files || r.combatLogs.segments) {
          log(`ingest: ${r.savedVariables.files} SavedVariables files, ${r.combatLogs.segments} new fights (${r.ms} ms)`);
        }
      } catch (e) {
        log(`ingest failed: ${(e as Error).message}`);
      }
    }, 2000);
  };
  const watchers: FSWatcher[] = [];
  for (const dir of [join(cfg.wowDir, "WTF", "Account"), join(cfg.wowDir, "Logs")]) {
    try {
      watchers.push(watch(dir, { recursive: true }, (_e, name) => {
        if (!name || /\.(lua|txt)$/i.test(String(name))) schedule();
      }));
    } catch (e) {
      log(`cannot watch ${dir}: ${(e as Error).message}`);
    }
  }
  const interval = setInterval(schedule, 120_000);
  return () => {
    for (const w of watchers) w.close();
    clearInterval(interval);
    if (timer) clearTimeout(timer);
  };
}
