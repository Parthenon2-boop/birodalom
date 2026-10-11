# -*- coding: utf-8 -*-
"""A Birodalom négy korszakzenéje – kotta adatként.

Mind a négy saját szerzemény. Minden darab formarészekből áll; egy rész
akkordmenetet és kiírt dallamokat tartalmaz, a kíséretet (lantbontás, járó
basszus, indulókíséret, ostinato) az akkordokból minták állítják elő.
A jelölés leírása a kotta.py elején van.

Egy darab = szótár:
  tempo (negyed/perc), utemhossz (negyedekben), szolamok (hangszer, erősség,
  panoráma, zengetés), esemenyek [(szólam, kezdet, hossz, hang, hangerő)],
  menet [(kezdet, hossz, akkord)], dallamok (mely szólamok visznek dallamot).
"""
from kotta import szolam, akkord, terc, akkordmenet, tartomanyban, fekves


class Darab:
    def __init__(self, nev, fajl, tempo, utemhossz, szolamok, zengo, leiras):
        self.nev = nev
        self.fajl = fajl
        self.tempo = tempo
        self.utemhossz = float(utemhossz)
        self.szolamok = szolamok
        self.zengo = zengo
        self.leiras = leiras
        self.esemenyek = []
        self.menet = []
        self.dallamok = set()
        self.forma = []          # (rész neve, kezdő ütem, ütemek száma)
        self.t = 0.0             # hol tartunk (negyedekben)

    def resz(self, nev, akkordok):
        """Új formarész: felveszi az akkordjait, és visszaadja a kezdetét."""
        kezd = self.t
        for k, h, jel in akkordmenet(akkordok, self.utemhossz):
            self.menet.append((kezd + k, h, jel))
        self.forma.append((nev, int(round(kezd / self.utemhossz)) + 1, len(akkordok)))
        self.t += len(akkordok) * self.utemhossz
        return kezd

    def hang(self, sz, t, h, m, v):
        self.esemenyek.append((sz, t, h, m, max(0.05, min(1.0, v))))

    def ir(self, sz, kezd, szoveg, vel=0.7, eltolas=0, dallam=True):
        """Kiírt szólam a rész elejétől; eltolas: transzponálás félhangban."""
        hangok, _ = szolam(szoveg, self.utemhossz, vel, "%s/%s" % (self.nev, sz))
        for t, h, mk, v in hangok:
            for m in mk:
                self.hang(sz, kezd + t, h, m + eltolas, v)
        if dallam:
            self.dallamok.add(sz)

    def dobok(self, sz, kezd, utemek, minta, szorzo=1.0):
        for u in utemek:
            for hely, nev, v in minta:
                self.hang(sz, kezd + u * self.utemhossz + hely, 0.25, nev, v * szorzo)

    @property
    def utemek(self):
        return int(round(self.t / self.utemhossz))

    def reszmenet(self, kezd, db):
        """A rész akkordjai: [(kezdet, hossz, jel)] a kezdettől db ütemig."""
        veg = kezd + db * self.utemhossz
        return [(k, h, j) for k, h, j in self.menet if kezd - 1e-6 <= k < veg - 1e-6]


def sz(tipus, hsz, eros, pan, zeng, artik=1.0, ember=4.0):
    return dict(tipus=tipus, hsz=hsz, eros=eros, pan=pan, zeng=zeng, artik=artik, ember=ember)


# ===========================================================================
# 0. korszak – 15. század: „Udvari tánc”  (d-dór, 3/4)
# ===========================================================================
#
# Modális menet: nincs vezetőhangos zárlat, a mozgás a Dm – C – G – F – Am
# hangzatok között jár (a G-dúr a dór skála jellegzetes h hangjával).

