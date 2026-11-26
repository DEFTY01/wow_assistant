## 2.8.0

Harc oldal: minden számnál látszik, miből jött és milyen fajta szám.

- Új "Honnan a számok" táblázat a kiválasztott harchoz: saját sebzés, pet sebzése, időtartam, DPS (saját + pet és pet nélkül), várt DPS, mért/várt arány, adatforrás
  - mindegyiknél az állapot: **mért** (harcnaplóból vagy a játék damage meteréből), **becsült** (óra szerinti hossz, a célpont ütései, nem igazolt pet), **szimulált** (a Waystone saját modellje), **nem értékelhető** (ilyenkor "–", nem 0)
  - és hogy miből számolta: melyik forrás, melyik képlet, mi hiányzik
- A harcnapló mostantól effektív sebzést számol: a túlsebzés (overkill) a gyilkos ütésből levonva
- A pet csak akkor a tiéd, ha a harcnapló jelzői szerint a tiéd (név alapján nem párosít); a damage meter pet-sora "részleges", ha közben újrahívtad
- A várt DPS-hez csak azonos szinten (és ha a harc rögzítette, azonos felszereléssel) hasonlít; másképp a pontszám DPS-része és az arány kimarad
- A játékban rögzített harc megjegyzi a felszerelést és a damage meter sessionjét; ugyanannak a sessionnek a későbbi frissítése nem ad hozzá új harcot
- WoWSims-referencia: nincs bekötve, és 60 alatt a Forever motor nem is ad szintazonos referenciát; a táblázat ezt "nem értékelhető"-ként mutatja

## 2.7.0

Shaman: a Haditerv, a Felszerelés és a Harc oldal mostantól shamannal is működik (1–60).

- Sebzésmodell (enhancement szintezés):
  - közelharc egy fegyverrel (kétkezes, vagy egykezes + pajzs), a fegyver-imbue szorzójával: Rockbiter, 10-től Flametongue, 30-tól Windfury (lassú kétkezesen a legjobb)
  - Earth Shock és Lightning Bolt rangonként, spell powerrel (a 20. szint előtti rangok kisebb együtthatóval)
  - Searing Totem, Stormstrike (40-től, talenttel), Flurry, Thundering Strikes, Elemental Fury
  - mindent a rögzített harcaidhoz igazít: ütések aránya, dodge, shock és Lightning Bolt percenként, az imbue és a totem sebzése
- Felszerelés:
  - shamannak való tárgyak: bot, buzogány, balta, ököl, tőr, pajzs; mail 40-től
  - a kétkezes balta és buzogány csak a Two-Handed Axes and Maces talenttel (a talentek beolvasása után)
  - strength, agility, intellect és spell power a tárgyakon (a Forever "+spell damage" tárgyai is)
- Haditerv: shaman trainer képességek (Earth Shock, Lightning Shield, imbue-k, totemek, Ghost Wolf), mi az alap és mi kihagyható
- Harc oldal shamannal:
  - pontszám: DPS a várthoz képest, ütések folyamatossága, shock percenként, totem a hosszú harcban, Stormstrike cooldownra
  - shaman összesítő: közelharc, imbue, varázslat, totem és DoT része, ütések aránya, shock percenként, Lightning Shield uptime
  - shaman tanácsok (sok castolás, ritka shock, nincs totem vagy Windfury, Lightning Shield)

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
