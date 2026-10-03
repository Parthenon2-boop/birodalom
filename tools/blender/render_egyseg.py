# -*- coding: utf-8 -*-
# Egységlapok renderelése.
#   blender --background --python render_egyseg.py -- <kimeneti mappa> [egység ...] [--proba]
#   egység: pl. worker_0 cav_2 galleon_1 fighter_3 (alapból mind)
#
# Egységenként EGY lap (<e>.png) és a hozzá tartozó maszklap (<e>_m.png):
#   8 sor = 8 irány (K, DK, D, DNy, Ny, ÉNy, É, ÉK — a játék szögei szerint),
#   oszlopok: pihenő | járás | támadás | halál  (a kockaszám az ANIM-ból).
# A kockák az összes kocka közös befoglaló téglalapjára vannak vágva; a
# talppont helye a kockán belül (ox, oy) a manifest.json-ban van, a lap
# felbontása s képpont / világképpont.
#   --proba: csak a D és DK irány, a lap a <e>_proba.png-be kerül.
import os, sys, json, time
os.environ.setdefault('BIR_BOUNCE', '1')      # 1 visszaverődés: a kép ugyanaz, fele annyi idő
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import bir_common as C
import bir_units as U
import bir_ships as SH

ORDER = ["idle", "walk", "attack", "death"]

a = C.args()
out = a[0]
os.makedirs(out, exist_ok=True)
proba = "--proba" in a
tmp = os.path.join(out, "_tmp")
os.makedirs(tmp, exist_ok=True)
katalogus = dict(U.UNITS)
katalogus.update(SH.SHIPS)
nevek = [x for x in a[1:] if not x.startswith("--")] or list(katalogus)
man_p = os.path.join(out, "manifest.json")


def man_load():
    return json.load(open(man_p, encoding="utf-8")) if os.path.exists(man_p) else {}


for nev in nevek:
    if not proba and '--ujra' not in a and os.path.exists(os.path.join(out, nev + '.json')):
        print(f'[egyseg] {nev}: már kész, kihagyva', flush=True)
        continue
    t0 = time.time()
    cls = katalogus[nev]
    C.reset_mats()
    C.reset_scene()
    water = getattr(cls, "water", False)
    plane = nev.startswith(("fighter", "bomber"))
    if water:
        C.water_holdout()
    u = cls()
    u.build()
    if not water and not plane:
        C.shadow_disc(u.cell[1] * 0.42)
    anim = cls.ANIM
    w, h, ox, oy = u.cell
    C.frame_fixed(w * C.PPU, h * C.PPU, ox * C.PPU, oy * C.PPU)
    dirs = [1, 2] if proba else list(range(8))
    frames = {}
    jobs = []
    for d in dirs:
        for st in ("idle", "walk", "attack"):
            n = anim[st]
            for i in range(n):
                jobs.append((d, st, i, n))
    for d in dirs:
        n = anim["death"]
        for i in range(n):
            jobs.append((d, "death", i, n))
    cyc = getattr(cls, "cycles_alpha", False)
    for (d, st, i, n) in jobs:
        u.set_dir(d)
        if st == "walk":
            t = i / n
        else:
            t = i / max(1, n - 1)
        u.pose(st, t, i)
        col, m = C.render_frame(os.path.join(tmp, nev), outline=True, cycles_alpha=cyc)
        frames[(d, st, i)] = (col, m)
    # közös befoglaló téglalap
    H, W = next(iter(frames.values()))[0].shape[:2]
    acc = np.zeros((H, W), dtype=bool)
    for col, m in frames.values():
        acc |= col[..., 3] > 0.012
    ys, xs = np.nonzero(acc)
    y0, y1 = max(0, ys.min() - 1), min(H, ys.max() + 2)
    x0, x1 = max(0, xs.min() - 1), min(W, xs.max() + 2)
    cw, ch = x1 - x0, y1 - y0
    cols = []
    for st in ORDER:
        for i in range(anim[st]):
            cols.append((st, i))
    sheet = np.zeros((len(dirs) * ch, len(cols) * cw, 4), dtype=np.float32)
    msheet = np.zeros_like(sheet)
    msheet[..., 3] = 1.0
    for r, d in enumerate(dirs):
        for c, (st, i) in enumerate(cols):
            col, m = frames[(d, st, i)]
            sheet[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw] = col[y0:y1, x0:x1]
            msheet[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw] = m[y0:y1, x0:x1]
    alap = nev + ("_proba" if proba else "")
    C.save_px(sheet, os.path.join(out, alap + ".png"))
    C.save_px(msheet, os.path.join(out, alap + "_m.png"))
    # az alak magassága (a D irányú pihenő kockán) — az életsáv helyéhez
    col_s = frames[(2, "idle", 0)][0][y0:y1, x0:x1]
    rows = np.nonzero(col_s[..., 3] > 0.5)[0]
    foot_y = oy * C.PPU - y0
    fig_h = float(foot_y - rows.min()) / C.PPU if len(rows) else 20.0
    dt = time.time() - t0
    if True:
        man = {}
        start = {}
        c0 = 0
        for st in ORDER:
            start[st] = [c0, anim[st]]
            c0 += anim[st]
        man[nev] = {"cw": int(cw), "ch": int(ch), "ox": float(ox * C.PPU - x0), "oy": float(oy * C.PPU - y0),
                    "s": C.PPU, "dirs": len(dirs), "anim": start, "fh": round(fig_h, 1),
                    "sec": round(dt, 1), "kockak": len(jobs)}
        json.dump(man, open(os.path.join(out, alap + ".json"), "w", encoding="utf-8"), indent=1)
    print(f"[egyseg] {nev}: {len(jobs)} kocka, lap {sheet.shape[1]}x{sheet.shape[0]}, cella {cw}x{ch}, "
          f"{dt:.0f} mp ({dt / max(1, len(jobs)):.2f} mp/kocka)", flush=True)
