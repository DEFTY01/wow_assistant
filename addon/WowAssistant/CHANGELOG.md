## 2.17.0

Paladin: saját modell, harcoldal és Haditerv. Ezzel mind a kilenc kasztnak van sebzésmodellje.

- A paladinnak saját sebzésmodellje van (Paladin.lua), a Wowhead Forever adatai alapján:
  - fehér ütések, 1 strength = 2 AP, az agility critet ad, egy fegyver (a paladin nem forgat két fegyvert);
  - Holy Strike (a Forever saját paladin-ütése, 10 mp cooldown): a fegyver sebzésének 25–50%-a + rangonként fix holy sebzés (6-os szinten 11–14, 60-ason 97–121) + a spell power 0,429-e;
  - Seal of Righteousness: holy sebzés minden ütésre, rangonként a tooltip képletéből (R/87–R/25 + a spell power 7,65–12%-a), a harcaid pontosítják;
  - Seal of Command (Retribution talent): az ütés 70%-a holy sebzésként esélyre; a Wowhead nem mutat proc-gyakoriságot, ezért a harcaidban mért arányt használja;
  - Judgement, Consecration, Exorcism és a Retribution Aura a harcaidból mérve;
  - szövet, bőr, mail, pajzs, és 40-től plate; fejsze, buzogány, kard, polearm.
- Harcoldal paladinnak:
  - pontszám: DPS a várthoz képest, folyamatos ütés, Holy Strike a cooldownjához képest (a harc hosszába hány fér), kárba ment manaital;
  - "Paladin összesítő": fehér ütés, Holy Strike, seal, Judgement és a többi aránya; miss, dodge, crit; Holy Strike percenként.
- Tanácsok paladinnak: a teli manánál ivott manaital hiba, ha a harcnapló igazolja; ha sok fehér ütés mellett egyik sebző seal sem sebez, az megfigyelés (az aura-eseményeket az addon nem rögzíti, így nem tudni, melyik seal volt fent).
- Holy talentfán a gyógyító, Protection talentfán a tank súlyok maradnak az enchant részben.
- Haditerv: a paladin trainer képességei fontosság szerint.

## 2.16.0

Priest: saját modell, harcoldal és Haditerv.

- A priestnek saját sebzésmodellje van (Priest.lua), a Wowhead Forever adatai alapján:
  - Smite, Mind Blast (8 mp cooldown), Shadow Word: Pain (18 mp, 3 mp-enként tick), Mind Flay (3 mp csatornázás, másodpercenként tick) és Holy Fire (direkt + DoT), rangonként a Forever tooltipjeiből;
  - a spell power együtthatók a Wowhead Forever Spell Details táblájából: Smite cast idő / 3,5 (0,429–0,714), Mind Blast 0,429, Shadow Word: Pain tickenként 0,2, Mind Flay tickenként 0,167, Holy Fire 0,75 és tickenként 0,05;
  - a harcnapló szerint Foreveren a DoT-tickek is critelnek (Shadow Word: Pain, Holy Fire), ezért a modell a tickekre is számol critet;
  - holy és shadow spell power külön (Smite és Holy Fire a holyt, a többi a shadow-t használja);
  - Shadow talentfán a töltelék a Mind Flay, egyébként a Smite; a harcaid felülírják, mit mennyit használsz;
  - szövet; tőr, egykezes buzogány, bot és pálca.
- Harcoldal priestnek:
  - pontszám: DPS a várthoz képest, folyamatos castolás (pálcával együtt), Shadow Word: Pain a 15 mp-nél hosszabb harcban (a tickekből), kárba ment manaital;
  - "Priest összesítő": a direkt varázslatok, a Mind Flay, a DoT-ok és a pálca aránya; Mind Blast percenként a 8 mp-es cooldownhoz képest; Shadow Word: Pain a harcidő arányában.
- Tanácsok priestnek: a teli manánál ivott manaital hiba, ha a harcnapló igazolja (ugyanaz a szabály, mint a mage-nél); a Mind Blast használata mért adat.
- A gyógyítást a modell nem számolja: Discipline és Holy talentfán az enchant rész a gyógyító súlyokat használja.
- Haditerv: a priest trainer képességei fontosság szerint.

