## 2.6.0

Hunter: új **Pet** oldal, lőszerár, és a Harc oldal hunterre szabva.

- Pet oldal (`/wa pet`):
  - a petedet olvassa: család, szint, training point, boldogság, ismert rangok
  - mit taníts neki: a következő rang, mennyi training point, és ha még nem tudod tanítani, melyik állatot szelídítsd meg érte (hol, hányas szinten)
  - a legjobb sebző és tank pet a szintedhez: a család szorzója × a támadási sebesség (a Forever gyors állatai, például a Broken Tooth 1.0 mp-cel)
  - családok: sebzés, páncél, élet, mit eszik, mire jó, milyen képességeket tanulhat
  - bestiárium: mind a 666 szelídíthető állat a Wowhead Forever adataiból, kereshetően (név, család, zóna, képesség)
  - képességek rangonként: pet-szint, training point, mit csinál
- Lőszer:
  - a kereskedőnél látott árat megjegyzi (különben AH-ár vagy becslés)
  - 200 darab ára és egy óra folyamatos harc lőszerköltsége a Haditervben
- Harc oldal hunterrel:
  - a pet sebzése mostantól a tiéd (harcnapló és játékban rögzített harc is), "Pet: …" sorokkal
  - pontszám hunternek: DPS a várthoz képest, Auto Shot folyamatossága, a pet része, távolság, Serpent Sting, lövések percenként
  - hunter összesítő: honnan jön a sebzés (távolsági, pet, közelharc, DoT), képességek percenként és használatonként, Auto Shot-, Serpent Sting- és Aspect of the Hawk-uptime
  - hunter tanácsok a rogue-é helyett (gyenge pet, sok közelharc, sok miss, nincs Sting, ritka Arcane Shot)

## 2.5.0

A Haditerv és a Felszerelés oldal mostantól **hunterrel** is működik, 1-től 60-as szintig.

- Hunter sebzésmodell:
  - Auto Shot, lőszer és tegez-gyorsítás
  - Arcane Shot, Multi-Shot és Aimed Shot
  - Raptor Strike és közelharc a pet előtti szinteken
  - a pet és a Serpent Sting
  - a rögzített harcaidból kalibrálva
- Távolsági fegyverek (íj, puska, számszeríj, hajítófegyver), kétkezes fegyverek, mail páncél 40-től.
- Haditerv:
  - hunter trainer-képességek fontosság szerint
  - lőszer-ajánlás a szintedhez
  - tanácsok a harcaid alapján (kevés Auto Shot, sok közelharc, gyenge pet)
- Javítás minden kasztnak:
  - a dungeon-loot hit és crit értékei ratingek voltak, nem százalékok (10 hit rating = 1% hit, 14 crit rating = 1% crit)
  - a gyűrűk, nyakláncok, trinketek és köpenyek eddig kimaradtak az ajánlásokból

## 2.4.0

Az addon új neve **Waystone**.

- Új név és logó: ablakcím, chat-előtag, minimap gomb és az addonlista ikonja.
- Új parancs: `/waystone` (a `/wa` és a `/wowassistant` továbbra is működik).
- A mentett adatok és beállítások megmaradnak.

## 2.3.1

Első nyilvános kiadás.

- `/wa` főablak: terv, harc, felszerelés és szakmák oldal, kereséssel.
- Harci napló a játék saját sebzésmérőjéből, harci pontszámmal.
- Vendor gyártás: melyik gyártott tárgy hozza a legtöbb pénzt egy eladással, a megadott darabszámra,
  az aukciósház élő áraival (minden szakma 10 legjobb receptjére).
- Session sáv (XP, arany, idő) és Azeroth Chronicle napló.
- Minimap gomb.
