# -*- coding: utf-8 -*-
"""A kész zenefájlok mérése (meghallgatás helyett) és spektrogramok.

    blender.exe -b --factory-startup --python tools/zene/ellenor.py -- [--be MAPPA] [--kep MAPPA]

  --be    honnan olvas (alapértelmezés: assets/audio); music_age*.ogg vagy .wav
  --kep   ide ír spektrogramokat (PNG): a teljes darabot, és külön a
          hurokpont környékét (az utolsó 3 mp után az első 3 mp)

Mit néz:
  * néma-e, van-e levágott (túlvezérelt) minta, egyenszint;
  * hurokpont: a vég–kezdet átmenet ugrása és meredekség-törése a darab
    szokásos mintakülönbségeihez mérve;
  * hangosság 1 mp-es ablakokban: a legcsendesebb és leghangosabb ablak,
    a legnagyobb ugrás két szomszédos ablak között (a hurkon át is);
  * spektrum: súlypont és sávonkénti energia – éles-e (4–8 kHz).
Ogg-ot csak a Blender Pythonja tud olvasni (aud); sima Pythonnal WAV megy.
"""
import glob
import os
import struct
import sys
import wave
import zlib

import numpy as np

try:
    import aud
except ImportError:
    aud = None

ITT = os.path.dirname(os.path.abspath(__file__))


def db(x):
    return -200.0 if x <= 1e-10 else 20.0 * np.log10(x)


def beolvas(ut):
    if ut.lower().endswith(".wav"):
        with wave.open(ut, "rb") as w:
            sr, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
            a = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float64) / 32768.0
        return a.reshape(-1, ch), sr
    s = aud.Sound.file(ut)
    return s.data().astype(np.float64), int(s.specs[0])