def kor0():
    d = Darab(
        "Udvari tánc", "music_age0", tempo=96, utemhossz=3,
        szolamok={
            "furulya": sz("tartott", "furulya", 0.95, -0.15, 0.34, 0.93),
            "sip":     sz("tartott", "sip", 0.80, 0.28, 0.30, 0.95),
            "lant":    sz("pengetett", "lant", 0.72, -0.38, 0.22, 1.0, 6.0),
            "harfa":   sz("pengetett", "harfa", 0.75, 0.40, 0.30, 1.0, 6.0),
            "burdon":  sz("tartott", "burdon", 0.50, 0.0, 0.25, 1.0, 0.0),
            "kezidob": sz("dob", None, 0.75, 0.12, 0.18, 1.0, 3.0),
        },
        zengo=(1.5, 1.3, 0.75, 0.30),
        leiras="d-dór, 3/4, furulya és nádsíp dallam, lant- és hárfapengetés, burdon, kézidob",
    )
    U = d.utemhossz

    def lant(kezd, db, minta, v=1.0):
        for k, h, jel in d.reszmenet(kezd, db):
            pc, _ = akkord(jel)
            R = tartomanyban(pc, 43, 54)
            T = R + 12 + terc(jel)
            if minta == "negyed":
                for i, (m, e) in enumerate(((R, .75), (R + 7, .5), (R + 12, .55))):
                    d.hang("lant", k + i, 1.0, m, e * v)
            elif minta == "bontas":
                for i, (m, e) in enumerate(((R, .80), (R + 7, .50), (R + 12, .60), (T, .55), (R + 7, .45), (R + 12, .55))):
                    d.hang("lant", k + i * .5, 0.5, m, e * v)
            elif minta == "hullam":
                for i, (m, e) in enumerate(((R, .75), (R + 7, .50), (R + 12, .55), (T, .60), (R + 19, .50), (T, .50))):
                    d.hang("lant", k + i * .5, 0.5, m, e * v)
            elif minta == "tanc":
                for j, m in enumerate((R, R + 7, R + 12)):
                    d.hang("lant", k + j * 0.04, 1.0, m, (.80 - j * .08) * v)
                for hely, m, e in ((1.0, T, .55), (1.5, R + 7, .45), (2.0, R + 12, .60), (2.5, R + 7, .45)):
                    d.hang("lant", k + hely, 0.5, m, e * v)

    def burdon(kezd, db, v=0.55):
        for k, h, jel in d.reszmenet(kezd, db):
            R = tartomanyban(akkord(jel)[0], 43, 54)
            d.hang("burdon", k, h, R, v)
            d.hang("burdon", k, h, R + 7, v * 0.8)

    def harfa_akkord(kezd, db, v=0.55):
        """Ütemenként egy lassan megpendített hárfaakkord (kvint–oktáv–kvint)."""
        for k, h, jel in d.reszmenet(kezd, db):
            R = tartomanyban(akkord(jel)[0], 55, 66)
            for j, m in enumerate((R, R + 7, R + 12)):
                d.hang("harfa", k + j * 0.09, 2.0, m, v - j * 0.04)

    # --- Bevezetés: burdon, lant és hárfa (ide tér vissza az ismétlés) ---
    k = d.resz("bevezetés", ["Dm", "Dm", "C", "Dm"])
    lant(k, 4, "negyed", 1.0)
    harfa_akkord(k, 4)
    burdon(k, 4, 0.70)
    d.dobok("kezidob", k, (2, 3), ((0, "dum", .45),))

    # --- A: a főtéma furulyán ---
    A = ["Dm", "Dm", "C", "Dm", "F", "C", "Am", "Dm"]
    k = d.resz("A", A)
    d.ir("furulya", k, "v72 d5/2 e5/1 | f5/1 e5/.5 d5/.5 a4/1 | c5/1 e5/1 g5/1 | f5/1.5 e5/.5 d5/1 | "
                       "a5/2 g5/1 | g5/1 f5/.5 e5/.5 c5/1 | e5/1 d5/.5 c5/.5 b4/.5 a4/.5 | d5/3")
    lant(k, 8, "bontas")
    burdon(k, 8)
    d.dobok("kezidob", k, range(8), ((0, "dum", .65), (2, "tak", .42)))

    # --- A': változat, a G-dúr hangzat h hangjával; a hárfa oktávval lejjebb kíséri ---
    k = d.resz("A'", ["Dm", "G", "C", "Dm", "F", "C", "C", "Dm"])
    dallam = ("d5/1 a5/2 | b5/1 a5/.5 g5/.5 d5/1 | e5/1 g5/1 c6/1 | a5/1.5 g5/.5 f5/1 | "
              "a5/1 c6/1 a5/1 | g5/1.5 f5/.5 e5/1 | e5/.5 f5/.5 g5/1 e5/1 | d5/3")
    d.ir("furulya", k, "v74 " + dallam)
    d.ir("harfa", k, "v48 " + dallam, eltolas=-12, dallam=False)
    lant(k, 8, "bontas")
    burdon(k, 8)
    d.dobok("kezidob", k, range(8), ((0, "dum", .65), (1.5, "tak", .32), (2, "tak", .45)))

    # --- B: a nádsíp felel, a lant hullámzó bontással ---
    k = d.resz("B", ["F", "F", "C", "C", "G", "Dm", "C", "Am"])
    d.ir("sip", k, "v82 c5/1 a4/1 c5/1 | f5/2 e5/.5 d5/.5 | e5/1.5 d5/.5 c5/1 | g4/3 | "
                   "b4/1 d5/1 g5/1 | f5/1.5 e5/.5 d5/1 | e5/1 c5/1 e5/1 | e5/2 r/1")
    lant(k, 8, "hullam", 1.0)
    harfa_akkord(k, 8, 0.50)
    burdon(k, 8, 0.62)
    d.dobok("kezidob", k, range(8), ((0, "dum", .5),))

    # --- A'': a téma díszítve, alatta a síp hosszú hangjai ---
    k = d.resz("A''", ["Dm", "Dm", "C", "Dm", "F", "G", "C", "Dm"])
    d.ir("furulya", k, "v75 d5/1 e5/.5 f5/.5 a5/1 | f5/1 e5/.5 d5/.5 a4/1 | c5/.5 d5/.5 e5/1 g5/1 | f5/1.5 e5/.5 d5/1 | "
                       "a5/2 c6/1 | b5/1 a5/.5 g5/.5 d5/1 | e5/1 g5/1 e5/1 | d5/3")
    d.ir("sip", k, "v42 a4/3 | a4/3 | g4/3 | a4/3 | c5/3 | b4/3 | g4/3 | a4/3", dallam=False)
    lant(k, 8, "bontas")
    burdon(k, 8)
    d.dobok("kezidob", k, range(8), ((0, "dum", .68), (1.5, "tak", .32), (2, "tak", .46)))

    # --- C: táncos közjáték – a hárfa viszi, majd a furulya fölé lép ---
    k = d.resz("C", ["G", "G", "Dm", "Dm", "F", "C", "Am", "Am"])
    d.ir("harfa", k, "v72 d5/1 b4/.5 g4/.5 b4/1 | d5/1 e5/.5 d5/.5 b4/1 | a4/1 d5/.5 f5/.5 d5/1 | f5/1 e5/.5 d5/.5 a4/1 | "
                     "v55 c5/1 a4/1 f4/1 | e4/1 g4/1 c5/1 | a4/1 e4/1 c4/1 | e4/3")
    d.ir("furulya", k, "r/3 | r/3 | r/3 | r/3 | v72 c6/2 a5/1 | g5/1.5 e5/.5 g5/1 | a5/1 e5/1 c5/1 | e5/3")
    lant(k, 8, "tanc")
    burdon(k, 8)
    d.dobok("kezidob", k, range(8), ((0, "dum", .75), (1, "tak", .40), (1.5, "tak", .30), (2, "dum", .45), (2.5, "tak", .36)))

    # --- Átvezetés: elcsendesedik, és a d-re visszavezet ---
    k = d.resz("átvezetés", ["Dm", "C", "Am", "Am"])
    d.ir("furulya", k, "v62 d5/2 f5/1 | e5/2 c5/1 | a4/3 | r/3")
    lant(k, 4, "negyed", 1.0)
    harfa_akkord(k, 4)
    burdon(k, 4, 0.65)
    d.dobok("kezidob", k, (0, 1), ((0, "dum", .5),))
    return d


