## 2.37.0

AH → vendor: auctions that sell for less than a merchant pays for them.

- **New window, AH → vendor** (`/wa flip`, or the button at the auction house). The full auction house scan (`/wa ah`) now compares every auction with the merchant price the game client reports, and lists the ones you can buy and sell to any merchant at a profit. Buying on the auction house has no fee, so the profit is exact.
- Items the client had not loaded during the scan are loaded afterwards and checked too. Items no merchant buys are left out.
- **Buying with one click each**: click an item and it is searched again on the auction house. Buy takes only the auctions that are still there and still pay, and only as many as your gold covers. For stackable items the game quotes its final price first: Waystone confirms it only while it still pays, otherwise it cancels.
- **Selling**: bought items arrive in your mailbox. At a merchant, the "Sell AH buys" button sells exactly the stacks you bought this way, at most 12 at a time, so the buyback tab can undo them. The window keeps a tally of what you spent and earned.
- **Vendor crafting, more accurate**: your own auctions are no longer counted as materials you could buy, in the scan and in live prices. An orange * marks a cost whose AH price is over an hour old, and the shopping list says how old each price is. When the materials cost more than your gold, it says how many crafts you can pay for.

## 2.36.0

Waystone now speaks English, and you can switch it to Hungarian.

- **English by default**: every window, tooltip, piece of advice and chat message is in English, on all pages (Plan, Combat, Gear, Professions, Pet, Talents), the session bar, the chronicle and the minimap button. Numbers use a decimal point.
- **Language switch**: click the EN/HU button next to the main window's close button, or type `/wa lang en` or `/wa lang hu`. The interface reloads in the chosen language. The choice is saved for the whole account.
- **English commands**: `/wa talents` opens the talent calculator, `/wa help` lists every command. The old Hungarian names still work: `/wa talentek`, `/wa harc`, `/wa ah lassu`, and the session bar's `cel`, `tanacs`, `zonak`, `osszegzes`, `torol`.
- Nothing changed in the calculations: the same numbers, sources and rules in both languages.
- Fix: the Chronicle's weekly guild list showed your own character twice ("Name" and "Name Realm"). The game sends the sender's name as "Name Realm", which the addon did not recognise as you. It now does, and the duplicates already saved are merged on login.
- Fix: the vendor crafting chat message mixed up the number of professions and the number of crafts per profession.

## 2.34.0

Javasolt rotáció, elsőként a Combat rogue-nak.

- A Harc oldalon új rész: "Javasolt rotáció". Megmondja, milyen sorrendben érdemes használni a képességeidet, és mennyi DPS-t vár tőle a modell. Mellette a harcaid: képességenként hányszor használtad percenként, és ez mennyi DPS-be került vagy hozott.
- Combat rogue: Slice and Dice (hány ponttal éri meg a te harcaid hosszánál), Eviscerate 5 ponttal, Shank cooldownon 80 energia alatt, Blade Flurry és Adrenaline Rush (egy használat értéke). Minden szám mellett ott a forrás (Wowhead Forever, WoWSims Forever).
- A Haditervben egy sor összefoglalja.
- Ez számítás, nem hibalista: a harcaid átlagában benne van a futás, a célpontváltás és a rövid harc is.
- A többi spec rotációja a saját ticketjében jön; addig a rész megmondja, melyik.

## 2.33.0

Aura-idővonal: a harcnapló most azt is megjegyzi, mikor került fel és le egy buff vagy egy debuffod.

- Eddig csak az összidő volt meg (pl. a Slice and Dice a harc 70%-ában volt fent). Most az is, mikor: ebből lehet majd megmondani, fent volt-e a Slice and Dice, amikor lejárt, vagy fent volt-e a Shadow Word: Pain a Mind Flay alatt. Ez a rotációs javaslatok alapja.
- A saját buffjaid és a célponton lévő saját debuffjaid (DoT-ok, Sunder Armor, Faerie Fire) kerülnek bele.
- Az uploader frissítése után az új harcoknál jelenik meg; a régi harcok ugyanúgy működnek, mint eddig.

## 2.32.0

Szintfüggő kalibráció: a harcaid annyira számítanak, amennyire közel vannak a mostani szintedhez.

