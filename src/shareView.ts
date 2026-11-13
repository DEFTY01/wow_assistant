import { html } from "hono/html";
import { type Html, page } from "./layout";
import type { Character } from "./share";

const CLASS: Record<number, string> = {
  1: "Warrior", 2: "Paladin", 3: "Hunter", 4: "Rogue", 5: "Priest", 7: "Shaman", 8: "Mage", 9: "Warlock", 11: "Druid",
};

/** Public page where an invited player registers a character. */
export function joinPage(opts: { code: string; valid: boolean; error?: string; name?: string }): Html {
  return page({
    title: "Csatlakozás",
    active: null,
    body: html`<section class="wide" style="max-width:640px;margin:0 auto">
      <h2>Csatlakozás a saját karaktereddel</h2>
      ${opts.valid
        ? html`<p>Írd be a WoW: Forever karaktered teljes nevét. Az oldal a Blizzard nyilvános API-jából kéri le a
            felszerelésedet, a talentjeidet és a mesterségeidet, és ebből készít neked saját tervet.</p>
          ${opts.error ? html`<p class="err">${opts.error}</p>` : ""}
          <form method="post" action="/u/join" class="gold" style="margin-top:14px">
            <input type="hidden" name="code" value="${opts.code}">
            <label for="name">Karakter</label>
            <input id="name" name="name" required placeholder="Keresztnév Vezetéknév" value="${opts.name ?? ""}" style="width:260px">
            <button>Mehet</button>
          </form>
          <h3>Mit kell tudnod</h3>
          <p class="muted">• A karakternek legalább 10-es szintűnek kell lennie, és egyszer ki kell jelentkezned vele, hogy az API lássa.</p>
          <p class="muted">• A kapott link a jelszavad: aki ismeri, látja és módosíthatja a karaktered oldalát. Ne tedd ki nyilvánosan.</p>
          <p class="muted">• A sebzésmodell egyelőre csak rogue karakterre készült el. Más kaszttal a karakterlap, a mesterség-útvonal
            és a harcnapló működik, a felszerelés-ajánló nem.</p>
          <p class="muted">• Az aukciós árak az EU Normal ruleset Horde aukciósházából származnak.</p>`
        : html`<p class="err">Ez a meghívó link nem érvényes. Kérj újat attól, akitől kaptad.</p>`}
    </section>`,
  });
}

/** Owner-only panel: the invite link and who has joined. */
export function sharePanel(opts: { origin: string; code: string; characters: Character[] }): Html {
  const invite = `${opts.origin}/u/join?code=${opts.code}`;
  const guests = opts.characters.filter((c) => !c.is_owner);
  return html`<section class="wide"><h2>Megosztás <span class="muted">mások a saját karakterükkel</span></h2>
    <p>Ezt a meghívó linket küldd el annak, akit be akarsz engedni. A saját karakterét regisztrálja vele, és kap egy saját, titkos linket.</p>
    <p><code style="user-select:all;word-break:break-all">${invite}</code></p>
    <p class="muted">Ahhoz, hogy a link az Access mögül elérhető legyen, a Cloudflare Zero Trust felületen kell még egy
      <b>Bypass</b> alkalmazás a <code>wow.mucsibence.hu/u</code> útvonalra, ugyanúgy, ahogy a feltöltő útvonalaknál csináltad.
      A megosztott oldalakat a linkben lévő titkos kulcs védi; a te oldalaid továbbra is csak neked nyílnak meg.</p>
    ${guests.length
      ? html`<table><thead><tr><th>Karakter</th><th>Kaszt</th><th class="num">Szint</th><th>Utolsó szinkron</th><th>Saját link</th><th></th></tr></thead><tbody>
          ${guests.map(
            (c) => html`<tr><td><b>${c.name ?? c.slug}</b></td><td class="muted">${CLASS[c.class_id ?? 0] ?? "?"}</td>
              <td class="num">${c.level ?? ""}</td><td class="muted">${c.last_sync ? new Date(c.last_sync).toLocaleString("hu-HU", { timeZone: "Europe/Budapest" }) : "még nem volt"}</td>
              <td><a href="/u/${c.share_key}/">megnyitás</a></td>
              <td><form method="post" action="/share/remove" style="margin:0"><input type="hidden" name="slug" value="${c.slug}">
                <button title="A karakter és minden adata törlődik">Törlés</button></form></td></tr>`,
          )}
        </tbody></table>`
      : html`<p class="muted">Még senki nem csatlakozott.</p>`}
  </section>`;
}

/** Shown to a shared user on their character page: how to connect the addon and uploader. */
export function setupPanel(opts: { origin: string; key: string; name: string }): Html {
  return html`<section class="wide"><h2>Addon és feltöltő <span class="muted">a gold, a táskák, a trainer és a harcok miatt</span></h2>
    <p>Az addon nélkül is működik a karakterlap és a mesterség-útvonal. A vásárlási tervhez (gold, táskák, bank, trainer skillek)
      és a harcelemzéshez az addon és a feltöltő script kell, amit attól kapsz, aki meghívott.</p>
    <p>A feltöltő <code>.uploader.env</code> fájljába ez kerüljön:</p>
    <pre style="user-select:all">APP_URL=${opts.origin}
UPLOAD_TOKEN=${opts.key}
WOW_CHARACTER=${opts.name}
WOW_DIR=C:/Program Files (x86)/World of Warcraft/_forever_</pre>
    <p class="muted">A <code>WOW_DIR</code> a játékod mappája legyen. A játékban: <code>/wa log</code> bekapcsolja a harcnaplót,
      <code>/wa save</code> kiírja az adatokat.</p>
  </section>`;
}