## 2.15.0

Warrior: saját modell, harcoldal és Haditerv.

- A warriornak saját sebzésmodellje van (Warrior.lua), a Wowhead Forever és a WoWSims Forever adatai alapján:
  - fehér ütések, Heroic Strike a következő ütésre (rangonként +11-től +157-ig, Wowhead Forever), fegyveres specialek (Mortal Strike, Overpower, Slam, Whirlwind) fegyversebzés + fix sebzéssel; a többit (Rend, Execute, Bloodthirst) a harcaidból méri;
  - a Forever rage-szabálya: egy fehér ütés 3,46 × fegyversebesség rage-et ad, kétkezes fegyverrel 4,5 ×, critnél a dupláját, balkézzel a felét; 100 fölött a rage elvész (WoWSims Forever sim/core/rage.go). A Felszerelés oldal mutatja, mennyi rage-et adnak másodpercenként a fehér ütéseid;
  - 1 strength = 2 attack power, az agility critet ad;
  - szövet, bőr, mail, pajzs, és 40-től plate; minden közelharci fegyver; második fegyver 20-as szinttől, kétkezes mellé nem.
- Harcoldal warriornak:
  - pontszám: folyamatos ütés, a 100 fölött elveszett rage (a harcnapló rage-eseményeiből);
  - "Warrior összesítő": fehér ütés, Heroic Strike, special, Rend aránya; miss, dodge, crit; elveszett rage.
- Tanácsok warriornak:
  - a Bloodrage vagy a Charge teli rage-nél hiba, ha a harcnapló igazolja: a rage-esemény maga mondja meg, mennyi ment a 100 fölé (a Bloodrage tickjei nem számítanak, csak a megnyomott azonnali rage);
  - a passzív források (Shield Specialization, Unbridled Wrath...) 100 fölötti rage-e mért adat: ilyenkor a rage-ed tele volt;
  - ha egyetlen Heroic Strike sincs, pedig rage veszett el a 100 fölött, az oldal szól.
- A harcnapló-feldolgozó a harc közbeni rage-eseményeket is rögzíti (a tickeket külön jelölve).
- A plate páncél 40-es szinttől használható (warrior; a paladin jön).
- Haditerv: a warrior trainer képességei fontosság szerint.

## 2.14.0

Mage: saját modell, harcoldal és Haditerv.

- A mage-nek saját sebzésmodellje van (Mage.lua), a Wowhead Forever és a WoWSims Forever adatai alapján:
  - a fő varázslat a Frostbolt vagy a Fireball: amelyiket a harcaidban többször használod, harcok nélkül a tehetségfád szerint (Fire fa: Fireball);
  - a szintedhez tartozó rang a Wowhead Forever táblájából: a Frostbolt 1,5 mp-től 3 mp-ig, a Fireball 1,5 mp-től 3,5 mp-ig nő rangonként;
  - spell power-együttható: Frostbolt 0,407 (1,5 mp) és 0,814 (3 mp), Fire Blast és Scorch 0,429, Arcane Missiles 0,286 rakétánként (Wowhead Forever). A Fireballnál a Wowhead nem mutat együtthatót: a modell a Frostbolt mintáját követi (cast idő / 3,5), és ezt ki is írja;
  - a felszerelésnél a spell power és az intellect számít, a strength és az agility nem; a pálca a távolsági helyre megy, a sebzése nem nő a spell powerrel;
  - szövetpáncél; tőr, egykezes kard, bot és pálca.
- Harcoldal mage-nek:
  - pontszám: folyamatos castolás (a fő varázslat a rangja szerinti cast idővel, pálcalövésekkel együtt), kárba ment manaital vagy mana gem;
  - "Mage összesítő": honnan jön a sebzés (direkt varázslat, DoT, AoE, pálca), a fő varázslat percenként, crit és miss aránya, manaitalok.
- Tanácsok mage-nek:
  - a manaital vagy mana gem teli manánál hiba, ha a harcnapló igazolja: a mana-esemény maga mondja meg, mennyi ment a maximum fölé. Hiba, ha legalább a fele elveszett; a kisebb túlcsordulás csak mért adat;
  - sok pálcázás (nem megállapítható: a manád a harc alatt nem látszik).
