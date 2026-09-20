# Kész bejegyzések a weboldal népszerűsítéséhez

Cím, amit mindenhol linkelj: **https://parthenon2-boop.github.io/birodalom/**
(angolul: `?lang=en`, németül: `?lang=de`)

A link mellé mindig kerüljön **kép vagy rövid videó** – enélkül a bejegyzések elvesznek.
Az oldal megosztási képe már be van állítva, tehát a puszta link is szép kártyaként jelenik meg.

---

## 1. Reddit – r/IndieGames, r/playmygame (angol)

**Cím:** I built three free games and a launcher that keeps them updated (solo dev, Godot)

**Szöveg:**
> I've been making games on my own and got tired of sending people zip files, so I built a small
> launcher that installs and updates all of them: a grand strategy game set in Anglo-Saxon Britain
> from 790 (Heptarchia), a real-time empire builder spanning 1400–1945 (Birodalom), and a roguelike
> where a knight, an archer or a mage fight down five depths to a dragon (Kard és Mágia).
>
> Everything is free, Windows and macOS. The site has screenshots and the download:
> https://parthenon2-boop.github.io/birodalom/?lang=en
>
> Happy to answer anything about how the launcher handles updates, or about the games themselves.

*Tipp: a reddites közösségek nem szeretik a puszta reklámot. Írd oda, mit tanultál a fejlesztés
közben, és válaszolj minden hozzászólásra az első pár órában – ettől megy fel a bejegyzés.*

---

## 2. Reddit – r/roguelikes (angol, csak a roguelike-ról)

**Cím:** Kard és Mágia – a small roguelike with three classes and hand-drawn vector art (free)

**Szöveg:**
> Five depths, five bosses, three classes: the knight blocks with a shield and hits hard up close,
> the archer shoots from range, and the mage throws an arcane orb that mostly ignores armour.
> Every level is guaranteed to be fully walkable – the generator flood-fills after generation and
> carves a corridor if anything got cut off, and chests can never block the only path.
>
> Free, Windows and macOS: https://parthenon2-boop.github.io/birodalom/?lang=en

---

## 3. Reddit – r/godot (angol, fejlesztői oldal)

**Cím:** Lessons from porting a canvas game to Godot 4 and making it run on a 2017 office PC

**Szöveg:**
> I ported a browser roguelike to Godot 4.7 and it ran at 28 FPS on an Intel HD 630. Two things
> were eating the frame: a 512×512 gradient texture that was being rebuilt every single frame
> because of a stale size check, and the number of draw batches (on this GL-compatibility setup a
> single triangle-array call costs ~0.4 ms, while vertex count is almost free – 40 batches of 6
> vertices were slower than 1 batch of 12 000).
>
> After caching static meshes and only redrawing layers whose contents actually changed: 74 FPS in
> the menu, 137 in gameplay. Screenshots and the game: https://parthenon2-boop.github.io/birodalom/?lang=en

---

## 4. Magyar csoportok (Facebook, Discord, Gamekapocs)

> Sziasztok! Egyedül fejlesztek játékokat, és most egy közös indítóba tettem mindet.
> Három játék, mind ingyenes, magyar nyelven:
> • **Heptarchia** – angolszász nagystratégia 790-től: Wessex, Mercia, a vikingek érkezése.
> • **Birodalom** – valós idejű stratégia 1400-tól 1945-ig.
> • **Kard és Mágia** – roguelike kaland: lovag, íjász vagy mágus, öt mélység, a végén a sárkány.
>
> Az indító letölti és naprakészen tartja őket, Windowsra és Macre:
> https://parthenon2-boop.github.io/birodalom/
>
> Bármilyen visszajelzésnek örülök – főleg annak, ami nem tetszik benne.

---

## 5. X / Bluesky / Mastodon (rövid, képpel)

**Magyarul:**
> Három játék, egy indító, mind ingyenes: angolszász nagystratégia, birodalomépítés 1400–1945, és
> egy roguelike a katakombákban. Windows és macOS.
> https://parthenon2-boop.github.io/birodalom/
> #indiedev #godot #roguelike #stratégia

