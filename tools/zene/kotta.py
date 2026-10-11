# -*- coding: utf-8 -*-
"""Kottaírás szövegből, akkordok, és a zenei önellenőrzés.

Szólam-jelölés (egy szólam egy szöveg, a hangok szóközzel elválasztva):

    d5/2 e5/1 | f5/1 e5/.5 d5/.5 a4/1 | r/3 | c4+e4+g4/2 v60 g4/1

  * hang:      betű (c d e f g a b; a „b” a magyar H), utána # vagy b
               (félhanggal fel / le), végül az oktáv száma: c4 = egyvonalas C;
  * hossz:     a / után negyedekben (1 = negyed, .5 = nyolcad, 3 = pontozott fél);
  * r:         szünet;   + : egyszerre szóló hangok;
  * vNN:       innentől ez a hangerő (0–100);
  * |          ütemvonal – az értelmező ELLENŐRZI, hogy tényleg ütemhatárra
               esik-e, így az elírt ritmus nem csúszik szét észrevétlenül.
"""

HANG = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}
NEVEK = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "H"]


def midi(nev):
    n = nev.strip().lower()
    pc = HANG[n[0]]
    i = 1
    while i < len(n) and n[i] in "#b" and not n[i:].lstrip("-").isdigit():
        pc += 1 if n[i] == "#" else -1
        i += 1
    return 12 * (int(n[i:]) + 1) + pc