- A modell eddig minden rögzített harcodat egyformán vette figyelembe. Most egy harc súlya 5 szintenként a felére esik: ami 15 szinttel lejjebb volt (más rotáció, más rangok), az csak 1/8 súllyal számít, és a modell ennyivel jobban támaszkodik a Wowhead-alapértékekre.
- A Felszerelés oldalon a modell megjegyzései között egy új sor mondja meg, honnan jönnek a számok: hány harc, melyik szintekről, és a harcidőből mennyi számít.
- A Harc oldal statisztikái és tanácsai nem változtak: azok továbbra is az egész harcokat mutatják.

## 2.31.0

Specfelismerés: a modell tudja, melyik specben vagy, és kiírja, miből tudja.

- A spec az a talentfa, amelyikben a legtöbb pontod van. Egyenlő pontszámnál a mélyebb talent dönt. Bizonyítékként a fa mély talentjei is látszanak.
- Vegyes fánál kézzel is választhatsz specet a Harc oldalon, a "Modell a kasztodhoz" szakaszban. Ez a modellre és az enchant-ajánlásra is hat.
- A Harc oldalon a szakasz címe és első sora, a Felszerelés oldalon a modell első megjegyzése mondja meg, melyik spec szerint számol.
- A specfüggő részek (Balance druid, a mage fő varázslata, a priest Mind Flayje, a paladin seal-je) mostantól ebből dolgoznak.

## 2.30.0

Talent-kalkulátor a játékban: új Talentek oldal a /wa ablakban (/wa talentek).

- A három talentfád a játék adataiból: ikon, rang, előfeltételek. Arany: tele, zöld: van benne pont vagy most beletehetsz, szürke: zárva.
- Tervezés: bal klikk egy pont a tervbe, jobb klikk egy pont ki. A játék szabályai szerint: annyi pont, amennyi van, soronként 5 pont kell alatta, és az előfeltétel. Ha nem megy, megmondja, miért.
- A terv DPS-e a mostanihoz képest, és talentenként, mennyit ad az a változás, a forrással.
- Tooltip: a talent leírása, alatta mennyit ér a tervben és a következő pontja a mostani felszereléseddel, melyik stat ér miatta többet, és a forrás.
- A legtöbbet érő következő pont fénylő kerettel.
- Tervek mentése karakterenként, és megosztás szövegként (Waystone:KASZT:…), amit egy másik Waystone be tud tölteni.
- A terv csak terv: a talentet a játék talent-ablakában te tanulod meg.

## 2.29.0

Talentérték: mennyit ér egy talent a mostani felszereléseddel.

- A /wa talent most minden számolt talentednél kiírja:
  - mennyi DPS-t ad most (a modell a talenttel és nélküle);
  - mennyit adna a következő pont benne;
  - melyik stat ér miatta többet vagy kevesebbet (pl. a Careful Aim miatt az intellect).
- A végén: melyik talentbe érné meg most a legjobban a következő pontot tenni. Csak olyan talentet ajánl, amibe a játék szabályai szerint tehetsz pontot.
- A karakterlapon már benne lévő talenteket (crit, hit) is kiszámolja: a modell a lapról is levonja a részüket.
- A Felszerelés oldalon egy új sor mutatja, hogy a talentjeid miatt melyik stat mennyit ér.
- A tank- és gyógyító talentek a hatásukkal szerepelnek, érték nélkül, amíg a tank- és gyógyítómodell nincs kész.

## 2.28.0

Paladin: mindhárom talentfa a modellben. Ezzel mind a kilenc kaszt talentjei bekerültek.

- A paladin mind az 51 talentje besorolva. Amelyik az ütéseid, a sealjeid vagy a Holy Strike sebzését változtatja, azzal a modell most számol, a rangod Wowhead Forever számaival:
  - Seal of Command: ha megvan a talent, a modell vele számol a Seal of Righteousness helyett;
  - Improved Seals, Sacred Arbiter (Holy Strike) és Two-Handed Weapon Specialization (kétkezes fegyverrel minden sebzésed; a felszerelés-értékelés ezt egy egykezes fegyvernél nem adja meg);
  - Divine Strength, Divine Intellect és Champion of the Light: az intellectből spell power lesz, ezért a felszerelés-értékelés az intellectet is számolja;
  - a Conviction és a Precision a karakterlapodon már benne van.
