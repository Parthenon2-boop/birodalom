# -*- coding: utf-8 -*-
# BIRODALOM — HAJÓK ÉS REPÜLŐGÉPEK (eljárással, bpy)
#
# A hajók orra -Y felé néz (mint minden egységé), a vízvonal a z = 0 sík:
# ami alatta van, azt a render a víz-kitakaró (water_holdout) eltünteti —
# így a süllyedő hajó valóban elmerül.
#
# Korszakok: 0 = kogge/karakk, 1 = fregatt/galleon (vitorla), 2 = gőzös
# (kémény + vitorla, lapátkerék, páncélos), 3 = acélhajó (vitorla nélkül).

import math, random
import bpy
from mathutils import Vector
from bir_common import *
from bir_units import R, dir_rot, fx_smoke, Machine

SHIP_ANIM = {"idle": 1, "walk": 2, "attack": 2, "death": 4}
PLANE_ANIM = {"idle": 1, "walk": 2, "attack": 2, "death": 4}


def hull(name, L, W, fb, parent, mat='hull', deck='deck', draft=3.0, sheer=0.35, stern_w=0.75, n=16,
         bow_len=0.38, deck_drop=0.6):
    """Hajótest keresztmetszetekből. L hossz (Y), W szélesség, fb szabad
    oldalmagasság. Az orr a -Y végen."""
    secs = []
    for i in range(n + 1):
        t = i / n                      # 0 = orr, 1 = tat
        if t < bow_len:
            k = t / bow_len
            w = W / 2 * max(0.04, math.sin(k * math.pi / 2) ** 0.8)
        elif t > 0.82:
            k = (t - 0.82) / 0.18
            w = W / 2 * (1 - (1 - stern_w) * k)
        else:
            w = W / 2
        y = -L / 2 + L * t
        zd = fb * (1 + sheer * (abs(2 * t - 1) ** 2) * 2.2)
        ring = [(-w, zd), (-0.96 * w, 0.0), (-0.62 * w, -draft * 0.7), (0, -draft), (0.62 * w, -draft * 0.7),
                (0.96 * w, 0.0), (w, zd)]
        secs.append((y, ring))
    verts, faces = [], []
    m = 7
    for (y, ring) in secs:
        for (x, z) in ring:
            verts.append((x, y, z))
    for i in range(n):
        for j in range(m - 1):
            a = i * m + j
            faces.append((a, a + 1, a + m + 1, a + m))
    faces.append(tuple((n * m + j) for j in range(m)))          # tükör (tat)
    ob = mesh(name, verts, faces, (0, 0, 0), mat, parent=parent, smooth=False)
    # fedélzet: a két felső él között, kicsit a perem alatt
    dv, df = [], []
    for (y, ring) in secs:
        dv.append((ring[0][0] * 0.92, y, ring[0][1] - deck_drop))
        dv.append((ring[-1][0] * 0.92, y, ring[-1][1] - deck_drop))
    for i in range(n):
        a = i * 2
        df.append((a, a + 1, a + 3, a + 2))
    mesh(name + "_fedelzet", dv, df, (0, 0, 0), deck, parent=parent)
    return ob


def sail_square(name, w, h, loc, parent, material='sail', bulge=1.2):
    nx, nz = 6, 4
    v, f = [], []
    for j in range(nz + 1):
        for i in range(nx + 1):
            u, s = i / nx, j / nz
            x = -w / 2 + w * u
            z = -h * s
            y = -bulge * math.sin(math.pi * u) * math.sin(math.pi * (0.2 + 0.8 * s))
            v.append((x, y, z))
    for j in range(nz):
        for i in range(nx):
            a = j * (nx + 1) + i
            f.append((a, a + 1, a + nx + 2, a + nx + 1))
    ob = mesh(name, v, f, loc, material, parent=parent, smooth=True)
    ob.modifiers.new("V", 'SOLIDIFY').thickness = 0.2
    return ob


