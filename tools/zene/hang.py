# -*- coding: utf-8 -*-
"""Hangszintézis a Birodalom korszakzenéihez – csak numpy kell hozzá.

Minden hang kódból készül, mintafájl nélkül:
  * tartott hangok (vonós, rézfúvó, furulya, nádsíp, burdon): hullámtáblás
    additív szintézis – a felhangok erősségét hangszerenként egy spektrum-
    burkoló adja, a tábla sávhatárolt (nincs tükröződő felhang);
  * pengetett hangok (lant, hárfa, csembaló, pizzicato): felhangonként
    külön lecsengő szinuszok – a magas felhangok gyorsabban halnak el,
    ahogy a valódi húron;
  * dobok: lecsúszó hangmagasságú szinusz + szűrt zaj;
  * zengető: szintetikus teremválasz (lecsengő, sávonként más hosszú zaj),
    amellyel KÖRKÖRÖSEN konvolválunk.

A körkörösség a lényeg: a keverőpuffer pontosan egy ismétlésnyi hosszú, és
minden hang, ami a végén túllógna (lecsengés, zengés), az elejére fordul
vissza. Így a kész darab matematikailag periodikus – a hurokpontnál nincs
varrat, mintha a zene mindig is szólt volna.
"""
import zlib

import numpy as np

SR = 44100
F32 = np.float32
KET_PI = 2.0 * np.pi


def hz(midi):
    """MIDI-hangszám -> frekvencia (a' = 440 Hz, egyenletes temperálás)."""
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def db(x):
    return -200.0 if x <= 1e-10 else 20.0 * np.log10(x)


# ---------------------------------------------------------------------------
# Segédek
# ---------------------------------------------------------------------------

def szuro(x, also=None, felso=None, rend=2):
    """Spektrális (nulla fázisú) sávszűrő. KÖRKÖRÖS: zajra és a teljes,
    periodikus keverésre használjuk, egyedi hangra burkoló ELŐTT."""
    n = len(x)
    X = np.fft.rfft(x, axis=0)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    H = np.ones_like(f)
    if also:
        H *= 1.0 / np.sqrt(1.0 + (also / np.maximum(f, 1e-6)) ** (2 * rend))
    if felso:
        H *= 1.0 / np.sqrt(1.0 + (f / felso) ** (2 * rend))
    if X.ndim == 2:
        H = H[:, None]
    return np.fft.irfft(X * H, n, axis=0)


def pup(f, kozep, szel_okt):
    """Harang alakú kiemelés a spektrum-burkolókhoz (logaritmikus tengelyen)."""
    return np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / kozep) / szel_okt) ** 2)


def alul(f, fc, rend):
    """Aluláteresztő jellegű súly."""
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * rend))


def burkolo(n, n_tart, felfut, lecseng, tartas=1.0, eses=0.0):
    """Felfutás (koszinusz-ív) – esés a tartási szintre – lecsengés a hang
    végétől. Minden él lekerekített: a hang se indulásnál, se elengedésnél
    nem kattan."""
    e = np.full(n, tartas, dtype=np.float64)
    a = max(8, min(int(felfut * SR), int(n_tart * 0.45)))
    e[:a] = 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    if eses > 0.0 and tartas < 1.0:
        d = max(1, int(eses * SR))
        veg = min(n, a + d)
        k = np.arange(veg - a) / d
        e[a:veg] = tartas + (1.0 - tartas) * (0.5 + 0.5 * np.cos(np.pi * k))
    else:
        e[:a] *= tartas
    r0 = min(n_tart, n)
    r = n - r0
    if r > 0:
        e[r0:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(r) / r)
    return e


# ---------------------------------------------------------------------------
# Hullámtábla
# ---------------------------------------------------------------------------

TN = 4096