# ===========================================================================
# 1. korszak – 17. század: „Palotabeli muzsika”  (G-dúr, 4/4)
# ===========================================================================
#
# Barokk szerkezet: félütemenként váltó harmónia, járó nyolcad-basszus,
# csembaló-bontás, a középrészben e-moll és kvintlépő szekvencia.

def kor1():
    d = Darab(
        "Palotabeli muzsika", "music_age1", tempo=84, utemhossz=4,
        szolamok={
            "hegedu":   sz("tartott", "szolo", 0.80, -0.22, 0.30, 0.95),
            "fuvola":   sz("tartott", "furulya", 0.62, 0.26, 0.32, 0.93),
            "csembalo": sz("pengetett", "csembalo", 0.95, 0.16, 0.20, 0.95, 5.0),
            "basszus":  sz("tartott", "melyvonos", 0.60, 0.04, 0.18, 0.86, 4.0),
            "vonosok":  sz("tartott", "vonos", 0.36, -0.10, 0.36, 1.0, 0.0),
        },
        zengo=(1.7, 1.5, 0.85, 0.30),
        leiras="G-dúr (középrész e-moll), 4/4, szólóhegedű és fuvola, csembaló, járó basszus, vonós continuo",
    )
    DUR_G = {7, 9, 11, 0, 2, 4, 6}
    MOLL_E = {4, 6, 7, 9, 11, 0, 2, 3}

    def basszus(kezd, db, skala):
        menet = d.reszmenet(kezd, db)
        elozo = 43
        gyokok = []
        for k, h, jel in menet:
            pc = akkord(jel)[0]
            R = min((m for m in range(38, 51) if m % 12 == pc), key=lambda m: abs(m - elozo))
            gyokok.append(R)
            elozo = R
        for i, (k, h, jel) in enumerate(menet):
            R = gyokok[i]
            T = R + terc(jel)
            N = gyokok[i + 1] if i + 1 < len(menet) else 43      # a rész után G jön
            ugyanaz = i + 1 < len(menet) and menet[i + 1][2] == jel
            if ugyanaz:
                hangok = [R, R + 7, T, R + 7]
            else:
                if R + 7 > N:
                    kozelito = N + 1 if (N + 1) % 12 in skala else N + 2
                else:
                    kozelito = N - 1 if (N - 1) % 12 in skala else N - 2
                hangok = [R, T, R + 7, kozelito]
            for j, m in enumerate(hangok):
                d.hang("basszus", k + j * .5, 0.5, m, (.78, .55, .62, .55)[j])

    def csembalo(kezd, db, minta, v=1.0):
        for k, h, jel in d.reszmenet(kezd, db):
            pc, pcs = akkord(jel)
            R = tartomanyban(pc, 43, 54)
            f = fekves(pcs, 59, 71)[:3]
            if minta == "tort":
                d.hang("csembalo", k, 1.0, R, .70 * v)
                for j, m in enumerate(f):
                    d.hang("csembalo", k + j * 0.045, 0.5, m, (.62 - j * .04) * v)
                d.hang("csembalo", k + .5, 0.5, f[1], .45 * v)
                d.hang("csembalo", k + 1.0, 0.5, f[2], .55 * v)
                d.hang("csembalo", k + 1.0, 0.5, f[0], .45 * v)
                d.hang("csembalo", k + 1.5, 0.5, f[1], .45 * v)
            elif minta == "futo":
                d.hang("csembalo", k, 1.0, R, .68 * v)
                for j, i in enumerate((0, 1, 2, 1, 0, 1, 2, 1)):
                    d.hang("csembalo", k + j * .25, 0.25, f[i], (.55 if j % 4 == 0 else .40) * v)
            elif minta == "nyugodt":
                d.hang("csembalo", k, 2.0, R, .62 * v)
                for j, m in enumerate(f):
                    d.hang("csembalo", k + j * 0.06, 1.0, m, (.55 - j * .03) * v)
                d.hang("csembalo", k + 1.0, 1.0, f[1], .42 * v)
                d.hang("csembalo", k + 1.0, 1.0, f[2], .46 * v)

    def vonosok(kezd, db, v=0.5):
        for k, h, jel in d.reszmenet(kezd, db):
            for m in fekves(akkord(jel)[1], 55, 67)[:3]:
                d.hang("vonosok", k, h, m, v)

    # --- A: a téma hegedűn ---
    A = ["G G", "C D", "G Em", "Am D", "Em Am", "D G", "C Am", "D D"]
    k = d.resz("A", A)
    d.ir("hegedu", k, "v72 d5/1.5 b4/.5 g4/1 b4/.5 d5/.5 | e5/1.5 d5/.25 c5/.25 d5/1 a4/1 | b4/1 d5/1 g5/1.5 f#5/.5 | "
                      "e5/1 c5/1 d5/.5 e5/.5 f#5/1 | b5/.5 g5/.5 e5/.5 g5/.5 a5/.5 e5/.5 c5/.5 e5/.5 | "
                      "a5/.5 f#5/.5 d5/.5 f#5/.5 g5/.5 d5/.5 b4/.5 d5/.5 | e5/1.5 d5/.5 c5/1 b4/.5 a4/.5 | "
                      "a4/1.5 b4/.25 c5/.25 d5/1 f#5/1")
    basszus(k, 8, DUR_G)
    csembalo(k, 8, "tort")
    vonosok(k, 8)

    # --- A': díszítettebb változat, a csembaló futamokkal, teljes zárlat ---
    k = d.resz("A'", ["G G", "C D", "G Em", "Am D", "Em Am", "D G", "C D", "G G"])
    d.ir("hegedu", k, "v74 d5/1.5 b4/.5 g4/.5 a4/.5 b4/.5 d5/.5 | e5/1 g5/.5 e5/.5 f#5/1 d5/1 | g5/1.5 d5/.5 e5/1 b4/1 | "
                      "c5/.5 b4/.5 c5/.5 e5/.5 d5/1 f#5/1 | b5/.5 g5/.5 e5/.5 g5/.5 a5/.5 e5/.5 c5/.5 e5/.5 | "
                      "a5/.5 f#5/.5 d5/.5 f#5/.5 g5/.5 d5/.5 b4/.5 d5/.5 | "
                      "e5/1 g5/1 g5/.25 f#5/.25 g5/.25 f#5/.25 f#5/.5 g5/.5 | g5/3 r/1")
    basszus(k, 8, DUR_G)
    csembalo(k, 8, "futo")
    vonosok(k, 8)

    # --- B: e-moll, a fuvola énekel, a hegedű hosszú hangokkal kíséri ---
    k = d.resz("B", ["Em Em", "Am B", "Em C", "Am B", "Em Am", "D G", "C Am", "B B"])
    d.ir("fuvola", k, "v72 e5/1.5 f#5/.5 g5/1 b5/1 | a5/1.5 g5/.5 f#5/1 d#5/1 | e5/1 g5/1 e5/1 c5/1 | "
                      "c5/.5 d5/.5 e5/1 d#5/1 b4/1 | g5/.5 f#5/.5 e5/1 a5/.5 g5/.5 e5/1 | "
                      "f#5/.5 e5/.5 d5/1 g5/.5 f#5/.5 d5/1 | e5/.5 d5/.5 c5/1 c5/.5 b4/.5 a4/1 | b4/1.5 d#5/.5 f#5/2")
    d.ir("hegedu", k, "v48 b4/2 b4/2 | c5/2 b4/2 | b4/2 c5/2 | c5/2 b4/2 | b4/2 a4/2 | a4/2 g4/2 | g4/2 a4/2 | f#4/3 r/1",
         dallam=False)
    basszus(k, 8, MOLL_E)
    csembalo(k, 8, "nyugodt")
    vonosok(k, 8, 0.45)

    # --- A'': visszatérés, hegedű és fuvola együtt; a vége a kezdetre vezet ---
    k = d.resz("A''", ["G G", "C D", "G Em", "Am D", "G C", "Am D", "C D", "G D"])
    tema = ("g5/1.5 d5/.5 b4/1 d5/.5 g5/.5 | e5/1.5 d5/.25 c5/.25 d5/1 a4/1 | b4/1 d5/1 g5/1.5 f#5/.5 | "
            "e5/1 c5/1 d5/.5 e5/.5 f#5/1 | b5/1 g5/1 g5/1 e5/1 | c5/.5 e5/.5 a5/1 f#5/.5 a5/.5 d5/1 | "
            "e5/1 g5/1 g5/.25 f#5/.25 g5/.25 f#5/.25 f#5/.5 g5/.5 | g5/2 r/1 f#4/.5 a4/.5")
    d.ir("hegedu", k, "v76 " + tema)
    d.ir("fuvola", k, "v55 " + tema)
    basszus(k, 8, DUR_G)
    csembalo(k, 8, "tort")
    vonosok(k, 8)
    return d