def sail_fore_aft(name, h, L, loc, parent, material='sail'):
    v = [(0, 0, 0), (0, 0, h), (0, L, 0.4)]
    ob = mesh(name, v, [(0, 1, 2)], loc, material, parent=parent)
    ob.modifiers.new("V", 'SOLIDIFY').thickness = 0.2
    return ob


def mast(name, x, y, z0, h, parent, yards=(), sails=True, r=0.45, flag=False):
    cyl(name, r, h, (x, y, z0), 'wood', verts=8, r2=r * 0.6, parent=parent)
    for k, (zf, w, sh) in enumerate(yards):
        w, sh = w * 0.72, sh * 0.85
        cyl(f"{name}_ra{k}", 0.22, w, (x - w / 2, y, z0 + h * zf), 'wood', verts=6, rot=(0, math.pi / 2, 0),
            base=True, parent=parent)
        if sails:
            sail_square(f"{name}_v{k}", w * 0.92, h * sh, (x, y - 0.3, z0 + h * zf), parent)
    if flag:
        v = [(0, 0, 0), (0, 0, -2.4), (0, 4.5, -1.2)]
        ob = mesh(name + "_zaszlo", v, [(0, 1, 2)], (x, y, z0 + h + 0.2), 'team', parent=parent)
        ob.modifiers.new("V", 'SOLIDIFY').thickness = 0.2


def gunports(name, L, x, z, n, parent, y0=None):
    for sd in (-1, 1):
        for i in range(n):
            y = (y0 if y0 is not None else -L * 0.3) + (L * 0.6) * i / max(1, n - 1)
            box(f"{name}{sd}{i}", (0.4, 1.2, 1.0), (sd * x, y, z), 'window', bevel=0.0, parent=parent)


def funnel(name, x, y, z0, h, r, parent, band=True, mat='funnel'):
    cyl(name, r, h, (x, y, z0), mat, verts=14, parent=parent)
    if band:
        cyl(name + "_s", r * 1.03, h * 0.18, (x, y, z0 + h * 0.62), 'team', verts=14, parent=parent)
    cyl(name + "_t", r * 1.05, 0.5, (x, y, z0 + h), 'black', verts=14, parent=parent)


def turret(name, x, y, z, r, parent, barrels=2, L=7.0, fwd=True, mat='steel_h'):
    g = empty(name + "_g", (x, y, z), parent)
    cyl(name, r, r * 0.7, (0, 0, 0), mat, verts=14, r2=r * 0.85, parent=g)
    for b in range(barrels):
        dx = (b - (barrels - 1) / 2) * r * 0.45
        cyl(f"{name}_c{b}", 0.3, L, (dx, 0, r * 0.35), 'steel_hd', verts=6,
            rot=(math.pi / 2 if fwd else -math.pi / 2, 0, 0), base=True, parent=g)
    return g