def png(ut, kep):
    """kep: (magasság, szélesség, 3) uint8."""
    h, w, _ = kep.shape
    nyers = b"".join(b"\x00" + kep[y].tobytes() for y in range(h))

    def darab(tipus, adat):
        return struct.pack(">I", len(adat)) + tipus + adat + struct.pack(">I", zlib.crc32(tipus + adat) & 0xffffffff)
    with open(ut, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + darab(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + darab(b"IDAT", zlib.compress(nyers, 6)) + darab(b"IEND", b""))


SZINEK = np.array([[0, 0, 0], [20, 10, 80], [110, 20, 130], [210, 60, 70], [250, 160, 30], [255, 250, 200]], dtype=np.float64)


def spektrogram(mono, sr, ut, szel=1500, mag=520, ablak=4096, f_also=40.0, f_felso=16000.0):
    n = len(mono)
    lepes = max(1, (n - ablak) // szel)
    oszlopok = min(szel, (n - ablak) // lepes)
    w = np.hanning(ablak)
    S = np.empty((ablak // 2 + 1, oszlopok))
    for i in range(oszlopok):
        S[:, i] = np.abs(np.fft.rfft(mono[i * lepes:i * lepes + ablak] * w))
    S = 20.0 * np.log10(S / (ablak / 4.0) + 1e-9)
    f = np.fft.rfftfreq(ablak, 1.0 / sr)
    cel = f_also * (f_felso / f_also) ** (np.arange(mag) / (mag - 1.0))
    idx = np.clip(np.searchsorted(f, cel), 1, len(f) - 1)
    kep = S[idx][::-1]
    v = np.clip((kep + 85.0) / 75.0, 0.0, 1.0) * (len(SZINEK) - 1)
    i0 = np.clip(v.astype(int), 0, len(SZINEK) - 2)
    t = (v - i0)[..., None]
    rgb = SZINEK[i0] * (1.0 - t) + SZINEK[i0 + 1] * t
    for hz_ in (100, 1000, 4000, 8000):               # segédvonalak
        y = mag - 1 - int(np.argmin(np.abs(cel - hz_)))
        rgb[y, ::6] = (90, 90, 90)
    png(ut, rgb.astype(np.uint8))


def mer(ut, kepmappa):
    x, sr = beolvas(ut)
    nev = os.path.basename(ut)
    if not np.any(x):
        print("\n%s: NÉMA – csupa nulla minta (%d Hz, %d csatorna, %.3f mp)" % (nev, sr, x.shape[1], len(x) / sr))
        return
    if x.shape[1] == 1:
        x = np.repeat(x, 2, axis=1)
    n = len(x)
    mono = x.mean(axis=1)
    csucs = float(np.max(np.abs(x)))
    rms = float(np.sqrt(np.mean(x ** 2)))
    print("\n%s: %d Hz, %d csatorna, %.3f mp, %d bájt" % (nev, sr, x.shape[1], n / sr, os.path.getsize(ut)))
    print("  csúcs %.2f dBFS, RMS %.2f dBFS, csúcstényező %.1f dB, levágott minta (|x| >= 0,999): %d, egyenszint: %.5f / %.5f"
          % (db(csucs), db(rms), db(csucs) - db(rms), int(np.sum(np.abs(x) >= 0.999)), x[:, 0].mean(), x[:, 1].mean()))
    # hurokpont
    for c, cs in enumerate("BJ"):
        d1 = np.abs(np.diff(x[:, c]))
        ugras = abs(x[0, c] - x[-1, c])
        d2 = np.abs(np.diff(x[:, c], 2))
        tores = abs((x[1, c] - x[0, c]) - (x[0, c] - x[-1, c]))
        tores2 = abs((x[0, c] - x[-1, c]) - (x[-1, c] - x[-2, c]))
        print("  hurok %s: ugrás %.5f (a darab mintakülönbségei: medián %.5f, 99%% %.5f, legnagyobb %.5f) | "
              "meredekség-törés %.5f (99%% %.5f)" % (cs, ugras, np.median(d1), np.percentile(d1, 99), d1.max(),
                                                      max(tores, tores2), np.percentile(d2, 99)))
    # hangosság 1 mp-es ablakokban (a hurkon át is)
    ab = sr
    db_ab = n // ab
    szint = np.array([db(float(np.sqrt(np.mean(x[i * ab:(i + 1) * ab] ** 2)))) for i in range(db_ab)])
    lepes = np.abs(np.diff(np.concatenate([szint, szint[:1]])))
    print("  1 mp-es ablakok: legcsendesebb %.1f dB (%d. mp), leghangosabb %.1f dB (%d. mp), szórás %.1f dB, "
          "legnagyobb ugrás szomszédos ablakok között %.1f dB (%d. mp)"
          % (szint.min(), int(szint.argmin()), szint.max(), int(szint.argmax()), szint.std(), lepes.max(), int(lepes.argmax())))
    print("  hangosság 3 mp-enként (dB): " + " ".join("%.0f" % np.mean(szint[i:i + 3]) for i in range(0, db_ab - 2, 3)))
    # rövid kiesés: 50 ms-os ablakok
    kis = sr // 20
    rov = np.array([db(float(np.sqrt(np.mean(x[i * kis:(i + 1) * kis] ** 2)))) for i in range(n // kis)])
    print("  50 ms-os ablakok: legcsendesebb %.1f dB, -50 dB alatti ablak: %d" % (rov.min(), int(np.sum(rov < -50.0))))
    # spektrum
    P = np.abs(np.fft.rfft(mono)) ** 2
    f = np.fft.rfftfreq(n, 1.0 / sr)
    ossz = P.sum()
    savok = [(0, 200), (200, 1000), (1000, 4000), (4000, 8000), (8000, sr / 2)]
    reszek = ["%d–%d Hz: %.1f%% (%.1f dB)" % (a, b, 100.0 * P[(f >= a) & (f < b)].sum() / ossz,
                                              10.0 * np.log10(P[(f >= a) & (f < b)].sum() / ossz + 1e-12)) for a, b in savok]
    print("  spektrum súlypontja %.0f Hz; sávok: %s" % ((P * f).sum() / ossz, "; ".join(reszek)))
    kor = float(np.sum(x[:, 0] * x[:, 1]) / np.sqrt(np.sum(x[:, 0] ** 2) * np.sum(x[:, 1] ** 2)))
    print("  sztereó: a két csatorna korrelációja %.2f (1 = mono)" % kor)
    if kepmappa:
        os.makedirs(kepmappa, exist_ok=True)
        alap = os.path.join(kepmappa, os.path.splitext(nev)[0])
        spektrogram(mono, sr, alap + ".png")
        hurok = np.concatenate([mono[-3 * sr:], mono[:3 * sr]])
        spektrogram(hurok, sr, alap + "_hurok.png", szel=1200, mag=420, ablak=1024)
        print("  képek: %s.png, %s_hurok.png (a hurokpont a kép közepén)" % (alap, alap))


def main():
    arg = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ([] if aud is not None else sys.argv[1:])
    be = os.path.normpath(os.path.join(ITT, "..", "..", "assets", "audio"))
    kep = None
    i = 0
    while i < len(arg):
        if arg[i] == "--be":
            be = arg[i + 1]
            i += 1
        elif arg[i] == "--kep":
            kep = arg[i + 1]
            i += 1
        i += 1
    fajlok = sorted(glob.glob(os.path.join(be, "music_age*.ogg")) + glob.glob(os.path.join(be, "music_age*.wav")))
    if not fajlok:
        raise SystemExit("nincs zenefájl itt: " + be)
    for ut in fajlok:
        mer(ut, kep)


if __name__ == "__main__":
    main()