**Angolul (#screenshotsaturday):**
> Three free games in one launcher: Anglo-Saxon grand strategy, a 1400–1945 empire builder, and a
> roguelike with knight/archer/mage. Made solo in Godot.
> https://parthenon2-boop.github.io/birodalom/?lang=en
> #screenshotsaturday #godot #indiedev #roguelike

---

## 6. YouTube Shorts / TikTok – 15–30 másodperces ötletek

1. **„Minden pálya bejárható”** – mutasd a generátort: 500 pálya, 0 hibás. Felirat: *„54 pályán
   ragadtál volna be – most egyen sem.”*
2. **Varázsgömb** – lassítva a kék gömb becsapódása, a sebzésszám felugrik.
3. **Viking portya** – Lindisfarne feldúlása a Heptarchiában, egy mondatos felirattal.
4. **Előtte–utána** – 28 FPS → 137 FPS, a képernyőn a számláló.
5. **„Egy gomb, három játék”** – a launcher, ahogy letölt és indít.

A leírásba mindig az oldal linkje kerüljön.

---

## 7. itch.io / IndieDB oldal szövege (angol)

**Rövid leírás:**
> Three free games in one launcher: Heptarchia (Anglo-Saxon grand strategy from 790), Birodalom
> (real-time strategy, 1400–1945) and Kard és Mágia (roguelike). Windows and macOS, automatic updates.

**Hosszabb:**
> ParthLauncher installs and updates all three games for you. Heptarchia puts you in charge of an
> Anglo-Saxon kingdom: the Witan, the church, population and recruitment, and the vikings arriving
> on your shores. Birodalom spans five and a half centuries of economy, armies and great-power
> politics. Kard és Mágia is a roguelike with three very different heroes and five depths of
> catacombs. Optional add-ons expand Heptarchia with Scandinavia, the viking raids, religion, and
> the Varangian road east to Byzantium.

---

## 8. Ütemterv (heti kb. fél óra)

| Nap | Teendő |
|---|---|
| Hétfő | egy kép vagy rövid videó X/Bluesky/Mastodon oldalra |
| Szerda | egy Short vagy TikTok |
| Péntek | fejlesztői napló (mit csináltál a héten) itch.io-ra vagy Redditre |
| Havonta | egy nagyobb bejegyzés valamelyik közösségbe (új játék, nagy frissítés) |

**Fontos:** ugyanazt a linket használd mindenhol, és az első órákban válaszolj a hozzászólásokra.

---

# HEPTARCHIA – az első kampány anyagai

A Heptarchia oldala: **https://parthenon2-boop.github.io/birodalom/heptarchia.html**
(angolul `?lang=en`, németül `?lang=de`)

## H1. Reddit – r/grandstrategy, r/strategygames, r/4Xgaming (angol)

**Cím:** Heptarchia – a free grand strategy game about the Anglo-Saxon kingdoms from 790 (solo dev, Godot)

> You take one of the kingdoms of the Heptarchy in 790 – Wessex, Mercia, Northumbria, or the Scots,
> Picts and Irish – three years before the first viking ships reach Lindisfarne.
>
> What it has: a Witan you must keep on your side, royal goals that decide how long the nobles
> tolerate you, a church you build up from a minster to an archbishopric (only where a real
> archiepiscopal see existed), population that your armies are actually recruited from, and the
> papacy in Rome that will broker peace – but a pilgrimage leaves your kingdom weaker while you
> are away.
>
> It's free, Windows and macOS, and it's in English, German and Hungarian:
> https://parthenon2-boop.github.io/birodalom/heptarchia.html?lang=en
>
> I'm a solo developer and this is the game I've spent the most time on. Ask me anything –
> especially if you know the period, I'd like to hear what feels wrong.

## H2. Reddit – r/history, r/MedievalHistory (csak ha szabad a linkelés; történelmi hangsúly)

**Cím:** I made a strategy game set in 790s Britain and tried to keep the church hierarchy accurate

> The bit I enjoyed most was the church: minsters, bishoprics, and archbishoprics that can only be
> built where a see actually existed (Canterbury, York). Old place names show up as well –
> Winchester is Wintanceaster, Exeter is Exanceaster.
> Free game, if anyone wants to poke holes in the history:
> https://parthenon2-boop.github.io/birodalom/heptarchia.html?lang=en

## H3. Magyar bejegyzés (Facebook-csoportok, Discord, Gamekapocs)

> **Heptarchia – ingyenes magyar nagystratégia a 790-es évek Britanniájában**
>
> Wessex, Mercia vagy Northumbria élén állsz, három évvel a vikingek első támadása előtt.
> Witan, királyi célok, egyház a templomtól az érsekségig, lakosságból toborzott sereg, és a
> pápaság Rómában. 793-ban megérkeznek a hajók, és onnantól minden part veszélyes.
>
> Ingyenes, magyarul, Windowsra és Macre:
> https://parthenon2-boop.github.io/birodalom/heptarchia.html
>
> Egyedül fejlesztem, minden visszajelzésnek örülök.

## H4. Rövid posztok (X, Bluesky, Mastodon)

> 790. Wessex trónján ülsz. Három éved van Lindisfarne előtt.
> Heptarchia – ingyenes nagystratégia, magyarul is.
> https://parthenon2-boop.github.io/birodalom/heptarchia.html
> #indiedev #godot #strategygame

> In 790 you take a kingdom of the Heptarchy. In 793 the ships come.
> Heptarchia – free Anglo-Saxon grand strategy, made solo in Godot.
> https://parthenon2-boop.github.io/birodalom/heptarchia.html?lang=en
> #screenshotsaturday #gamedev #strategygame

## H5. Rövid videó vázlatok (15–30 mp)

1. **„793"** – a térkép békés, majd megjelenik a sárkányorrú hajó, felirat: *Lindisfarne*.
2. **Witan** – a tanács ablaka, a támogatás sáv mozog, felirat: *„A tanács nélkül nincs király."*
3. **Egyház** – templom → püspökség → érsekség fejlődés három vágásban.
4. **Toborzás** – a falu nő, a sereg nő; felirat: *„A sereged a parasztjaidból áll."*
5. **Kiegészítők** – gyors körkép Skandináviáról és a varég útról.

## H6. Egymondatos leírás (mindenhova)

> Heptarchia: ingyenes angolszász nagystratégia 790-től – Witan, egyház, lakosság és a vikingek.