- Amelyikkel nem számol, annál a /wa talent megmondja, miért: gyógyítás, tank (blokk, a téged érő ütések), mana, túlélés, vagy olyan hatás, amihez az aura-idővonal kell (Vengeance).
- Talentek nélkül a számok nem változtak.

## 2.27.0

Priest: mindhárom talentfa a modellben.

- A priest mind az 52 talentje besorolva. Amelyik a varázslataid vagy a pálcád sebzését változtatja, azzal a modell most számol, a rangod Wowhead Forever számaival:
  - Searing Light (holy), Darkness és Shadowform (shadow; Shadowformban a shadow crit dupla bónuszt ad), Twin Disciplines (Shadow Word: Pain), Improved Mind Flay;
  - Holy Precision, Shadow Focus (hit) és Holy Specialization (holy crit; az addon a játék holy és shadow critjéből látja, hogy a karakterlapodon már benne van-e);
  - Mind Flay: ha megvan a talent, a modell Mind Flay-jel számol a Smite helyett;
  - Divine Fury és Improved Mind Blast: rövidebb Smite és Mind Blast cooldown (amíg nincs harcnapló);
  - Mental Strength (intellect) és Wand Specialization (pálca).
- Amelyikkel nem számol, annál a /wa talent megmondja, miért: gyógyítás, mana, túlélés, cooldown, olyan hatás, amihez az aura-idővonal kell (Power in Light, Shadow Weaving), vagy a Penance, ami még nincs külön a modellben.
- Talentek nélkül a számok nem változtak.

## 2.26.0

Druid: mindhárom talentfa a modellben.

- A druid mind az 52 talentje besorolva. Eddig a druid modell egy talentet sem nézett, most a rangod Wowhead Forever számaival számol:
  - Cat Form: Ferocity, Savage Fury, Natural Instinct; a Sharpened Claws, a Leader of the Pack és a Predatory Strikes. Ha nem Cat Formban nézed a karakterlapot, ezeket a modell hozzáadja;
  - Heart of the Wild (intellect, Cat Formban strength) és Naturalist (minden sebzés);
  - varázslás: Vengeance, Eclipse és Moonkin Form (Moonkin Formban számol);
  - a Nature's Majesty és a Nature's Reach a karakterlapodon már benne van.
- Ha a legtöbb talentpontod a Balance fában van, a modell varázslóként számol akkor is, ha tudod a Cat Formot.
- A varázslataid hitjét a modell most a játékból olvassa (spell hit).
- Amelyikkel nem számol, annál a /wa talent megmondja, miért: medve (tank), gyógyítás, mana, túlélés, több célpont, vagy olyan hatás, ami a képességeid gyakoriságát változtatja (ezt a modell a harcaidból méri; a rotációs javaslatokkal jön).
- Talentek nélkül a számok nem változtak.

## 2.25.0

Shaman: mindhárom talentfa a modellben.

- A shaman mind az 50 talentje besorolva. Amelyik a közelharcod, a shockjaid, a Lightning Bolt vagy a totemjeid sebzését változtatja, azzal a modell most számol, a rangod Wowhead Forever számaival:
  - Concussion és Call of Flame: a Lightning Bolt, az Earth Shock, a Flame Shock és a tűztotemek. Hogy mennyi a shockjaidból Earth Shock és mennyi Flame Shock, azt a harcnaplóból látja;
  - Call of Thunder és Lightning Overload: a Lightning Bolt critje és a második, fél sebzésű villám;
  - Elemental Fury: a varázslataid critje többet sebez;
  - Ancestral Knowledge, Mental Dexterity, Mental Quickness: több intellect, és abból attack power és spell power. Ezért a felszerelés-értékelés enhancementnél az intellectet is számolja;
  - a Flurry, az Elemental Weapons és a Stormstrike ahogy eddig; a Thundering Strikes és a Tidal Focus a karakterlapodon már benne van.
- A varázslataid hitjét a modell most a játékból olvassa (spell hit).
- Amelyikkel nem számol, annál a /wa talent megmondja, miért: gyógyítás, mana, túlélés, több célpont, cooldown, vagy olyan hatás, ami a varázslataid gyakoriságát változtatja (ezt a modell a harcaidból méri; a rotációs javaslatokkal jön).
- Talentek nélkül a számok nem változtak.

