# -*- coding: utf-8 -*-
# BIRODALOM — ÉPÜLETMODELLEK (eljárással, bpy)
#
# Minden építő a talp közepére (világ-origó) épít. A telek a játékban w x h
# világképpont (HtmlEpulet.MERET); a modellben a mélység h / sin(ELEV), hogy
# a képen pontosan h legyen. Az "age" a korszak (0 = 15. század ... 3 = 20. sz.).

import math, random
import bpy
from mathutils import Vector
from bir_common import *

MERET = {
    "hq": (104, 104), "barracks": (80, 80), "stable": (76, 68), "farm": (56, 56),
    "tower": (50, 50), "house": (56, 44), "market": (72, 56),
}


def D(h):
    """A telek mélysége a modellben."""
    return h / SIN_E


# ---------------------------------------------------------------- apró elemek

def tri_prism(name, w, h, thick, loc, material='plaster', axis='x'):
    """Háromszög oromfal (alap w, magasság h), vastagsága az axis mentén."""
    t = thick / 2
    if axis == 'x':   # a háromszög az YZ síkban (oldalsó oromfal)
        v = [(-t, -w / 2, 0), (-t, w / 2, 0), (-t, 0, h), (t, -w / 2, 0), (t, w / 2, 0), (t, 0, h)]
    else:             # az XZ síkban (homlokzati oromfal)
        v = [(-w / 2, -t, 0), (w / 2, -t, 0), (0, -t, h), (-w / 2, t, 0), (w / 2, t, 0), (0, t, h)]
    f = [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
    return mesh(name, v, f, loc, material)


def flag(name, loc, L=14.0, H=9.0, material='team', amp=1.4, waves=1.3, parent=None, pole_h=None,
         pole_mat='wood'):
    """Lobogó zászló rúddal. loc = a rúd talpa; a zászló a rúd tetején."""
    if pole_h is None:
        pole_h = 16.0
    cyl(name + "_rud", 0.55, pole_h, loc, pole_mat, verts=8)
    sphere(name + "_gomb", 0.9, (loc[0], loc[1], loc[2] + pole_h + 0.5), 'gold', seg=8, rings=6)
    nx, nz = 12, 4
    verts, faces = [], []
    for i in range(nx + 1):
        x = L * i / nx
        k = x / L
        y = math.sin(k * math.pi * 2 * waves) * amp * k
        zdrop = -k * k * 1.2
        for j in range(nz + 1):
            verts.append((x + 0.5, y, pole_h - H + H * j / nz + zdrop))
    for i in range(nx):
        for j in range(nz):
            a = i * (nz + 1) + j
            faces.append((a, a + nz + 1, a + nz + 2, a + 1))
    ob = mesh(name, verts, faces, loc, material, smooth=True)
    sol = ob.modifiers.new("Vastag", 'SOLIDIFY')
    sol.thickness = 0.35
    return ob


def banner(name, loc, w=6.0, h=14.0, material='team', trim=True, face=-1):
    """Falra akasztott hosszú zászló (a homlokzat előtt, -Y felé)."""
    x, y, z = loc
    v = [(-w / 2, 0, 0), (w / 2, 0, 0), (w / 2, 0, h), (-w / 2, 0, h), (0, 0, -w * 0.45)]
    f = [(4, 1, 2, 3, 0)]
    ob = mesh(name, v, f, (x, y - 0.6 * (-face), z), material)
    sol = ob.modifiers.new("Vastag", 'SOLIDIFY')
    sol.thickness = 0.4
    if trim:
        box(name + "_rud", (w + 2.0, 0.9, 0.9), (x, y - 0.8, z + h), 'wood', bevel=0.2)
        box(name + "_szel", (w * 0.9, 0.5, 1.2), (x, y - 1.0, z + h - 2.4), 'accent', bevel=0.1)
    return ob


def merlons(name, x0, x1, y0, y1, z, size=3.0, gap=2.5, h=3.2, material='stone', thick=None):
    """Pártázat egy téglalap négy oldalán (a téglalap a fal külső éle)."""
    t = thick or size
    n = 0
    def row(ax, a0, a1, fixed, horiz):
        nonlocal n
        L = a1 - a0
        k = max(1, int((L + gap) // (size + gap)))
        step = L / k
        for i in range(k):
            c = a0 + step * (i + 0.5)
            if horiz:
                box(f"{name}{n}", (size, t, h), (c, fixed, z), material, bevel=0.3)
            else:
                box(f"{name}{n}", (t, size, h), (fixed, c, z), material, bevel=0.3)
            n += 1
    row('x', x0, x1, y0 + t / 2, True)
    row('x', x0, x1, y1 - t / 2, True)
    row('y', y0 + t, y1 - t, x0 + t / 2, False)
    row('y', y0 + t, y1 - t, x1 - t / 2, False)


def ring_merlons(name, cx, cy, r, z, n=10, size=2.6, h=3.0, material='stone'):
    for i in range(n):
        a = 2 * math.pi * i / n
        ob = box(f"{name}{i}", (size, 2.4, h), (cx + math.cos(a) * (r - 1.2), cy + math.sin(a) * (r - 1.2), z),
                 material, bevel=0.3)
        ob.rotation_euler = (0, 0, a + math.pi / 2)


def arch_door(name, x, y, z, w, h, material='door', frame='stone_d', face_y=-1):
    """Ívelt tetejű ajtó a -Y homlokzaton (y = a homlokzat síkja)."""
    box(name + "_k", (w + 2.0, 1.2, h + 1.2), (x, y - 0.3, z), frame, bevel=0.3)
    box(name, (w, 1.2, h), (x, y - 0.8, z), material, bevel=0.15)
    cyl(name + "_iv", w / 2, 1.2, (x, y - 0.8, z + h), material, verts=12, rot=(math.pi / 2, 0, 0),
        base=False)
    box(name + "_vas", (w * 0.9, 1.4, 0.5), (x, y - 1.0, z + h * 0.3), 'iron', bevel=0.0)
    box(name + "_vas2", (w * 0.9, 1.4, 0.5), (x, y - 1.0, z + h * 0.72), 'iron', bevel=0.0)


def window(name, x, y, z, w=3.0, h=4.0, shutters=None, frame='timber', rot_z=0.0):
    """Ablak a -Y homlokzaton (shutters: anyagnév vagy None)."""
    box(name + "_k", (w + 1.0, 0.8, h + 1.0), (x, y - 0.2, z - 0.5), frame, bevel=0.15)
    box(name, (w, 0.8, h), (x, y - 0.5, z), 'window', bevel=0.0)
    if shutters:
        box(name + "_sl", (w * 0.5, 0.6, h), (x - w * 0.78, y - 0.7, z), shutters, bevel=0.1)
        box(name + "_sr", (w * 0.5, 0.6, h), (x + w * 0.78, y - 0.7, z), shutters, bevel=0.1)


def side_window(name, x, y, z, w=3.0, h=4.0, side=1, frame='timber'):
    """Ablak az oldalfalon (x = a fal síkja, side = +1 kelet / -1 nyugat)."""
    box(name + "_k", (0.8, w + 1.0, h + 1.0), (x + 0.2 * side, y, z - 0.5), frame, bevel=0.15)
    box(name, (0.8, w, h), (x + 0.5 * side, y, z), 'window', bevel=0.0)


def barrel(name, loc, r=2.0, h=4.2):
    cyl(name, r, h, loc, 'wood', verts=10, r2=r)
    sphere(name + "_has", r * 1.08, (loc[0], loc[1], loc[2] + h / 2), 'wood', scale=(1, 1, h / (2.2 * r)),
           seg=10, rings=6)
    for k, zz in enumerate((0.18, 0.82)):
        cyl(f"{name}_ab{k}", r * 1.1, 0.5, (loc[0], loc[1], loc[2] + h * zz), 'iron', verts=10)


def crate(name, loc, s=3.6, material='wood_l', rot=0.0):
    ob = box(name, (s, s, s * 0.85), loc, material, bevel=0.3)
    ob.rotation_euler = (0, 0, rot)
    return ob


def sack(name, loc, r=1.6):
    sphere(name, r, (loc[0], loc[1], loc[2] + r * 0.85), 'canvas', scale=(1, 0.9, 1.1), seg=8, rings=6)


def fence(name, pts, h=4.5, post_every=6.0, material='wood'):
    """Karókerítés a pontsoron (zárt ha az első = utolsó)."""
    n = 0
    for (a, b) in zip(pts[:-1], pts[1:]):
        a, b = Vector(a), Vector(b)
        L = (b - a).length
        k = max(1, int(L // post_every))
        for i in range(k + 1):
            p = a + (b - a) * (i / k)
            box(f"{name}_c{n}", (1.0, 1.0, h), (p.x, p.y, 0), material, bevel=0.2)
            n += 1
        mid = (a + b) / 2
        ang = math.atan2(b.y - a.y, b.x - a.x)
        for zz in (h * 0.35, h * 0.8):
            ob = box(f"{name}_l{n}", (L, 0.6, 0.7), (mid.x, mid.y, zz), material, bevel=0.1)
            ob.rotation_euler = (0, 0, ang)
            n += 1


def half_timber_front(name, x0, x1, y, z0, z1, n=4, braces=True):
    """Favázas homlokzat (-Y oldal): oszlopok, gerendák, keresztmerevítők."""
    for i in range(n + 1):
        x = x0 + (x1 - x0) * i / n
        box(f"{name}_o{i}", (1.3, 0.8, z1 - z0), (x, y - 0.3, z0), 'timber', bevel=0.15)
    for k, z in enumerate((z0, (z0 + z1) / 2, z1 - 1.2)):
        box(f"{name}_g{k}", (x1 - x0 + 1.3, 0.9, 1.2), ((x0 + x1) / 2, y - 0.35, z), 'timber', bevel=0.15)
    if braces:
        for i in range(n):
            if i % 2:
                continue
            xa = x0 + (x1 - x0) * i / n
            xb = x0 + (x1 - x0) * (i + 1) / n
            zm = (z0 + z1) / 2
            L = math.hypot(xb - xa, zm - z0)
            ob = box(f"{name}_m{i}", (L, 0.7, 1.0), ((xa + xb) / 2, y - 0.3, (z0 + zm) / 2 - 0.5), 'timber',
                     bevel=0.1)
            ob.rotation_euler = (0, math.atan2(zm - z0, xb - xa) * -1, 0)


def half_timber_side(name, x, y0, y1, z0, z1, n=4, side=1):
    for i in range(n + 1):
        y = y0 + (y1 - y0) * i / n
        box(f"{name}_o{i}", (0.8, 1.3, z1 - z0), (x + 0.3 * side, y, z0), 'timber', bevel=0.15)
    for k, z in enumerate((z0, (z0 + z1) / 2, z1 - 1.2)):
        box(f"{name}_g{k}", (0.9, y1 - y0 + 1.3, 1.2), (x + 0.35 * side, (y0 + y1) / 2, z), 'timber', bevel=0.15)


# ---------------------------------------------------------------- korszak 0

def house0():
    # oromzatos, emeletes favázas polgárház: kőből a földszint, az emelet
    # előreugrik, az oromzat a néző felé fordul
    w, d = 30.0, 36.0
    y0 = 3.0
    yf = y0 - d / 2
    g1, g2 = 9.5, 9.0          # földszint, emelet
    box("labazat", (w + 2, d + 2, 1.5), (0, y0, 0), 'stone_d', bevel=0.5)
    box("fsz", (w, d, g1), (0, y0, 1.5), 'stone', bevel=0.4)
    z1 = 1.5 + g1
    box("gerendasor", (w + 2.2, d + 2.2, 1.2), (0, y0 - 0.6, z1 - 0.2), 'timber', bevel=0.2)
    box("em", (w + 2, d + 1.2, g2), (0, y0 - 0.6, z1), 'plaster', bevel=0.3)
    yfe = yf - 1.2
    half_timber_front("fh", -w / 2 - 1, w / 2 + 1, yfe, z1, z1 + g2, n=4)
    half_timber_side("fo", w / 2 + 1, yfe, y0 + d / 2, z1, z1 + g2, n=4, side=1)
    z2 = z1 + g2
    rh = 15.0
    gable_roof("teto", w + 2, d + 1.2, rh, (0, y0 - 0.6, z2), 'roof', over=1.8, thick=1.0, ridge_x=False)
    tri_prism("orom", w + 2, rh, 1.0, (0, yfe + 0.5, z2), 'plaster', axis='y')
    # az oromzat favázának gerendái
    box("orom_o", (1.2, 0.8, rh - 1), (0, yfe - 0.2, z2), 'timber', bevel=0.1)
    box("orom_g", (w * 0.62, 0.8, 1.0), (0, yfe - 0.2, z2 + rh * 0.42), 'timber', bevel=0.1)
    window("orom_ab", 0, yfe - 0.2, z2 + 1.6, 2.6, 3.4, frame='timber')
    box("kemeny", (4.0, 4.0, 18), (w * 0.3, y0 + d * 0.2, z2 - 2), 'stone', bevel=0.4)
    box("kemeny_t", (5.0, 5.0, 1.2), (w * 0.3, y0 + d * 0.2, z2 + 16), 'stone_d', bevel=0.3)
    arch_door("ajto", -w * 0.2, yf, 1.5, 5.0, 6.5)
    window("ab1", w * 0.22, yf, 4.0, 3.6, 3.8, shutters='team', frame='stone_d')
    window("ab2", -w * 0.24, yfe, z1 + 2.5, 3.2, 3.8, shutters='team')
    window("ab3", w * 0.24, yfe, z1 + 2.5, 3.2, 3.8, shutters='team')
    side_window("abo", w / 2, y0 + 4, 4.0, 3.4, 3.6, side=1, frame='stone_d')
    side_window("abo2", w / 2 + 1, y0 + 4, z1 + 2.5, 3.4, 3.6, side=1)
    # kellékek: farakás a fal mellett, hordó
    for i in range(3):
        for j in range(2 - i // 2):
            cyl(f"hasab{i}{j}", 1.2, 10, (-w / 2 - 2.6 - j * 0.3, yf + 5 + i * 2.3, 1.2 + j * 2.2), 'wood',
                verts=8, rot=(math.pi / 2, 0, 0), base=False)
    barrel("hordo", (w / 2 + 3.2, yf - 1.5, 0))


def barracks0():
    w, d = 58.0, 42.0
    y0 = 6.0
    wall1, wall2 = 10.0, 11.0
    yf = y0 - d / 2
    box("labazat", (w + 2, d + 2, 2.0), (0, y0, 0), 'stone_d', bevel=0.5)
    box("also", (w, d, wall1), (0, y0, 2.0), 'stone', bevel=0.4)
    box("felso", (w + 1.6, d + 1.6, wall2), (0, y0, 2 + wall1), 'plaster', bevel=0.3)
    half_timber_front("fh", -w / 2 - 0.8, w / 2 + 0.8, yf - 0.8, 2 + wall1, 2 + wall1 + wall2, n=8)
    half_timber_side("fo", w / 2 + 0.8, yf - 0.8, yf + d + 0.8, 2 + wall1, 2 + wall1 + wall2, n=5)
    rz = 2 + wall1 + wall2
    gable_roof("teto", w + 1.6, d + 1.6, 14.0, (0, y0, rz), 'shingle', over=2.6, ridge_x=True)
    tri_prism("orom_k", d + 1.6, 14.0, 1.0, (w / 2 + 0.3, y0, rz), 'plaster', axis='x')
    tri_prism("orom_ny", d + 1.6, 14.0, 1.0, (-w / 2 - 0.3, y0, rz), 'plaster', axis='x')
    arch_door("kapu", 0, yf, 2.0, 9.0, 10.0)
    for i, x in enumerate((-w * 0.36, -w * 0.2, w * 0.2, w * 0.36)):
        window(f"lo{i}", x, yf - 0.8, 2 + wall1 + 3, 3.0, 4.0)
        box(f"res{i}", (1.4, 0.8, 3.2), (x, yf - 0.4, 5.0), 'window', bevel=0.0)
    banner("zaszlo1", (-9.5, yf - 0.4, 3.0 + wall1), 5.5, 12.0)
    banner("zaszlo2", (9.5, yf - 0.4, 3.0 + wall1), 5.5, 12.0)
    flag("lobogo", (w / 2 - 4, y0 + 2, rz + 12.0), L=12, H=7, pole_h=14)
    # gyakorlótér előtte: fegyverállvány, bábu, céltábla
    yard = yf - 10
    box("allvany", (12, 1.2, 1.2), (-w * 0.3, yard, 5.5), 'wood', bevel=0.2)
    for i in range(2):
        box(f"allv_l{i}", (1.2, 1.2, 7), (-w * 0.3 - 5.5 + i * 11, yard, 0), 'wood', bevel=0.2)
    for i in range(5):
        cyl(f"landzsa{i}", 0.35, 15, (-w * 0.3 - 4.4 + i * 2.2, yard + 0.8, 0), 'wood', verts=6)
        cone(f"lhegy{i}", 0.7, 2.2, (-w * 0.3 - 4.4 + i * 2.2, yard + 0.8, 15), 'steel', verts=6)
    # szalmabábu
    cyl("baba", 0.6, 11, (w * 0.3, yard, 0), 'wood', verts=6)
    box("baba_kar", (8, 0.8, 0.8), (w * 0.3, yard, 8), 'wood', bevel=0.1)
    sphere("baba_test", 2.4, (w * 0.3, yard, 7.2), 'hay', scale=(1, 0.8, 1.3), seg=8, rings=6)
    sphere("baba_fej", 1.6, (w * 0.3, yard, 11.4), 'canvas', seg=8, rings=6)
    # céltábla
    ob = cyl("cel", 4.0, 1.4, (w * 0.46, yard + 4, 5.5), 'hay', verts=16, rot=(math.radians(80), 0, 0),
             base=False)
    cyl("cel_k", 2.6, 1.5, (w * 0.46, yard + 3.9, 5.5), 'canvas', verts=16, rot=(math.radians(80), 0, 0),
        base=False)
    cyl("cel_p", 1.2, 1.6, (w * 0.46, yard + 3.8, 5.5), 'team', verts=12, rot=(math.radians(80), 0, 0),
        base=False)
    for s in (-1, 1):
        ob = box(f"cel_l{s}", (0.8, 0.8, 9), (w * 0.46 + s * 2.5, yard + 5.5, 0), 'wood', bevel=0.1)
        ob.rotation_euler = (math.radians(-12), 0, 0)
    fence("kerites", [(-w / 2 - 2, yard - 6), (w / 2 + 2, yard - 6)], h=3.5, post_every=7)


def farm0():
    # a tábla (a telek nagy része) — a játékban alacsony, lapos épület
    fw, fd = 50.0, D(56) * 0.92
    box("tabla", (fw, fd, 1.0), (0, 0, 0), 'dirt', bevel=0.3)
    # gabonasorok
    n = 9
    for i in range(n):
        x = -fw / 2 + 4 + (fw - 8) * i / (n - 1)
        box(f"sor{i}", (3.6, fd - 18, 2.0), (x, 4, 0.8), 'field', bevel=0.6)
    # kis csűr hátul balra
    bx, by = -fw / 2 + 10, fd / 2 - 8
    box("csur", (16, 11, 8), (bx, by, 0.8), 'wood', bevel=0.3)
    gable_roof("csur_t", 16, 11, 7, (bx, by, 8.8), 'thatch', over=1.8, ridge_x=True)
    tri_prism("csur_o1", 11, 7, 0.8, (bx + 7.6, by, 8.8), 'wood', axis='x')
    tri_prism("csur_o2", 11, 7, 0.8, (bx - 7.6, by, 8.8), 'wood', axis='x')
    box("csur_a", (5, 0.8, 6), (bx + 2, by - 5.8, 0.8), 'door', bevel=0.1)
    # szénakazal
    sphere("kazal", 5.0, (fw / 2 - 8, fd / 2 - 8, 2.5), 'hay', scale=(1, 1, 0.9), seg=12, rings=8)
    # madárijesztő (csapatszínű ing)
    sx, sy = 6, -2
    cyl("mi_rud", 0.45, 12, (sx, sy, 0), 'wood', verts=6)
    box("mi_kar", (8, 0.6, 0.6), (sx, sy, 9.2), 'wood', bevel=0.1)
    box("mi_ing", (6, 1.8, 5), (sx, sy, 5.2), 'team', bevel=0.5)
    sphere("mi_fej", 1.4, (sx, sy, 11.5), 'canvas', seg=8, rings=6)
    cone("mi_kalap", 2.2, 1.8, (sx, sy, 12.2), 'hay', verts=10)
    # karókerítés az elején
    yf = -fd / 2
    fence("kerites", [(-fw / 2, yf), (fw / 2, yf), (fw / 2, fd / 2 - 2)], h=3.4, post_every=6.5)


def tower0():
    r = 12.0
    box("talp", (r * 2 + 4, r * 2 + 4, 2.5), (0, 3, 0), 'stone_d', bevel=0.6)
    cyl("torzs", r, 44, (0, 3, 2.5), 'stone', verts=20, r2=r * 0.92)
    zt = 46.5
    # fa védőfolyosó (hurdíció)
    cyl("folyoso", r + 2.6, 7.5, (0, 3, zt), 'wood', verts=20)
    for i in range(10):
        a = 2 * math.pi * i / 10
        box(f"konzol{i}", (1.2, 1.2, 3.0), (math.cos(a) * (r + 1.4), 3 + math.sin(a) * (r + 1.4), zt - 3),
            'timber', bevel=0.2)
    # lőrések a fa folyosón
    for i in range(7):
        a = math.pi * (1.15 + 0.7 * i / 6)
        ob = box(f"fl{i}", (1.2, 0.6, 2.6), (math.cos(a) * (r + 2.7), 3 + math.sin(a) * (r + 2.7), zt + 2.2),
                 'window', bevel=0.0)
        ob.rotation_euler = (0, 0, a + math.pi / 2)
    cone("sisak", r + 3.2, 30, (0, 3, zt + 7.5), 'roof', verts=24, smooth=False)
    flag("lobogo", (0, 3, zt + 35), L=12, H=7, pole_h=9)
    # lőrések és ajtó
    for k, z in enumerate((14, 26, 36)):
        box(f"lores{k}", (1.2, 1.0, 4.5), (0 + (k - 1) * 3.5, 3 - r * 0.93, z), 'window', bevel=0.0)
    arch_door("ajto", 0, 3 - r * 0.98 + 0.3, 2.5, 4.4, 7.5)
    banner("zaszlo", (5.5, 3 - r * 0.9 + 0.5, 20.0), 4.5, 10.0)


def market0():
    w, d = 64.0, D(56) * 0.9
    box("ter", (w, d, 0.8), (0, 0, 0), 'cobble', bevel=0.3)
    # raktár hátul
    box("raktar", (30, 14, 12), (-12, d / 2 - 9, 0.8), 'plaster', bevel=0.3)
    half_timber_front("rh", -27, 3, d / 2 - 16, 0.8, 12.8, n=4, braces=True)
    gable_roof("raktar_t", 30, 14, 9, (-12, d / 2 - 9, 12.8), 'roof', over=2.0)
    tri_prism("r_o1", 14, 9, 0.8, (2.6, d / 2 - 9, 12.8), 'plaster', axis='x')
    arch_door("r_ajto", -2, d / 2 - 16, 0.8, 4.0, 6.5)
    # kút
    cyl("kut", 4.2, 3.5, (w * 0.3, d * 0.22, 0.8), 'stone', verts=14)
    cyl("kut_v", 3.2, 0.3, (w * 0.3, d * 0.22, 4.1), 'window', verts=14)
    for s in (-1, 1):
        box(f"kut_o{s}", (0.8, 0.8, 8), (w * 0.3 + s * 3.8, d * 0.22, 4.0), 'wood', bevel=0.1)
    gable_roof("kut_t", 9, 5, 3, (w * 0.3, d * 0.22, 12.0), 'shingle', over=0.6, thick=0.6)
    # három árusbódé csíkos ponyvával
    stalls = [(-20, -d * 0.18), (4, -d * 0.26), (26, -d * 0.1)]
    goods = ['#c0392b', '#e0a030', '#6a8a30', '#8a4a9a']
    random.seed(5)
    for si, (sx, sy) in enumerate(stalls):
        sw, sd_ = 15.0, 10.0
        for px in (-1, 1):
            for py in (-1, 1):
                box(f"b{si}_o{px}{py}", (0.9, 0.9, 10 if py > 0 else 8), (sx + px * sw / 2, sy + py * sd_ / 2, 0.8),
                    'wood', bevel=0.1)
        # pult
        box(f"b{si}_pult", (sw - 1, 4, 4.5), (sx, sy - sd_ / 2 + 2.5, 0.8), 'wood_l', bevel=0.3)
        # áru a pulton
        for g in range(5):
            gx = sx - sw / 2 + 2.5 + g * (sw - 5) / 4
            col = goods[(g + si) % 4]
            gm = mat(f"aru{col}", 'plain', col, rough=0.6)
            sphere(f"b{si}_a{g}", 1.2, (gx, sy - sd_ / 2 + 2.5, 6.4), gm, seg=8, rings=6)
        # csíkos ponyva: a csíkok felváltva csapatszínűek
        n = 6
        for k in range(n):
            x0 = sx - sw / 2 - 1 + (sw + 2) * k / n
            x1 = sx - sw / 2 - 1 + (sw + 2) * (k + 1) / n
            m_ = 'team' if k % 2 == 0 else 'canvas'
            v = [(x0, sy - sd_ / 2 - 2.5, 7.4), (x1, sy - sd_ / 2 - 2.5, 7.4), (x1, sy + sd_ / 2, 11.4),
                 (x0, sy + sd_ / 2, 11.4)]
            ob = mesh(f"b{si}_p{k}", v, [(0, 1, 2, 3)], (0, 0, 0.8), m_)
            ob.modifiers.new("V", 'SOLIDIFY').thickness = 0.4
        # ládák, zsákok, hordók mellette
        crate(f"b{si}_l", (sx + sw / 2 + 2.5, sy - 2, 0.8), 3.4, rot=random.random())
        sack(f"b{si}_z", (sx - sw / 2 - 2.2, sy - 3, 0.8))
    barrel("hordo1", (-w / 2 + 4, d / 2 - 22, 0.8))
    barrel("hordo2", (-w / 2 + 8, d / 2 - 21, 0.8))


def hq0():
    W, Dd = 92.0, D(104) * 0.84
    y0 = 4.0
    x0, x1 = -W / 2, W / 2
    yb0, yb1 = y0 - Dd / 2, y0 + Dd / 2
    wt, wh = 5.0, 17.0            # fal vastagság, magasság
    # udvar
    box("udvar", (W - 2, Dd - 2, 0.6), (0, y0, 0), 'dirt', bevel=0.2)["talaj"] = True
    # várfalak
    box("fal_d", (W, wt, wh), (0, yb0 + wt / 2, 0), 'stone', bevel=0.5)
    box("fal_e", (W, wt, wh), (0, yb1 - wt / 2, 0), 'stone', bevel=0.5)
    box("fal_ny", (wt, Dd, wh), (x0 + wt / 2, y0, 0), 'stone', bevel=0.5)
    box("fal_k", (wt, Dd, wh), (x1 - wt / 2, y0, 0), 'stone', bevel=0.5)
    merlons("partazat", x0, x1, yb0, yb1, wh, size=3.0, gap=2.6, h=3.0, thick=2.0)
    # lakótorony (donjon)
    kw, kd, kh = 40.0, 36.0, 44.0
    ky = y0 + 8
    box("donjon", (kw, kd, kh), (0, ky, 0), 'stone', bevel=0.6)
    box("donjon_p", (kw + 3, kd + 3, 3.0), (0, ky, kh - 1), 'stone_d', bevel=0.5)
    merlons("dp", -kw / 2 - 1.5, kw / 2 + 1.5, ky - kd / 2 - 1.5, ky + kd / 2 + 1.5, kh + 2, size=3.2, gap=2.8,
            h=3.4, thick=2.2)
    hip_roof("donjon_t", kw - 6, kd - 6, 14.0, (0, ky, kh + 1.6), 'roof_d', over=0.0)
    # sarok-őrtorony a donjonon
    cyl("tornyocska", 5.0, 14, (kw / 2 - 5, ky + kd / 2 - 5, kh + 1), 'stone', verts=14)
    cone("tornyocska_t", 6.4, 10, (kw / 2 - 5, ky + kd / 2 - 5, kh + 15), 'roof', verts=14)
    # zászlórúd lobogó nélkül: a nemzeti zászlót a játék lengeti élőben
    px, py, pz = -kw / 2 + 5, ky + kd / 2 - 5, kh + 14.6
    cyl("lobogo_rud", 0.6, 18, (px, py, pz), 'wood', verts=8)
    sphere("lobogo_gomb", 0.95, (px, py, pz + 18.5), 'gold', seg=8, rings=6)
    empty("lobogo_pont", (px + 0.5, py, pz + 17.6))["zaszlo"] = True
    yk = ky - kd / 2
    for i, x in enumerate((-12, 0, 12)):
        window(f"dab{i}", x, yk, 30, 3.0, 5.0, frame='stone_d')
        box(f"dab{i}_iv", (3.0, 0.8, 1.2), (x, yk - 0.5, 35), 'window', bevel=0.0)
    banner("d_zaszlo1", (-12, yk, 11), 7.0, 16.0)
    banner("d_zaszlo2", (12, yk, 11), 7.0, 16.0)
    arch_door("d_ajto", 0, yk, 0.6, 6.0, 9.0)
    # sarokbástyák
    for i, (cx, cy) in enumerate(((x0, yb0), (x1, yb0), (x0, yb1), (x1, yb1))):
        cyl(f"bastya{i}", 9.0, 27, (cx, cy, 0), 'stone', verts=18, r2=8.4)
        cyl(f"bastya{i}_p", 9.4, 2.0, (cx, cy, 27), 'stone_d', verts=18)
        cone(f"bastya{i}_t", 10.6, 14, (cx, cy, 29), 'roof', verts=18)
        box(f"bastya{i}_l", (1.1, 1.0, 4.0), (cx, cy - 8.6, 15), 'window', bevel=0.0)
    # kaputorony elöl
    gw = 22.0
    box("kapu", (gw, 12, 25), (0, yb0 + 3, 0), 'stone', bevel=0.5)
    merlons("kp", -gw / 2, gw / 2, yb0 - 3, yb0 + 9, 25, size=2.8, gap=2.4, h=3.0, thick=2.0)
    arch_door("kapu_a", 0, yb0 - 3, 0.0, 8.0, 10.0, material='window')
    # csapórács
    for i in range(4):
        box(f"racs{i}", (0.6, 0.6, 12), (-3 + i * 2, yb0 - 3.6, 0), 'iron', bevel=0.0)
    for i in range(3):
        box(f"racsv{i}", (8, 0.6, 0.6), (0, yb0 - 3.6, 3 + i * 3.5), 'iron', bevel=0.0)
    box("kapu_cimer", (6, 0.8, 7), (0, yb0 - 3.4, 15), 'team', bevel=0.3)
    box("kapu_cimer_k", (7.4, 0.6, 8.4), (0, yb0 - 3.0, 14.3), 'accent', bevel=0.3)
    for i, x in enumerate((-7, 7)):
        box(f"kapu_l{i}", (1.1, 1.0, 4.0), (x, yb0 - 3.3, 16), 'window', bevel=0.0)


# ---------------------------------------------------------------- korszak 3

def barracks3():
    w, d = 60.0, 34.0
    y0 = 8.0
    yf = y0 - d / 2
    box("alap", (w + 2, d + 2, 1.6), (0, y0, 0), 'concrete', bevel=0.3)
    box("test", (w, d, 24), (0, y0, 1.6), 'brick', bevel=0.3)
    box("parkany", (w + 1.6, d + 1.6, 2.0), (0, y0, 25.6), 'concrete', bevel=0.3)
    box("teto", (w - 1, d - 1, 0.8), (0, y0, 25.8), 'tarpaper', bevel=0.1)
    box("parkany_i", (w - 1.5, d - 1.5, 2.2), (0, y0, 25.7), 'tarpaper', bevel=0.0)
    box("parkany_f", (w + 1.6, 1.6, 1.4), (0, yf - 0.8, 27.6), 'concrete', bevel=0.2)
    box("parkany_h", (w + 1.6, 1.6, 1.4), (0, yf + d + 0.8, 27.6), 'concrete', bevel=0.2)
    box("parkany_k", (1.6, d + 1.6, 1.4), (w / 2 + 0.8, y0, 27.6), 'concrete', bevel=0.2)
    box("parkany_n", (1.6, d + 1.6, 1.4), (-w / 2 - 0.8, y0, 27.6), 'concrete', bevel=0.2)
    box("parkany_ff", (w + 1.6, 1.6, 1.4), (0, yf - 0.8, 27.6), 'concrete', bevel=0.2)
    # ablaksorok
    for row, z in enumerate((5.5, 15.5)):
        for i in range(8):
            x = -w / 2 + 5 + i * (w - 10) / 7
            if row == 0 and abs(x) < 6:
                continue
            box(f"ab{row}_{i}_k", (4.2, 0.8, 6.0), (x, yf - 0.2, z - 0.6), 'concrete', bevel=0.1)
            box(f"ab{row}_{i}", (3.4, 0.8, 5.0), (x, yf - 0.5, z), 'window', bevel=0.0)
            box(f"ab{row}_{i}_o", (0.4, 0.9, 5.0), (x, yf - 0.6, z), 'concrete', bevel=0.0)
        for i in range(3):
            y = yf + 6 + i * (d - 12) / 2
            side_window(f"abk{row}_{i}", w / 2, y, z, 3.4, 5.0, side=1, frame='concrete')
    # bejárat, lépcső, előtető
    box("ajto", (6.0, 1.0, 8.5), (0, yf - 0.4, 1.6), 'door', bevel=0.1)
    box("eloteto", (11, 5, 0.8), (0, yf - 2.5, 11.0), 'concrete', bevel=0.2)
    for i in range(3):
        box(f"lepcso{i}", (10 - i * 1.6, 3.2 - i * 1.0, 0.8), (0, yf - 2.6 + i * 0.5, i * 0.8), 'concrete',
            bevel=0.1)
    box("tabla", (12, 0.6, 2.4), (0, yf - 0.6, 12.4), 'team', bevel=0.1)
    # zászlórúd elöl
    flag("lobogo", (-w / 2 + 2, yf - 9, 0), L=13, H=8, pole_h=34, pole_mat='steel_d', amp=1.2)
    cyl("rud_talp", 2.0, 1.2, (-w / 2 + 2, yf - 9, 0), 'concrete', verts=10)
    # homokzsák-fészek jobbra elöl
    cx, cy = w / 2 - 4, yf - 12
    for ring, (rr, z) in enumerate(((7.0, 0), (6.6, 1.9), (6.2, 3.8))):
        n = 11
        for i in range(n):
            a = math.pi * (0.1 + 1.25 * i / (n - 1)) + math.pi * 0.6
            ob = box(f"hz{ring}_{i}", (3.6, 2.2, 2.0), (cx + math.cos(a) * rr, cy + math.sin(a) * rr, z), 'sandbag',
                     bevel=0.7)
            ob.rotation_euler = (0, 0, a + math.pi / 2 + (0.08 if (i + ring) % 2 else -0.05))
    # hordók, láda
    barrel("hordo1", (-w / 2 + 10, yf - 5, 0), r=1.9)
    barrel("hordo2", (-w / 2 + 14, yf - 4, 0), r=1.9)
    crate("lada", (w / 2 - 16, yf - 5, 0), 4.0, material='olive_d', rot=0.3)


BUILDERS = {
    ("hq", 0): hq0, ("house", 0): house0, ("barracks", 0): barracks0, ("farm", 0): farm0,
    ("tower", 0): tower0, ("market", 0): market0, ("barracks", 3): barracks3,
}


# ---------------------------------------------------------------- építkezés

def make_construction(frac=0.45, seed=3, flat=False):
    """A kész modellből félkész építkezést csinál: a frac-nyi magasság fölött
    minden lekerül, köré állvány, létra, kő- és gerendarakás kerül."""
    random.seed(seed)
    bpy.context.view_layer.update()
    obs = [o for o in bpy.context.scene.objects if o.type == 'MESH' and not o.get("catcher")]
    zmax = 0.0
    xs, ys = [], []
    for o in obs:
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            zmax = max(zmax, p.z)
            xs.append(p.x); ys.append(p.y)
    cut = 3.0 if flat else zmax * frac
    import bmesh
    if flat:      # lapos telek (tábla, piactér): a vetés és a bódék még hiányoznak
        for o in list(obs):
            if o.name.startswith(("sor", "mi_")):
                obs.remove(o)
                bpy.data.objects.remove(o, do_unlink=True)
    for o in obs:
        zs = [(o.matrix_world @ Vector(c)).z for c in o.bound_box]
        if min(zs) >= cut - 0.01:
            bpy.data.objects.remove(o, do_unlink=True)
        elif max(zs) > cut:
            # síkkal elvágjuk (a helyi térben), a felső részt eldobjuk, a
            # vágást lefedjük
            inv = o.matrix_world.inverted()
            co = inv @ Vector((0, 0, cut))
            no = (inv.to_3x3() @ Vector((0, 0, 1))).normalized()
            bm = bmesh.new()
            bm.from_mesh(o.data)
            res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-4,
                                         plane_co=co, plane_no=no, clear_outer=True)
            edges = [e for e in res['geom_cut'] if isinstance(e, bmesh.types.BMEdge)]
            if edges:
                try:
                    fr = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
                    # a vágás lapja deszkapadló (nem a fal anyaga — az a
                    # felülről érő napfényben kiégne)
                    if len(o.data.materials) < 2:
                        o.data.materials.append(M('deck'))
                    for f in fr['faces']:
                        f.material_index = 1
                    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
                except Exception:
                    pass
            bm.to_mesh(o.data)
            bm.free()
            o.data.update()
    # az épület alapterülete (a megmaradt rész)
    bpy.context.view_layer.update()
    rest = [o for o in bpy.context.scene.objects if o.type == 'MESH' and not o.get("catcher")]
    bx0 = min((o.matrix_world @ Vector(c)).x for o in rest for c in o.bound_box)
    bx1 = max((o.matrix_world @ Vector(c)).x for o in rest for c in o.bound_box)
    by0 = min((o.matrix_world @ Vector(c)).y for o in rest for c in o.bound_box)
    by1 = max((o.matrix_world @ Vector(c)).y for o in rest for c in o.bound_box)
    # állvány a homlokzat és a két oldal előtt
    top = cut + 6.0
    m = 2.5
    xa, xb, ya, yb = bx0 - m, bx1 + m, by0 - m, by1 + m
    posts = []
    yh = ya + (yb - ya) * 0.6       # az oldalsó állvány csak a telek elejét fedi
    nx = max(2, int((xb - xa) // 14))
    ny = max(2, int((yb - ya) // 14))
    for i in range(nx + 1):
        posts.append((xa + (xb - xa) * i / nx, ya))
    for j in range(1, ny + 1):
        posts.append((xa, ya + (yh - ya) * j / ny))
        posts.append((xb, ya + (yh - ya) * j / ny))
    if flat:
        posts = []
    for k, (px, py) in enumerate(posts):
        cyl(f"all_o{k}", 0.6, top, (px, py, 0), 'wood_l', verts=6)
    lv = [] if flat else [cut * 0.5, cut]
    for li, z in enumerate(lv + ([] if flat else [top - 0.6])):
        box(f"all_hf{li}", (xb - xa, 0.8, 0.8), ((xa + xb) / 2, ya, z), 'wood_l', bevel=0.1)
        box(f"all_hk{li}", (0.8, yh - ya, 0.8), (xb, (ya + yh) / 2, z), 'wood_l', bevel=0.1)
        box(f"all_hn{li}", (0.8, yh - ya, 0.8), (xa, (ya + yh) / 2, z), 'wood_l', bevel=0.1)
    for li, z in enumerate(lv):
        box(f"all_d{li}", (xb - xa, 3.2, 0.5), ((xa + xb) / 2, ya + 1.4, z + 0.8), 'wood', bevel=0.1)
    # átlós merevítő
    L = math.hypot((xb - xa) / nx, cut * 0.5)
    for i in range(0 if flat else nx):
        ob = box(f"all_m{i}", (L, 0.5, 0.5), (xa + (xb - xa) * (i + 0.5) / nx, ya - 0.5, cut * 0.25), 'wood_l',
                 bevel=0.0)
        ob.rotation_euler = (0, -math.atan2(cut * 0.5, (xb - xa) / nx) * (1 if i % 2 else -1), 0)
    # létra
    lx = xa + (xb - xa) * 0.3
    for s in (() if flat else (-1, 1)):
        ob = box(f"letra{s}", (0.5, 0.5, cut + 3), (lx + s * 1.6, ya - 3.0, 0), 'wood_l', bevel=0.0)
        ob.rotation_euler = (math.radians(-12), 0, 0)
    for i in range(0 if flat else int(cut // 2.5)):
        box(f"letra_f{i}", (3.4, 0.4, 0.4), (lx, ya - 3.0 + (i * 2.5) * math.tan(math.radians(12)), i * 2.5 + 1.5),
            'wood_l', bevel=0.0)
    # kőrakás és gerendarakás elöl
    for i in range(6):
        box(f"ko{i}", (4.0, 3.0, 2.4), (xa + 4 + (i % 3) * 4.4, ya - 8 + (i // 3) * 3.4, (i // 3) * 0.0),
            'stone', bevel=0.4)
    for i in range(3):
        box(f"ko_f{i}", (4.0, 3.0, 2.4), (xa + 6 + (i % 2) * 4.4, ya - 7 + (i // 2) * 3.4, 2.4), 'stone', bevel=0.4)
    for i in range(4):
        cyl(f"gerenda{i}", 1.0, 20, (xb - 13, ya - 7 + (i % 2) * 2.1, 1.0 + (i // 2) * 1.8), 'wood',
            verts=8, rot=(0, math.pi / 2, 0), base=False)
    # felásott föld a telken
    ob = sphere("fold", 1.0, ((xa + xb) / 2, ya + 2, -0.4), 'dirt',
                scale=((xb - xa) * 0.56, 9.0, 0.9), seg=16, rings=6)
    ob["talaj"] = True
    return cut