# ===========================================================================
# 2. korszak – 19. század: „Díszszemle”  (Esz-dúr, 4/4, induló)
# ===========================================================================
#
# Indulólüktetés (basszus az egyen és hármon, akkord a kettőn és négyen,
# pergődob), széles ívű dallam a hegedűkön és kürtökön; a trió (Asz-dúr)
# pergő nélkül, klarinéttal és pizzicatóval pihenteti a fület.

def kor2():
    d = Darab(
        "Díszszemle", "music_age2", tempo=100, utemhossz=4,
        szolamok={
            "hegeduk":  sz("tartott", "vonos", 0.85, -0.26, 0.36, 0.95, 5.0),
            "kurt":     sz("tartott", "kurt", 0.80, 0.22, 0.36, 0.95, 5.0),
            "klarinet": sz("tartott", "sip", 0.55, 0.10, 0.34, 0.95),
            "kurtok":   sz("tartott", "kurt", 0.42, 0.30, 0.36, 1.0, 0.0),
            "harsona":  sz("tartott", "harsona", 0.45, 0.14, 0.30, 1.0, 0.0),
            "basszus":  sz("tartott", "melyvonos", 0.75, 0.0, 0.16, 0.80, 3.0),
            "utem":     sz("tartott", "vonos_r", 0.58, -0.10, 0.26, 0.60, 3.0),
            "pizz":     sz("pengetett", "pizz", 0.80, -0.20, 0.26, 1.0, 4.0),
            "pergo":    sz("dob", None, 0.70, 0.10, 0.20, 1.0, 2.0),
            "nagydob":  sz("dob", None, 0.60, 0.0, 0.14, 1.0, 2.0),
        },
        zengo=(1.8, 1.6, 0.9, 0.30),
        leiras="Esz-dúr (trió: Asz-dúr), 4/4 induló, hegedűk és kürtök, klarinét, harsona, pergődob, nagydob",
    )

    def indulo(kezd, db, v=1.0, hosszu=False):
        menet = d.reszmenet(kezd, db)
        for i, (k, h, jel) in enumerate(menet):
            pc, pcs = akkord(jel)
            R = tartomanyban(pc, 36, 47)
            masodik = i > 0 and menet[i - 1][2] == jel and abs(k / 4.0 - round(k / 4.0)) > 1e-6
            m = R
            if masodik:                       # ugyanaz az akkord az ütem második felében: kvint
                m = R + 7 if R + 7 <= 48 else R - 5
            if hosszu:
                d.hang("basszus", k, 2.0 * 1.2, m, .55 * v)
            else:
                d.hang("basszus", k, 1.0, m, .75 * v)
                for q in fekves(pcs, 55, 67)[:3]:
                    d.hang("utem", k + 1.0, 0.5, q, .50 * v)

    def kurtok(kezd, db, v=0.5, harsona=False):
        for k, h, jel in d.reszmenet(kezd, db):
            pc, pcs = akkord(jel)
            for m in fekves(pcs, 53, 64)[:2]:
                d.hang("kurtok", k, h, m, v)
            if harsona:
                d.hang("harsona", k, h, tartomanyban(pc, 43, 54), v)

    def pizz(kezd, db):
        for k, h, jel in d.reszmenet(kezd, db):
            f = fekves(akkord(jel)[1], 55, 70)
            d.hang("pizz", k, 1.0, f[0], .55)
            d.hang("pizz", k + 1.0, 1.0, f[2], .48)

    P1 = ((0, "pergo", .55), (1, "pergo", .40), (1.5, "pergo_h", .34), (2, "pergo", .52), (3, "pergo", .40), (3.5, "pergo_h", .34))
    P2 = ((0, "pergo", .55), (1, "pergo", .40), (1.5, "pergo_h", .34), (2, "pergo", .52),
          (3, "pergo_h", .34), (3.25, "pergo_h", .36), (3.5, "pergo_h", .40), (3.75, "pergo_h", .44))
    ND = ((0, "nagydob", .62), (2, "nagydob", .45))

    def dobok(kezd, db, v=1.0):
        for u in range(db):
            d.dobok("pergo", kezd, (u,), P2 if u % 4 == 3 else P1, v)
        d.dobok("nagydob", kezd, range(db), ND, v)

    # --- Bevezetés: dobszó, lépő basszus, halk kürthívás ---
    k = d.resz("bevezetés", ["Eb Eb", "Eb Eb", "Ab Eb", "Bb Bb"])
    d.ir("kurt", k, "v72 bb3/1.5 bb3/.5 eb4/2 | g4/1.5 eb4/.5 bb3/2 | c4/1 ab3/1 bb3/1 g3/1 | bb3/1 d4/1 f4/2")
    indulo(k, 4, 1.0)
    kurtok(k, 4, 0.50, harsona=True)
    dobok(k, 4, 0.9)

    # --- A: főtéma, hegedűk, alattuk oktávval a kürt ---
    A = ["Eb Eb", "Ab Eb", "Cm Fm", "Bb Bb", "Eb Eb", "Ab Eb", "Fm Bb", "Eb Eb"]
    tema = ("eb5/1.5 bb4/.5 eb5/1 g5/1 | ab5/1.5 f5/.5 g5/1 eb5/1 | g5/1 eb5/.5 c5/.5 f5/1 ab5/1 | f5/2 d5/1 bb4/1 | "
            "eb5/1.5 bb4/.5 eb5/1 g5/1 | c6/1.5 ab5/.5 bb5/1 g5/1 | ab5/1 f5/1 f5/1.5 d5/.5 | eb5/3 r/1")
    k = d.resz("A", A)
    d.ir("hegeduk", k, "v70 " + tema)
    d.ir("kurt", k, "v55 " + tema, eltolas=-12)
    indulo(k, 8)
    kurtok(k, 8, 0.42)
    dobok(k, 8)

    # --- A': a dallam följebb lép, kitérés c-moll felé ---
    k = d.resz("A'", ["Eb Eb", "Cm Cm", "Ab Fm", "Bb Bb", "Eb G", "Cm Ab", "Eb Bb", "Eb Eb"])
    d.ir("hegeduk", k, "v74 g5/1.5 ab5/.5 bb5/2 | c6/1.5 bb5/.5 g5/1 eb5/1 | ab5/1 c6/1 ab5/1 f5/1 | bb5/2 f5/1 d5/1 | "
                       "bb5/1 g5/1 g5/1 b5/1 | c6/1.5 g5/.5 ab5/1 eb5/1 | g5/1 bb5/1 f5/1.5 eb5/.5 | eb5/3 r/1")
    indulo(k, 8)
    kurtok(k, 8, 0.5)
    dobok(k, 8)

    # --- B (trió): Asz-dúr, klarinét, pizzicato, hosszú basszus – dob nélkül ---
    k = d.resz("trió", ["Ab Ab", "Db Ab", "Bbm Eb", "Ab Ab", "Fm Fm", "Db Db", "Ab Fm", "Bb Bb"])
    d.ir("klarinet", k, "v70 c5/2 eb5/1.5 c5/.5 | f5/2 eb5/1 c5/1 | db5/1 f5/1 eb5/1.5 db5/.5 | c5/3 r/1 | "
                        "c5/1 f5/1 ab5/2 | bb5/1.5 ab5/.5 f5/2 | eb5/1 c5/1 f5/1 ab5/1 | f5/2 d5/1 bb4/1")
    indulo(k, 8, 1.0, hosszu=True)
    pizz(k, 8)
    kurtok(k, 8, 0.40)
    d.dobok("nagydob", k, range(8), ((0, "nagydob", .38),))

    # --- A'': a főtéma teljes zenekarral ---
    k = d.resz("A''", A)
    d.ir("hegeduk", k, "v76 " + tema)
    d.ir("kurt", k, "v60 " + tema, eltolas=-12)
    indulo(k, 8)
    kurtok(k, 8, 0.48, harsona=True)
    dobok(k, 8)

    # --- Zárórész: a domináns hangzaton megáll, és a bevezetésre vezet ---
    k = d.resz("zárórész", ["Eb Ab", "Eb Cm", "Fm Bb", "Bb Bb"])
    veg = "g5/1 bb5/1 ab5/1 c6/1 | bb5/1 g5/1 eb5/1 g5/1 | f5/1 ab5/1 f5/1 d5/1 | bb4/2 r/2"
    d.ir("hegeduk", k, "v72 " + veg)
    d.ir("kurt", k, "v56 " + veg, eltolas=-12)
    indulo(k, 4)
    kurtok(k, 4, 0.45, harsona=True)
    dobok(k, 4)
    return d