## 2.24.0

Hunter: mindhárom talentfa a modellben.

- A hunter mind az 50 talentje besorolva. Amelyik a lövéseid, a közelharcod, a peted vagy a Serpent Sting sebzését változtatja, azzal a modell most számol, a rangod Wowhead Forever számaival:
  - Focused Fire (pettel) és Lone Wolf (pet nélkül): minden sebzésed;
  - Unleashed Fury: a peted sebzése;
  - Ranged Weapon Specialization, Barrage, Mortal Shots: a távolsági sebzés, a Multi-Shot, az Aimed Shot és a critek;
  - Improved Stings: a Serpent Sting;
  - Careful Aim: az intellectből attack power lesz, ezért a felszerelés-értékelés az intellectet is számolja;
  - Savage Strikes, Predator's Edge, Lightning Reflexes: a közelharc és az agility;
  - a Surefooted, a Lethal Attacks és a Trueshot Aura a karakterlapodon már benne van.
- Amelyikkel nem számol, annál a /wa talent megmondja, miért: túlélés, mana, mozgás, a pet fajtájától függő hatás, cooldown, vagy olyan képesség, ami még nincs külön a modellben (Counterattack, Mongoose Bite, Sniper Shot, csapdák…; ezek a rotációs javaslatokkal jönnek).
- Talentek nélkül a számok nem változtak.

## 2.23.0

Warlock: mindhárom talentfa a modellben.

- A warlock mind az 52 talentje besorolva. Amelyik a varázslataid, a DoT-jaid vagy a démonod sebzését változtatja, azzal a modell most számol, a rangod Wowhead Forever számaival:
  - Shadow Mastery, Agonizing Flames, Aftermath, Improved Corruption, Improved Bane of Agony, Improved Drains. Ezek a harcaidban mért arányon hatnak: a modell a harcnaplóból látja, mennyi a sebzésedből árnyék, Destruction, Corruption vagy drain;
  - Ruin: a Destruction varázslatok critje többet sebez (5/5-nél kétszeres);
  - Malevolence: árnyék crit. Az addon a játék árnyék és tűz critjének különbségéből látja, hogy a karakterlapodon már benne van-e;
  - Unholy Power: a démonod sebzése;
  - a Suppression és a Demonic Knowledge a karakterlapodon már benne van.
- Amelyikkel nem számol, annál a /wa talent megmondja, miért: mana, túlélés, a démon fajtájától függő hatás, olyan hatás, amihez az aura-idővonal kell (pl. Improved Shadow Bolt, Demonic Sacrifice), vagy olyan varázslat, ami még nincs külön a modellben (Shadowburn, Conflagrate, Incinerate, Wrack…; ezek a rotációs javaslatokkal jönnek).
- Talentek nélkül a számok nem változtak.

## 2.22.0

Mage: mindhárom talentfa a modellben.

- A mage mind az 53 talentje besorolva. Amelyik a fő varázslatod (Frostbolt vagy Fireball) vagy a pálcád sebzését változtatja, azzal a modell most számol, a rangod Wowhead Forever számaival:
  - Accelerant és Improved Frostbolt: rövidebb cast idő;
  - Ignite: a tűz critek égése. Ezzel a crit (és az intellect) többet ér;
  - Ice Shards: a fagy crit többet sebez (5/5-nél kétszeres);
  - Critical Mass: tűz crit. Az addon a játék tűz és fagy critjének különbségéből látja, hogy a karakterlapodon már benne van-e, így nem számolja kétszer;
  - Arcane Instability, Arcane Mind, Wand Specialization: több spell sebzés, több intellect, erősebb pálca.
- Javítva: a modell eddig a tűz és a fagy crit közül a nagyobbikkal számolt; most a fő varázslatod iskolájáéval.
- Amelyikkel nem számol, annál a /wa talent megmondja, miért: a manát a modell nem számolja, túlélés, több célpont, vagy olyan varázslat, ami még nincs külön a modellben (Fire Blast, Scorch, Pyroblast, Ice Lance, Arcane Missiles…; ezek a rotációs javaslatokkal jönnek).
- Talentek nélkül a számok nem változtak.