- A harcnapló-feldolgozó a harc közbeni manaitalokat és mana gemeket is rögzíti ("Restore Mana", "Replenish Mana"), a kapott manával és a maximum fölötti résszel.
- Haditerv: a mage trainer képességei fontosság szerint (alap, helyzeti, kihagyható: Slow Fall, teleportok, portálok).
- Az enchant-ajánló mage-nél is a sebzésmodell DPS-ét használja.

## 2.13.0

Enchantok a szerepedre, minden kasztnak.

- A Felszerelés oldalon új rész: "Enchantok a szerepedre". Minden viselt tárgyadhoz a legjobb enchantok, a szerepedhez mérve: sebzőnek a sebzés, tanknak a túlélés, gyógyítónak a gyógyítás számít.
- A szerepet a tehetségfáidból olvassa (ahol a legtöbb pontod van): gyógyító a Restoration Druid és Shaman, a Holy Paladin, a Discipline és a Holy Priest; tank a Protection Warrior és Paladin, és a Feral Druid, ha Bear Formban vagy. Gombbal kézzel is választhatsz: automatikus, DPS, Tank, Gyógyító.
- Hogyan pontoz:
  - sebző, akinek a kasztját a sebzésmodell ismeri (rogue, hunter, shaman, druid, warlock): a modell DPS-e a jelenlegi tárgyaddal és az enchanttal;
  - minden más esetben a WoWSims Forever motor saját súlytáblája (EP) arra a specre: Bear tank, Protection Warrior, Holy és Discipline Priest, Shadow Priest, Retribution Paladin, Fury és Arms Warrior. Ahol a motornak nincs saját táblája (Protection Paladin, Holy Paladin, Restoration Druid és Shaman), a legközelebbi specét használja, és ezt ki is írja;
  - az enchant számait a motor saját átváltásaival számolja (14 crit rating = 1% crit, 12 dodge rating = 1% dodge, 10 életerő / Stamina);
  - a proc enchantok (Crusader, Fiery Weapon) listán vannak, de pontszám nélkül: a gyakoriságuk nincs megadva.
- Látszik, melyik tárgyadon van már enchant (a tárgylinkből), mennyibe kerülnek a reagensek (AH vagy vendor), és mekkora enchanting skill kell hozzá.
- Az enchantok a kasztmodell nélküli kasztoknál (mage, warrior, paladin, priest) is megjelennek a Felszerelés oldalon.
- Az enchantok adatai a Wowhead Forever leírásaiból jönnek (a Forever értékei eltérnek a Classicétól): node scripts/build-enchants.mjs --install. Az Enchants.lua generált fájl, nincs a repóban.

## 2.12.1

- A Felszerelés oldal most pálcát is ajánl (warlock). A Wowhead Forever a pálcáknak csak a DPS-ét és a sebességét adja, sebzéstartományt nem, ezért eddig a pálcák sebzés nélkül kerültek a játékadatba, és az oldal kihagyta őket. Most az átlagos ütés a DPS × sebesség, így a pálca DPS-e pontos.
- Ugyanez a hiány érintett öt dobófegyvert (Thrown) is: a hunter modellje most ezeket is értékeli.
- A játékadatot újra kell építeni, hogy az új számok bekerüljenek: npm run addon:recipes.

## 2.12.0

Warlock: saját modell, harcoldal és Haditerv.

- A warlocknak saját sebzésmodellje van (Warlock.lua), a Wowhead Forever és a WoWSims Forever motor adatai alapján:
  - Shadow Bolt (1,7 mp, a spell power 48,6%-a), DoT-ok, drainek, a démon és a pálca;
  - a felszerelésnél a spell power és az intellect számít, a strength és az agility nem; a pálca a távolsági helyre megy, a sebzése nem nő a spell powerrel;
  - szövetpáncél; tőr, egykezes kard, bot és pálca.
