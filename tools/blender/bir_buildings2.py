# -*- coding: utf-8 -*-
# BIRODALOM — A TELJES ÉPÜLETKÉSZLET: 15 típus x 4 korszak.
#
# A korszakok "építőkészlete":
#   0 = 15. század   vakolat + favázas emelet, kő, cserép / zsúp, pártázat
#   1 = 17. század   okker vakolat kőszegéllyel, magas ablakok, manzárd- és
#                    kontyolt tetők, barokk kupola, csillagerőd
#   2 = 19. század   tégla, íves ablakok, pala-/cseréptető, gyárkémény, öntöttvas
#                    és üveg, klasszicista oszlopcsarnok, rézkupola
#   3 = 20. század   beton, tégla, lapos tető, hullámlemez, acél
# A cseréptető ('roof') semleges szürke: a nemzeti színt a játék adja (maszk B).
#
# A lábnyom a játék Building.BUILD_SIZE táblája (w x h világképpont); a modell
# mélysége h / sin(ELEV). A kémények tetején "fust" jelű üres pont, a főváros
# zászlórúdjának tetején "zaszlo" jelű pont van — a render ezek képpontját a
# manifestbe írja (élő füst, élő lobogó).

import math, random
import bpy
from mathutils import Vector
from bir_common import *
from bir_buildings import (D, tri_prism, flag, banner, merlons, arch_door, window, side_window, barrel, crate,
                           sack, fence, half_timber_front, half_timber_side)
import bir_buildings as B0

FP = {
    "hq": (108, 106), "barracks": (86, 82), "stable": (82, 70), "farm": (66, 62), "tower": (54, 52),
    "house": (66, 52), "harbor": (86, 62), "temple": (78, 68), "airfield": (112, 78), "goldmine": (70, 58),
    "sugar": (74, 60), "market": (80, 62), "hospital": (78, 64), "smith": (74, 62), "academy": (86, 72),
}

WALL = {0: 'plaster', 1: 'ochre', 2: 'brick', 3: 'concrete'}
BASE = {0: 'stone_d', 1: 'stone', 2: 'stone_d', 3: 'concrete'}


def fp(t):
    w, h = FP[t]
    return float(w), D(h)


# ---------------------------------------------------------------- jelölőpontok

def smoke_point(name, loc):
    e = empty(name, loc)
    e["fust"] = True
    return e


def flag_pole(name, loc, h=18.0, mat='wood'):
    """Zászlórúd lobogó NÉLKÜL: a nemzeti zászlót a játék lengeti élőben."""
    cyl(name + "_rud", 0.6, h, loc, mat, verts=8)
    sphere(name + "_gomb", 0.95, (loc[0], loc[1], loc[2] + h + 0.5), 'gold', seg=8, rings=6)
    e = empty(name + "_pont", (loc[0] + 0.5, loc[1], loc[2] + h - 0.4))
    e["zaszlo"] = True
    return e


def chimney(name, x, y, z, h=9.0, w=3.2, mat='brick', smoke=True):
    box(name, (w, w, h), (x, y, z), mat, bevel=0.3)
    box(name + "_t", (w + 0.8, w + 0.8, 0.8), (x, y, z + h), 'stone_d', bevel=0.2)
    if smoke:
        smoke_point(name + "_f", (x, y, z + h + 1.0))


def factory_chimney(name, x, y, h=40.0, r=2.6):
    cyl(name, r, h, (x, y, 0), 'brick', verts=14, r2=r * 0.75)
    cyl(name + "_t", r * 0.85, 1.4, (x, y, h - 0.4), 'stone_d', verts=14)
    smoke_point(name + "_f", (x, y, h + 1.5))


# ---------------------------------------------------------------- tömbök

def win(name, x, y, z, age, w=None, h=None, side=None, shutters=False):
    """Korszakhoz illő ablak a -Y homlokzaton (side = ±1: a K/Ny oldalfalon)."""
    if age == 0:
        w, h, fr = w or 2.8, h or 3.4, 'timber'
    elif age == 1:
        w, h, fr = w or 2.8, h or 5.0, 'white'
    elif age == 2:
        w, h, fr = w or 2.8, h or 5.2, 'stone'
    else:
        w, h, fr = w or 4.0, h or 3.8, 'concrete'
    if side is None:
        window(name, x, y, z, w, h, shutters='team' if shutters else None, frame=fr)
        if age == 2:
            cyl(name + "_iv", w / 2, 0.8, (x, y - 0.5, z + h), 'window', verts=10, rot=(math.pi / 2, 0, 0), base=False)
            box(name + "_zk", (0.8, 0.9, 1.0), (x, y - 0.6, z + h + w / 2 - 0.5), 'stone', bevel=0.1)
        if age == 1:
            box(name + "_sz", (w + 1.6, 1.0, 0.6), (x, y - 0.4, z + h + 0.4), 'white', bevel=0.1)
    else:
        side_window(name, x, y, z, w, h, side=side, frame=fr)


def win_row(name, x0, x1, y, z, n, age, **kw):
    for i in range(n):
        x = x0 + (x1 - x0) * (i + 0.5) / n
        win(f"{name}{i}", x, y, z, age, **kw)


def win_col(name, x, y0, y1, z, n, age, side=1):
    for i in range(n):
        y = y0 + (y1 - y0) * (i + 0.5) / n
        win(f"{name}{i}", x, y, z, age, side=side)