## 2.21.0

Warrior: mindhárom talentfa a modellben.

- A warrior mind az 53 talentje besorolva. Amelyik a sebzést, a critet, a sebességet vagy az off-handet változtatja, azzal a modell most számol, a rangod Wowhead Forever számaival:
  - Two-Handed Weapon Specialization: kétkezes fegyverrel több sebzés;
  - Bastion: pajzzsal több sebzés. A felszerelési javaslat ezt figyelembe veszi, ha pajzsot cserélsz vagy kétkezesre váltanál;
  - Impale: a Heroic Strike és a fegyveres specialok critje többet sebez;
  - Weaponmaster: karddal extra támadás;
  - Flurry: a crit utáni 3 ütés gyorsabb, így a crit többet ér;
  - Dual Wield Specialization és Furious Precision: több off-hand sebzés, kevesebb off-hand miss;
  - a Cruelty a karakterlapodon már benne van.
- Amelyikkel nem számol, annál a /wa talent megmondja, miért. A leggyakoribb ok a rage: a modell nem szimulálja, ezért a rage-et adó talentek (pl. Anger Management, Unbridled Wrath) a rotációs javaslatokkal jönnek. Más okok: túlélés vagy fenyegetés (a tankmodellbe kerül), több célpont, vagy olyan képesség, amit a modell a harcaidból mér (Mortal Strike, Bloodthirst, Deep Wounds).
- Talentek nélkül a számok nem változtak.

## 2.20.0

Rogue: mindhárom talentfa a modellben.

- A rogue mind az 54 talentje besorolva. Amelyik a sebzést, az energiát, a combo pontot vagy a találatot változtatja, azzal a modell most számol, a rangod Wowhead Forever számaival:
  - Efficient Strikes, Flawless Execution, Relentless Strikes: kevesebb energia egy Sinister Strike + Eviscerate körre;
  - Ruthlessness, Seal Fate: kevesebb Sinister Strike egy Eviscerate-hez. Seal Fate mellett a crit többet ér, ezt a felszerelési javaslat is figyelembe veszi;
  - Coup de Grace, Aggression, Lethality, Dual Wield Specialization: több sebzés;
  - Weapon Expertise: kevesebb dodge és parry; Hack and Slash: fejszével vagy karddal extra támadás, így a felszerelési javaslatban egy kard többet érhet, mint ugyanolyan buzogány;
  - a Malice és a Precision a karakterlapodon már benne van.
- Amelyikkel nem számol, annál a /wa talent megmondja, miért: túlélés (a tankmodellbe kerül), mozgás vagy lopakodás, vagy olyan képesség, ami még nincs a modellben (Backstab, Mutilate, Slice and Dice, Rupture…; ezek a rotációs javaslatokkal jönnek).
- Talentek nélkül a számok nem változtak.

## 2.19.0

Talentek: a talentek hatása egy közös kereten át jut a modellekbe, a Forever számaival.

- A talentek hatását eddig kasztonként, kézzel beírt számok adták (rogue, hunter, shaman). Most egy közös keret adja őket: a számot mindig a rangod Wowhead Forever szövegéből veszi. Például a Malice 3/5 3% crit, mert a 3. rang szövege ezt írja.
- A /wa talent most azt is kiírja, melyik talentedet számolja a modell (a számmal együtt), és melyiket még nem, indokkal: a kaszt ticketje (WA-032a – WA-032i), vagy hogy a talent nincs meg a Wowhead Forever adatában, vagy hogy a játék más rangszámot mutat. Amelyiket nem számolja, azzal a modell nem számol, és nem is talál ki rá számot.
- Javítva, mert a Forever talentjei mások, mint a Classicéi:
  - Hunter: a Classic Lethal Shots helyett a Foreveren Lethal Attacks van (rangonként +1% crit minden támadásra). Az addon eddig a Lethal Shotsot kereste, ezért ezt a talentet sosem találta meg.
  - Shaman Flurry: Foreveren rangonként 6% (6–30%). Eddig a Classic értékeivel számolt (10–30%), így 1–4. rangon túl sokat adott.
  - Shaman Elemental Fury: Foreveren 5 rangú, rangonként +20%-kal növeli a spell crit bónuszát (5/5-nél 2×). Eddig már 1 ponttól a teljes 2×-ost számolta.
  - Shaman Elemental Weapons: a Forever számaival hat az imbue-ra (Windfury 13/27/40%, Flametongue 5/10/15%, Rockbiter 7/13/20%). Az eddigi rangonkénti +2%-nak nem volt forrása.
  - Shaman, kétkezes fejsze és buzogány: a Forever talentfáiban nincs Two-Handed Axes and Maces talent. Eddig emiatt a játékban a felszerelési javaslat sosem ajánlott kétkezes fejszét vagy buzogányt, és a figyelmeztetés egy nem létező talentet kért. Most a fegyverskilled dönt: ha megvan a Two-Handed Axes vagy Two-Handed Maces skill, ajánlja, ha nincs, a figyelmeztetés a fegyvermestert említi.