- Harcoldal warlocknak:
  - pontszám: folyamatos castolás (a pálcalövésekkel együtt), DoT a hosszabb harcban, kárba ment Life Tap;
  - "Warlock összesítő": honnan jön a sebzés (direkt varázslat, DoT, drain és Wrack, démon, pálca), a DoT-ok a harcidő hány százalékában sebeztek (a tickekből: a Corruption, az Immolate és a Siphon Life 3, a Bane of Agony 2 mp-enként), Life Tap.
  - A Wrack alatt a DoT-ok gyorsabban tickelnek, ezért ilyenkor a tickekből számolt érték felfelé torzít; az oldal ezt ki is írja.
- Tanácsok warlocknak:
  - a Life Tap teli manánál hiba, ha a harcnapló igazolja: a mana-esemény maga mondja meg, mennyi ment a maximum fölé. Hiba, ha egy Life Tap a manája legalább felét elvesztette (az életerőt ugyanúgy kifizetted); a kisebb túlcsordulás csak mért adat;
  - ritkán sebző DoT-ok (nem megállapítható: a manád és a célpont élete nem látszik), alig sebző démon.
- A harcnapló-feldolgozó a harc közbeni Life Tapeket is rögzíti, a kapott manával és a maximum fölötti résszel.
- Ismert hiány: a dungeon-loot adataiban a pálcáknak nincs sebzése, ezért a Felszerelés oldal pálcát nem ajánl; a felvett pálcádat a modell ismeri.

## 2.11.0

Druid: saját modell, harcoldal és Haditerv.

- A druidnak saját sebzésmodellje van (Druid.lua), a WoWSims Forever motor és a Wowhead Forever adatai alapján:
  - Cat Form előtt varázsló (Wrath, Moonfire, bot), utána Cat Form; hogy megtanultad-e, a varázskönyvedből látszik;
  - Cat Formban a mancs másodpercenként üt, a sebzése a főkezes fegyvered DPS-e: a fegyver sebessége nem számít, csak a DPS-e. A felszerelés-összehasonlítás is így számol;
  - a Cat Formban olvasott attack powert az addon megjegyzi, és akkor is azzal számol, ha éppen más formában vagy;
  - 1 agility = 1 AP Cat Formban: ez a klasszikus szabály, Foreverre nincs ellenőrizve, és a modell jegyzete ezt meg is mondja.
- Harcoldal druidnak:
  - pontszám: Cat Formban ütések folyamatossága, kárba ment energia, a finisherek combo pontjai, Rake a hosszabb harcban; Cat Form nélkül varázslatok percenként;
  - "Druid összesítő": honnan jön a sebzés (mancs, Cat Form-képesség, vérzés, medve, varázslat), a Rake és a Rip a harcidő hány százalékában vérzett (a tickekből: a Rake 3, a Rip 2 mp-enként), a finisherek átlagos combo pontja, teli energia.
- Tanácsok druidnak:
  - a kevés (1–2) combo pontos Ferocious Bite csak akkor hiba, ha a harcnapló igazolja: ugyanaz a szabály, mint a rogue Eviscerate-jénél (nem ölt, krittel sem ölt volna, és a célpont még legalább 8 mp-ig élt);
  - teli energia, ritka Rake (ez nem megállapítható: a harc várható hossza nem látszik), sok mellé ütés.
- Haditerv és Felszerelés druidnak: a trainer képességei rangsorolva; bőr- és szövetpáncél, buzogány, kétkezes buzogány, bot, ököl és tőr.
- A harcnapló-feldolgozó a Ferocious Bite-ot is rögzíti, a célpont életerejével együtt. Egy finisher combo pontja most a cast saját költségéből jön, ha a napló megadja; a számlálóból csak akkor, ha nem. A rogue Eviscerate-átlaga ezért pontosabb lett: a valódi naplóban 3,2 helyett 3,4.
- A Tiger's Fury Foreveren nincs a játékban (Wowhead Forever), ezért a modell nem is számol vele.

## 2.10.0

A kilenc kaszt modellje, és a motor három referenciafüggvénye.