def hangnev(m):
    return "%s%d" % (NEVEK[m % 12], m // 12 - 1)


def szolam(szoveg, utemhossz, vel=0.7, hely=""):
    """Szöveg -> [(kezdet, hossz, [midi...], hangerő)] negyedekben mérve."""
    ki = []
    t = 0.0
    for szo in szoveg.split():
        if szo == "|":
            if abs(t / utemhossz - round(t / utemhossz)) > 1e-6:
                raise ValueError("%s: az ütemvonal nem ütemhatáron áll (%.3f negyednél, %d. ütem)"
                                 % (hely, t, int(t // utemhossz) + 1))
            continue
        if szo[0] == "v" and szo[1:].isdigit():
            vel = int(szo[1:]) / 100.0
            continue
        hangok, hossz = szo.split("/")
        h = float(hossz)
        if hangok != "r":
            ki.append((t, h, [midi(x) for x in hangok.split("+")], vel))
        t += h
    if abs(t / utemhossz - round(t / utemhossz)) > 1e-6:
        raise ValueError("%s: a szólam nem egész ütemnyi (%.3f negyed)" % (hely, t))
    return ki, t


# --- Akkordok ---------------------------------------------------------------

MINOSEG = {
    "": (0, 4, 7), "m": (0, 3, 7), "7": (0, 4, 7, 10), "m7": (0, 3, 7, 10),
    "dim": (0, 3, 6), "sus": (0, 5, 7),
}


def akkord(jel):
    """'Dm', 'Bb', 'F#m', 'G7' -> (alaphang hangosztálya, [hangosztályok])."""
    pc = HANG[jel[0].lower()]
    i = 1
    if i < len(jel) and jel[i] in "#b":
        pc += 1 if jel[i] == "#" else -1
        i += 1
    lepesek = MINOSEG[jel[i:]]
    return pc % 12, [(pc + l) % 12 for l in lepesek]


def terc(jel):
    """Az akkord terce félhangokban (3 = kis, 4 = nagy)."""
    i = 2 if len(jel) > 1 and jel[1] in "#b" else 1
    return MINOSEG[jel[i:]][1]


def akkordmenet(utemek, utemhossz):
    """['Dm', 'C G', ...] -> [(kezdet, hossz, jel)]; egy ütemben több akkord
    egyenlően osztozik."""
    ki = []
    for u, sor in enumerate(utemek):
        jelek = sor.split()
        h = utemhossz / len(jelek)
        for j, jel in enumerate(jelek):
            ki.append((u * utemhossz + j * h, h, jel))
    return ki


def tartomanyban(pc, also, felso):
    """A legalsó hang az [also, felso] sávban, amelynek ez a hangosztálya."""
    m = also + ((pc - also) % 12)
    return m if m <= felso else m - 12


def kozeli(pc, cel):
    """A célhoz legközelebbi hang ezzel a hangosztállyal."""
    m = cel + ((pc - cel + 6) % 12) - 6
    return m


def fekves(pcs, also, felso):
    """Az akkord minden hangja a megadott sávban, alulról fölfelé."""
    return [m for m in range(also, felso + 1) if m % 12 in pcs]


# --- Önellenőrzés -----------------------------------------------------------

def hangkeszlet(esemenyek, szolamok):
    """Szólamonként: mely hangosztályok szerepelnek, és a hangterjedelem."""
    ki = {}
    for sz, t, h, m, v in esemenyek:
        if szolamok[sz]["tipus"] == "dob":
            continue
        d = ki.setdefault(sz, {"pcs": {}, "min": 999, "max": -1, "db": 0})
        d["pcs"][m % 12] = d["pcs"].get(m % 12, 0.0) + h
        d["min"] = min(d["min"], m)
        d["max"] = max(d["max"], m)
        d["db"] += 1
    return ki


DUR = (0, 2, 4, 5, 7, 9, 11)


def hangnem_tipp(esemenyek, szolamok):
    """Melyik hétfokú (dúr-rokon) készlet fedi le legjobban a hangokat –
    a hangok időtartamával súlyozva."""
    suly = [0.0] * 12
    for sz, t, h, m, v in esemenyek:
        if szolamok[sz]["tipus"] == "dob":
            continue
        suly[m % 12] += h
    ossz = sum(suly) or 1.0
    legjobb = max(range(12), key=lambda k: sum(suly[(k + d) % 12] for d in DUR))
    fed = sum(suly[(legjobb + d) % 12] for d in DUR) / ossz
    return legjobb, fed, suly


def osszhang(esemenyek, szolamok, utem_mp, utemhossz, kuszob_mp=0.42):
    """Egyszerre szóló hangpárok: mennyi ideig szól kis szekund / nagy
    szeptim (1, 11 félhang) és tritónusz (6)? A küszöbnél hosszabb eseteket
    egyenként felsorolja. A pengetett hang a leírt hosszáig számít (utána
    már csak halkan cseng)."""
    hangok = []
    for sz, t, h, m, v in esemenyek:
        d = szolamok[sz]
        if d["tipus"] in ("dob",):
            continue
        hossz = h * d.get("artik", 1.0)
        hangok.append((t * utem_mp, (t + hossz) * utem_mp, m, sz, t))
    hangok.sort()
    ossz = {1: 0.0, 6: 0.0}
    teljes = 0.0
    esetek = []
    for i, (k1, v1, m1, s1, t1) in enumerate(hangok):
        j = i + 1
        while j < len(hangok) and hangok[j][0] < v1:
            k2, v2, m2, s2, t2 = hangok[j]
            j += 1
            atf = min(v1, v2) - k2
            if atf <= 0.0:
                continue
            teljes += atf
            kul = abs(m1 - m2) % 12
            if kul in (1, 11):
                ossz[1] += atf
            elif kul == 6:
                ossz[6] += atf
            else:
                continue
            if atf >= kuszob_mp:
                esetek.append((atf, kul, int(max(t1, t2) // utemhossz) + 1,
                               s1, hangnev(m1), s2, hangnev(m2)))
    esetek.sort(reverse=True)
    return ossz, teljes, esetek


def dallam_akkord(esemenyek, dallamok, menet, min_hossz=1.0):
    """A dallamszólamok legalább negyed hosszú hangjai közül hány akkordhang
    az éppen szóló akkordban? Visszaadja az arányt és a kivételeket."""
    ok = 0
    ossz = 0
    kivetel = []
    for sz, t, h, m, v in esemenyek:
        if sz not in dallamok or h < min_hossz:
            continue
        jel = None
        for k, hh, j in menet:
            if k - 1e-6 <= t < k + hh - 1e-6:
                jel = j
                break
        if jel is None:
            continue
        ossz += 1
        if m % 12 in akkord(jel)[1]:
            ok += 1
        else:
            kivetel.append((t, sz, hangnev(m), h, jel))
    return ok, ossz, kivetel