def _tabla(erossegek, fazisok=None):
    k = len(erossegek)
    spek = np.zeros(TN // 2 + 1, dtype=np.complex128)
    ph = np.zeros(k) if fazisok is None else fazisok
    spek[1:k + 1] = erossegek * np.exp(1j * (ph - np.pi / 2)) * (TN / 2)
    t = np.fft.irfft(spek, TN)
    return np.concatenate([t, t[:1]]).astype(F32)


def _olvas(tab, fazis):
    p = (fazis % 1.0) * TN
    i = p.astype(np.int64)
    fr = (p - i).astype(F32)
    return tab[i] * (1.0 - fr) + tab[i + 1] * fr


# ---------------------------------------------------------------------------
# Tartott hangú hangszerek
# ---------------------------------------------------------------------------
#
# spek(f_k, k, vel): a k-adik felhang erőssége.
# a/r: felfutás és lecsengés (mp); vr/vd: vibrato sebessége (Hz) és mélysége
# (arány); vk/vf: a vibrato késése és beúszása; kor: a kórus szólamainak
# elhangolása centben; zaj: levegő-/vonózaj aránya.

def _sp_vonos(fk, k, vel):
    test = 0.55 + 0.7 * pup(fk, 320, 0.7) + 0.55 * pup(fk, 800, 0.6) + 0.35 * pup(fk, 2400, 0.5)
    return test / k * alul(fk, 2100 + 1500 * vel, 1.6)


def _sp_szolo(fk, k, vel):
    test = 0.5 + 0.6 * pup(fk, 450, 0.6) + 0.6 * pup(fk, 1100, 0.6) + 0.4 * pup(fk, 2600, 0.45)
    return test / k ** 0.95 * alul(fk, 2600 + 1500 * vel, 1.8)


def _sp_melyvonos(fk, k, vel):
    test = 0.6 + 0.8 * pup(fk, 180, 0.8) + 0.5 * pup(fk, 520, 0.7)
    return test / k * alul(fk, 1300 + 900 * vel, 1.6)


def _sp_kurt(fk, k, vel):
    return (0.7 + 0.5 * pup(fk, 480, 0.8)) * alul(fk, 520 + 800 * vel, 1.7)


def _sp_harsona(fk, k, vel):
    return (0.7 + 0.5 * pup(fk, 550, 0.8)) * alul(fk, 600 + 1000 * vel, 1.5)


def _sp_furulya(fk, k, vel):
    a = np.array([1.0, 0.30, 0.12, 0.05, 0.022, 0.01, 0.005])
    out = np.zeros_like(fk)
    m = min(len(a), len(fk))
    out[:m] = a[:m]
    return out * alul(fk, 3200, 1.5)


def _sp_sip(fk, k, vel):
    paros = np.where(k % 2 == 1, 1.0, 0.16)
    return paros / k ** 1.05 * (0.6 + 0.6 * pup(fk, 1150, 0.6)) * alul(fk, 1900 + 700 * vel, 1.8)


def _sp_burdon(fk, k, vel):
    return (0.6 + 0.6 * pup(fk, 420, 0.8)) / k * alul(fk, 1100, 1.7)


TARTOTT = {
    "vonos":     dict(sp=_sp_vonos, a=0.11, r=0.20, vr=5.3, vd=0.0040, vk=0.12, vf=0.35, kor=(-7, 0, 6), zaj=0.010),
    "vonos_r":   dict(sp=_sp_vonos, a=0.035, r=0.11, vr=5.3, vd=0.0020, vk=0.20, vf=0.30, kor=(-6, 5), zaj=0.012),
    "szolo":     dict(sp=_sp_szolo, a=0.055, r=0.12, vr=5.6, vd=0.0050, vk=0.16, vf=0.30, kor=(0, 4), zaj=0.008),
    "melyvonos": dict(sp=_sp_melyvonos, a=0.06, r=0.14, vr=5.0, vd=0.0025, vk=0.20, vf=0.40, kor=(-5, 4), zaj=0.010),
    "kurt":      dict(sp=_sp_kurt, a=0.075, r=0.16, vr=4.8, vd=0.0012, vk=0.35, vf=0.50, kor=(-3, 3), zaj=0.004),
    "harsona":   dict(sp=_sp_harsona, a=0.065, r=0.15, vr=4.8, vd=0.0010, vk=0.40, vf=0.50, kor=(-4, 0, 4), zaj=0.004),
    "furulya":   dict(sp=_sp_furulya, a=0.045, r=0.09, vr=4.9, vd=0.0035, vk=0.22, vf=0.35, kor=(0,), zaj=0.035),
    "sip":       dict(sp=_sp_sip, a=0.040, r=0.09, vr=5.0, vd=0.0015, vk=0.30, vf=0.40, kor=(0,), zaj=0.010),
    "burdon":    dict(sp=_sp_burdon, a=0.30, r=0.45, vr=0.35, vd=0.0015, vk=0.0, vf=0.01, kor=(-6, 0, 5), zaj=0.006),
}

_tabla_gyorstar = {}


def _hangszer_tabla(nev, midi, velk):
    kulcs = (nev, midi, velk)
    t = _tabla_gyorstar.get(kulcs)
    if t is None:
        f = hz(midi)
        K = max(1, min(200, int(0.44 * SR / (f * 1.012))))
        k = np.arange(1, K + 1, dtype=np.float64)
        e = TARTOTT[nev]["sp"](f * k, k, velk)
        # Hangszerenként rögzített, de felhangonként eltérő fázis: így a
        # hullám nem tűhegyes, a csúcstényező kisebb.
        rng = np.random.default_rng(1000 + int(midi))
        fazis = rng.random(K) * KET_PI
        t = _tabla(e, fazis)
        t = (t / max(1e-9, np.sqrt(np.mean(t.astype(np.float64) ** 2)))).astype(F32) * 0.25
        _tabla_gyorstar[kulcs] = t
    return t


_hang_gyorstar = {}


def tartott(nev, midi, hossz, vel):
    """Egy tartott hang (mono, float32). hossz mp-ben a lecsengés nélkül."""
    velk = round(float(vel) * 10) / 10.0
    kulcs = (nev, midi, round(hossz, 4), velk)
    kesz = _hang_gyorstar.get(kulcs)
    if kesz is not None:
        return kesz
    p = TARTOTT[nev]
    f = hz(midi)
    n_tart = max(16, int(hossz * SR))
    n = n_tart + int(p["r"] * SR)
    t = np.arange(n) / SR
    # Rögzített mag (nem a Python futásonként változó hash-e): ugyanabból a
    # kottából mindig bitre ugyanaz a hang lesz.
    rng = np.random.default_rng(zlib.crc32(("%s|%d|%.4f" % (nev, midi, hossz)).encode()))
    tab = _hangszer_tabla(nev, midi, velk)
    vibenv = np.clip((t - p["vk"]) / p["vf"], 0.0, 1.0)
    ki = np.zeros(n, dtype=F32)
    for c in p["kor"]:
        vr = p["vr"] * (1.0 + 0.07 * rng.standard_normal())
        elt = p["vd"] * vibenv * np.sin(KET_PI * vr * t + rng.random() * KET_PI)
        # lassú, apró hangmagasság-vándorlás: ettől él a tartott hang
        elt += 0.0012 * np.sin(KET_PI * (0.2 + 0.3 * rng.random()) * t + rng.random() * KET_PI)
        finst = f * 2.0 ** (c / 1200.0) * (1.0 + elt)
        fazis = np.cumsum(finst) / SR + rng.random()
        ki += _olvas(tab, fazis)
    ki /= len(p["kor"]) ** 0.75
    e = burkolo(n, n_tart, p["a"], p["r"], tartas=0.86, eses=0.25)
    if p["zaj"] > 0.0:
        z = szuro(rng.standard_normal(n), max(300.0, f * 1.5), min(6000.0, f * 7.0), 1)
        ki += (z * p["zaj"] * 2.0).astype(F32)
    ki = (ki * e * (float(vel) ** 1.25)).astype(F32)
    _hang_gyorstar[kulcs] = ki
    return ki


# ---------------------------------------------------------------------------
# Pengetett hangszerek
# ---------------------------------------------------------------------------
#
# poz: a pengetés helye a húron (ettől függ, mely felhangok hiányoznak);
# alfa: a felhangok esése; fc0/fc1: fényesség (a hangerővel nő); tau: az
# alaphang lecsengése 220 Hz-en; csill: mennyivel gyorsabban halnak el a
# magas felhangok; cseng: a leütés után még meddig zeng szabadon (a lant
# és a hárfa húrja tovább szól, a csembalóét a tompító megfogja);
# kor: a húrpár – (cent, frekvenciaszorzó, erősség).

PENGETETT = {
    "lant":     dict(poz=0.23, alfa=1.10, fc0=2100, fc1=1500, rend=1.4, tau=1.05, tauf=0.45, csill=0.030,
                     cseng=0.9, r=0.10, maxh=28, B=0.00006, kor=((0, 1, 1.0), (4, 1, 0.55)), zaj=0.05),
    "harfa":    dict(poz=0.37, alfa=1.30, fc0=1700, fc1=1300, rend=1.5, tau=1.60, tauf=0.50, csill=0.040,
                     cseng=1.6, r=0.20, maxh=20, B=0.00003, kor=((0, 1, 1.0),), zaj=0.025),
    "csembalo": dict(poz=0.11, alfa=0.85, fc0=2600, fc1=1200, rend=1.6, tau=1.25, tauf=0.40, csill=0.012,
                     cseng=0.0, r=0.07, maxh=40, B=0.00004, kor=((0, 1, 1.0), (3, 2, 0.20)), zaj=0.06),
    "pizz":     dict(poz=0.30, alfa=1.30, fc0=900, fc1=1100, rend=1.6, tau=0.30, tauf=0.35, csill=0.060,
                     cseng=0.35, r=0.08, maxh=18, B=0.0, kor=((0, 1, 1.0), (-5, 1, 0.6)), zaj=0.03),
}

_zaj_bank = {}


def _szurt_zaj(also, felso, n, mag, rend=2):
    """Előre szűrt zaj – egy hosszabb darabból vágunk, hogy a szűrés
    körkörössége ne számítson."""
    kulcs = (also, felso, mag, rend)
    z = _zaj_bank.get(kulcs)
    if z is None or len(z) < n:
        rng = np.random.default_rng(mag)
        hossz = max(n, SR * 2)
        z = szuro(rng.standard_normal(hossz), also, felso, rend)
        z = (z / np.sqrt(np.mean(z ** 2))).astype(F32)
        _zaj_bank[kulcs] = z
    return z[:n]


def pengetett(nev, midi, hossz, vel):
    velk = round(float(vel) * 10) / 10.0
    kulcs = ("p", nev, midi, round(hossz, 4), velk)
    kesz = _hang_gyorstar.get(kulcs)
    if kesz is not None:
        return kesz
    p = PENGETETT[nev]
    n_tart = max(64, int((hossz + p["cseng"]) * SR))
    n = n_tart + int(p["r"] * SR)
    t = (np.arange(n) / SR).astype(F32)
    ki = np.zeros(n, dtype=F32)
    for cent, szorzo, eros in p["kor"]:
        f = hz(midi) * szorzo * 2.0 ** (cent / 1200.0)
        K = max(1, min(p["maxh"], int(0.42 * SR / f)))
        k = np.arange(1, K + 1, dtype=np.float64)
        fk = f * k * np.sqrt(1.0 + p["B"] * k * k)
        amp = np.abs(np.sin(np.pi * k * p["poz"])) / k ** p["alfa"]
        amp *= alul(fk, p["fc0"] + p["fc1"] * velk, p["rend"])
        tau = p["tau"] * (220.0 / f) ** p["tauf"] / (1.0 + p["csill"] * k * k)
        # felhangonként lecsengő szinuszok összege, darabokban (memória)
        for i0 in range(0, K, 8):
            sl = slice(i0, i0 + 8)
            fazis = (KET_PI * fk[sl, None]).astype(F32) * t[None, :]
            lecs = np.exp(-t[None, :] / tau[sl, None].astype(F32))
            ki += eros * np.sum(amp[sl, None].astype(F32) * lecs * np.sin(fazis), axis=0)
    ki /= max(1e-9, float(np.max(np.abs(ki[:int(0.05 * SR)]))))
    ki *= 0.5
    if p["zaj"] > 0.0:
        z = _szurt_zaj(700, 3200, n, 77) * np.exp(-t / 0.004)
        ki += (z * p["zaj"] * 0.5).astype(F32)
    e = burkolo(n, n_tart, 0.0015, p["r"])
    ki = (ki * e * (float(vel) ** 1.2)).astype(F32)
    _hang_gyorstar[kulcs] = ki
    return ki


# ---------------------------------------------------------------------------
# Dobok
# ---------------------------------------------------------------------------
#
# test: (kezdő Hz, vég Hz, a lecsúszás ideje, lecsengés, erősség) szinuszok;
# zaj: (alsó Hz, felső Hz, lecsengés, erősség). A zajt mindenütt 4,5 kHz
# alatt tartjuk: a dob tompán puffan, nem csattan.

DOBOK = {
    "dum":     dict(test=((105, 74, 0.030, 0.20, 1.0), (176, 150, 0.02, 0.09, 0.30)), zaj=(140, 900, 0.022, 0.35)),
    "tak":     dict(test=((290, 235, 0.015, 0.060, 0.7), (540, 500, 0.01, 0.035, 0.25)), zaj=(500, 3000, 0.030, 0.55)),
    "pergo":   dict(test=((200, 182, 0.010, 0.055, 0.55), (310, 295, 0.01, 0.04, 0.25)), zaj=(650, 4200, 0.075, 1.0)),
    "pergo_h": dict(test=((200, 185, 0.010, 0.035, 0.40),), zaj=(700, 3600, 0.040, 0.9)),
    "tompa":   dict(test=((150, 128, 0.012, 0.080, 0.8), (240, 225, 0.01, 0.05, 0.30)), zaj=(300, 2200, 0.060, 0.55)),
    "nagydob": dict(test=((70, 47, 0.045, 0.30, 1.0), (104, 88, 0.03, 0.12, 0.25)), zaj=(60, 420, 0.035, 0.30)),
}


def dob(nev, vel):
    velk = round(float(vel) * 20) / 20.0
    kulcs = ("d", nev, velk)
    kesz = _hang_gyorstar.get(kulcs)
    if kesz is not None:
        return kesz
    p = DOBOK[nev]
    leghosszabb = max([x[3] for x in p["test"]] + [p["zaj"][2]])
    n = int(leghosszabb * 7.0 * SR)
    t = np.arange(n) / SR
    ki = np.zeros(n)
    for f0, f1, tcs, tau, eros in p["test"]:
        f = f1 + (f0 - f1) * np.exp(-t / tcs)
        ki += eros * np.sin(KET_PI * np.cumsum(f) / SR) * np.exp(-t / tau)
    also, felso, tau, eros = p["zaj"]
    felfut = np.minimum(1.0, t / 0.0012)
    ki += eros * 0.45 * _szurt_zaj(also, felso, n, 31 + len(nev)) * np.exp(-t / tau) * felfut
    veg = int(0.25 * n)
    ki[-veg:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(veg) / veg)
    ki = (ki * 0.5 * velk ** 1.3).astype(F32)
    _hang_gyorstar[kulcs] = ki
    return ki


def ust(midi, hossz, vel):
    """Üstdob: hangolt, de nem tisztán harmonikus részhangokkal."""
    velk = round(float(vel) * 20) / 20.0
    kulcs = ("u", midi, round(hossz, 3), velk)
    kesz = _hang_gyorstar.get(kulcs)
    if kesz is not None:
        return kesz
    f = hz(midi)
    n = int(min(2.2, max(0.5, hossz + 0.8)) * SR)
    t = np.arange(n) / SR
    ki = np.zeros(n)
    for arany, eros, tau in ((1.0, 1.0, 0.75), (1.5, 0.45, 0.42), (1.99, 0.22, 0.30), (2.44, 0.10, 0.20)):
        ki += eros * np.sin(KET_PI * f * arany * t * (1.0 + 0.012 * np.exp(-t / 0.05))) * np.exp(-t / tau)
    ki += 0.25 * _szurt_zaj(80, 700, n, 55) * np.exp(-t / 0.02) * np.minimum(1.0, t / 0.001)
    veg = int(0.3 * n)
    ki[-veg:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(veg) / veg)
    ki = (ki * 0.4 * velk ** 1.3).astype(F32)
    _hang_gyorstar[kulcs] = ki
    return ki


# ---------------------------------------------------------------------------
# Körkörös keverő és zengető
# ---------------------------------------------------------------------------

class Kevero:
    def __init__(self, hossz_minta):
        self.L = int(hossz_minta)
        self.savok = {}      # szólamnév -> (L, 2) száraz jel
        self.kuldes = {}     # szólamnév -> mennyi megy a zengetőbe

    def sav(self, nev, zeng):
        if nev not in self.savok:
            self.savok[nev] = np.zeros((self.L, 2), dtype=F32)
            self.kuldes[nev] = zeng
        return self.savok[nev]

    def tesz(self, nev, jel, kezd, eros, pan, zeng):
        """Mono hang a sávba; ami túllóg a végén, az elejére fordul."""
        puff = self.sav(nev, zeng)
        szog = (np.clip(pan, -1.0, 1.0) + 1.0) * np.pi / 4.0
        gb, gj = eros * np.cos(szog), eros * np.sin(szog)
        L = self.L
        k = int(kezd) % L
        i = 0
        n = len(jel)
        while i < n:
            db_ = min(n - i, L - k)
            puff[k:k + db_, 0] += jel[i:i + db_] * gb
            puff[k:k + db_, 1] += jel[i:i + db_] * gj
            i += db_
            k = 0


def teremvalasz(rt_mely, rt_kozep, rt_magas, mag=5):
    """Szintetikus teremválasz: sávonként más ütemben lecsengő zaj. A magas
    sáv hal el leghamarabb (a levegő és a falak nyelik el) – ettől meleg."""
    hossz = max(rt_mely, rt_kozep, rt_magas) * 1.15
    n = int(hossz * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(mag)
    ki = np.zeros((n, 2))
    kesl = 0.018
    for c in range(2):
        z = rng.standard_normal(n)
        mely = szuro(z, 90, 420, 2)
        kozep = szuro(z, 420, 2400, 2)
        magas = szuro(z, 2400, 7000, 2)
        v = (mely * np.exp(-6.91 * t / rt_mely) + kozep * np.exp(-6.91 * t / rt_kozep)
             + 0.6 * magas * np.exp(-6.91 * t / rt_magas))
        v *= np.clip((t - kesl) / 0.035, 0.0, 1.0)
        veg = int(0.2 * n)
        v[-veg:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(veg) / veg)
        ki[:, c] = v / np.sqrt(np.sum(v ** 2))
    return ki


def kor_konvolucio(jel, valasz):
    """Körkörös konvolúció csatornánként (a hossz a jelé)."""
    L = len(jel)
    ki = np.zeros_like(jel, dtype=np.float64)
    for c in range(2):
        h = np.zeros(L)
        m = min(L, len(valasz))
        h[:m] = valasz[:m, c]
        ki[:, c] = np.fft.irfft(np.fft.rfft(jel[:, c].astype(np.float64)) * np.fft.rfft(h), L)
    return ki


def hatarolo(x, kuszob):
    """Körkörös, előretekintő csúcshatároló. 256 mintás tömbönként nézi a
    csúcsot, a szomszéd tömbökét is figyelembe veszi, és a tömbközepek
    között egyenesen vezeti az erősítést – ugrás nélkül, a küszöböt
    garantáltan betartva."""
    L = len(x)
    B = 256
    nb = L // B
    assert nb * B == L, "a hossz legyen 256 többszöröse"
    cs = np.max(np.abs(x), axis=1).reshape(nb, B).max(axis=1)
    g = np.minimum(1.0, kuszob / np.maximum(cs, 1e-9))
    g = np.minimum(g, np.minimum(np.roll(g, 1), np.roll(g, -1)))
    # még egy simítás: a visszaállás lassabb legyen, mint a lefogás
    for _ in range(3):
        g = np.minimum(g, 0.5 * (np.roll(g, 1) + np.roll(g, -1)) * 0.5 + 0.5 * g)
    kozep = (np.arange(nb) + 0.5) * B
    xp = np.concatenate([[kozep[-1] - L], kozep, [kozep[0] + L]])
    gp = np.concatenate([[g[-1]], g, [g[0]]])
    gi = np.interp(np.arange(L), xp, gp)
    return x * gi[:, None], float(g.min())


def mesterel(x, cel_rms_db=-20.0, csucs_db=-3.0):
    """Mélyvágás, egyenszint levétele, hangosság beállítása, csúcshatárolás."""
    x = szuro(x, also=32.0, rend=2)
    x = x - x.mean(axis=0, keepdims=True)
    rms = np.sqrt(np.mean(x ** 2))
    x = x * (10.0 ** (cel_rms_db / 20.0) / rms)
    kuszob = 10.0 ** (csucs_db / 20.0)
    x, gmin = hatarolo(x, kuszob * 0.985)
    cs = float(np.max(np.abs(x)))
    if cs > kuszob:
        x *= kuszob / cs
    return x.astype(F32), gmin
