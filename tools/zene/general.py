# -*- coding: utf-8 -*-
"""A Birodalom korszakzenéinek előállítása.

Futtatás (a Blender saját Pythonjával, mert az Ogg Vorbis kódolót – az `aud`
modult – a Blender adja):

    blender.exe -b --factory-startup --python tools/zene/general.py
    blender.exe -b --factory-startup --python tools/zene/general.py -- --csak 2
    blender.exe -b --factory-startup --python tools/zene/general.py -- --kotta

Kapcsolók (a `--` után):
    --csak 0,3     csak a felsorolt korszakok
    --ki MAPPA     ide ír (alapértelmezés: assets/audio)
    --wav          Ogg helyett WAV-ot ír (belehallgatáshoz, méréshez; a játék
                   Ogg-ot vár, WAV-ot NE tegyél az assets/audio mappába)
    --kotta        nem szintetizál, csak a zenei önellenőrzést írja ki
                   (hangkészlet szólamonként, hangnem, súrlódó hangközök)

Sima Pythonnal is fut (numpy kell hozzá), de akkor csak WAV-ot tud írni.
"""
import os
import sys
import time
import wave

import numpy as np

ITT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ITT)

import hang                                    # noqa: E402
import kotta                                   # noqa: E402
from darabok import DARABOK                    # noqa: E402

try:
    import aud
except ImportError:                            # sima Python: nincs Ogg-kódoló
    aud = None

SR = hang.SR
# A hossz 4096 minta többszöröse. Ok: a Blender Vorbis-írója a fájl utolsó
# töredék-keretét hibásan zárja le (kimérve: az utolsó ~64 minta eltorzul, ami
# a hurokpontnál kattanna); egész keretnyi hossznál ez nem lép fel.
RACS = 4096
BITRATA = 160000
CEL_RMS_DB = -20.0
CSUCS_DB = -3.0


def kapcsolok():
    arg = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else (
        [] if aud is not None else sys.argv[1:])
    k = {"csak": None, "ki": os.path.normpath(os.path.join(ITT, "..", "..", "assets", "audio")),
         "wav": aud is None, "kotta": False}
    i = 0
    while i < len(arg):
        a = arg[i]
        if a == "--csak":
            k["csak"] = [int(x) for x in arg[i + 1].split(",")]
            i += 1
        elif a == "--ki":
            k["ki"] = arg[i + 1]
            i += 1
        elif a == "--wav":
            k["wav"] = True
        elif a == "--kotta":
            k["kotta"] = True
        else:
            raise SystemExit("ismeretlen kapcsoló: " + a)
        i += 1
    return k