- A többi kaszt talentjei még "nem számolt" állapotban vannak. Kasztonként jönnek: docs/tickets WA-032a – WA-032i.

## 2.18.0

Talentek: a Forever talentfái az addonban.

- Az addon most a teljes talentfádat ismeri, minden kasztnál: mindhárom fa minden talentjét, a helyét, a rangjait, az előfeltételét és a pontjaidat. A fák alakját a játékból olvassa.
- A rangok szövegét és számait a Wowhead Forever talent-kalkulátorának adataiból veszi (a Forevernek saját talentjei vannak, pl. a rogue Efficient Strikes vagy a mage Heating Up talentje, ezért a Classic adatai nem jók). Ez generált fájl (TalentData.lua): node scripts/build-talents.mjs --install. A CurseForge-os csomagban benne van.
- Új parancs: /wa talent. Kiírja a fáidat, az elköltött és a szabad pontjaidat, és fánként, hogy a Wowhead Forever adata hány talentben egyezik a játékkal. Ha egy talent a játékban más (másik rangszám vagy hely), vagy az adatban nincs meg, azt megnevezi: így egy Forever-frissítés nem marad észrevétlen.
- Ez az első lépés: a talentek hatása a sebzésmodellekben, a talentenkénti érték a jelenlegi felszereléseddel és a játékon belüli talent-kalkulátor a következő verziókban jön (docs/tickets, WA-032 – WA-034).

## 2.17.1

Paladin: a seal a harcnaplóból, és a Seal of Fury is sebző seal.

- Javítva: a paladin tanácsa azt írta, hogy az addon nem rögzíti a harcnapló aura-eseményeit, ezért nem tudni, melyik seal volt fent. Ez nem volt igaz: a feltöltő minden saját buff idejét harconként menti, és a seal is buffként szerepel a naplóban.
- Új a harcoldalon, "Seal a harcaidban" (mért adat): melyik seal a naplózott harcidő hány százalékában volt rajtad, és ebből mennyi volt sebző seal. A "Paladin összesítő" Seal kártyája a leggyakoribb sealt is mutatja.
- A "Nem sebez seal" megfigyelés most megnevezi, melyik seal volt fent (pl. Seal of the Crusader 95%). Hiba nem lesz belőle: a Crusader attack powert, a Wisdom manát, a Light gyógyulást ad, és hogy ez megérte-e, az a harcadatból nem mérhető. Az élő mérő harcainál megírja, hogy a seal csak a harcnaplóból látszik.
- Javítva: a Seal of Fury (34-es szinttől) Foreveren minden ütésre holy sebzést ad (Wowhead Forever spell=20419: 19 holy a legfelső rangon, pajzzsal elnyelő pajzs is). Eddig a modell az "egyéb" sebzéshez sorolta, így a Seal of Fury-t használó paladinnál a "Nem sebez seal" tévesen jelezhetett. Most sebző sealként számít; a Haditervben is megjelenik.
- A sealDamage szabály szövege a Forever tooltipjei szerint: a Righteousness és a Fury minden ütésre, a Command esélyre ad holy sebzést; a Crusader, Wisdom, Light és Justice ütésenként nem.
- Valódi naplóval ellenőrizve: egy Seal of Command-os paladin (86% Command), és egy Seal of Fury-s (66% Fury, a seal a sebzése 29%-a).

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
