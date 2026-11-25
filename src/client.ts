import { html } from "hono/html";
import chronicleShim from "../addon/AzerothChronicle/Shim.lua";
import chronicleToc from "../addon/AzerothChronicle/AzerothChronicle.toc";
import sessionShim from "../addon/SessionBar/Shim.lua";
import sessionToc from "../addon/SessionBar/SessionBar.toc";
import chronicle from "../addon/WowAssistant/Chronicle.lua";
import combat from "../addon/WowAssistant/Combat.lua";
import core from "../addon/WowAssistant/Core.lua";
import exporter from "../addon/WowAssistant/Exporter.lua";
import game from "../addon/WowAssistant/Game.lua";
import meter from "../addon/WowAssistant/Meter.lua";
import model from "../addon/WowAssistant/Model.lua";
import plan from "../addon/WowAssistant/Plan.lua";
import routes from "../addon/WowAssistant/Routes.lua";
import session from "../addon/WowAssistant/Session.lua";
import ui from "../addon/WowAssistant/UI.lua";
import vendorCraft from "../addon/WowAssistant/VendorCraft.lua";
import addonToc from "../addon/WowAssistant/WowAssistant.toc";
import { parseCombatLog } from "../scripts/combat-log.mjs";
import { parseSavedVariables } from "../scripts/lua-table.mjs";
import main from "./browserSync.txt";
import type { Html } from "./layout";

/**
 * The script behind the "sync from the browser" panel. The two parsers are the very functions
 * the Node uploader uses: both are self-contained, so their own source can be shipped as is.
 */
export function clientScript(): string {
  // Folder -> files. The generated data files (Recipes.lua, GameData.lua, Fights.lua, Market.lua) are not in the bundle: they are
  // built locally (npm run addon:recipes) and an install here leaves them in place.
  const addon = {
    WowAssistant: {
      "WowAssistant.toc": addonToc, "Core.lua": core, "Exporter.lua": exporter, "VendorCraft.lua": vendorCraft,
      "Session.lua": session, "Chronicle.lua": chronicle, "Model.lua": model, "Combat.lua": combat, "Routes.lua": routes,
      "Plan.lua": plan, "Game.lua": game, "Meter.lua": meter, "UI.lua": ui,
    },
    SessionBar: { "SessionBar.toc": sessionToc, "Shim.lua": sessionShim },
    AzerothChronicle: { "AzerothChronicle.toc": chronicleToc, "Shim.lua": chronicleShim },
  };
  return [
    "(async () => {",
    '"use strict";',
    // The bundler wraps inner functions in a naming helper; give the copied source a stand-in.
    "const __name = (fn) => fn;",
    `const parseSavedVariables = ${parseSavedVariables.toString()};`,
    `const parseCombatLog = ${parseCombatLog.toString()};`,
    `const ADDON = ${JSON.stringify(addon)};`,
    main,
    "})();",
  ].join("\n");
}

/** Panel on the character page. `base` is the shared-link prefix ("" for the owner). */
export function syncPanel(opts: { base: string; character: string }): Html {
  return html`<section class="wide" id="bsync" data-base="${opts.base}" data-character="${opts.character}">
    <h2>Szinkron a böngészőből <span class="muted">telepítés nélkül</span></h2>
    <p>Válaszd ki egyszer a játék mappáját, és ez az oldal maga olvassa ki az addon adatait és a harcnaplót, amíg nyitva van egy fülön.
      A <b>World of Warcraft</b> vagy a benne lévő <b>_forever_</b> mappát add meg.</p>
    <p class="gold">
      <button type="button" data-pick>Játék mappa kiválasztása</button>
      <button type="button" data-grant hidden>Engedély megerősítése</button>
      <button type="button" data-install hidden>Addon telepítése / frissítése</button>
      <button type="button" data-stop hidden>Leállítás</button>
    </p>
    <p data-status class="muted">Még nincs mappa kiválasztva.</p>
    <ul data-log class="synclog"></ul>
    <p class="muted" style="margin-bottom:0">Chrome-ban és Edge-ben működik. A böngésző a fájlokat csak olvassa, írni egyedül az addon
      mappájába ír, és csak akkor, ha a telepítés gombra kattintasz. A játékban: <code>/wa log</code> bekapcsolja a harcnaplót,
      <code>/wa save</code> kiírja a goldot, a táskákat és a trainer adatait.</p>
    <script src="/client.js" defer></script>
  </section>`;
}