# ===========================================================================
# 3. korszak – 20. század: „Hosszú menet”  (c-moll, 4/4, lassú induló)
# ===========================================================================
#
# Komor, de nem zajos: mélyvonós nyolcad-ostinato, lassú gyászinduló-ritmus
# tompított dobon, a dallam mély rezeken; a középrész (Esz-dúr felé) rövid
# időre kivilágosodik a hegedűkön, aztán visszasötétül.

def kor3():
    d = Darab(
        "Hosszú menet", "music_age3", tempo=75, utemhossz=4,
        szolamok={
            "kurtok":   sz("tartott", "kurt", 0.95, 0.20, 0.40, 0.97, 5.0),
            "harsonak": sz("tartott", "harsona", 0.55, 0.10, 0.36, 0.97, 5.0),
            "hegeduk":  sz("tartott", "vonos", 0.85, -0.26, 0.42, 0.97, 5.0),
            "sip":      sz("tartott", "sip", 0.70, -0.10, 0.40, 0.95),
            "ostinato": sz("tartott", "melyvonos", 0.70, -0.10, 0.22, 0.62, 3.0),
            "melyrez":  sz("tartott", "harsona", 0.50, 0.0, 0.30, 1.0, 0.0),
            "vonospad": sz("tartott", "vonos", 0.34, 0.12, 0.42, 1.0, 0.0),
            "nagydob":  sz("dob", None, 0.70, 0.0, 0.18, 1.0, 2.0),
            "tompadob": sz("dob", None, 0.80, 0.12, 0.24, 1.0, 2.0),
            "ustdob":   sz("ust", None, 0.62, -0.05, 0.28, 1.0, 2.0),
        },
        zengo=(2.3, 2.0, 1.0, 0.34),
        leiras="c-moll (középrész Esz-dúr felé), 4/4 lassú induló, kürtök és harsonák, mélyvonós ostinato, tompított dob, üstdob",
    )

    def ostinato(kezd, db, v=1.0):
        for k, h, jel in d.reszmenet(kezd, db):
            R = tartomanyban(akkord(jel)[0], 36, 47)
            T = R + 12 + terc(jel)
            for j, (m, e) in enumerate(((R, .72), (R + 7, .45), (R + 12, .56), (R + 7, .45),
                                         (T, .60), (R + 7, .45), (R + 12, .56), (R + 7, .45))):
                d.hang("ostinato", k + j * .5, 0.5, m, e * v)

    def melyrez(kezd, db, v=0.5):
        for k, h, jel in d.reszmenet(kezd, db):
            d.hang("melyrez", k, h, tartomanyban(akkord(jel)[0], 36, 47), v)

    def pad(kezd, db, v=0.42):
        for k, h, jel in d.reszmenet(kezd, db):
            for m in fekves(akkord(jel)[1], 55, 67)[:3]:
                d.hang("vonospad", k, h, m, v)

    def ust(kezd, utemek, v=0.5):
        menet = d.reszmenet(kezd, 99)
        for u in utemek:
            k, h, jel = menet[u]
            d.hang("ustdob", k, 1.5, tartomanyban(akkord(jel)[0], 41, 52), v)

    GYASZ = ((1, "tompa", .42), (1.75, "tompa", .30), (2, "tompa", .46), (3, "tompa", .40))
    ND = ((0, "nagydob", .70), (2, "nagydob", .48))

    # --- Bevezetés: a lüktetés, fölötte a kürtök hosszú hangjai ---
    k = d.resz("bevezetés", ["Cm", "Cm", "Ab", "G"])
    ostinato(k, 4, 1.0)
    d.dobok("nagydob", k, range(4), ND, 0.9)
    d.dobok("tompadob", k, range(4), GYASZ, 0.8)
    melyrez(k, 4, 0.58)
    pad(k, 4, 0.52)
    ust(k, (0, 2), 0.42)
    d.ir("kurtok", k, "v54 c4/4 | g3/4 | v58 ab3/2 c4/2 | b3/2 g3/2")

    # --- A: a téma kürtökön, alattuk oktávval a harsonák ---
    A = ["Cm", "Cm", "Ab", "Ab", "Fm", "Cm", "G", "G"]
    tema = ("g3/2 c4/2 | eb4/3 d4/.5 c4/.5 | ab3/1 c4/1 eb4/2 | f4/1 eb4/1 c4/2 | "
            "ab4/3 g4/.5 f4/.5 | g4/2 eb4/2 | d4/2 b3/1 d4/1 | g3/3 r/1")
    k = d.resz("A", A)
    d.ir("kurtok", k, "v68 " + tema)
    d.ir("harsonak", k, "v52 " + tema, eltolas=-12)
    ostinato(k, 8)
    melyrez(k, 8, 0.45)
    pad(k, 8, 0.36)
    d.dobok("nagydob", k, range(8), ND)
    d.dobok("tompadob", k, range(8), GYASZ)

    # --- B: a hegedűk világosabb dallama; a dob elhallgat ---
    k = d.resz("B", ["Eb", "Bb", "Fm", "Cm", "Ab", "Eb", "Fm", "G"])
    d.ir("hegeduk", k, "v66 g4/2 bb4/2 | d5/2 bb4/1 f4/1 | ab4/1 c5/1 f5/2 | eb5/3 d5/.5 c5/.5 | "
                       "c5/2 eb5/2 | g5/3 eb5/1 | f5/2 c5/1 ab4/1 | d5/2 b4/1 g4/1")
    ostinato(k, 8, 0.78)
    melyrez(k, 8, 0.42)
    pad(k, 8, 0.46)
    d.dobok("nagydob", k, range(8), ((0, "nagydob", .5),))
    ust(k, (0, 2, 4, 6), 0.40)
    for j in range(8):                                    # üstdob-pergés a domináns hangon
        d.hang("ustdob", k + 7 * 4 + 2 + j * .25, 0.4, 43, 0.22 + j * 0.035)

    # --- A': a téma változata rezeken, fölötte halkan a hegedűk ---
    k = d.resz("A'", ["Cm", "Cm", "Ab", "Ab", "Fm", "Fm", "G", "Cm"])
    tema2 = ("g3/2 c4/2 | eb4/2 g4/2 | ab4/3 g4/.5 f4/.5 | eb4/2 c4/2 | "
             "f4/2 ab4/1 c5/1 | c5/1.5 bb4/.5 ab4/2 | g4/2 d4/1 b3/1 | c4/3 r/1")
    d.ir("kurtok", k, "v72 " + tema2)
    d.ir("harsonak", k, "v55 " + tema2, eltolas=-12)
    d.ir("hegeduk", k, "v44 " + tema2, eltolas=12, dallam=False)
    ostinato(k, 8)
    melyrez(k, 8, 0.48)
    pad(k, 8, 0.38)
    d.dobok("nagydob", k, range(8), ND)
    d.dobok("tompadob", k, range(8), GYASZ)
    ust(k, (0, 2, 4, 6, 7), 0.45)

    # --- Átvezetés: magányos nádsíp, majd vissza a lüktetéshez ---
    k = d.resz("átvezetés", ["Cm", "Ab", "Fm", "G"])
    d.ir("sip", k, "v80 g4/2 g4/1 c5/1 | eb5/2 c5/2 | ab4/2 f4/2 | d4/2 r/2")
    ostinato(k, 4, 1.0)
    melyrez(k, 4, 0.55)
    pad(k, 4, 0.50)
    d.dobok("nagydob", k, range(4), ND, 0.85)
    d.dobok("tompadob", k, range(4), GYASZ, 0.8)
    return d


DARABOK = [kor0, kor1, kor2, kor3]