- Új a harcoldalon, "Modell a kasztodhoz":
  - a kasztod mindhárom specje, és mi modellezi őket a WoWSims Forever motorban (d5144855): "Alpha" közösségi modell, vagy "GearPlanner";
  - a GearPlanner gyógyító specek csak felszerelést terveznek, ezekből HPS- vagy rotációs pontszám nem igazolható;
  - van-e hozzá Waystone szintezési modell (rogue, hunter, shaman);
  - a te fád, a talentpontjaid alapján;
  - 60 alatt, hogy a motor csak 60-as karaktert épít, ezért nincs szintazonos referencia. A saját mért adataid ettől még használhatók.
- Referenciafüggvények, a motor kódjából ellenőrizve:
  - Sinister Strike: +AP / 14 × a normalizált fegyversebesség (tőr 1,7, egykezes 2,4, kétkezes 3,3, távolsági 2,8). +140 AP egykezes karddal +24, tőrrel +17.
  - Hunter pet: a melee és a ranged AP közül a nagyobbik 10%-a, idézéskor rögzül. 700 / 1000 AP esetén +100.
  - Warlock démon: S = spell damage + max(shadow, fire); AP 0,17 × S, spell damage 0,10 × S. 300 / 100 / 50 esetén +68 AP és +40 spell damage.
  - A harcoldal mutatja a te értékeidet: a rogue Sinister Strike-ját, a hunter petjét, a warlock démonját.
- Javítva: a rogue modell a Sinister Strike-ot eddig a fegyver saját sebességével számolta. Foreveren a normalizált sebesség számít, így egy lassú (2,7-es) kard Sinister Strike-ja kevesebbet nyer az AP-ból, mint eddig mutatta. Ez a felszerelés-összehasonlítást is pontosítja. A webes modell ugyanígy számol.
- A "Referencia-szimuláció" sor most megnevezi a kasztod és a specced modelljét, GearPlanner specnél pedig azt is, hogy ott nincs referencia.

## 2.9.2

Javítások egy átnézés után. Mindhárom ugyanazt a szabályt sértette: csak azt mondjuk, ami igazolt.

- Kevés pontos Eviscerate:
  - "Indokolt" csak akkor jelenik meg, ha minden 1–2 pontos ellenőrizhető volt. Ha van ellenőrizetlen (régebbi napló, élő mérő, vagy nem látszik a célpont élete), akkor "nem megállapítható", és kiírja, hány indokolt és hány nem ellenőrizhető.
  - Hiba csak akkor, ha a célpontnak több mint négyszer annyi élete maradt, mint az ütés normál sebzése. A sebzés dobott része legfeljebb kétszerese a legkisebbnek, ehhez jön a krit (WoWSims Forever: csak a rang alapsebzése szór).
  - A blokkolt rész is beszámít.
  - Az ismeretlen max életerő "?", nem 0.
- Cooldownok: az élő mérő harcai ténylegesen kimaradnak. Eddig, ha volt bennük cast, beszámítottak, pedig a leírás mást mondott.
- A webes harcoldal és a coach ugyanígy számol.

## 2.9.1

- Javítva: a Stormstrike cooldownja Foreveren 8 mp (Wowhead Forever), nem 20, mint Classicban. A shaman modell ezért 10 mp-enként számol vele, a cooldownja 80%-ával. A pontszám percenként 6-nál ad teljes pontot (8 mp-es cooldownnal legfeljebb 7,5 lehet), és a szövege is 8 mp-et mond.

## 2.9.0

Új a harcoldalon: cooldownok kihasználtsága.

- A harcnapló castjaiból számolja, hogy a harcidő hány százalékában töltődött egy cooldownos képesség. A módszer a WoWAnalyzer CastEfficiency normál ága: befejezett töltődések, plusz a harc végén még futó töltődés, osztva a harcidővel.
- Csak a Foreverre ellenőrzött cooldownokkal számol (Wowhead Forever): Shank 10 mp, Blade Flurry 2 perc, Kidney Shot 20 mp, Arcane Shot 6 mp, a shockok közös 6 mp-e, Stormstrike 8 mp.
- Minden sor mutatja, miből jött: hány harc, mennyi harcidő, abból mennyi töltődés, hány mp húzódott át az előző harcból, és a cooldown forrása.
- Csak az első használat utáni harcok számítanak, mert előtte lehet, hogy még nem volt meg a képesség. Amit még sosem használtál, az nem 0%, hanem nincs sora.
- Csak a harcnapló harcai számítanak (2.9.2-től ténylegesen): az élő mérő harcának ideje a mérő sessionjéből jön, a castjainak ideje a harci óráról, és a kettő nem feltétlenül egyezik.
- A reaktív képességek (Riposte parry után, Kick egy castra) kimaradnak: hogy mikor lehetett használni, azt egy esemény dönti el, nem a töltődés.
- Az alacsony érték nem hiba, és nem is így jelenik meg.

