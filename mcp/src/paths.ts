// Finds accounts, characters and data files inside a WoW flavor folder.
//   WTF/Account/<account>/SavedVariables/<Addon>.lua                       account-wide
//   WTF/Account/<account>/<regionId>/<Name-Realm>/SavedVariables/...        WoW Forever
//   WTF/Account/<account>/<Realm>/<Name>/SavedVariables/...                 Retail layout
import { existsSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

export interface CharacterDir {
  account: string;
  name: string;
  realm: string;
  key: string; // "Name-Realm"
  svDir: string;
}

const dirs = (p: string): string[] =>
  existsSync(p) ? readdirSync(p).filter((d) => statSync(join(p, d)).isDirectory()) : [];

export function accountDirs(wowDir: string): { account: string; dir: string }[] {
  const base = join(wowDir, "WTF", "Account");
  return dirs(base)
    .filter((a) => a !== "SavedVariables")
    .map((account) => ({ account, dir: join(base, account) }));
}

export function characterDirs(wowDir: string): CharacterDir[] {
  const out: CharacterDir[] = [];
  for (const { account, dir } of accountDirs(wowDir)) {
    for (const level1 of dirs(dir)) {
      if (level1 === "SavedVariables") continue;
      for (const level2 of dirs(join(dir, level1))) {
        const svDir = join(dir, level1, level2, "SavedVariables");
        if (!existsSync(svDir)) continue;
        const dash = level2.lastIndexOf("-");
        // Forever: "<regionId>/<Name-Realm>"; Retail: "<Realm>/<Name>".
        const [name, realm] = dash > 0 ? [level2.slice(0, dash), level2.slice(dash + 1)] : [level2, level1];
        out.push({ account, name, realm, key: `${name}-${realm}`, svDir });
      }
    }
  }
  return out;
}

export function accountSavedVariables(wowDir: string, addon: string): { account: string; file: string }[] {
  return accountDirs(wowDir)
    .map(({ account, dir }) => ({ account, file: join(dir, "SavedVariables", `${addon}.lua`) }))
    .filter((x) => existsSync(x.file));
}

export function combatLogFiles(wowDir: string): string[] {
  const dir = join(wowDir, "Logs");
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((f) => /^WoWCombatLog.*\.txt$/i.test(f))
    .map((f) => join(dir, f))
    .sort((a, b) => statSync(a).mtimeMs - statSync(b).mtimeMs);
}

export function addonsDir(wowDir: string): string {
  return join(wowDir, "Interface", "AddOns");
}