def roof_on(name, w, d, z, cx, cy, kind, age, h=None, ridge_x=True, mat=None, wall_mat=None):
    """Tető a (cx, cy) közepű w x d tömbre, z magasságban."""
    m = mat or ('roof' if kind != 'flat' else 'tarpaper')
    if kind == 'gable':
        h = h or (min(w, d) * 0.45)
        gable_roof(name, w, d, h, (cx, cy, z), m, over=1.8, thick=1.0, ridge_x=ridge_x)
        wm = wall_mat or WALL[age]
        if ridge_x:
            tri_prism(name + "_o1", d, h, 1.0, (cx + w / 2 - 0.5, cy, z), wm, axis='x')
            tri_prism(name + "_o2", d, h, 1.0, (cx - w / 2 + 0.5, cy, z), wm, axis='x')
        else:
            tri_prism(name + "_o1", w, h, 1.0, (cx, cy - d / 2 + 0.5, z), wm, axis='y')
            tri_prism(name + "_o2", w, h, 1.0, (cx, cy + d / 2 - 0.5, z), wm, axis='y')
    elif kind == 'hip':
        h = h or (min(w, d) * 0.4)
        hip_roof(name, w, d, h, (cx, cy, z), m, over=1.6)
    elif kind == 'mansard':
        h = h or 9.0
        ov = 1.4
        hw, hd = w / 2 + ov, d / 2 + ov
        iw, idd = w / 2 * 0.62, d / 2 * 0.62
        v = [(-hw, -hd, 0), (hw, -hd, 0), (hw, hd, 0), (-hw, hd, 0),
             (-iw, -idd, h), (iw, -idd, h), (iw, idd, h), (-iw, idd, h)]
        f = [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 6, 7), (3, 2, 1, 0)]
        mesh(name, v, f, (cx, cy, z), m, bevel=0.2)
        # tetőablakok elöl
        n = max(1, int(w // 12))
        for i in range(n):
            x = cx - w / 2 + w * (i + 0.5) / n
            box(f"{name}_ta{i}", (2.6, 2.4, 3.2), (x, cy - hd + 2.6, z + 1.2), 'white', bevel=0.2)
            box(f"{name}_tab{i}", (1.8, 0.4, 2.2), (x, cy - hd + 1.3, z + 1.6), 'window', bevel=0.0)
    elif kind == 'flat':
        box(name, (w - 0.8, d - 0.8, 0.6), (cx, cy, z), m, bevel=0.0)
        pm = 'concrete' if age >= 3 else 'stone'
        box(name + "_p1", (w + 1.0, 1.2, 1.6), (cx, cy - d / 2, z), pm, bevel=0.2)
        box(name + "_p2", (w + 1.0, 1.2, 1.6), (cx, cy + d / 2, z), pm, bevel=0.2)
        box(name + "_p3", (1.2, d + 1.0, 1.6), (cx - w / 2, cy, z), pm, bevel=0.2)
        box(name + "_p4", (1.2, d + 1.0, 1.6), (cx + w / 2, cy, z), pm, bevel=0.2)


def block(name, cx, cy, w, d, h, age, roof='gable', roof_h=None, ridge_x=True, wall=None, rows=None,
          nwin=None, door=True, timber=None, side_win=True, plinth=True, roof_mat=None, shutters=False):
    """Egy ház-tömb a korszak stílusában: lábazat, fal, ablaksorok, ajtó, tető.
    Visszaadja a tető alsó síkjának magasságát."""
    wm = wall or WALL[age]
    z = 0.0
    if plinth:
        box(name + "_lab", (w + 1.4, d + 1.4, 1.6), (cx, cy, 0), BASE[age], bevel=0.4)
        z = 1.6
    box(name + "_fal", (w, d, h), (cx, cy, z), wm, bevel=0.3)
    yf = cy - d / 2
    if timber is None:
        timber = (age == 0 and wm == 'plaster')
    if timber:
        half_timber_front(name + "_fh", cx - w / 2, cx + w / 2, yf, z, z + h, n=max(2, int(w // 8)))
        half_timber_side(name + "_fo", cx + w / 2, yf, yf + d, z, z + h, n=max(2, int(d // 8)), side=1)
    if age == 1 and wm in ('ochre', 'plaster', 'white'):
        for sx in (-1, 1):   # kőszegély a sarkokon
            for k in range(int(h // 3)):
                box(f"{name}_q{sx}{k}", (1.6 if k % 2 else 2.4, 1.2, 1.4), (cx + sx * (w / 2 - 0.6), yf - 0.1,
                    z + 0.5 + k * 3.0), 'stone', bevel=0.15)
        box(name + "_parkany", (w + 1.2, d + 1.2, 1.0), (cx, cy, z + h - 0.8), 'white', bevel=0.2)
    if age == 2:
        box(name + "_parkany", (w + 1.0, d + 1.0, 0.9), (cx, cy, z + h - 0.9), 'stone', bevel=0.2)
    rows = rows if rows is not None else max(1, int(h // 9))
    nwin = nwin if nwin is not None else max(1, int(w // 9))
    wh = {0: 3.4, 1: 5.0, 2: 5.2, 3: 3.8}[age]
    for r in range(rows):
        zr = z + 1.8 + r * (h - 2.0) / rows
        if r == 0 and door:
            # az ajtó körül kihagyjuk a középső ablakot
            xs = [cx - w / 2 + w * (i + 0.5) / nwin for i in range(nwin)]
            for i, x in enumerate(xs):
                if abs(x - cx) > 4.0:
                    win(f"{name}_a{r}_{i}", x, yf, zr, age, shutters=shutters)
        else:
            win_row(f"{name}_a{r}_", cx - w / 2, cx + w / 2, yf, zr, nwin, age, shutters=shutters)
        if side_win:
            win_col(f"{name}_o{r}_", cx + w / 2, yf, yf + d, zr, max(1, int(d // 10)), age, side=1)
    if door:
        if age == 0:
            arch_door(name + "_ajto", cx, yf, z, 4.4, 6.0)
        elif age == 1:
            arch_door(name + "_ajto", cx, yf, z, 4.4, 7.0, frame='white')
        elif age == 2:
            arch_door(name + "_ajto", cx, yf, z, 4.4, 7.0, frame='stone')
        else:
            box(name + "_ajto", (5.0, 1.0, 7.0), (cx, yf - 0.4, z), 'door', bevel=0.1)
            box(name + "_elo", (8.0, 3.5, 0.6), (cx, yf - 1.6, z + 7.8), 'concrete', bevel=0.1)
    zt = z + h
    if roof:
        roof_on(name + "_teto", w, d, zt, cx, cy, roof, age, h=roof_h, ridge_x=ridge_x, mat=roof_mat, wall_mat=wm)
    return zt


# ---------------------------------------------------------------- kellékek

def cannon_prop(name, x, y, rot=0.0, age=1):
    g = empty(name, (x, y, 0))
    g.rotation_euler = (0, 0, rot)
    for sd in (-1, 1):
        cyl(f"{name}_k{sd}", 2.0, 0.6, (sd * 2.0, 0, 2.0), 'wood', verts=12, rot=(0, math.pi / 2, 0), base=False,
            parent=g)
    box(name + "_l", (2.0, 7.0, 1.4), (0, 2.0, 1.2), 'wood', bevel=0.3, parent=g)
    cyl(name + "_c", 0.8, 8.0, (0, 2.0, 3.0), 'bronze' if age <= 1 else 'iron', verts=10, r2=0.6,
        rot=(math.pi / 2, 0, 0), base=True, parent=g)
    return g


def cannonballs(name, x, y):
    for i, (dx, dy, dz) in enumerate([(0, 0, 0), (1.2, 0, 0), (0.6, 1.0, 0), (0.6, 0.35, 0.9)]):
        sphere(f"{name}{i}", 0.65, (x + dx, y + dy, 0.65 + dz), 'iron', seg=8, rings=6)


def haystack(name, x, y, r=4.5):
    sphere(name, r, (x, y, r * 0.45), 'hay', scale=(1, 1, 0.95), seg=12, rings=8)


def tree(name, x, y, s=1.0, palm=False):
    if palm:
        cyl(name + "_t", 0.7 * s, 14 * s, (x, y, 0), 'wood', verts=8, r2=0.5 * s)
        for i in range(6):
            a = 2 * math.pi * i / 6
            ob = box(f"{name}_l{i}", (1.4 * s, 7 * s, 0.3), (x + math.cos(a) * 3 * s, y + math.sin(a) * 3 * s, 14 * s),
                     'leaves', bevel=0.1)
            ob.rotation_euler = (R_(15), 0, a + math.pi / 2)
    else:
        cyl(name + "_t", 0.8 * s, 6 * s, (x, y, 0), 'wood', verts=8)
        sphere(name + "_k", 4.5 * s, (x, y, 8.5 * s), 'leaves', seg=10, rings=8)


def R_(d):
    return math.radians(d)


def cart(name, x, y, rot=0.0, load='hay'):
    g = empty(name, (x, y, 0))
    g.rotation_euler = (0, 0, rot)
    box(name + "_p", (5.0, 8.0, 1.0), (0, 0, 2.2), 'wood', bevel=0.2, parent=g)
    for sd in (-1, 1):
        cyl(f"{name}_k{sd}", 2.0, 0.5, (sd * 2.8, 0.5, 2.0), 'wood', verts=12, rot=(0, math.pi / 2, 0), base=False,
            parent=g)
    box(name + "_r", (4.6, 7.6, 2.0), (0, 0, 3.2), load, bevel=0.6, parent=g)
    for sd in (-1, 1):
        box(f"{name}_ru{sd}", (0.4, 6.0, 0.4), (sd * 1.2, -6.5, 2.4), 'wood', bevel=0.0, parent=g)


def truck(name, x, y, rot=0.0):
    g = empty(name, (x, y, 0))
    g.rotation_euler = (0, 0, rot)
    for i, yy in enumerate((-4.5, 4.5)):
        for sd in (-1, 1):
            cyl(f"{name}_k{i}{sd}", 1.5, 0.9, (sd * 3.0, yy, 1.5), 'rubber', verts=12, rot=(0, math.pi / 2, 0),
                base=False, parent=g)
    box(name + "_f", (5.4, 13.0, 1.0), (0, 0, 2.0), 'olive_d', bevel=0.2, parent=g)
    box(name + "_c", (5.2, 3.8, 4.0), (0, -4.8, 3.0), 'olive', bevel=0.4, parent=g)
    box(name + "_ab", (4.4, 0.3, 1.4), (0, -6.75, 5.2), 'window', bevel=0.0, parent=g)
    box(name + "_p", (5.6, 8.2, 4.6), (0, 2.2, 3.0), 'canvas', bevel=0.8, parent=g)
    return g


# ================================================================ TÍPUSOK

# ---------------------------------------------------------------- lakóház
def house(age):
    if age == 0:
        return B0.house0()
    w, d = 34.0, 34.0
    y0 = 2.0
    if age == 1:          # barokk polgárház, manzárdtető
        zt = block("haz", 0, y0, w, d, 17, 1, roof='mansard', roof_h=9, rows=2, nwin=3, shutters=True)
        chimney("kemeny", w * 0.28, y0 + 6, zt + 5, 7, 2.8, 'plaster')
        barrel("hordo", (w / 2 + 3, y0 - d / 2 - 1.5, 0))
        box("pad", (7, 2, 1.8), (-w * 0.28, y0 - d / 2 - 2.5, 0), 'wood', bevel=0.2)
    elif age == 2:        # téglaház palatetővel, két kéménnyel
        zt = block("haz", 0, y0, w, d, 18, 2, roof='gable', roof_h=11, ridge_x=True, rows=2, nwin=3)
        chimney("kemeny1", -w * 0.3, y0 + 2, zt + 2, 10)
        chimney("kemeny2", w * 0.3, y0 + 2, zt + 2, 10)
        fence("kerites", [(-w / 2 - 2, y0 - d / 2 - 5), (-4, y0 - d / 2 - 5)], h=3.2, post_every=4, material='iron')
        fence("kerites2", [(4, y0 - d / 2 - 5), (w / 2 + 2, y0 - d / 2 - 5)], h=3.2, post_every=4, material='iron')
    else:                 # 20. századi családi ház: vakolt, cseréptető, garázs
        zt = block("haz", -4, y0 + 2, 28, 30, 16, 3, wall='white', roof='hip', roof_h=9, rows=2, nwin=3)
        box("garazs", (12, 16, 8.5), (w / 2 - 2, y0 + 8, 0), 'white', bevel=0.3)
        box("garazs_ajto", (9, 0.8, 6.5), (w / 2 - 2, y0, 0.0), 'corrug', bevel=0.1)
        box("garazs_t", (13, 17, 0.8), (w / 2 - 2, y0 + 8, 8.5), 'tarpaper', bevel=0.1)
        chimney("kemeny", -10, y0 + 8, zt + 2, 8)
        fence("kerites", [(-w / 2 - 2, y0 - 19), (w / 2 + 6, y0 - 19)], h=2.8, post_every=3, material='white')
        tree("fa", -w / 2 - 2, y0 + 16, 0.9)


# ---------------------------------------------------------------- főváros
def hq(age):
    if age == 0:
        B0.hq0()
        return
    W, Dm = fp("hq")
    if age == 1:          # csillagerőd: négyszögű sánc, a sarkokon nyílhegy-bástyák, benne barokk kastély
        S = W * 0.6
        y0 = 4.0
        box("udvar", (S, S, 0.6), (0, y0, 0), 'dirt', bevel=0.2)["talaj"] = True
        wt, wh = 5.0, 9.0
        box("sanc_e", (S, wt, wh), (0, y0 - S / 2, 0), 'stone', bevel=0.5)
        box("sanc_h", (S, wt, wh), (0, y0 + S / 2, 0), 'stone', bevel=0.5)
        box("sanc_ny", (wt, S, wh), (-S / 2, y0, 0), 'stone', bevel=0.5)
        box("sanc_k", (wt, S, wh), (S / 2, y0, 0), 'stone', bevel=0.5)
        for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
            x, y = sx * S / 2, y0 + sy * S / 2
            ob = cyl(f"bastya{i}", 15, wh + 0.4, (x, y, 0), 'stone', verts=4, r2=14, smooth=False, bevel=0.4)
            ob.rotation_euler = (0, 0, math.atan2(sy, sx))
            cyl(f"bastya_p{i}", 13.5, 0.6, (x, y, wh + 0.4), 'stone_d', verts=4, smooth=False).rotation_euler = \
                (0, 0, math.atan2(sy, sx))
            a = math.atan2(sy, sx)
            ob = cannon_prop(f"agyu{i}", x + math.cos(a) * 4, y + math.sin(a) * 4, rot=a + math.pi / 2, age=1)
            ob.location = (ob.location[0], ob.location[1], wh + 1.0)
        zt = block("kastely", 0, y0 + 6, 38, 20, 16, 1, roof='mansard', roof_h=8, rows=2, nwin=5, plinth=False)
        box("rizalit", (11, 3, 17), (0, y0 + 6 - 10 - 1.0, 0), 'ochre', bevel=0.3)
        tri_prism("timpanon", 13, 4, 1.2, (0, y0 + 6 - 11.5, 17), 'white', axis='y')
        sphere("kupola", 4.6, (0, y0 + 6, zt + 7), 'copper', scale=(1, 1, 0.9))
        cyl("lampas", 1.3, 3, (0, y0 + 6, zt + 11), 'white', verts=10)
        cone("lampas_t", 1.6, 2.4, (0, y0 + 6, zt + 14), 'copper', verts=10)
        box("cimer", (4, 0.8, 4.4), (0, y0 + 6 - 12.1, 11), 'team', bevel=0.3)
        box("cimer_k", (5.0, 0.6, 5.4), (0, y0 + 6 - 11.8, 10.5), 'accent', bevel=0.3)
        flag_pole("lobogo", (0, y0 + 6, zt + 16.4), h=12)
        # kaputorony a déli sáncon
        box("kapu", (12, 8, 12), (0, y0 - S / 2, 0), 'white', bevel=0.4)
        arch_door("kapu_a", 0, y0 - S / 2 - 4, 0, 5, 6, material='window', frame='stone')
        roof_on("kapu_t", 12, 8, 12, 0, y0 - S / 2, 'hip', 1, h=4)
        for i in range(4):
            tree(f"fa{i}", (-1) ** i * S * 0.33, y0 - S * 0.3 + (i // 2) * 4, 0.6)
    elif age == 2:        # klasszicista kormányzósági palota oszlopcsarnokkal és rézkupolával
        y0 = 8
        zt = block("palota", 0, y0, 76, 44, 26, 2, wall='marble', roof='hip', roof_h=8, rows=2, nwin=9,
                   door=False)
        yf = y0 - 22
        box("lepcso", (30, 8, 2.4), (0, yf - 4, 0), 'marble', bevel=0.3)
        n = 6
        for i in range(n):
            x = -12.5 + 25 * i / (n - 1)
            cyl(f"oszlop{i}", 1.3, 22, (x, yf - 3.5, 2.4), 'marble', verts=12)
        box("parkany", (30, 6, 2.2), (0, yf - 3, 24.4), 'marble', bevel=0.3)
        tri_prism("timpanon", 30, 7, 5.5, (0, yf - 3, 26.6), 'marble', axis='y')
        box("timpanon_c", (6, 0.6, 3.5), (0, yf - 5.9, 27.2), 'team', bevel=0.2)
        cyl("dob", 11, 9, (0, y0 + 2, zt + 4), 'marble', verts=24)
        sphere("kupola", 11.5, (0, y0 + 2, zt + 13), 'copper', scale=(1, 1, 0.85), seg=24, rings=12)
        cyl("lampas", 2.2, 5, (0, y0 + 2, zt + 22), 'marble', verts=12)
        flag_pole("lobogo", (0, y0 + 2, zt + 27), h=14, mat='iron')
        arch_door("ajto", 0, yf, 2.4, 6, 9, frame='marble')
        for sd in (-1, 1):
            chimney(f"kemeny{sd}", sd * 30, y0 + 8, zt + 1, 8)
            tree(f"fa{sd}", sd * 44, yf - 8, 1.0)
        fence("kerites", [(-W / 2, yf - 16), (-10, yf - 16)], h=3.6, post_every=3, material='iron')
        fence("kerites2", [(10, yf - 16), (W / 2, yf - 16)], h=3.6, post_every=3, material='iron')
    else:                 # 20. századi kormányépület: beton, oszlopsor, lapos tető, antenna
        y0 = 8
        zt = block("kozpont", 0, y0, 78, 46, 30, 3, wall='concrete', roof='flat', rows=3, nwin=10, door=False)
        box("torony", (22, 20, 16), (0, y0 + 4, zt), 'concrete', bevel=0.4)
        roof_on("torony_t", 22, 20, zt + 16, 0, y0 + 4, 'flat', 3)
        yf = y0 - 23
        for i in range(8):
            x = -21 + 42 * i / 7
            box(f"pillér{i}", (2.4, 2.4, 26), (x, yf - 3.0, 0), 'concrete', bevel=0.2)
        box("parkany", (48, 6, 3.0), (0, yf - 2, 26), 'concrete', bevel=0.3)
        box("felirat", (20, 0.6, 2.2), (0, yf - 5.1, 26.4), 'team', bevel=0.1)
        box("lepcso", (40, 8, 1.6), (0, yf - 4, 0), 'concrete', bevel=0.2)
        for sd in (-1, 1):
            box(f"transzparens{sd}", (5, 0.5, 18), (sd * 30, yf - 0.8, 6), 'team', bevel=0.1)
            box(f"transzparens_k{sd}", (5.6, 0.4, 1.0), (sd * 30, yf - 1.0, 24), 'accent', bevel=0.0)
        cyl("antenna", 0.35, 22, (8, y0 + 8, zt + 16), 'iron', verts=6)
        for k in range(3):
            box(f"antenna_k{k}", (6 - k * 1.5, 0.3, 0.3), (8, y0 + 8, zt + 24 + k * 4), 'iron', bevel=0.0)
        flag_pole("lobogo", (-8, y0 + 4, zt + 16), h=16, mat='iron')
        for sd in (-1, 1):
            box(f"homokzsak{sd}", (10, 3, 3.4), (sd * 30, yf - 12, 0), 'sandbag', bevel=0.8)


# ---------------------------------------------------------------- laktanya
def barracks(age):
    if age == 0:
        return B0.barracks0()
    if age == 3:
        return B0.barracks3()
    W, Dm = fp("barracks")
    y0 = 8
    if age == 1:
        zt = block("laktanya", 0, y0, 62, 36, 18, 1, roof='hip', roof_h=10, rows=2, nwin=7)
        chimney("kemeny", 18, y0 + 6, zt + 3, 7, 3.0, 'ochre')
        yf = y0 - 18
        for i, x in enumerate((-24, 24)):
            cannon_prop(f"agyu{i}", x, yf - 10, rot=0, age=1)
        cannonballs("golyo", -16, yf - 8)
        # muskétagúla
        for i in range(4):
            a = 2 * math.pi * i / 4
            ob = cyl(f"gula{i}", 0.25, 9, (14 + math.cos(a) * 1.3, yf - 9 + math.sin(a) * 1.3, 0), 'wood', verts=5)
            ob.rotation_euler = (math.sin(a) * 0.15, -math.cos(a) * 0.15, 0)
        banner("zaszlo1", (-8, yf, 9), 5, 10)
        banner("zaszlo2", (8, yf, 9), 5, 10)
        flag("lobogo", (-28, yf - 6, 0), L=12, H=8, pole_h=26)
    else:
        zt = block("laktanya", 0, y0 + 2, 64, 34, 20, 2, roof='gable', roof_h=10, ridge_x=True, rows=2, nwin=8)
        yf = y0 - 15
        # óratorony középen
        box("oratorony", (10, 8, 32), (0, yf + 3, 0), 'brick', bevel=0.3)
        cyl("ora", 2.4, 0.5, (0, yf - 1.2, 26), 'white', verts=16, rot=(math.pi / 2, 0, 0), base=False)
        hip_roof("oratorony_t", 10, 8, 6, (0, yf + 3, 32), 'roof', over=0.8)
        arch_door("kapu", 0, yf - 1, 1.6, 5.5, 8.0, frame='stone')
        for sd in (-1, 1):
            chimney(f"kemeny{sd}", sd * 22, y0 + 6, zt + 2, 8)
        for i in range(3):
            cannon_prop(f"agyu{i}", -26 + i * 9, yf - 13, rot=0, age=2)
        flag("lobogo", (28, yf - 8, 0), L=12, H=8, pole_h=30, pole_mat='iron')
        fence("kerites", [(-W / 2, yf - 20), (W / 2, yf - 20)], h=3.4, post_every=4, material='iron')


# ---------------------------------------------------------------- istálló
def stable(age):
    W, Dm = fp("stable")
    y0 = 6
    if age == 0:
        box("labazat", (56, 32, 1.4), (0, y0, 0), 'stone_d', bevel=0.4)
        box("fal", (54, 30, 11), (0, y0, 1.4), 'wood', bevel=0.3)
        gable_roof("teto", 54, 30, 12, (0, y0, 12.4), 'thatch', over=2.4, ridge_x=True)
        tri_prism("orom1", 30, 12, 1.0, (26.5, y0, 12.4), 'wood', axis='x')
        tri_prism("orom2", 30, 12, 1.0, (-26.5, y0, 12.4), 'wood', axis='x')
        doors_m = 'door'
    elif age == 1:
        block("istallo", 0, y0, 56, 30, 13, 1, roof='hip', roof_h=9, rows=1, nwin=0, door=False, side_win=False)
        doors_m = 'door'
    elif age == 2:
        block("istallo", 0, y0, 56, 30, 14, 2, roof='gable', roof_h=9, rows=1, nwin=0, door=False, side_win=False)
        doors_m = 'door'
    else:
        block("istallo", 0, y0, 56, 30, 12, 3, wall='brick', roof='gable', roof_h=7, rows=1, nwin=0, door=False,
              side_win=False, roof_mat='corrug')
        doors_m = 'corrug'
    yf = y0 - 15
    # istállóajtók, kilógó lófejek
    for i in range(4):
        x = -21 + 14 * i
        box(f"ajto{i}", (6, 0.8, 8), (x, yf - 0.4, 1.4), doors_m, bevel=0.1)
        box(f"ajto_f{i}", (6.6, 1.0, 0.8), (x, yf - 0.5, 9.4), 'timber' if age < 2 else 'stone', bevel=0.1)
        if i % 2 == 0:
            box(f"lofej{i}", (1.8, 3.4, 2.0), (x, yf - 1.8, 7.0), 'horse', bevel=0.6)
    # karám és szénakazal, vályú
    fence("karam", [(-W / 2 + 2, yf - 4), (-W / 2 + 2, yf - 18), (W / 2 - 6, yf - 18), (W / 2 - 6, yf - 4)],
          h=3.6, post_every=6, material='wood')
    haystack("kazal", W / 2 - 4, y0 + 10, 4.2)
    box("valyu", (8, 2.4, 1.8), (-10, yf - 10, 0), 'wood', bevel=0.3)
    box("valyu_v", (7, 1.6, 0.3), (-10, yf - 10, 1.6), 'water', bevel=0.0)
    banner("zaszlo", (21, yf - 0.3, 3.0), 4.5, 7.0)
    if age >= 3:
        truck("teherauto", 20, yf - 11, rot=math.pi / 2)


# ---------------------------------------------------------------- major
def farm(age):
    if age == 0:
        return B0.farm0()
    W, Dm = fp("farm")
    fw, fd = W * 0.9, Dm * 0.9
    box("tabla", (fw, fd, 1.0), (0, 0, 0), 'dirt', bevel=0.3)
    n = 9
    for i in range(n):
        x = -fw / 2 + 4 + (fw - 8) * i / (n - 1)
        box(f"sor{i}", (3.8, fd - 22, 2.0), (x, 5, 0.8), 'field' if age != 2 else 'field_g', bevel=0.6)
    bx, by = -fw / 2 + 12, fd / 2 - 9
    yf = -fd / 2
    if age == 1:
        box("csur", (20, 13, 10), (bx, by, 0.8), 'wood', bevel=0.3)
        roof_on("csur_t", 20, 13, 10.8, bx, by, 'gable', 1, h=8, wall_mat='wood')
        box("csur_a", (6, 0.8, 7), (bx + 2, by - 6.8, 0.8), 'door', bevel=0.1)
        cart("szekér", fw / 2 - 9, fd / 2 - 10, rot=0.4)
    elif age == 2:        # tanya szélmalommal
        block("tanya", bx, by, 20, 13, 9, 2, roof='gable', roof_h=7, rows=1, nwin=2, side_win=False)
        mx, my = fw / 2 - 10, fd / 2 - 8
        cyl("malom", 4.5, 18, (mx, my, 0.8), 'plaster', verts=12, r2=3.2)
        cone("malom_t", 4.0, 5, (mx, my, 18.8), 'roof', verts=12)
        g = empty("vitorla_g", (mx, my - 4.2, 16))
        for i in range(4):
            ob = box(f"lapat{i}", (1.6, 0.3, 11), (0, 0, 0), 'canvas', bevel=0.0, parent=g, base=True)
            ob.rotation_euler = (0, i * math.pi / 2 + 0.3, 0)
        haystack("kazal", fw / 2 - 18, fd / 2 - 18, 3.6)
    else:                 # gépesített major: hullámlemez pajta, siló, traktor
        box("pajta", (22, 14, 10), (bx, by, 0.8), 'corrug', bevel=0.3)
        roof_on("pajta_t", 22, 14, 10.8, bx, by, 'gable', 3, h=6, mat='corrug', wall_mat='corrug')
        sx, sy = fw / 2 - 8, fd / 2 - 8
        cyl("silo", 4.2, 22, (sx, sy, 0.8), 'concrete', verts=16)
        sphere("silo_t", 4.2, (sx, sy, 22.8), 'copper', scale=(1, 1, 0.6))
        g = empty("traktor", (6, -6, 0.8))
        g.rotation_euler = (0, 0, 0.5)
        for sd in (-1, 1):
            cyl(f"traktor_hk{sd}", 3.0, 1.4, (sd * 3.2, 3.0, 3.0), 'rubber', verts=14, rot=(0, math.pi / 2, 0),
                base=False, parent=g)
            cyl(f"traktor_ek{sd}", 1.8, 1.0, (sd * 2.6, -4.0, 1.8), 'rubber', verts=12, rot=(0, math.pi / 2, 0),
                base=False, parent=g)
        box("traktor_t", (3.2, 8.0, 3.0), (0, -1.0, 2.6), 'team', bevel=0.5, parent=g)
        box("traktor_u", (3.0, 3.0, 3.0), (0, 2.6, 5.4), 'team', bevel=0.3, parent=g)
        cyl("traktor_k", 0.35, 3.0, (0.9, -3.6, 5.4), 'iron', verts=6, parent=g)
    fence("kerites", [(-fw / 2, yf), (fw / 2, yf), (fw / 2, fd / 2 - 2)], h=3.4, post_every=6.5,
          material='wood' if age < 3 else 'iron')
    # madárijesztő
    sx, sy = 4, -4
    cyl("mi_rud", 0.45, 12, (sx, sy, 0), 'wood', verts=6)
    box("mi_kar", (8, 0.6, 0.6), (sx, sy, 9.2), 'wood', bevel=0.1)
    box("mi_ing", (6, 1.8, 5), (sx, sy, 5.2), 'team', bevel=0.5)
    sphere("mi_fej", 1.4, (sx, sy, 11.5), 'canvas', seg=8, rings=6)


# ---------------------------------------------------------------- őrtorony
def tower(age):
    if age == 0:
        return B0.tower0()
    y0 = 3
    if age == 1:          # sokszögű ágyútorony tömzsi kúptetővel
        cyl("talp", 15, 3, (0, y0, 0), 'stone_d', verts=8)
        cyl("torzs", 13.5, 30, (0, y0, 3), 'stone', verts=8, r2=12.5)
        cyl("parkany", 13.8, 1.4, (0, y0, 33), 'white', verts=8)
        for i in range(8):
            a = 2 * math.pi * (i + 0.5) / 8
            if math.sin(a) < 0.3:
                box(f"agyunyilas{i}", (3.0, 1.2, 2.4), (math.cos(a) * 12.9, y0 + math.sin(a) * 12.9, 18), 'window',
                    bevel=0.0).rotation_euler = (0, 0, a + math.pi / 2)
        cone("sisak", 15.5, 16, (0, y0, 34.4), 'roof', verts=8, smooth=False)
        flag("lobogo", (0, y0, 50), L=12, H=7, pole_h=9)
        arch_door("ajto", 0, y0 - 12.6, 3, 4.2, 6.5, frame='white')
        banner("zaszlo", (6, y0 - 12.2, 18), 4.0, 9.0)
    elif age == 2:        # martello-torony: zömök, kerek, a tetején löveggel
        cyl("torzs", 15, 26, (0, y0, 0), 'stone', verts=24, r2=13.5)
        cyl("mellved", 14.2, 3.2, (0, y0, 26), 'stone_d', verts=24)
        cyl("tetoszint", 12.8, 0.6, (0, y0, 28.4), 'stone_d', verts=24)
        g = empty("loveg", (0, y0, 29))
        cyl("loveg_a", 3.0, 2.0, (0, 0, 0), 'iron', verts=12, parent=g)
        cyl("loveg_c", 1.1, 12, (0, 0, 2.2), 'iron', verts=10, r2=0.8, rot=(math.pi / 2 + 0.15, 0, 0), base=True,
            parent=g)
        for i, x in enumerate((-5, 5)):
            box(f"ablak{i}", (2.0, 1.0, 3.6), (x, y0 - 14.3, 14), 'window', bevel=0.0)
        box("ajto", (4, 1.2, 6), (0, y0 - 14.5, 8), 'door', bevel=0.1)
        box("lepcso", (3, 8, 0.6), (0, y0 - 18, 4), 'wood', bevel=0.1).rotation_euler = (R_(-30), 0, 0)
        flag("lobogo", (7, y0 + 5, 28.4), L=12, H=7, pole_h=12, pole_mat='iron')
    else:                 # beton lövegállás (bunker) + figyelőtorony
        box("bunker", (34, 30, 10), (0, y0 + 4, 0), 'concrete', bevel=1.8)
        box("bunker_t", (37, 33, 3), (0, y0 + 4, 10), 'concrete', bevel=1.2)
        box("reses", (18, 1.0, 2.2), (0, y0 - 11.2, 6.2), 'window', bevel=0.0)
        cyl("cso", 0.9, 10, (0, y0 - 11, 7.2), 'tank_d', verts=8, rot=(math.pi / 2, 0, 0), base=True)
        for i in range(10):
            a = math.pi * (0.1 + 0.8 * i / 9) + math.pi
            box(f"zsak{i}", (4.0, 2.4, 2.2), (math.cos(a) * 21, y0 + 4 + math.sin(a) * 19, 0), 'sandbag',
                bevel=0.8).rotation_euler = (0, 0, a + math.pi / 2)
        # fa figyelőtorony a bunker tetején
        for sx in (-1, 1):
            for sy in (-1, 1):
                cyl(f"lab{sx}{sy}", 0.5, 16, (8 + sx * 3.5, y0 + 10 + sy * 3.5, 13), 'wood', verts=6)
        box("kosar", (10, 10, 3.5), (8, y0 + 10, 29), 'wood', bevel=0.2)
        gable_roof("kosar_t", 10, 10, 3, (8, y0 + 10, 34), 'corrug', over=1.0, thick=0.5)
        cyl("fenyszoro", 1.2, 1.6, (8, y0 + 5, 32.6), 'iron', verts=10, rot=(math.pi / 2, 0, 0), base=False)
        flag("lobogo", (-12, y0 + 12, 13), L=12, H=7, pole_h=16, pole_mat='iron')


# ---------------------------------------------------------------- kikötő
def harbor(age):
    W, Dm = fp("harbor")
    # a móló a telek elején (a víz felé) — a víz a játékban a telek körül van
    deck_m = 'deck' if age < 3 else 'concrete'
    box("rakpart", (W * 0.92, Dm * 0.5, 2.4), (0, -Dm * 0.18, 0), deck_m if age < 2 else 'stone', bevel=0.4)
    if age < 2:
        for i in range(8):
            x = -W * 0.42 + W * 0.84 * i / 7
            cyl(f"colop{i}", 0.9, 4.2, (x, -Dm * 0.43, -1.5), 'wood', verts=8)
    box("molo", (12, Dm * 0.4, 2.0), (W * 0.26, -Dm * 0.52, 0), deck_m, bevel=0.3)
    y0 = Dm * 0.2
    if age == 0:
        zt = block("raktar", -14, y0, 40, 24, 12, 0, roof='gable', roof_h=11, rows=1, nwin=3)
        # taposókerekes daru
        g = empty("daru", (22, -8, 2.4))
        box("daru_haz", (8, 8, 9), (0, 0, 0), 'wood', bevel=0.3, parent=g)
        cyl("daru_kerek", 4.5, 2.4, (0, 0, 12), 'wood_l', verts=16, rot=(0, math.pi / 2, 0), base=False, parent=g)
        ob = box("daru_gem", (1.2, 1.2, 18), (0, -4, 9), 'wood', bevel=0.2, parent=g, base=True)
        ob.rotation_euler = (R_(40), 0, 0)
        gable_roof("daru_t", 8, 8, 4, (0, 0, 9), 'shingle', over=0.8, thick=0.6, parent=g)
    elif age == 1:
        zt = block("raktar", -12, y0, 44, 24, 16, 1, roof='hip', roof_h=9, rows=2, nwin=4)
        g = empty("daru", (22, -8, 2.4))
        cyl("daru_oszlop", 1.2, 14, (0, 0, 0), 'wood', verts=8, parent=g)
        ob = box("daru_gem", (1.0, 1.0, 16), (0, 0, 12), 'wood', bevel=0.2, parent=g, base=True)
        ob.rotation_euler = (R_(55), 0, 0)
        cannon_prop("agyu", -34, -Dm * 0.3, rot=0, age=1)
    elif age == 2:
        zt = block("raktar", -12, y0, 44, 26, 18, 2, roof='gable', roof_h=9, ridge_x=True, rows=2, nwin=5)
        g = empty("daru", (22, -8, 2.4))
        for sx in (-1, 1):
            ob = box(f"daru_lab{sx}", (1.0, 1.0, 16), (sx * 3, 0, 0), 'iron', bevel=0.1, parent=g)
            ob.rotation_euler = (0, sx * 0.15, 0)
        ob = box("daru_gem", (1.2, 1.2, 20), (0, 0, 15), 'iron', bevel=0.1, parent=g, base=True)
        ob.rotation_euler = (R_(60), 0, 0)
        factory_chimney("kemeny", -30, y0 + 10, 30, 1.8)
    else:
        zt = block("raktar", -12, y0, 46, 26, 16, 3, wall='corrug', roof='gable', roof_h=6, ridge_x=True,
                   rows=1, nwin=4, roof_mat='corrug')
        g = empty("daru", (20, -6, 2.4))
        for sx in (-1, 1):
            for sy in (-1, 1):
                box(f"daru_lab{sx}{sy}", (0.9, 0.9, 16), (sx * 4, sy * 4, 0), 'steel_h', bevel=0.1, parent=g)
        box("daru_fulke", (6, 6, 4), (0, 0, 16), 'team', bevel=0.3, parent=g)
        ob = box("daru_gem", (1.4, 1.4, 26), (0, 0, 18), 'steel_h', bevel=0.1, parent=g, base=True)
        ob.rotation_euler = (R_(62), 0, 0)
        for i in range(3):
            box(f"kontener{i}", (9, 4, 4), (-30 + i * 2, -Dm * 0.3 + i * 4.4, 2.4), ['team', 'olive_d', 'grey'][i],
                bevel=0.2)
    # rakomány, hordók
    for i in range(3):
        barrel(f"hordo{i}", (-30 + i * 4.4, -Dm * 0.12, 2.4))
    crate("lada1", (-18, -Dm * 0.18, 2.4), 4.0)
    crate("lada2", (-18, -Dm * 0.18, 5.8), 3.4, rot=0.3)
    flag("lobogo", (W * 0.26 + 4, -Dm * 0.68, 2.0), L=10, H=6, pole_h=14, pole_mat='wood' if age < 2 else 'iron')
    # kikötött csónak
    g = empty("csonak", (W * 0.26 - 10, -Dm * 0.62, 0.2))
    sphere("csonak_t", 1.0, (0, 0, 0.8), 'hull', scale=(2.8, 7.5, 1.2), parent=g)


# ---------------------------------------------------------------- templom
def temple(age):
    W, Dm = fp("temple")
    y0 = 6
    if age == 0:          # gótikus templom kőtoronnyal és gúlasisakkal
        box("hajo", (30, 44, 20), (4, y0 + 2, 0), 'stone', bevel=0.4)
        gable_roof("hajo_t", 30, 44, 16, (4, y0 + 2, 20), 'roof', over=1.6, ridge_x=False)
        tri_prism("orom", 30, 16, 1.0, (4, y0 - 20 + 0.5, 20), 'stone', axis='y')
        for i in range(4):
            y = y0 - 14 + i * 10
            box(f"tamfal{i}", (3, 3.4, 16), (19.6, y, 0), 'stone_d', bevel=0.3)
            box(f"csucsiv{i}", (0.8, 3.0, 9), (19.2, y + 5, 6), 'window', bevel=0.0)
        cyl("rozsa", 4.5, 0.8, (4, y0 - 20.4, 21), 'glass', verts=16, rot=(math.pi / 2, 0, 0), base=False)
        arch_door("kapu", 4, y0 - 20, 0, 6, 9)
        box("torony", (14, 14, 38), (-16, y0 - 12, 0), 'stone', bevel=0.4)
        for sd in (-1, 1):
            box(f"hangablak{sd}", (0.8, 3, 6), (-16 + sd * 7.2, y0 - 12, 29), 'window', bevel=0.0)
        box("hangablak_e", (3, 0.8, 6), (-16, y0 - 19.2, 29), 'window', bevel=0.0)
        cone("sisak", 10.5, 28, (-16, y0 - 12, 38), 'roof_d', verts=8, smooth=False)
        cyl("kereszt1", 0.3, 5, (-16, y0 - 12, 66), 'gold', verts=4)
        box("kereszt2", (3, 0.5, 0.5), (-16, y0 - 12, 69), 'gold', bevel=0.0)
        banner("zaszlo", (-16, y0 - 19, 10), 5, 11)
    elif age == 1:        # barokk templom két hagymakupolás toronnyal
        box("hajo", (34, 42, 22), (0, y0 + 4, 0), 'ochre', bevel=0.4)
        gable_roof("hajo_t", 34, 42, 13, (0, y0 + 4, 22), 'roof', over=1.4, ridge_x=False)
        yf = y0 - 17
        box("homlokzat", (38, 4, 26), (0, yf, 0), 'ochre', bevel=0.4)
        tri_prism("orom", 18, 7, 2.0, (0, yf, 26), 'white', axis='y')
        box("cimer", (5, 0.6, 5), (0, yf - 2.3, 19), 'team', bevel=0.2)
        for sd in (-1, 1):
            box(f"torony{sd}", (10, 10, 36), (sd * 14, yf + 2, 0), 'ochre', bevel=0.4)
            box(f"torony_p{sd}", (11, 11, 1.2), (sd * 14, yf + 2, 36), 'white', bevel=0.3)
            sphere(f"hagyma{sd}", 5.4, (sd * 14, yf + 2, 42), 'copper', scale=(1, 1, 1.25))
            cone(f"hegy{sd}", 1.6, 7, (sd * 14, yf + 2, 47), 'copper', verts=10)
            sphere(f"gomb{sd}", 0.8, (sd * 14, yf + 2, 54.5), 'gold', seg=8, rings=6)
            box(f"ora{sd}", (4, 0.5, 4), (sd * 14, yf - 3.1, 28), 'white', bevel=0.3)
        for i in range(3):
            win(f"ab{i}", -8 + i * 8, yf - 2, 9, 1, h=7)
        arch_door("kapu", 0, yf - 2, 0, 6, 9, frame='white')
    elif age == 2:        # neogótikus székesegyház két karcsú toronnyal
        box("hajo", (34, 46, 24), (0, y0 + 4, 0), 'stone', bevel=0.4)
        gable_roof("hajo_t", 34, 46, 18, (0, y0 + 4, 24), 'roof', over=1.4, ridge_x=False)
        yf = y0 - 19
        box("homlokzat", (40, 4, 30), (0, yf, 0), 'stone', bevel=0.4)
        tri_prism("orom", 22, 12, 2.0, (0, yf, 30), 'stone', axis='y')
        cyl("rozsa", 5.5, 0.8, (0, yf - 2.3, 22), 'glass', verts=18, rot=(math.pi / 2, 0, 0), base=False)
        for sd in (-1, 1):
            box(f"torony{sd}", (11, 11, 44), (sd * 15, yf + 3, 0), 'stone', bevel=0.4)
            cone(f"sisak{sd}", 8.5, 30, (sd * 15, yf + 3, 44), 'roof_d', verts=8, smooth=False)
            for k in range(4):
                a = math.pi / 4 + k * math.pi / 2
                cone(f"fiala{sd}{k}", 1.2, 6, (sd * 15 + math.cos(a) * 5.2, yf + 3 + math.sin(a) * 5.2, 44), 'stone',
                     verts=6)
            box(f"hangablak{sd}", (3, 0.8, 8), (sd * 15, yf - 2.6, 32), 'window', bevel=0.0)
        arch_door("kapu", 0, yf - 2, 0, 7, 11, frame='stone')
        banner("zaszlo", (0, yf - 2.4, 14), 5, 8)
    else:                 # modern beton templom haranglábbal
        box("hajo", (36, 40, 18), (0, y0 + 4, 0), 'white', bevel=0.4)
        v = [(-20, -22, 0), (20, -22, 0), (20, 22, 0), (-20, 22, 0), (0, -22, 16), (0, 22, 10)]
        mesh("hajo_t", v, [(0, 1, 4), (1, 2, 5, 4), (2, 3, 5), (3, 0, 4, 5)], (0, y0 + 4, 18), 'roof', bevel=0.2)
        yf = y0 - 16
        box("uveg", (12, 0.8, 22), (0, yf - 0.2, 0), 'glass', bevel=0.1)
        box("kereszt_f", (1.4, 0.8, 16), (0, yf - 0.6, 12), 'white', bevel=0.1)
        box("kereszt_v", (8, 0.8, 1.4), (0, yf - 0.6, 24), 'white', bevel=0.1)
        box("harangtorony", (7, 7, 48), (-26, yf + 4, 0), 'concrete', bevel=0.3)
        box("harangtorony_ny", (7.2, 3.0, 8), (-26, yf + 4, 34), 'window', bevel=0.0)
        cyl("kereszt1", 0.35, 6, (-26, yf + 4, 48), 'gold', verts=4)
        box("kereszt2", (3.4, 0.5, 0.5), (-26, yf + 4, 51.6), 'gold', bevel=0.0)
        banner("zaszlo", (12, yf, 6), 4.5, 10)
    tree("fa1", W / 2 - 2, y0 + 18, 0.9)


# ---------------------------------------------------------------- aranybánya
def goldmine(age):
    W, Dm = fp("goldmine")
    y0 = 6
    # sziklás domb
    sphere("domb", 1.0, (-6, y0 + 8, 0), 'stone_d', scale=(28, 22, 16), seg=16, rings=10)
    sphere("domb2", 1.0, (14, y0 + 12, 0), 'stone', scale=(16, 14, 11), seg=14, rings=8)
    # tárna bejárat ácsolattal
    yf = y0 - 12
    box("tarna", (8, 3, 9), (-6, yf, 0), 'window', bevel=0.2)
    for sd in (-1, 1):
        box(f"acs{sd}", (1.3, 1.6, 10), (-6 + sd * 4.6, yf - 1.2, 0), 'wood', bevel=0.2)
    box("acs_f", (11, 1.8, 1.4), (-6, yf - 1.2, 10), 'wood', bevel=0.2)
    # sín és csille
    for sd in (-1, 1):
        box(f"sin{sd}", (0.4, 20, 0.4), (-6 + sd * 1.8, yf - 11, 0.2), 'iron', bevel=0.0)
    for i in range(6):
        box(f"talpfa{i}", (5, 1.0, 0.4), (-6, yf - 3 - i * 3.4, 0), 'wood', bevel=0.0)
    box("csille", (4.4, 5.4, 3.0), (-6, yf - 13, 0.8), 'iron', bevel=0.4)
    sphere("csille_rako", 2.2, (-6, yf - 13, 3.6), 'gold_ore', scale=(1, 1.2, 0.6), seg=10, rings=6)
    # érchalom
    sphere("halom", 1.0, (12, yf - 8, 0), 'gold_ore', scale=(7, 6, 4), seg=12, rings=8)
    sphere("aranyrog", 1.4, (10, yf - 12, 1.2), 'gold', seg=8, rings=6)
    if age == 0:
        box("kunyho", (12, 9, 7), (-24, yf - 4, 0), 'wood', bevel=0.3)
        gable_roof("kunyho_t", 12, 9, 5, (-24, yf - 4, 7), 'shingle', over=1.0, thick=0.6)
        chimney("kemeny", -27, yf - 2, 7, 5, 2.0, 'stone')
    elif age == 1:
        box("kunyho", (14, 10, 8), (-24, yf - 4, 0), 'wood', bevel=0.3)
        gable_roof("kunyho_t", 14, 10, 6, (-24, yf - 4, 8), 'roof', over=1.0, thick=0.6)
        g = empty("csorlo", (10, y0 - 2, 10))
        for sd in (-1, 1):
            ob = box(f"csorlo_l{sd}", (1, 1, 12), (sd * 4, 0, -10), 'wood', bevel=0.1, parent=g)
        cyl("csorlo_h", 1.0, 9, (-4.5, 0, 1), 'wood', verts=8, rot=(0, math.pi / 2, 0), base=True, parent=g)
        chimney("kemeny", -27, yf - 2, 8, 5, 2.0, 'stone')
    elif age == 2:        # gőzgépes aknatorony
        block("gephaz", -24, yf + 2, 16, 12, 12, 2, roof='gable', roof_h=6, rows=1, nwin=2, side_win=False)
        factory_chimney("kemeny", -32, yf + 8, 30, 1.8)
        for sd in (-1, 1):
            ob = box(f"akna_lab{sd}", (1.2, 1.2, 26), (8 + sd * 5, y0 - 4, 0), 'wood', bevel=0.2)
            ob.rotation_euler = (0, sd * 0.18, 0)
        cyl("akna_kerek", 4.2, 0.8, (8, y0 - 4, 26), 'iron', verts=18, rot=(math.pi / 2, 0, 0), base=False)
    else:                 # acél aknatorony és szállítószalag
        for sx in (-1, 1):
            for sy in (-1, 1):
                ob = box(f"akna_lab{sx}{sy}", (1.0, 1.0, 30), (8 + sx * 5, y0 - 4 + sy * 4, 0), 'steel_h', bevel=0.1)
                ob.rotation_euler = (-sy * 0.1, sx * 0.1, 0)
        for sd in (-1, 1):
            cyl(f"akna_kerek{sd}", 3.6, 0.6, (8 + sd * 2.5, y0 - 4, 30), 'team', verts=18, rot=(0, math.pi / 2, 0),
                base=False)
        box("gephaz", (18, 12, 10), (-24, yf + 2, 0), 'corrug', bevel=0.3)
        roof_on("gephaz_t", 18, 12, 10, -24, yf + 2, 'gable', 3, h=4, mat='corrug', wall_mat='corrug')
        ob = box("szalag", (3, 26, 1.2), (8, yf - 6, 6), 'steel_hd', bevel=0.2)
        ob.rotation_euler = (R_(-18), 0, 0)
    flag("lobogo", (W / 2 - 6, yf - 4, 0), L=10, H=6, pole_h=14, pole_mat='wood' if age < 3 else 'iron')


# ---------------------------------------------------------------- repülőtér
def airfield(age):
    W, Dm = fp("airfield")
    box("gyep", (W * 0.95, Dm * 0.9, 0.4), (0, 0, 0), 'field_g', bevel=0.2)
    box("kifuto", (W * 0.9, 14, 0.6), (0, -Dm * 0.22, 0.2), 'asphalt', bevel=0.2)
    for i in range(9):
        box(f"csik{i}", (5, 1.0, 0.1), (-W * 0.4 + i * W * 0.1, -Dm * 0.22, 0.8), 'white', bevel=0.0)
    # hangár (félhenger hullámlemezből)
    hx, hy = -W * 0.2, Dm * 0.18
    ob = cyl("hangar", 13, 34, (hx, hy - 17, 0), 'corrug', verts=24, rot=(-math.pi / 2, 0, 0), base=True)
    ob.scale = (1.0, 1.0, 1.0)
    box("hangar_talp", (27, 34, 0.5), (hx, hy, 0), 'concrete', bevel=0.0)
    box("hangar_kapu", (20, 0.6, 10), (hx, hy - 17.2, 0.4), 'team_s', bevel=0.1)
    # irányítótorony
    tx, ty = W * 0.3, Dm * 0.22
    box("torony", (8, 8, 18), (tx, ty, 0), 'white', bevel=0.3)
    box("torony_ab", (10, 10, 4), (tx, ty, 18), 'glass', bevel=0.3)
    box("torony_t", (11, 11, 0.8), (tx, ty, 22), 'concrete', bevel=0.2)
    # szélzsák és zászló
    cyl("szelzsak_r", 0.3, 14, (tx + 12, ty - 8, 0), 'iron', verts=6)
    ob = cyl("szelzsak", 1.2, 5, (tx + 12, ty - 8, 13.5), 'team', verts=10, r2=0.6, rot=(0, math.pi / 2, 0), base=True)
    flag("lobogo", (tx - 10, ty - 10, 0), L=11, H=7, pole_h=18, pole_mat='iron')
    for i in range(4):
        barrel(f"hordo{i}", (W * 0.1 + i * 4.2, Dm * 0.08, 0.4), r=1.6, h=3.6)


# ---------------------------------------------------------------- cukornád-ültetvény
def sugar(age):
    W, Dm = fp("sugar")
    fw, fd = W * 0.92, Dm * 0.9
    box("tabla", (fw, fd, 1.0), (0, 0, 0), 'dirt', bevel=0.3)
    random.seed(3)
    for i in range(7):
        x = -fw / 2 + 5 + (fw * 0.55) * i / 6
        for j in range(5):
            y = -fd / 2 + 10 + j * (fd - 20) / 4
            cyl(f"nad{i}_{j}", 1.6, 7 + random.random() * 2, (x, y, 0.8), 'cane', verts=6, r2=2.4)
    # cukormalom (az ültetvény ura: szélmalom, a 19. századtól gőzös főzőház)
    mx, my = fw / 2 - 14, fd / 2 - 16
    if age <= 1:
        cyl("malom", 7, 16, (mx, my, 0.8), 'stone', verts=14, r2=5.5)
        cone("malom_t", 6.2, 6, (mx, my, 16.8), 'palm', verts=12)
        g = empty("vitorla_g", (mx, my - 6.4, 14))
        for i in range(4):
            ob = box(f"lapat{i}", (2.0, 0.3, 12), (0, 0, 0), 'canvas', bevel=0.0, parent=g, base=True)
            ob.rotation_euler = (0, i * math.pi / 2 + 0.4, 0)
        box("fozohaz", (16, 10, 7), (mx - 4, my + 16, 0.8), 'plaster', bevel=0.3)
        gable_roof("fozohaz_t", 16, 10, 5, (mx - 4, my + 16, 7.8), 'palm', over=1.2, thick=0.6)
    else:
        block("fozohaz", mx - 2, my + 6, 22, 16, 10, 2 if age == 2 else 3, roof='gable', roof_h=6, rows=1, nwin=2,
              side_win=False)
        factory_chimney("kemeny", mx + 10, my + 14, 28, 1.8)
    tree("palma1", -fw / 2 + 2, fd / 2 - 4, 1.0, palm=True)
    tree("palma2", fw / 2 - 2, -fd / 2 + 6, 0.9, palm=True)
    cart("szeker", mx - 14, -fd / 2 + 12, rot=0.2, load='cane')
    flag("lobogo", (-fw / 2 + 4, -fd / 2 + 4, 0.8), L=10, H=6, pole_h=12)


# ---------------------------------------------------------------- piac
def market(age):
    if age == 0:
        return B0.market0()
    W, Dm = fp("market")
    w, d = W * 0.84, Dm * 0.86
    box("ter", (w, d, 0.8), (0, 0, 0), 'cobble', bevel=0.3)
    yf = -d / 2
    if age == 1:          # árkádos vásárcsarnok (nyitott földszint)
        cy = d * 0.12
        hw, hd = 44.0, 26.0
        for i in range(6):
            for j in (0, 1):
                x = -hw / 2 + hw * i / 5
                y = cy - hd / 2 + hd * j
                box(f"pillér{i}{j}", (2.4, 2.4, 9), (x, y, 0.8), 'stone', bevel=0.2)
        box("emelet", (hw + 2.4, hd + 2.4, 9), (0, cy, 9.8), 'ochre', bevel=0.3)
        win_row("em_ab", -hw / 2, hw / 2, cy - hd / 2 - 1.2, 11.5, 6, 1)
        roof_on("teto", hw + 2.4, hd + 2.4, 18.8, 0, cy, 'hip', 1, h=10)
        cyl("ora_torony", 2.4, 6, (0, cy, 26), 'white', verts=8)
        cone("ora_t", 3.0, 4, (0, cy, 32), 'copper', verts=8)
        for k in range(4):
            crate(f"lada{k}", (-18 + k * 9, cy - 4 + (k % 2) * 6, 0.8), 3.4, rot=k * 0.4)
            sack(f"zsak{k}", (-14 + k * 9, cy + 4, 0.8))
    elif age == 2:        # öntöttvas-üveg vásárcsarnok
        cy = d * 0.1
        hw, hd = 50.0, 30.0
        box("labazat", (hw, hd, 3.0), (0, cy, 0.8), 'brick', bevel=0.3)
        for i in range(7):
            x = -hw / 2 + hw * i / 6
            box(f"vas{i}", (1.2, hd, 12), (x, cy, 3.8), 'iron', bevel=0.1)
        box("uvegfal", (hw - 1, hd - 1, 12), (0, cy, 3.8), 'glass', bevel=0.0)
        ob = cyl("boltiv", hd / 2, hw, (-hw / 2, cy, 15.8), 'glass', verts=20, rot=(0, math.pi / 2, 0), base=True)
        ob.scale = (0.55, 1.0, 1.0)
        for i in range(7):
            ob = cyl(f"iv{i}", hd / 2 + 0.2, 0.8, (-hw / 2 + hw * i / 6, cy, 15.8), 'iron', verts=20,
                     rot=(0, math.pi / 2, 0), base=False)
            ob.scale = (0.55, 1.0, 1.0)
        arch_door("kapu", 0, cy - hd / 2, 0.8, 7, 9, frame='brick')
        box("felirat", (18, 0.6, 2.4), (0, cy - hd / 2 - 0.5, 12.5), 'team', bevel=0.1)
    else:                 # áruház: tégla, kirakatok, napellenzők
        cy = d * 0.16
        zt = block("aruhaz", 0, cy, 54, 26, 20, 3, wall='brick', roof='flat', rows=2, nwin=6, door=True)
        for i in range(5):
            x = -22 + 11 * i
            v = [(x - 4.5, cy - 13 - 4.0, 6.5), (x + 4.5, cy - 13 - 4.0, 6.5), (x + 4.5, cy - 13, 9.5),
                 (x - 4.5, cy - 13, 9.5)]
            ob = mesh(f"ellenzo{i}", v, [(0, 1, 2, 3)], (0, 0, 0.8), 'team' if i % 2 == 0 else 'canvas')
            ob.modifiers.new("V", 'SOLIDIFY').thickness = 0.3
        box("felirat", (24, 0.8, 3.0), (0, cy - 13.4, 22), 'team', bevel=0.1)
    # árusok elöl (minden korszakban)
    goods = ['#c0392b', '#e0a030', '#6a8a30', '#8a4a9a']
    for si, sx in enumerate((-22, 20)):
        sy = yf + 8
        box(f"pult{si}", (12, 4, 4.0), (sx, sy, 0.8), 'wood_l', bevel=0.3)
        for g in range(4):
            gm = mat(f"aru{goods[(g + si) % 4]}", 'plain', goods[(g + si) % 4], rough=0.6)
            sphere(f"aru{si}{g}", 1.1, (sx - 4.5 + g * 3, sy, 5.8), gm, seg=8, rings=6)
        n = 4
        for k in range(n):
            x0 = sx - 7 + 14 * k / n
            x1 = sx - 7 + 14 * (k + 1) / n
            v = [(x0, sy - 4, 7.5), (x1, sy - 4, 7.5), (x1, sy + 5, 10.5), (x0, sy + 5, 10.5)]
            ob = mesh(f"ponyva{si}{k}", v, [(0, 1, 2, 3)], (0, 0, 0.8), 'team' if k % 2 == 0 else 'canvas')
            ob.modifiers.new("V", 'SOLIDIFY').thickness = 0.3
        for px in (-1, 1):
            box(f"rud{si}{px}", (0.7, 0.7, 10), (sx + px * 6.6, sy + 4.6, 0.8), 'wood', bevel=0.1)


# ---------------------------------------------------------------- ispotály
def hospital(age):
    W, Dm = fp("hospital")
    y0 = 6
    if age == 0:          # kolostori ispotály: kőház kereszttel, kerttel
        zt = block("ispotaly", -4, y0, 46, 28, 14, 0, wall='stone', roof='gable', roof_h=12, ridge_x=True,
                   rows=1, nwin=4, timber=False)
        cyl("kereszt1", 0.4, 6, (-4, y0 - 14, zt + 12), 'gold', verts=4)
        box("kereszt2", (3.4, 0.6, 0.6), (-4, y0 - 14, zt + 16), 'gold', bevel=0.0)
        box("fuveskert", (16, 12, 0.6), (26, y0 - 12, 0), 'field_g', bevel=0.2)
        fence("kertkerites", [(18, y0 - 18), (34, y0 - 18), (34, y0 - 6)], h=2.6, post_every=4)
        banner("zaszlo", (-18, y0 - 14.3, 3), 4.5, 8)
    elif age == 1:
        zt = block("ispotaly", 0, y0, 54, 30, 18, 1, roof='mansard', roof_h=9, rows=2, nwin=6)
        box("cimer", (5, 0.6, 5), (0, y0 - 15.4, 14), 'team', bevel=0.2)
        cyl("kupola", 3, 5, (0, y0, zt + 9), 'white', verts=10)
        cone("kupola_t", 3.8, 4, (0, y0, zt + 14), 'copper', verts=10)
        chimney("kemeny", 18, y0 + 6, zt + 4, 6, 2.6, 'ochre')
    elif age == 2:        # téglakórház vöröskeresztes zászlóval
        zt = block("korhaz", 0, y0, 56, 30, 20, 2, roof='hip', roof_h=8, rows=2, nwin=7)
        box("kereszt_h", (10, 0.6, 3), (0, y0 - 15.4, 21.5), 'white', bevel=0.1)
        box("kereszt1", (6, 0.8, 1.6), (0, y0 - 15.6, 22.2), 'redcross', bevel=0.0)
        box("kereszt2", (1.6, 0.8, 6), (0, y0 - 15.6, 20.2), 'redcross', bevel=0.0)
        chimney("kemeny", 20, y0 + 6, zt + 2, 8)
        # mentőkocsi (lovas)
        cart("mentokocsi", -26, y0 - 24, rot=0.3, load='white')
    else:                 # tábori kórház: épület + sátrak vöröskereszttel
        zt = block("korhaz", -8, y0 + 4, 44, 26, 16, 3, wall='white', roof='flat', rows=2, nwin=5)
        for i, x in enumerate((-22, 6)):
            g = empty(f"sator{i}", (x, y0 - 22, 0))
            ob = gable_roof(f"sator{i}_t", 16, 11, 7, (0, 0, 2.0), 'olive', over=0.4, thick=0.3, ridge_x=True, parent=g)
            box(f"sator{i}_k1", (4.0, 0.4, 1.2), (0, -3.2, 5.5), 'white', bevel=0.0, parent=g).rotation_euler = (R_(-32), 0, 0)
            box(f"sator{i}_k2", (2.6, 0.5, 0.8), (0, -3.3, 5.5), 'redcross', bevel=0.0, parent=g).rotation_euler = (R_(-32), 0, 0)
            box(f"sator{i}_k3", (0.8, 0.5, 2.6), (0, -3.3, 4.6), 'redcross', bevel=0.0, parent=g).rotation_euler = (R_(-32), 0, 0)
        cyl("kereszt_kor", 4.0, 0.3, (-8, y0 + 4, zt + 0.7), 'white', verts=16)
        box("kereszt1", (5.6, 1.6, 0.2), (-8, y0 + 4, zt + 1.0), 'redcross', bevel=0.0)
        box("kereszt2", (1.6, 5.6, 0.2), (-8, y0 + 4, zt + 1.0), 'redcross', bevel=0.0)
        truck("mento", 24, y0 - 6, rot=math.pi / 2 + 0.2)
    flag("lobogo", (W / 2 - 4, y0 - 20, 0), L=10, H=6, pole_h=16, pole_mat='wood' if age < 2 else 'iron')


# ---------------------------------------------------------------- kovácsműhely
def smith(age):
    W, Dm = fp("smith")
    y0 = 6
    if age <= 1:
        wm = 'stone' if age == 0 else 'ochre'
        box("labazat", (40, 26, 1.4), (-6, y0 + 2, 0), 'stone_d', bevel=0.4)
        box("hatfal", (40, 6, 12), (-6, y0 + 12, 1.4), wm, bevel=0.3)
        box("oldalfal", (6, 26, 12), (-23, y0 + 2, 1.4), wm, bevel=0.3)
        for x in (-2, 12):
            box(f"oszlop{x}", (1.6, 1.6, 12), (x, y0 - 10, 1.4), 'timber', bevel=0.2)
        gable_roof("teto", 40, 26, 10, (-6, y0 + 2, 13.4), 'roof' if age == 1 else 'shingle', over=2.0, ridge_x=True)
        # kohó izzó parázzsal
        box("koho", (8, 6, 5), (-14, y0 + 6, 1.4), 'stone_d', bevel=0.5)
        sphere("parazs", 2.4, (-14, y0 + 4, 6.2), 'ember', scale=(1.2, 0.8, 0.4))
        chimney("kemeny", -14, y0 + 8, 6.4, 18, 3.4, 'stone')
        # üllő, fújtató, fegyverek
        box("ullo_t", (1.6, 1.6, 3), (2, y0 - 4, 1.4), 'wood', bevel=0.2)
        box("ullo", (3.4, 1.4, 1.4), (2, y0 - 4, 4.4), 'iron', bevel=0.3)
        box("fujtato", (4, 3, 2), (-18, y0 - 2, 3), 'leather', bevel=0.6)
        for i in range(4):
            ob = cyl(f"kard{i}", 0.25, 7, (10 + i * 1.2, y0 + 10, 1.6), 'steel', verts=4)
            ob.rotation_euler = (R_(-15), 0, 0)
        box("vizes_kad", (4, 3, 2.4), (8, y0 - 12, 0), 'wood', bevel=0.3)
        banner("zaszlo", (-2, y0 - 10.5, 5), 3.6, 6)
    elif age == 2:        # öntöde gyárkéménnyel
        zt = block("ontode", -4, y0 + 2, 48, 28, 16, 2, roof='gable', roof_h=8, ridge_x=True, rows=1, nwin=5)
        factory_chimney("kemeny", 24, y0 + 10, 44, 2.4)
        box("kemence_feny", (8, 0.8, 5), (-14, y0 - 12.4, 1.6), 'ember', bevel=0.0)
        for i in range(3):
            cyl(f"agyucso{i}", 0.9, 12, (-20 + i * 3, y0 - 20, 0.9), 'iron', verts=10, rot=(0, math.pi / 2, 0),
                base=False)
        cannonballs("golyo", 10, y0 - 20)
    else:                 # hadiüzem fűrészfogas tetővel
        box("uzem", (54, 30, 12), (-2, y0 + 2, 0), 'brick', bevel=0.3)
        for i in range(5):
            x = -26 + 11 * i
            v = [(0, -15, 0), (0, 15, 0), (0, 15, 6), (0, -15, 6), (10, -15, 0), (10, 15, 0)]
            mesh(f"fureszfog{i}", v, [(0, 1, 2, 3), (3, 2, 5, 4), (0, 3, 4), (1, 5, 2), (0, 4, 5, 1)],
                 (x, y0 + 2, 12), 'corrug', bevel=0.1)
            box(f"feluveg{i}", (0.4, 28, 5.4), (x + 0.2, y0 + 2, 12.2), 'glass', bevel=0.0)
        win_row("ab", -28, 24, y0 - 13.1, 3, 6, 3)
        box("kapu", (10, 0.8, 9), (16, y0 - 13.2, 0), 'corrug', bevel=0.1)
        factory_chimney("kemeny", -28, y0 + 14, 40, 2.4)
        for i in range(3):
            box(f"lada{i}", (5, 3.6, 3), (-20 + i * 6, y0 - 22, 0), 'olive_d', bevel=0.3)
        box("jel", (14, 0.6, 3), (-8, y0 - 13.5, 13), 'team', bevel=0.1)


# ---------------------------------------------------------------- akadémia
def academy(age):
    W, Dm = fp("academy")
    y0 = 8
    if age == 0:          # gótikus egyetemi kollégium udvarral és toronnyal
        zt = block("kollegium", 0, y0 + 6, 56, 26, 20, 0, wall='stone', roof='gable', roof_h=13, ridge_x=True,
                   rows=2, nwin=6, timber=False)
        box("torony", (12, 12, 36), (-22, y0 - 8, 0), 'stone', bevel=0.4)
        merlons("torony_p", -28, -16, y0 - 14, y0 - 2, 36, size=2.4, gap=2.0, h=2.6, thick=1.6)
        box("ora", (5, 0.6, 5), (-22, y0 - 14.4, 26), 'white', bevel=0.3)
        for sd in (-1, 1):
            box(f"kapu_sz{sd}", (1.6, 1.6, 8), (sd * 5 + 8, y0 - 12, 0), 'stone', bevel=0.2)
        banner("zaszlo", (8, y0 - 7.5, 8), 5, 9)
        tree("fa", 20, y0 - 14, 0.9)
    elif age == 1:        # barokk akadémia kupolával
        zt = block("akademia", 0, y0, 60, 30, 20, 1, roof='mansard', roof_h=10, rows=2, nwin=7)
        cyl("dob", 7, 5, (0, y0, zt + 9), 'ochre', verts=16)
        sphere("kupola", 7.2, (0, y0, zt + 14), 'copper', scale=(1, 1, 0.9), seg=18, rings=10)
        cyl("lampas", 1.5, 3, (0, y0, zt + 20), 'white', verts=8)
        box("cimer", (5, 0.6, 5), (0, y0 - 15.4, 21), 'team', bevel=0.2)
        for sd in (-1, 1):
            cyl(f"szobor{sd}", 1.2, 5, (sd * 10, y0 - 22, 0), 'marble', verts=8)
            sphere(f"szobor_f{sd}", 1.2, (sd * 10, y0 - 22, 6), 'marble', seg=8, rings=6)
    elif age == 2:        # klasszicista akadémia oszlopcsarnokkal és csillagvizsgálóval
        zt = block("akademia", 0, y0, 60, 30, 22, 2, wall='marble', roof='hip', roof_h=7, rows=2, nwin=8,
                   door=False)
        yf = y0 - 15
        for i in range(6):
            cyl(f"oszlop{i}", 1.2, 18, (-12 + 24 * i / 5, yf - 3, 1.6), 'marble', verts=12)
        box("parkany", (28, 5, 2.4), (0, yf - 2.5, 19.6), 'marble', bevel=0.3)
        tri_prism("timpanon", 28, 6, 4.5, (0, yf - 2.5, 22), 'marble', axis='y')
        arch_door("ajto", 0, yf, 1.6, 5, 8, frame='marble')
        cyl("csillagvizsgalo", 6.5, 5, (20, y0 + 6, zt + 2), 'marble', verts=16)
        sphere("csv_kupola", 6.6, (20, y0 + 6, zt + 7), 'copper', scale=(1, 1, 0.8), seg=16, rings=8)
        box("csv_res", (1.4, 7, 0.6), (20, y0 + 2.6, zt + 10), 'window', bevel=0.0).rotation_euler = (R_(40), 0, 0)
        box("felirat", (14, 0.6, 1.6), (0, yf - 5.1, 20.2), 'team', bevel=0.1)
    else:                 # kutatóintézet: beton, üvegszalag, rádióantenna, kupola
        zt = block("intezet", -6, y0, 50, 30, 22, 3, wall='white', roof='flat', rows=3, nwin=6)
        cyl("csv", 7.0, 8, (22, y0 - 2, 0), 'white', verts=18)
        sphere("csv_kupola", 7.0, (22, y0 - 2, 8), 'steel_h', scale=(1, 1, 0.9), seg=18, rings=8)
        box("csv_res", (1.6, 8, 0.6), (22, y0 - 6, 12.5), 'window', bevel=0.0).rotation_euler = (R_(35), 0, 0)
        cyl("antenna", 0.35, 26, (-20, y0 + 8, zt), 'iron', verts=6)
        for k in range(3):
            box(f"antenna_k{k}", (7 - 2 * k, 0.3, 0.3), (-20, y0 + 8, zt + 14 + k * 5), 'iron', bevel=0.0)
        box("felirat", (18, 0.6, 2.4), (-6, y0 - 15.4, 20), 'team', bevel=0.1)
        tree("fa", -30, y0 - 20, 0.8)


BUILDERS = {}
for _t, _f in (("hq", hq), ("house", house), ("barracks", barracks), ("stable", stable), ("farm", farm),
               ("tower", tower), ("harbor", harbor), ("temple", temple), ("airfield", airfield),
               ("goldmine", goldmine), ("sugar", sugar), ("market", market), ("hospital", hospital),
               ("smith", smith), ("academy", academy)):
    for _a in range(4):
        if _t == "airfield" and _a < 3:
            continue
        BUILDERS[(_t, _a)] = (lambda f, a: (lambda: f(a)))(_f, _a)

FLAT = ("farm", "market", "airfield", "sugar")


# ---------------------------------------------------------------- sérült állapot

def make_damage(seed=5):
    """A kész épületből romos változat: beszakadt tetőrész, kormos, ledőlt
    darabok, törmelék, kiégett gerendák. (A tüzet és a füstöt a játék élőben
    rajzolja rá.)"""
    rnd = random.Random(seed)
    bpy.context.view_layer.update()
    obs = [o for o in bpy.context.scene.objects if o.type == 'MESH' and not o.get("catcher") and not o.get("talaj")]
    if not obs:
        return
    xs, ys, zs = [], [], []
    for o in obs:
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            xs.append(p.x); ys.append(p.y); zs.append(p.z)
    x0, x1, y0, y1, zmax = min(xs), max(xs), min(ys), max(ys), max(zs)
    burnt = M('burnt')
    # 1) a legnagyobb tetőn lyuk: a tetőt egy függőleges síkkal kettévágjuk és
    #    az egyik felét süllyesztve, ferdén hagyjuk
    roofs = [o for o in obs if o.data.materials and o.data.materials[0] and
             o.data.materials[0].name in ('roof', 'roof_d', 'shingle', 'thatch', 'tarpaper', 'corrug', 'palm')]
    import bmesh
    for o in roofs[:2]:
        bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
        cx = sum(p.x for p in bb) / 8 + (max(p.x for p in bb) - min(p.x for p in bb)) * rnd.uniform(0.0, 0.25)
        inv = o.matrix_world.inverted()
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-4,
                               plane_co=inv @ Vector((cx, 0, 0)), plane_no=(inv.to_3x3() @ Vector((1, 0, 0))).normalized(),
                               clear_outer=True)
        bm.to_mesh(o.data)
        bm.free()
        # a lyuk alatt kiégett belső
        zb = min(p.z for p in bb)
        box(o.name + "_belso", (max(p.x for p in bb) - cx - 1.0, (max(p.y for p in bb) - min(p.y for p in bb)) * 0.6,
                                1.0), ((cx + max(p.x for p in bb)) / 2, (max(p.y for p in bb) + min(p.y for p in bb)) / 2,
                                       zb - 0.2), 'burnt', bevel=0.0)
        for k in range(4):
            ob = box(f"{o.name}_gerenda{k}", (0.9, (max(p.y for p in bb) - min(p.y for p in bb)) * 0.7, 0.9),
                     (cx + 2 + k * 3.2, (max(p.y for p in bb) + min(p.y for p in bb)) / 2, zb + 1.5 + rnd.random() * 2),
                     'burnt', bevel=0.1)
            ob.rotation_euler = (rnd.uniform(-0.4, 0.4), rnd.uniform(-0.3, 0.3), rnd.uniform(-0.2, 0.2))
    # 2) kormos, kiégett felületek: a darabok egy részén égett anyag
    for o in obs:
        if o.name.endswith(("_belso",)) or not o.data.materials:
            continue
        if rnd.random() < 0.22:
            if o.data.users > 1:
                o.data = o.data.copy()
            for i in range(len(o.data.materials)):
                o.data.materials[i] = burnt
    # 3) kisebb darabok ledőlnek
    smalls = [o for o in obs if max(o.dimensions) < 8 and o.parent is None]
    for o in rnd.sample(smalls, min(len(smalls), max(2, len(smalls) // 6))):
        o.rotation_euler = (o.rotation_euler[0] + rnd.uniform(-0.8, 0.8), o.rotation_euler[1] + rnd.uniform(-0.8, 0.8),
                            o.rotation_euler[2])
        o.location = (o.location[0], o.location[1], max(0.0, o.location[2] * rnd.uniform(0.3, 0.9)))
    # 4) törmelékhalmok a fal tövében
    for k in range(9):
        x = rnd.uniform(x0, x1)
        y = rnd.choice((y0 - 1.5, y0 + rnd.uniform(0, 6)))
        for j in range(3):
            ob = box(f"tormelek{k}_{j}", (rnd.uniform(1.5, 3.2), rnd.uniform(1.2, 2.6), rnd.uniform(0.8, 1.8)),
                     (x + rnd.uniform(-2, 2), y + rnd.uniform(-1.5, 1.5), 0), rnd.choice(('stone', 'stone_d', 'burnt',
                                                                                         'wood')), bevel=0.3)
            ob.rotation_euler = (rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), rnd.uniform(0, 3))
    # 5) a füstpontok maradnak (a játék nagyobb füstöt ereszt belőlük)