## 2.8.3

Az első bizonyítható hiba: a kevés combo pontos Eviscerate, a harcnaplóból.

- A feltöltő minden Eviscerate-hez elmenti:
  - a combo pontokat, a cast saját költségéből;
  - a célpont életerejét előtte, ami a harcnapló szerint utána maradt plusz a sebzés;
  - a sebzést, és hogy kritelt-e vagy ölt-e;
  - hogy a célpont utána még meddig élt.
- Hiba csak akkor, ha mind igaz: 1–2 pont, eltalálta és nem ölt, a célpontnak több mint kétszer annyi élete maradt, mint a sebzés (krittel sem halt volna meg), és utána még legalább 8 mp-ig élt. Ennyi idő alatt 1–2 pont még felépíthető.
- A hiba felsorolja az eseteket (időpont, célpont, pontszám, életerő előtte, sebzés, hátralévő idő), így mindegyik visszakereshető a naplóban.
- Ha a kevés pontos Eviscerate-ek mind ölők vagy indokoltak voltak, nem hibaként jelenik meg, hanem megfigyelésként. Élő harcnál, ahol a célpont élete nem látszik, marad a "nem megállapítható".
- Javítva: a játéknak írt harcnapló-harcokból eddig kimaradt a pet, a túlsebzés és a "miből számoltuk", ezért a harcoldal ezeket nem mutatta.

## 2.8.2

A tanácsok szabályai Foreverre ellenőrizve: 17-ből 16, forrással.

- Forrás: a WoWSims Forever motor kódja (d5144855) a mechanikához, a Wowhead Forever spell-adatai a költséghez, cooldownhoz, szinthez és hatáshoz
- Ellenőrizve: teli energia, Eviscerate combo pontonként, Slice and Dice, parry csak szemből, Instant Poison 20-tól, glancing, hit, hunter pet, a hunter 8 yardos holttere, Serpent Sting, Arcane Shot, Aspect of the Hawk, a shockok közös 6 mp-es cooldownja, Searing Totem, Windfury, Lightning Shield
- Javítva a Forever szerint:
  - a glancing esélye azonos szintű mobon is 10%, és minden hiányzó fegyverskill-pont +2%
  - a Windfury Foreveren 2 extra támadást ad (Classicban 1-et)
- Nem ellenőrizhető: "az enhancement shaman sebzésének nagyja a fegyver" játékstílus, nem szabály; megfigyelés marad
- A tanácsok továbbra sem mondanak hibát: a szabály most már igazolt, de a döntés pillanatának állapota (a célpont élete, a manád, a pet, hol álltál) nem látszik a harcadatból; ezt a tanács meg is írja

## 2.8.1

Tanácsok: hibát csak akkor jelez, ha a harcadat és egy Foreverre ellenőrzött szabály igazolja.

- Minden tanács egy mért ténnyel kezdődik, utána jön, mit érdemes kipróbálni ("ha ...")
- Szürkén alatta: miért nem mondható hibának, vagyis mi nem látszik a harcadatból (például a célpont életereje az Eviscerate pillanatában, a manád, a pet állapota, hol álltál), és hogy a szabály Foreverre nincs ellenőrizve
- Három fajta: **mért adat**, **megfigyelés**, **nem megállapítható**; **hiba** csak ellenőrzött szabállyal és teljes adattal lehet. Egyik szabály sincs még a Forever 1.60.1-re ellenőrizve, ezért most egyetlen tanács sem hibajelzés
- Rogue, hunter és shaman tanácsok, a Haditerv "Tanácsok a harcaid alapján" része is
- A pontszám mellett: egy alacsony rész önmagában nem bizonyított hiba

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