class Ship(Machine):
    ANIM = SHIP_ANIM
    role = "warship"
    age = 0
    cycles_alpha = True
    water = True

    L = 70.0

    def build(self):
        self.root = empty("root")
        self.body = empty("test_g", (0, 0, 0), self.root)
        B = self.body
        a, role = self.age, self.role
        L = {"fisher": 50.0, "transport": 64.0, "warship": 74.0, "galleon": 90.0}[role]
        self.L = L
        W = L * (0.30 if a < 2 else 0.2)
        self.flashes = []
        if a <= 1:
            fb = {"fisher": 3.0, "transport": 4.5, "warship": 5.0, "galleon": 6.0}[role]
            hull("test", L, W, fb, B, mat='hull' if a == 0 else ('hull_d' if role != "fisher" else 'hull'),
                 sheer=0.45 if a == 0 else 0.3)
            deck = fb - 0.6
            # fedélzeti felépítmények (orr- és tatvár)
            if role != "fisher":
                cas = 'hull_d' if a == 1 else 'hull'
                box("tatvar", (W * 0.85, L * 0.2, fb * (0.9 if a == 0 else 1.2)), (0, L * 0.36, deck + fb * 0.4),
                    cas, bevel=0.4, parent=B)
                if a == 0 or role == "galleon":
                    box("orrvar", (W * 0.6, L * 0.14, fb * 0.8), (0, -L * 0.33, deck + fb * 0.6), cas, bevel=0.4, parent=B)
                box("tatvar_sz", (W * 0.87, L * 0.21, 0.6), (0, L * 0.36, deck + fb * 0.4 + fb * (0.9 if a == 0 else 1.2)),
                    'accent' if a == 1 else 'wood_l', bevel=0.1, parent=B)
            # ágyúk
            if role in ("warship", "galleon"):
                n = 5 if role == "warship" else 7
                gunports("agyunyilas", L, W / 2 + 0.1, fb * 0.45, n if a == 1 else n - 2, B)
                if a == 1:
                    gunports("agyunyilas2", L, W / 2 + 0.1, fb * 0.95, n - 1, B, y0=-L * 0.25)
                for sd in (-1, 1):
                    for i in range(3):
                        y = -L * 0.2 + L * 0.2 * i
                        self.flashes.append(self._flash(f"tuz{sd}{i}", (sd * (W / 2 + 1.5), y, fb * 0.5), sd))
            # csík a hajótesten
            if a == 1:
                for sd in (-1, 1):
                    box(f"csik{sd}", (0.3, L * 0.62, 0.7), (sd * W * 0.49, 0, fb * 0.75), 'accent', bevel=0.0, parent=B)
            # árbocok és vitorlák
            h = L * 0.52
            if role == "fisher":
                if a == 0:
                    mast("arboc", 0, -L * 0.05, deck, h * 0.8, B, yards=((0.95, W * 1.6, 0.55),), flag=True)
                else:
                    cyl("arboc", 0.4, h * 0.85, (0, -L * 0.12, deck), 'wood', verts=8, parent=B)
                    sail_fore_aft("vitorla", h * 0.75, L * 0.42, (0, -L * 0.1, deck + 1.5), B)
                    sail_fore_aft("orrvitorla", h * 0.6, -L * 0.25, (0, -L * 0.14, deck + 1.5), B)
                    v = [(0, 0, 0), (0, 0, -2.4), (0, 4.5, -1.2)]
                    ob = mesh("zaszlo", v, [(0, 1, 2)], (0, -L * 0.12, deck + h * 0.85 + 0.2), 'team', parent=B)
                    ob.modifiers.new("V", 'SOLIDIFY').thickness = 0.2
                # halászháló, hordók
                for i in range(2):
                    cyl(f"hordo{i}", 1.0, 1.8, (W * 0.2 * (i * 2 - 1), L * 0.15, deck), 'wood', verts=8, parent=B)
            elif role == "transport":
                if a == 0:
                    mast("arboc", 0, 0, deck, h, B, yards=((0.92, W * 1.7, 0.6),), flag=True, r=0.6)
                else:
                    mast("arboc1", 0, -L * 0.22, deck, h * 0.9, B, yards=((0.9, W * 1.4, 0.4), (0.55, W * 1.6, 0.35)))
                    mast("arboc2", 0, L * 0.05, deck, h, B, yards=((0.9, W * 1.5, 0.4), (0.55, W * 1.7, 0.35)), flag=True)
                    mast("arboc3", 0, L * 0.3, deck + fb, h * 0.6, B, yards=())
                    sail_fore_aft("bezan", h * 0.5, L * 0.18, (0, L * 0.3, deck + fb + 1), B)
                for i in range(4):
                    box(f"lada{i}", (2.4, 2.4, 2.0), (W * 0.18 * (i % 2 * 2 - 1), -L * 0.1 + (i // 2) * 3.0, deck),
                        'wood_l', bevel=0.3, parent=B)
            else:
                big = role == "galleon"
                if a == 0:
                    mast("arboc1", 0, -L * 0.2, deck, h * 0.85, B, yards=((0.9, W * 1.4, 0.5),))
                    mast("arboc2", 0, L * 0.05, deck, h, B, yards=((0.92, W * 1.7, 0.55),), flag=True, r=0.6)
                    if big:
                        mast("arboc3", 0, L * 0.3, deck + fb, h * 0.55, B, yards=())
                        sail_fore_aft("bezan", h * 0.45, L * 0.16, (0, L * 0.3, deck + fb + 1), B)
                else:
                    mast("arboc1", 0, -L * 0.24, deck, h * 0.92, B, yards=((0.92, W * 1.3, 0.3), (0.6, W * 1.5, 0.3),
                                                                         (0.3, W * 1.6, 0.25)))
                    mast("arboc2", 0, L * 0.02, deck, h * 1.05, B, yards=((0.92, W * 1.4, 0.3), (0.6, W * 1.6, 0.3),
                                                                         (0.3, W * 1.7, 0.25)), flag=True)
                    mast("arboc3", 0, L * 0.28, deck + fb * 0.8, h * 0.7, B, yards=((0.85, W * 1.1, 0.35),))
                    cyl("orrarboc", 0.35, L * 0.25, (0, -L * 0.5, deck + 1.5), 'wood', verts=6,
                        rot=(R(70), 0, 0), base=True, parent=B)
                    sail_fore_aft("orrvitorla", h * 0.35, -L * 0.2, (0, -L * 0.42, deck + 2), B)
                # tatlámpás
                sphere("lampas", 0.8, (0, L * 0.47, deck + fb * 1.6), 'gold', parent=B, seg=8, rings=6)
        elif a == 2:
            fb = {"fisher": 3.0, "transport": 4.0, "warship": 3.6, "galleon": 4.6}[role]
            hmat = 'hull_b'
            hull("test", L, W, fb, B, mat=hmat, deck='deck', sheer=0.15, stern_w=0.8)
            deck = fb - 0.6
            for sd in (-1, 1):
                box(f"csik{sd}", (0.3, L * 0.7, 0.6), (sd * W * 0.49, 0, fb * 0.7), 'team', bevel=0.0, parent=B)
            h = L * 0.5
            if role == "fisher":
                box("kabin", (W * 0.5, L * 0.2, 3.5), (0, L * 0.15, deck), 'white', bevel=0.3, parent=B)
                funnel("kemeny", 0, L * 0.05, deck, 7.0, 1.0, B)
                cyl("arboc", 0.35, h * 0.8, (0, -L * 0.2, deck), 'wood', verts=8, parent=B)
            elif role == "transport":
                box("felep", (W * 0.7, L * 0.3, 4.0), (0, 0, deck), 'white', bevel=0.3, parent=B)
                for sd in (-1, 1):
                    ob = cyl(f"lapat{sd}", 4.5, 2.4, (sd * (W / 2 + 1.1), 0, 1.0), 'hull_b', verts=16,
                             rot=(0, math.pi / 2, 0), base=False, parent=B)
                    box(f"lapat_h{sd}", (2.6, 9.0, 0.5), (sd * (W / 2 + 1.1), 0, 1.0), 'team', bevel=0.1, parent=B)
                funnel("kemeny", 0, -L * 0.02, deck + 4, 10.0, 1.4, B)
                mast("arboc1", 0, -L * 0.3, deck, h * 0.8, B, yards=((0.85, W * 1.4, 0.35),))
                mast("arboc2", 0, L * 0.3, deck, h * 0.7, B, yards=(), flag=True)
            elif role == "warship":      # páncélos gőzös, egy toronnyal
                box("felep", (W * 0.6, L * 0.22, 3.0), (0, L * 0.1, deck), 'steel_h', bevel=0.3, parent=B)
                funnel("kemeny", 0, L * 0.05, deck + 3, 9.0, 1.4, B)
                turret("torony", 0, -L * 0.25, deck, 3.2, B, barrels=2, L=8.0)
                mast("arboc", 0, -L * 0.05, deck, h * 0.9, B, yards=((0.85, W * 1.6, 0.35),), flag=True)
                self.flashes.append(self._flash("tuz0", (0, -L * 0.25 - 11, deck + 1.5), 0))
            else:                        # sorhajó: két kémény, két torony
                box("felep", (W * 0.66, L * 0.3, 3.6), (0, L * 0.02, deck), 'steel_h', bevel=0.3, parent=B)
                funnel("kemeny1", 0, -L * 0.06, deck + 3.6, 9.5, 1.5, B)
                funnel("kemeny2", 0, L * 0.1, deck + 3.6, 9.5, 1.5, B)
                turret("torony1", 0, -L * 0.3, deck, 3.4, B, barrels=2, L=8.5)
                turret("torony2", 0, L * 0.32, deck, 3.4, B, barrels=2, L=8.5, fwd=False)
                mast("arboc1", 0, -L * 0.18, deck, h * 0.9, B, yards=((0.85, W * 1.5, 0.3),))
                mast("arboc2", 0, L * 0.22, deck, h * 0.8, B, yards=(), flag=True)
                self.flashes.append(self._flash("tuz0", (0, -L * 0.3 - 11, deck + 1.5), 0))
                self.flashes.append(self._flash("tuz1", (0, L * 0.32 + 11, deck + 1.5), 0))
        else:
            fb = {"fisher": 3.0, "transport": 4.2, "warship": 3.4, "galleon": 4.2}[role]
            hmat = 'steel_h' if role in ("warship", "galleon") else ('hull_b' if role == "transport" else 'redhull')
            hull("test", L, W * (0.95 if role in ("warship", "galleon") else 1.15), fb, B, mat=hmat,
                 deck='steel_hd' if role in ("warship", "galleon") else 'deck', sheer=0.12, stern_w=0.85,
                 bow_len=0.45)
            deck = fb - 0.6
            if role == "fisher":         # vonóhálós halászhajó
                box("kormanyhaz", (W * 0.6, L * 0.18, 4.0), (0, -L * 0.1, deck), 'white', bevel=0.3, parent=B)
                box("kormanyhaz_ab", (W * 0.62, 0.3, 1.0), (0, -L * 0.19, deck + 2.6), 'window', bevel=0.0, parent=B)
                cyl("arboc", 0.3, 12, (0, -L * 0.25, deck), 'steel_hd', verts=6, parent=B)
                box("csorlo", (W * 0.4, 3.0, 2.0), (0, L * 0.25, deck), 'team', bevel=0.3, parent=B)
                ob = cyl("gem", 0.3, 10, (0, L * 0.35, deck), 'steel_hd', verts=6, parent=B)
                ob.rotation_euler = (R(-30), 0, 0)
            elif role == "transport":    # teherhajó
                box("felep", (W * 0.8, L * 0.16, 7.0), (0, L * 0.3, deck), 'white', bevel=0.3, parent=B)
                box("felep_ab", (W * 0.82, 0.3, 1.2), (0, L * 0.22, deck + 5.0), 'window', bevel=0.0, parent=B)
                funnel("kemeny", 0, L * 0.34, deck + 7, 5.0, 1.5, B)
                for i in range(3):
                    box(f"raktar{i}", (W * 0.6, L * 0.14, 1.2), (0, -L * 0.3 + i * L * 0.17, deck), 'team_s', bevel=0.2,
                        parent=B)
                for i in range(2):
                    cyl(f"daru{i}", 0.4, 11, (0, -L * 0.22 + i * L * 0.2, deck), 'steel_hd', verts=6, parent=B)
            elif role == "warship":      # romboló
                box("felep", (W * 0.55, L * 0.2, 4.0), (0, -L * 0.1, deck), 'steel_h', bevel=0.3, parent=B)
                box("hid", (W * 0.5, L * 0.08, 2.0), (0, -L * 0.14, deck + 4), 'steel_h', bevel=0.2, parent=B)
                box("hid_ab", (W * 0.52, 0.3, 0.8), (0, -L * 0.18, deck + 5.0), 'window', bevel=0.0, parent=B)
                funnel("kemeny", 0, L * 0.05, deck, 7.5, 1.4, B, mat='steel_h')
                turret("torony1", 0, -L * 0.33, deck, 2.4, B, barrels=1, L=6.0)
                turret("torony2", 0, L * 0.36, deck, 2.4, B, barrels=1, L=6.0, fwd=False)
                cyl("arboc", 0.25, 11, (0, -L * 0.06, deck + 6), 'steel_hd', verts=6, parent=B)
                v = [(0, 0, 0), (0, 0, -2.4), (0, 4.5, -1.2)]
                ob = mesh("zaszlo", v, [(0, 1, 2)], (0, -L * 0.06, deck + 17.2), 'team', parent=B)
                ob.modifiers.new("V", 'SOLIDIFY').thickness = 0.2
                self.flashes.append(self._flash("tuz0", (0, -L * 0.33 - 8, deck + 1.2), 0))
            else:                        # cirkáló
                box("felep", (W * 0.6, L * 0.26, 4.5), (0, -L * 0.05, deck), 'steel_h', bevel=0.3, parent=B)
                box("hid", (W * 0.45, L * 0.1, 3.0), (0, -L * 0.13, deck + 4.5), 'steel_h', bevel=0.2, parent=B)
                box("hid_ab", (W * 0.47, 0.3, 0.9), (0, -L * 0.18, deck + 6.3), 'window', bevel=0.0, parent=B)
                funnel("kemeny1", 0, L * 0.02, deck + 4.5, 7.0, 1.5, B, mat='steel_h')
                funnel("kemeny2", 0, L * 0.12, deck + 4.5, 7.0, 1.5, B, mat='steel_h')
                turret("torony1", 0, -L * 0.34, deck, 3.0, B, barrels=3, L=8.0)
                turret("torony2", 0, -L * 0.24, deck + 1.6, 3.0, B, barrels=3, L=8.0)
                turret("torony3", 0, L * 0.34, deck, 3.0, B, barrels=3, L=8.0, fwd=False)
                cyl("arboc", 0.3, 14, (0, -L * 0.08, deck + 7.5), 'steel_hd', verts=6, parent=B)
                v = [(0, 0, 0), (0, 0, -2.6), (0, 5.0, -1.3)]
                ob = mesh("zaszlo", v, [(0, 1, 2)], (0, -L * 0.08, deck + 21.5), 'team', parent=B)
                ob.modifiers.new("V", 'SOLIDIFY').thickness = 0.2
                self.flashes.append(self._flash("tuz0", (0, -L * 0.34 - 10, deck + 1.4), 0))
                self.flashes.append(self._flash("tuz1", (0, L * 0.34 + 10, deck + 1.4), 0))
            # felségjel a fedélzeten (légi felismeréshez)
            if role in ("warship", "galleon"):
                box("jel", (W * 0.5, 4.0, 0.15), (0, L * 0.22, deck + 0.05), 'team', bevel=0.0, parent=B)
        # hab az orrnál és a nyomvonal (menet közben)
        self.foam = []
        for i, (x, y, r) in enumerate([(-W * 0.45, -L * 0.45, 2.4), (W * 0.45, -L * 0.45, 2.4),
                                       (0, L * 0.55, 3.0), (0, L * 0.7, 2.4)]):
            ob = sphere(f"hab{i}", r * 1.6, (x, y, 0.0), 'foam', scale=(0.8, 2.6, 0.2), parent=self.root, seg=10, rings=6)
            ob["fx"] = True
            self.foam.append(ob)
        self.parts = [self.body]
        self.smokes = [fx_smoke(f"fust{i}", (x, y, 0), r, parent=self.root)
                       for i, (x, y, r) in enumerate([(W * 0.8, -L * 0.1, 3.0), (-W * 0.8, L * 0.1, 3.0),
                                                     (0, -L * 0.45, 3.0)])]
        self.make_wreck_fx(8)

    def _flash(self, name, loc, sd):
        ob = sphere(name, 1.3, loc, 'fire', scale=(1.6 if sd else 1.0, 1.0 if sd else 1.6, 1.0),
                    parent=self.body, seg=8, rings=6)
        ob["fx"] = True
        return ob

    def pose(self, mode, t=0.0, k=0):
        kk = k
        self.body.location = (0, 0, 0)
        self.body.rotation_euler = (0, 0, 0)
        for f in self.foam:
            f.hide_render = mode != "walk"
        if mode == "walk":
            self.body.rotation_euler = (R(1.5 if kk else -1.5), 0, 0)
        for f in self.flashes:
            f.hide_render = not (mode == "attack" and kk == 0)
        for i, s in enumerate(self.smokes):
            s.hide_render = not (mode == "attack")
            s.location = (s.location[0], s.location[1], 3.0 + (2.0 if kk else 0.0))
        for fx in self.wreck_fx:
            fx.hide_render = True
        if mode == "death":
            roll = [8, 22, 40, 55][kk]
            self.body.rotation_euler = (R([0, -3, -8, -14][kk]), R(roll), 0)
            self.body.location = (0, 0, [0, -1.5, -5.0, -11.0][kk])
            for i, fx in enumerate(self.wreck_fx):
                fx.hide_render = not (i <= kk + 1) or (kk == 3 and i < 2)


def _ship(role, a):
    L = {"fisher": 50.0, "transport": 64.0, "warship": 74.0, "galleon": 90.0}[role]
    w = int(L * 1.25)
    h = int(L * 1.2)
    return type(f"Ship_{role}{a}", (Ship,), {"role": role, "age": a, "cell": (w, h, w // 2, int(h * 0.68))})


# ---------------------------------------------------------------- repülőgép

class Plane(Machine):
    ANIM = PLANE_ANIM
    cycles_alpha = True
    water = False
    bomber = False

    def build(self):
        self.root = empty("root")
        self.body = empty("gep_g", (0, 0, 0), self.root)
        B = self.body
        b = self.bomber
        L = 34.0 if b else 26.0
        span = 46.0 if b else 30.0
        r = 2.4 if b else 1.8
        # törzs (az orr -Y felé)
        cyl("torzs", r, L * 0.62, (0, -L * 0.1, 0), 'plane', verts=14, r2=r * 0.9, rot=(math.pi / 2, 0, 0),
            base=True, parent=B)
        cyl("torzs_h", r * 0.9, L * 0.48, (0, -L * 0.1, 0), 'plane', verts=14, r2=0.5, rot=(-math.pi / 2, 0, 0),
            base=True, parent=B)
        sphere("orr", r, (0, -L * 0.72, 0), 'plane', scale=(1, 0.7, 1), parent=B)
        sphere("kabin", r * 0.75, (0, -L * 0.28 if not b else -L * 0.5, r * 0.7), 'glass',
               scale=(0.8, 1.6, 0.7), parent=B)
        # szárnyak
        wy = -L * 0.25
        box("szarny", (span, 5.5 if not b else 7.0, 0.7), (0, wy, -0.4), 'plane', bevel=0.3, parent=B, base=False)
        for sd in (-1, 1):
            cyl(f"jel{sd}", 2.4 if not b else 3.0, 0.3, (sd * span * 0.36, wy, 0.0), 'accent', verts=16, parent=B)
            cyl(f"jel_b{sd}", 1.6 if not b else 2.0, 0.35, (sd * span * 0.36, wy, 0.02), 'team', verts=16, parent=B)
        # farok
        box("vizszintes", (span * 0.38, 3.5, 0.5), (0, L * 0.34, 0.2), 'plane', bevel=0.2, parent=B, base=False)
        ob = box("fuggoleges", (0.5, 4.0, 4.5), (0, L * 0.34, 0.3), 'plane', bevel=0.2, parent=B)
        box("farokcsik", (0.55, 2.0, 1.4), (0, L * 0.35, 3.0), 'team', bevel=0.1, parent=B)
        # motor(ok) és légcsavar
        self.props = []
        eng = [(0, -L * 0.76)] if not b else [(-span * 0.2, wy - 3.5), (span * 0.2, wy - 3.5)]
        for i, (x, y) in enumerate(eng):
            if b:
                cyl(f"motor{i}", 1.7, 7.0, (x, y + 5.5, -0.3), 'plane', verts=12, r2=1.4, rot=(math.pi / 2, 0, 0),
                    base=True, parent=B)
            p = cyl(f"legcsavar{i}", 3.2 if not b else 3.0, 0.15, (x, y - (1.5 if b else 0.8), -0.2 if b else 0),
                    'prop', verts=20, rot=(math.pi / 2, 0, 0), base=False, parent=B)
            p["fx"] = True
            self.props.append(p)
            sphere(f"kup{i}", 0.7, (x, y - (1.6 if b else 1.0), -0.2 if b else 0), 'iron', parent=B, seg=8, rings=6)
        # támadás: géppuska-torkolattűz (vadász) / bombák (bombázó)
        self.flashes = []
        if not b:
            for sd in (-1, 1):
                f = sphere(f"tuz{sd}", 0.8, (sd * span * 0.22, wy - 4.5, -0.3), 'fire', scale=(0.8, 2.2, 0.8),
                           parent=B, seg=8, rings=6)
                f["fx"] = True
                self.flashes.append(f)
        else:
            for i in range(3):
                f = cyl(f"bomba{i}", 0.8, 2.8, (0, L * 0.3 + i * 2.5, -4.0 - i * 4.0), 'olive_d', verts=8,
                        rot=(math.pi / 2, 0, 0), base=False, parent=B)
                self.flashes.append(f)
        self.parts = [self.body]
        self.make_wreck_fx(2)
        self.trail = [fx_smoke(f"csik{i}", (0, L * 0.4 + i * 5.0, 1.0 + i), 1.6 + i * 0.7, parent=self.root, light=False)
                      for i in range(3)]

    def pose(self, mode, t=0.0, k=0):
        kk = k
        self.body.location = (0, 0, 0)
        self.body.rotation_euler = (0, 0, 0)
        for p in self.props:
            p.hide_render = False
            p.scale = (1.0, 1.0, 1.0) if (mode != "walk" or kk == 0) else (0.85, 0.85, 1.0)
        for f in self.flashes:
            f.hide_render = not (mode == "attack" and (kk == 0 or self.bomber))
        for s in self.trail:
            s.hide_render = True
        for fx in self.wreck_fx:
            fx.hide_render = True
        if mode == "walk":
            self.body.rotation_euler = (0, R(6 if kk else -6), 0)
        if mode == "death":
            self.body.rotation_euler = (R([-5, -15, -30, 0][kk]), R([10, 25, 45, 15][kk]), 0)
            for i, s in enumerate(self.trail):
                s.hide_render = kk >= 3 or i > kk
            for i, fx in enumerate(self.wreck_fx):
                fx.hide_render = not (i <= kk)
            for p in self.props:
                p.hide_render = kk >= 1


class Fighter(Plane):
    cell = (48, 48, 24, 24)
    bomber = False


class Bomber(Plane):
    cell = (64, 60, 32, 30)
    bomber = True


SHIPS = {}
for _r in ("fisher", "transport", "warship", "galleon"):
    for _a in range(4):
        SHIPS[f"{_r}_{_a}"] = _ship(_r, _a)
SHIPS["fighter_3"] = Fighter
SHIPS["bomber_3"] = Bomber