def zenei_jelentes(d):
    """A kotta önellenőrzése: hangkészlet, hangnem, súrlódások. Igazat ad,
    ha nincs hosszan kitartott, nem szándékolt disszonancia."""
    utem_mp = 60.0 / d.tempo
    print("  forma: " + ", ".join("%s (%d–%d. ütem)" % (n, k, k + db - 1) for n, k, db in d.forma))
    keszlet = kotta.hangkeszlet(d.esemenyek, d.szolamok)
    for nev, a in keszlet.items():
        hangok = " ".join(kotta.NEVEK[p] for p in sorted(a["pcs"]))
        print("  %-9s %4d hang, %s–%s, készlet: %s" % (nev, a["db"], kotta.hangnev(a["min"]),
                                                       kotta.hangnev(a["max"]), hangok))
    alap, fed, suly = kotta.hangnem_tipp(d.esemenyek, d.szolamok)
    kivul = [kotta.NEVEK[p] for p in range(12) if suly[p] > 0 and (p - alap) % 12 not in kotta.DUR]
    print("  hangkészlet: a %s-dúr hét hangja (és rokonai) a hangok %.1f%%-át adják; azon kívül: %s"
          % (kotta.NEVEK[alap], fed * 100.0, ", ".join(kivul) or "semmi"))
    ossz, teljes, esetek = kotta.osszhang(d.esemenyek, d.szolamok, utem_mp, d.utemhossz)
    print("  együtthangzás: kis szekund/nagy szeptim %.1f%%, tritónusz %.1f%% (az összes együtt szóló hangpár idejéből)"
          % (100.0 * ossz[1] / teljes, 100.0 * ossz[6] / teljes))
    for atf, kul, utem, s1, h1, s2, h2 in esetek[:12]:
        print("    ! %.2f mp, %s: %d. ütem, %s %s – %s %s"
              % (atf, "tritónusz" if kul == 6 else "kis szekund/nagy szeptim", utem, s1, h1, s2, h2))
    ok, db, kivetel = kotta.dallam_akkord(d.esemenyek, d.dallamok, d.menet)
    print("  dallam: a legalább negyed hosszú hangok közül %d/%d akkordhang (%.0f%%)"
          % (ok, db, 100.0 * ok / max(1, db)))
    for t, s, h, hossz, jel in kivetel:
        print("    · %d. ütem %.2f: %s %s (%.2g negyed) a %s akkord fölött"
              % (int(t // d.utemhossz) + 1, t % d.utemhossz + 1, s, h, hossz, jel))
    return len(esetek) == 0


def renderel(d):
    osszes_negyed = d.t
    idealis = osszes_negyed * 60.0 / d.tempo * SR
    L = int(round(idealis / RACS)) * RACS
    negyed = L / osszes_negyed                    # egy negyed hossza mintában
    kev = hang.Kevero(L)
    rng = np.random.default_rng(len(d.nev) * 7919 + int(d.tempo))
    for nev, t, h, m, v in sorted(d.esemenyek, key=lambda e: (e[1], e[0], str(e[3]))):
        s = d.szolamok[nev]
        csusz = 0.0
        if s["ember"] > 0.0:                       # emberi pontatlanság: pár ezredmásodperc
            csusz = float(np.clip(rng.standard_normal(), -2.0, 2.0)) * s["ember"] / 1000.0
        v2 = float(np.clip(v * (1.0 + 0.06 * np.clip(rng.standard_normal(), -2.0, 2.0)), 0.05, 1.0))
        mp = h * negyed / SR * s["artik"]
        if s["tipus"] == "tartott":
            jel = hang.tartott(s["hsz"], m, mp, v2)
        elif s["tipus"] == "pengetett":
            jel = hang.pengetett(s["hsz"], m, mp, v2)
        elif s["tipus"] == "ust":
            jel = hang.ust(m, mp, v2)
        else:
            jel = hang.dob(m, v2)
        kev.tesz(nev, jel, int(round(t * negyed + csusz * SR)), s["eros"], s["pan"], s["zeng"])
    szaraz = np.zeros((L, 2), dtype=np.float64)
    kuld = np.zeros((L, 2), dtype=np.float64)
    szintek = {}
    for nev, puff in kev.savok.items():
        szaraz += puff
        kuld += puff * kev.kuldes[nev]
        szintek[nev] = hang.db(float(np.sqrt(np.mean(puff.astype(np.float64) ** 2))))
    rt_m, rt_k, rt_h, nedves = d.zengo
    zeng = hang.kor_konvolucio(kuld, hang.teremvalasz(rt_m, rt_k, rt_h)) * nedves * 1.3
    # a zengés a két csatornán független; egy kevés átkeverés összefogja a teret
    zeng = zeng * 0.85 + zeng[:, ::-1] * 0.15
    x, gmin = hang.mesterel(szaraz + zeng, CEL_RMS_DB, CSUCS_DB)
    adat = dict(L=L, mp=L / SR, szintek=szintek, hatarolo_db=hang.db(gmin),
                zeng_db=hang.db(float(np.sqrt(np.mean(zeng ** 2)))) - hang.db(float(np.sqrt(np.mean(szaraz ** 2)))))
    return x, adat


def ir_wav(ut, x):
    with wave.open(ut, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(np.round(np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2").tobytes())


def ir_ogg(ut, x):
    """Ogg Vorbis írás, majd visszaolvasás: a hossz mintára egyezzen, és a
    fájl vége ne legyen torzabb, mint a közepe (különben a hurok kattanna)."""
    if os.path.exists(ut):
        os.remove(ut)
    aud.Sound.buffer(np.ascontiguousarray(x, dtype=np.float32), SR).write(
        ut, SR, 2, aud.FORMAT_S16, aud.CONTAINER_OGG, aud.CODEC_VORBIS, BITRATA)
    vissza = aud.Sound.file(ut).data()
    if len(vissza) != len(x):
        raise SystemExit("HIBA: %s hossza %d minta, %d helyett" % (ut, len(vissza), len(x)))
    hiba = vissza - x

    def r(a):
        return hang.db(float(np.sqrt(np.mean(a.astype(np.float64) ** 2))))
    kozep = r(hiba[len(x) // 4: len(x) // 2])
    veg = max(r(hiba[-64:]), r(hiba[-512:]), r(hiba[:64]), r(hiba[:512]))
    print("  ogg: %d bájt (%.0f kbit/s), kódolási hiba középen %.1f dB, a hurokpont két oldalán legfeljebb %.1f dB"
          % (os.path.getsize(ut), os.path.getsize(ut) * 8 / (len(x) / SR) / 1000.0, kozep, veg))
    if veg > kozep + 12.0:
        raise SystemExit("HIBA: %s vége/eleje eltorzult a kódolásban – a hurok kattanna" % ut)


def main():
    k = kapcsolok()
    minden_rendben = True
    for i, epit in enumerate(DARABOK):
        if k["csak"] is not None and i not in k["csak"]:
            continue
        d = epit()
        print("\n=== %d. korszak: %s – %s ===" % (i, d.nev, d.leiras))
        print("  tempó %d, %d ütem, %g/4" % (d.tempo, d.utemek, d.utemhossz))
        tiszta = zenei_jelentes(d)
        minden_rendben = minden_rendben and tiszta
        if k["kotta"]:
            continue
        t0 = time.time()
        x, adat = renderel(d)
        print("  hossz: %.3f mp (%d minta), szintézis: %.0f mp" % (adat["mp"], adat["L"], time.time() - t0))
        print("  szólamszintek (száraz, dB): " + ", ".join(
            "%s %.1f" % (n, s) for n, s in sorted(adat["szintek"].items(), key=lambda p: -p[1])))
        print("  zengés a száraz jelhez képest: %.1f dB; a csúcshatároló legnagyobb fogása: %.1f dB"
              % (adat["zeng_db"], adat["hatarolo_db"]))
        print("  kész jel: csúcs %.2f dBFS, RMS %.2f dBFS" % (
            hang.db(float(np.max(np.abs(x)))), hang.db(float(np.sqrt(np.mean(x.astype(np.float64) ** 2))))))
        os.makedirs(k["ki"], exist_ok=True)
        if k["wav"]:
            ut = os.path.join(k["ki"], d.fajl + ".wav")
            ir_wav(ut, x)
            print("  wav: " + ut)
        else:
            ut = os.path.join(k["ki"], d.fajl + ".ogg")
            ir_ogg(ut, x)
            print("  ogg: " + ut)
    if not minden_rendben:
        print("\nFIGYELEM: a zenei önellenőrzés hosszan tartott súrlódást talált (lásd a ! sorokat).")


if __name__ == "__main__":
    main()
