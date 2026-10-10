# -*- coding: utf-8 -*-
# BIRODALOM — EGYSÉGMODELLEK ÉS PÓZOK (eljárással, bpy)
#
# Az alakok "bábuk": üres csuklópontok (Empty) láncai, rajtuk egyszerű
# testrészek. Csontváz és kulcskocka nincs — a póz függvény minden kockához
# közvetlenül beállítja a csuklók elfordulását, a render utána készül.
#
# Irányok (a játék szögei, y lefelé): 0 = K, 1 = DK, 2 = D, 3 = DNy, 4 = Ny,
# 5 = ÉNy, 6 = É, 7 = ÉK. A modell alapból délre (a kamera felé, -Y) néz.
#
# Fegyverek: saját gyökerük van; a helyi +Z a fegyver "hegye" felé mutat.
# A kézhez igazítás (grip_to) a test terében adott Euler-szöggel forgat:
#   X = +90°  -> a hegy ELŐRE (-Y) mutat,  X = 0 -> függőlegesen föl,
#   X = 180°  -> lefelé.
#
# Minden egység osztálya: build(), set_dir(k), pose(mode, t, k) ahol mode:
# "idle", "walk" (t = 0..1), "attack" (t = kockaszám/(n-1)), "death" (dtto).
# ANIM: az egyes állapotok kockaszáma (a lap oszlopai ebben a sorrendben).

import math, random
import bpy
from mathutils import Vector, Matrix, Euler
from bir_common import *

DIRS = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
HUMAN_ANIM = {"idle": 1, "walk": 8, "attack": 4, "death": 4}
MACHINE_ANIM = {"idle": 1, "walk": 4, "attack": 4, "death": 4}


def dir_rot(k):
    return -math.radians(45.0 * k) + math.pi / 2


def R(d):
    return math.radians(d)


# ---------------------------------------------------------------- testrészek

def limb(name, parent, r_top, r_bot, length, material, verts=8):
    """Végtag a csukló helyi terében lefelé (-Z)."""
    return cyl(name, r_bot, length, (0, 0, -length), material, verts=verts, r2=r_top, parent=parent)


class Rig:
    def __init__(self):
        self.j = {}

    def add(self, name, parent, loc):
        e = empty(name, loc, self.j.get(parent) if isinstance(parent, str) else parent)
        self.j[name] = e
        return e

    def __getitem__(self, k):
        return self.j[k]

    def __contains__(self, k):
        return k in self.j

    def rest(self, keep=("root",)):
        for k, e in self.j.items():
            if k not in keep:
                e.rotation_euler = (0, 0, 0)


# ---------------------------------------------------------------- fejfedők

def hat(neck, kind, s):
    band = s.get("hat_band", 'team')
    if kind == "straw":
        cyl("kalap_k", 1.65, 0.25, (0, 0, 1.95), 'hay', verts=14, parent=neck)
        cyl("kalap", 0.95, 1.0, (0, 0, 2.0), 'hay', verts=12, r2=0.6, parent=neck)
        cyl("kalap_sz", 0.98, 0.3, (0, 0, 2.15), band, verts=12, parent=neck)
    elif kind == "kettle":
        sphere("sisak", 1.12, (0, -0.05, 1.55), 'steel', scale=(1, 1, 0.95), parent=neck)
        cyl("sisak_k", 1.95, 0.22, (0, -0.05, 1.45), 'steel', verts=16, r2=1.6, parent=neck)
    elif kind == "sallet":
        sphere("sisak", 1.12, (0, 0.05, 1.5), 'steel', scale=(1, 1.12, 0.95), parent=neck)
        ob = box("sisak_f", (1.9, 1.3, 0.3), (0, 1.0, 1.15), 'steel', bevel=0.1, parent=neck)
        ob.rotation_euler = (R(-18), 0, 0)
        box("sisak_r", (1.9, 0.2, 0.25), (0, -1.02, 1.45), 'steel_d', bevel=0.0, parent=neck)
    elif kind == "bascinet":
        cyl("sisak", 1.15, 1.2, (0, 0.05, 1.2), 'steel', verts=12, r2=0.3, parent=neck)
        sphere("sisak_a", 1.1, (0, 0.05, 1.3), 'steel', scale=(1, 1.02, 0.8), parent=neck)
        cyl("csuklya_l", 1.25, 0.9, (0, 0.05, 0.1), 'mail', verts=12, r2=1.05, parent=neck)
    elif kind in ("greathelm", "crownhelm"):
        cyl("sisak", 1.15, 2.1, (0, -0.05, 0.4), 'steel', verts=14, r2=1.05, parent=neck)
        cyl("sisak_t", 1.05, 0.35, (0, -0.05, 2.5), 'steel_d', verts=14, r2=0.7, parent=neck)
        box("sisak_r", (1.9, 0.3, 0.22), (0, -1.12, 1.55), 'window', bevel=0.0, parent=neck)
        box("sisak_x", (0.22, 0.3, 1.8), (0, -1.14, 0.6), 'steel_d', bevel=0.0, parent=neck)
        if kind == "crownhelm":
            cyl("korona", 1.2, 0.5, (0, -0.05, 2.45), 'gold', verts=14, parent=neck)
            for i in range(6):
                a = 2 * math.pi * i / 6
                cone(f"korona{i}", 0.25, 0.6, (math.cos(a) * 1.1, -0.05 + math.sin(a) * 1.1, 2.9), 'gold',
                     verts=4, parent=neck)
        else:
            sphere("toll", 0.75, (0, 0.2, 3.35), s.get("plume", 'team'), scale=(0.55, 1.4, 1.1), parent=neck)
    elif kind == "morion":
        sphere("sisak", 1.1, (0, 0, 1.5), 'steel', scale=(1, 1.1, 0.9), parent=neck)
        box("sisak_taraj", (0.25, 1.9, 0.8), (0, 0, 2.2), 'steel', bevel=0.2, parent=neck)
        ob = cyl("sisak_k", 1.5, 0.2, (0, 0, 1.35), 'steel', verts=16, r2=1.3, parent=neck)
        ob.scale = (0.85, 1.35, 1.0)
    elif kind == "lobster":
        sphere("sisak", 1.12, (0, 0.02, 1.5), 'steel', scale=(1, 1.05, 0.95), parent=neck)
        box("sisak_n", (1.8, 1.0, 1.0), (0, 1.0, 0.6), 'steel', bevel=0.3, parent=neck)
        for x in (-0.3, 0.0, 0.3):
            box(f"sisak_r{x}", (0.12, 0.2, 1.2), (x, -1.05, 0.7), 'steel_d', bevel=0.0, parent=neck)
    elif kind in ("felt", "plumed"):
        cyl("kalap_k", 1.8, 0.2, (0, 0, 1.95), 'felt', verts=16, parent=neck)
        cyl("kalap", 0.95, 1.1, (0, 0, 2.0), 'felt', verts=12, r2=0.85, parent=neck)
        cyl("kalap_sz", 0.98, 0.25, (0, 0, 2.15), band, verts=12, parent=neck)
        if kind == "plumed":
            sphere("toll", 0.6, (0.9, 0.3, 2.8), s.get("plume", 'accent'), scale=(0.5, 1.5, 0.7), parent=neck)
    elif kind == "tricorne":
        cyl("kalap", 1.0, 0.9, (0, 0, 2.0), 'felt', verts=12, r2=0.9, parent=neck)
        for i in range(3):
            a = math.pi / 2 + 2 * math.pi * i / 3
            ob = box(f"kalap_sz{i}", (2.3, 0.3, 0.9), (math.cos(a) * 1.0, math.sin(a) * 1.0, 2.0),
                     'felt', bevel=0.1, parent=neck)
            ob.rotation_euler = (0, 0, a + math.pi / 2)
            box(f"kalap_d{i}", (2.2, 0.32, 0.18), (math.cos(a) * 1.0, math.sin(a) * 1.0, 2.8),
                band if band != 'team' else 'accent', bevel=0.0, parent=neck).rotation_euler = (0, 0, a + math.pi / 2)
    elif kind == "bicorne":
        ob = sphere("kalap", 1.0, (0, 0.0, 2.35), 'felt', scale=(2.1, 0.55, 1.0), parent=neck)
        sphere("kokarda", 0.35, (0.0, -0.55, 2.5), 'team', parent=neck)
        box("kalap_sz", (3.6, 0.6, 0.15), (0, 0.0, 2.05), 'accent', bevel=0.0, parent=neck)
    elif kind == "shako":
        cyl("csako", 1.02, 1.8, (0, 0, 1.6), 'felt', verts=12, r2=1.12, parent=neck)
        box("csako_e", (1.6, 0.8, 0.12), (0, -0.95, 1.65), 'leather', bevel=0.0, parent=neck)
        box("csako_j", (0.6, 0.12, 0.6), (0, -1.1, 2.6), 'brass', bevel=0.0, parent=neck)
        cyl("csako_s", 1.13, 0.25, (0, 0, 3.2), band, verts=12, parent=neck)
        sphere("csako_p", 0.4, (0, -0.8, 3.7), s.get("plume", 'accent'), scale=(0.7, 0.7, 1.4), parent=neck)
    elif kind == "kalpak":
        cyl("kalpag", 1.08, 1.7, (0, 0, 1.6), 'fur', verts=12, r2=1.15, parent=neck)
        sphere("kalpag_z", 0.6, (0.4, 0.6, 3.1), 'team', scale=(0.8, 1.3, 0.6), parent=neck)
        sphere("kalpag_t", 0.35, (-0.4, -0.5, 3.9), s.get("plume", 'accent'), scale=(0.5, 0.5, 1.8), parent=neck)
    elif kind == "bearskin":
        cyl("medve", 1.15, 2.4, (0, 0, 1.5), 'fur', verts=12, r2=1.25, parent=neck)
        sphere("medve_t", 1.25, (0, 0, 3.9), 'fur', scale=(1, 1, 0.5), parent=neck)
        box("medve_j", (0.7, 0.12, 0.7), (0, -1.2, 2.6), 'brass', bevel=0.0, parent=neck)
    elif kind == "kepi":
        cyl("kepi", 1.02, 1.1, (0, 0, 1.75), band if s.get("kepi_team") else 'felt', verts=12, r2=0.95,
            parent=neck).rotation_euler = (R(-8), 0, 0)
        box("kepi_e", (1.5, 0.8, 0.12), (0, -0.95, 1.8), 'leather', bevel=0.0, parent=neck)
    elif kind in ("ww2", "medhelm"):
        m = 'white' if kind == "medhelm" else 'helmet3'
        sphere("sisak", 1.18, (0, 0.0, 1.45), m, scale=(1.02, 1.08, 0.82), parent=neck)
        cyl("sisak_k", 1.5, 0.18, (0, 0.05, 1.2), m, verts=16, r2=1.25, parent=neck)
        if kind == "medhelm":
            box("kereszt1", (0.9, 0.2, 0.28), (0, -1.12, 1.75), 'redcross', bevel=0.0, parent=neck)
            box("kereszt2", (0.28, 0.2, 0.9), (0, -1.12, 1.75), 'redcross', bevel=0.0, parent=neck)
        else:
            cyl("sisak_s", 1.14, 0.22, (0, 0.0, 1.55), band, verts=16, parent=neck)
    elif kind == "peaked":
        cyl("sapka", 0.98, 0.7, (0, 0, 2.0), s.get("cap_mat", 'olive'), verts=14, r2=1.25, parent=neck)
        cyl("sapka_s", 1.0, 0.3, (0, 0, 1.95), band, verts=14, parent=neck)
        box("sapka_e", (1.5, 0.9, 0.12), (0, -1.0, 1.95), 'black', bevel=0.0, parent=neck).rotation_euler = (R(12), 0, 0)
        box("sapka_j", (0.4, 0.1, 0.35), (0, -1.05, 2.4), 'gold', bevel=0.0, parent=neck)
    elif kind == "cap":
        sphere("sapka", 1.08, (0, 0.05, 1.7), s.get("cap_mat", 'grey'), scale=(1.02, 1.1, 0.6), parent=neck)
        box("sapka_e", (1.5, 0.9, 0.12), (0, -1.05, 1.65), s.get("cap_mat", 'grey'), bevel=0.0, parent=neck)
    elif kind == "tophat":
        cyl("cilinder_k", 1.5, 0.15, (0, 0, 2.0), 'black', verts=14, parent=neck)
        cyl("cilinder", 0.85, 1.9, (0, 0, 2.0), 'black', verts=14, r2=0.92, parent=neck)
        cyl("cilinder_s", 0.88, 0.3, (0, 0, 2.15), band, verts=14, parent=neck)
    elif kind == "fedora":
        cyl("kalap_k", 1.6, 0.15, (0, 0, 1.95), 'grey', verts=14, parent=neck)
        cyl("kalap", 0.95, 1.0, (0, 0, 2.0), 'grey', verts=12, r2=0.8, parent=neck)
        cyl("kalap_sz", 0.97, 0.25, (0, 0, 2.1), band, verts=12, parent=neck)
    elif kind == "biretta":
        box("biretta", (1.9, 1.9, 0.9), (0, 0, 2.0), 'black', bevel=0.3, parent=neck)
        sphere("biretta_p", 0.25, (0, 0, 3.0), s.get("hat_band", 'team'), parent=neck)
    elif kind == "hood":
        m = s.get("hood_mat", 'team')
        sphere("csuklya", 1.14, (0, 0.1, 1.4), m, scale=(1, 1.05, 1.02), parent=neck)
        cyl("csuklya_v", 1.6, 0.9, (0, 0.0, -0.2), m, verts=12, r2=1.1, parent=neck)
    elif kind == "monk":
        sphere("haj", 1.02, (0, 0.12, 1.45), 'hair', scale=(0.94, 0.98, 0.95), parent=neck)
        sphere("tonzura", 0.55, (0, 0.1, 2.35), 'skin', scale=(1, 1, 0.3), parent=neck)
        cyl("csuklya_v", 1.55, 0.8, (0, 0.2, -0.1), s.get("hood_mat", 'brown'), verts=12, r2=1.1, parent=neck)
    elif kind == "surgcap":
        sphere("sapka", 1.08, (0, 0.05, 1.65), 'white', scale=(1.02, 1.05, 0.7), parent=neck)
    else:
        sphere("haj", 1.02, (0, 0.12, 1.45), 'hair', scale=(0.94, 0.98, 0.95), parent=neck)
    if s.get("beard"):
        sphere("szakall", 0.7, (0, -0.75, 0.75), 'hair', scale=(1.0, 0.6, 1.0), parent=neck)


# ---------------------------------------------------------------- emberalak

def human(rig, root, spec):
    """Emberalak a rig-be. spec: szótár az anyagokkal, a fejfedővel és a
    ruházat kiegészítőivel."""
    s = spec
    fall = rig.add("fall", root, (0, 0, 0))          # a halál forgáspontja (talp)
    body = rig.add("body", fall, (0, 0, 0))
    pel = rig.add("pelvis", body, (0, 0, 4.8))
    torso_m = s.get("torso", 'tunic')
    torso = cyl("torzs", 1.05, 2.9, (0, 0, 0), torso_m, verts=10, r2=1.3, parent=pel)
    torso.scale = (1.0, 0.72, 1.0)
    skirt_len = s.get("skirt_len", 1.5)
    sk = cyl("szoknya", 1.35 + (0.15 if skirt_len > 2 else 0), skirt_len, (0, 0, -skirt_len + 0.2),
             s.get("skirt", torso_m), verts=10, r2=1.05, parent=pel)
    sk.scale = (1.0, 0.8, 1.0)
    b = cyl("ov", 1.12, 0.35, (0, 0, -0.05), s.get("belt", 'leather'), verts=10, parent=pel)
    b.scale = (1.0, 0.76, 1.0)
    if s.get("tabard"):
        for sg, nm in ((-1, "tabard_e"), (1, "tabard_h")):
            box(nm, (1.9, 0.18, 3.8), (0, sg * 0.86, -1.2), s["tabard"], bevel=0.05, parent=pel)
        if s.get("tabard_trim"):
            box("tabard_cs", (0.5, 0.2, 3.6), (0, -0.98, -1.1), s["tabard_trim"], bevel=0.0, parent=pel)
    if s.get("breast"):
        ob = cyl("vert", 1.12, 1.9, (0, -0.05, 0.6), s["breast"], verts=10, r2=1.34, parent=pel)
        ob.scale = (1.0, 0.8, 1.0)
    if s.get("apron"):
        box("kotény", (1.9, 0.15, 3.6), (0, -0.92, -1.6), s["apron"], bevel=0.05, parent=pel)
    if s.get("sash"):
        ob = box("szalag", (0.5, 1.75, 3.7), (0, 0, 1.35), s["sash"], bevel=0.05, parent=pel)
        ob.rotation_euler = (0, R(35), 0)
    if s.get("crossbelt"):
        for sg in (-1, 1):
            ob = box(f"keresztszij{sg}", (0.35, 1.72, 3.6), (0, 0, 1.35), s["crossbelt"], bevel=0.0, parent=pel)
            ob.rotation_euler = (0, R(35) * sg, 0)
    if s.get("lapels"):
        box("hajtoka", (1.0, 0.15, 2.4), (0, -0.95, 1.4), s["lapels"], bevel=0.0, parent=pel)
    if s.get("braid"):
        for i in range(4):
            box(f"zsinor{i}", (1.6, 0.12, 0.18), (0, -0.98, 0.6 + i * 0.55), s["braid"], bevel=0.0, parent=pel)
    if s.get("backpack"):
        box("hatizsak", (1.9, 0.9, 2.0), (0, 1.1, 1.3), s["backpack"], bevel=0.2, parent=pel)
    if s.get("armband"):
        pass   # a vállcsuklóhoz kerül lent
    if s.get("cape"):
        v = [(-1.35, 0.9, 2.8), (1.35, 0.9, 2.8), (1.9, 1.5, -2.2), (-1.9, 1.5, -2.2)]
        ob = mesh("köpeny", v, [(0, 1, 2, 3)], (0, 0, 0), s["cape"], parent=pel)
        ob.modifiers.new("V", 'SOLIDIFY').thickness = 0.25
    if s.get("cloak"):
        ob = cyl("csuha", 1.7, 5.0, (0, 0.1, -3.2), s["cloak"], verts=12, r2=1.35, parent=pel)
        ob.scale = (1.0, 0.85, 1.0)
    neck = rig.add("neck", pel, (0, 0, 2.9))
    cyl("nyak", 0.42, 0.5, (0, 0, 0), 'skin', verts=8, parent=neck)
    sphere("fej", 1.0, (0, -0.05, 1.3), 'skin', scale=(0.92, 0.95, 1.05), parent=neck)
    sphere("orr", 0.2, (0, -1.0, 1.2), 'skin', parent=neck, seg=6, rings=4)
    hat(neck, s.get("hat"), s)
    for sd, nm in ((-1, "l"), (1, "r")):
        sh = rig.add("sh_" + nm, pel, (sd * 1.45, 0, 2.45))
        sphere("vall_" + nm, 0.55, (0, 0, 0), s.get("shoulder", torso_m), parent=sh)
        if s.get("epaulette"):
            sphere("epoulett_" + nm, 0.6, (sd * 0.1, 0, 0.35), s["epaulette"], scale=(1, 1, 0.45), parent=sh)
        limb("felkar_" + nm, sh, 0.45, 0.4, 1.55, s.get("arm", torso_m))
        if nm == "l" and s.get("armband"):
            cyl("karszalag", 0.5, 0.5, (0, 0, -0.95), s["armband"], verts=8, parent=sh)
        el = rig.add("el_" + nm, sh, (0, 0, -1.55))
        limb("alkar_" + nm, el, 0.4, 0.34, 1.35, s.get("forearm", s.get("arm", torso_m)))
        if s.get("cuffs"):
            cyl("mandzsetta_" + nm, 0.45, 0.4, (0, 0, -1.3), s["cuffs"], verts=8, parent=el)
        sphere("kez_" + nm, 0.38, (0, 0, -1.5), s.get("hand", 'skin'), parent=el)
        rig.add("hand_" + nm, el, (0, 0, -1.5))
    for sd, nm in ((-1, "l"), (1, "r")):
        hp = rig.add("hip_" + nm, pel, (sd * 0.58, 0, 0))
        limb("comb_" + nm, hp, 0.58, 0.48, 2.3, s.get("legs", 'hose'), verts=8)
        kn = rig.add("knee_" + nm, hp, (0, 0, -2.3))
        limb("lab_" + nm, kn, 0.46, 0.36, 2.1, s.get("shin", s.get("legs", 'hose')), verts=8)
        box("labfej_" + nm, (0.8, 1.45, 0.55), (0, -0.35, -2.5), s.get("boots", 'boot'), bevel=0.15, parent=kn)
        if s.get("boots_tall"):
            cyl("csizma_" + nm, 0.46, 1.2, (0, 0, -2.2), s["boots"], verts=8, r2=0.48, parent=kn)
        if s.get("gaiters"):
            cyl("kamasli_" + nm, 0.45, 1.3, (0, 0, -2.3), s["gaiters"], verts=8, r2=0.47, parent=kn)
    return rig


# ---------------------------------------------------------------- fegyverek

def weapon_root(name):
    return empty(name)


def w_spear(p, length=22.0, up=0.72, head='steel'):
    u = length * up
    cyl("nyel", 0.2, length, (0, 0, -length + u), 'wood', verts=6, parent=p)
    cone("hegy", 0.45, 2.0, (0, 0, u), head, verts=6, parent=p)


def w_pike(p):
    w_spear(p, length=34.0, up=0.78)


def w_halberd(p):
    L = 24.0
    u = L * 0.75
    cyl("nyel", 0.2, L, (0, 0, -L + u), 'wood', verts=6, parent=p)
    cone("hegy", 0.35, 2.4, (0, 0, u), 'steel', verts=6, parent=p)
    box("balta", (0.25, 2.2, 1.8), (0, -1.0, u - 1.6), 'steel', bevel=0.1, parent=p)
    box("horog", (0.25, 1.0, 0.5), (0, 0.6, u - 1.0), 'steel', bevel=0.0, parent=p)


def w_crossbow(p):
    box("tus", (0.55, 0.6, 5.0), (0, 0, -1.6), 'wood', bevel=0.1, parent=p)
    box("iv", (5.2, 0.4, 0.4), (0, 0, 3.0), 'steel_d', bevel=0.1, parent=p)
    for sd in (-1, 1):
        ob = box(f"iv{sd}", (2.0, 0.35, 0.35), (sd * 2.6, 0, 2.55), 'steel_d', bevel=0.0, parent=p)
        ob.rotation_euler = (0, sd * R(-28), 0)
    box("hur", (5.4, 0.12, 0.12), (0, 0, 1.6), 'rope', bevel=0.0, parent=p)


def w_musket(p, length=11.0, bayonet=False, metal='iron'):
    box("tus", (0.5, 0.9, 3.0), (0, 0.1, -3.2), 'wood', bevel=0.12, parent=p)
    box("agy", (0.42, 0.55, length * 0.55), (0, 0, -0.4), 'wood', bevel=0.08, parent=p)
    cyl("cso", 0.17, length * 0.62, (0, 0, -0.4 + length * 0.1), metal, verts=6, parent=p)
    box("zar", (0.45, 0.5, 1.0), (0, -0.1, -0.2), 'iron', bevel=0.05, parent=p)
    if bayonet:
        cone("szurony", 0.16, 3.0, (0.25, 0, -0.4 + length * 0.72), 'steel', verts=4, parent=p)


def w_rifle(p, bayonet=False):
    w_musket(p, length=9.5, bayonet=bayonet)


def w_bazooka(p):
    cyl("cso", 0.45, 8.0, (0, 0, -4.0), 'olive_d', verts=10, parent=p)
    cyl("torkolat", 0.55, 0.8, (0, 0, 3.6), 'olive_d', verts=10, r2=0.6, parent=p)
    box("markolat", (0.3, 0.8, 1.0), (0, 0.5, -0.8), 'wood', bevel=0.05, parent=p)


def w_sword(p, length=4.8, curve=False):
    cyl("markolat", 0.18, 1.0, (0, 0, -0.5), 'leather', verts=6, parent=p)
    box("keresztvas", (1.4, 0.3, 0.25), (0, 0, 0.5), 'brass' if curve else 'steel_d', bevel=0.0, parent=p)
    if curve:
        for i in range(3):
            ob = box(f"penge{i}", (0.38, 0.12, length / 3 + 0.1), (0, -0.25 * i * i, 0.6 + i * length / 3),
                     'steel', bevel=0.03, parent=p)
            ob.rotation_euler = (R(8 * i), 0, 0)
    else:
        box("penge", (0.42, 0.12, length), (0, 0, 0.6), 'steel', bevel=0.05, parent=p)


def w_axe(p, big=False):
    L = 7.0 if big else 5.4
    cyl("nyel", 0.2, L, (0, 0, -1.2), 'wood', verts=6, parent=p)
    box("fej", (0.35, 2.2 if big else 1.5, 1.6 if big else 1.1), (0, -0.7, L - 2.0), 'steel', bevel=0.1, parent=p)


def w_pickaxe(p):
    cyl("nyel", 0.2, 5.6, (0, 0, -1.2), 'wood', verts=6, parent=p)
    ob = box("fej", (0.3, 4.0, 0.45), (0, 0, 4.2), 'iron', bevel=0.1, parent=p)
    ob.rotation_euler = (R(8), 0, 0)


def w_shovel(p):
    cyl("nyel", 0.2, 6.0, (0, 0, -1.4), 'wood', verts=6, parent=p)
    box("lapat", (1.5, 0.2, 2.0), (0, 0, 4.4), 'iron', bevel=0.1, parent=p)


def w_staff(p, cross=True):
    cyl("bot", 0.2, 12.0, (0, 0, -3.5), 'wood', verts=6, parent=p)
    if cross:
        box("kereszt1", (0.25, 0.25, 2.2), (0, 0, 8.3), 'gold', bevel=0.0, parent=p)
        box("kereszt2", (1.5, 0.25, 0.25), (0, 0, 9.5), 'gold', bevel=0.0, parent=p)


def w_book(p):
    box("konyv", (1.5, 0.5, 1.9), (0, 0, 0.3), 'black', bevel=0.1, parent=p)
    box("konyv_k", (0.2, 0.52, 1.1), (0, 0, 0.35), 'gold', bevel=0.0, parent=p)


def w_bag(p):
    box("taska", (1.8, 1.0, 1.4), (0, 0, -1.0), 'leather', bevel=0.3, parent=p)
    box("taska_k", (0.8, 1.05, 0.25), (0, 0, -0.9), 'redcross', bevel=0.0, parent=p)
    box("taska_k2", (0.25, 1.05, 0.8), (0, 0, -0.9), 'redcross', bevel=0.0, parent=p)
    cyl("taska_f", 0.1, 1.0, (0, 0, -0.4), 'leather', verts=4, parent=p)


def w_pistol(p):
    box("markolat", (0.35, 0.6, 1.0), (0, 0.2, -0.3), 'wood', bevel=0.08, parent=p)
    cyl("cso", 0.14, 1.8, (0, 0, 0.2), 'iron', verts=6, parent=p)


def w_dagger(p):
    cyl("markolat", 0.16, 0.8, (0, 0, -0.4), 'leather', verts=6, parent=p)
    box("penge", (0.3, 0.1, 1.9), (0, 0, 0.4), 'steel', bevel=0.03, parent=p)


def w_lance(p, length=26.0, pennant=True):
    up = length * 0.75
    cyl("landzsa", 0.3, length, (0, 0, -length + up), 'wood_l', verts=8, r2=0.18, parent=p)
    cyl("landzsa_v", 0.75, 1.6, (0, 0, -0.2), 'steel_d', verts=8, r2=0.3, parent=p)
    cone("landzsa_h", 0.35, 1.6, (0, 0, up), 'steel', verts=6, parent=p)
    if pennant:
        v = [(0.0, 0, up - 1.0), (0.0, 0, up - 4.5), (0.0, 3.8, up - 3.4), (0.0, 3.2, up - 2.2)]
        ob = mesh("landzsa_z", v, [(0, 1, 2, 3)], (0, 0, 0), 'team', parent=p)
        ob.modifiers.new("V", 'SOLIDIFY').thickness = 0.15


WEAPONS = {
    "spear": w_spear, "pike": w_pike, "halberd": w_halberd, "crossbow": w_crossbow,
    "musket": w_musket, "musket_bay": lambda p: w_musket(p, bayonet=True), "rifle": w_rifle,
    "rifle_bay": lambda p: w_rifle(p, bayonet=True), "bazooka": w_bazooka, "sword": w_sword,
    "rapier": lambda p: w_sword(p, 5.4), "sabre": lambda p: w_sword(p, 5.0, curve=True),
    "axe": w_axe, "bigaxe": lambda p: w_axe(p, big=True), "pickaxe": w_pickaxe, "shovel": w_shovel,
    "staff": w_staff, "book": w_book, "bag": w_bag, "pistol": w_pistol, "dagger": w_dagger,
    "lance": w_lance,
}


def shield_heater(parent, w=4.2, h=5.0):
    pts = [(-w / 2, 0, h * 0.35), (w / 2, 0, h * 0.35), (w / 2, 0, -h * 0.05), (w * 0.3, 0, -h * 0.45),
           (0, 0, -h * 0.65), (-w * 0.3, 0, -h * 0.45), (-w / 2, 0, -h * 0.05)]
    ob = mesh("pajzs", pts, [tuple(range(len(pts)))[::-1]], (0, 0, 0), 'team', parent=parent)
    ob.modifiers.new("V", 'SOLIDIFY').thickness = 0.35
    pv = [(-0.45, -0.2, h * 0.35), (0.45, -0.2, h * 0.35), (0.45, -0.2, -h * 0.6), (-0.45, -0.2, -h * 0.6)]
    ob2 = mesh("pajzs_p", pv, [(3, 2, 1, 0)], (0, 0, 0), 'accent', parent=parent)
    ob2.modifiers.new("V", 'SOLIDIFY').thickness = 0.1
    return ob


def pavise(parent):
    box("paveze", (3.3, 0.5, 5.0), (0, 0, -3.4), 'team', bevel=0.25, parent=parent)
    box("paveze_p", (0.8, 0.55, 4.6), (0, -0.05, -3.2), 'accent', bevel=0.1, parent=parent)


def grip_to(wroot, hand, root, local_rot, offset=(0, 0, 0)):
    """A fegyver gyökerét a kéz világbeli helyére teszi; a forgatás a test
    (root) terében értendő."""
    bpy.context.view_layer.update()
    hp = hand.matrix_world.translation
    rm = root.matrix_world.to_3x3().normalized()
    sc = root.matrix_world.to_scale()[0]
    m = rm @ Euler(local_rot).to_matrix()
    off = rm @ Vector(offset) * sc
    wroot.matrix_world = Matrix.Translation(hp + off) @ m.to_4x4() @ Matrix.Diagonal((sc, sc, sc, 1.0))


def fx_flash(name, parent, loc, size=1.0):
    """Torkolattűz + füstpamacs (csak a színmenetben)."""
    a = sphere(name, 0.9 * size, loc, 'fire', scale=(1, 1.6, 1), parent=parent, seg=8, rings=6)
    a["fx"] = True
    return a


def fx_smoke(name, loc, r=1.5, parent=None, light=True):
    ob = sphere(name, r, loc, 'smoke_l' if light else 'smoke', parent=parent, seg=10, rings=6)
    ob["fx"] = True
    return ob


# ---------------------------------------------------------------- pózok

def walk_legs(rig, t, leg_amp=0.55):
    ph = 2 * math.pi * t
    s = math.sin(ph)
    rig["hip_l"].rotation_euler = (-s * leg_amp, 0, 0)
    rig["hip_r"].rotation_euler = (s * leg_amp, 0, 0)
    kl = max(0.0, math.sin(ph + math.pi * 0.35)) * 0.9 + 0.05
    kr = max(0.0, math.sin(ph + math.pi * 1.35)) * 0.9 + 0.05
    rig["knee_l"].rotation_euler = (kl, 0, 0)
    rig["knee_r"].rotation_euler = (kr, 0, 0)
    rig["body"].location = (0, 0, abs(math.cos(ph)) * 0.22 - 0.1)
    rig["pelvis"].rotation_euler = (0.06, 0, s * 0.08)
    return s


def stand_pose(rig):
    rig.rest()
    rig["sh_l"].rotation_euler = (0.05, 0, -0.12)
    rig["sh_r"].rotation_euler = (0.05, 0, 0.12)
    rig["el_l"].rotation_euler = (-0.2, 0, 0)
    rig["el_r"].rotation_euler = (-0.2, 0, 0)
    rig["hip_l"].rotation_euler = (0, 0.04, 0)
    rig["hip_r"].rotation_euler = (0, -0.04, 0)
    rig["body"].location = (0, 0, 0)
    rig["fall"].location = (0, 0, 0)
    rig["fall"].rotation_euler = (0, 0, 0)


def lerp(a, b, t):
    return a + (b - a) * t


# Stílusonként a fegyveres kar pózai. Mindegyik függvény (rig, mode, t, s)
# és visszaadja a fegyver forgatását (Euler a test terében) és eltolását.

def arms_set(rig, shr=None, elr=None, shl=None, ell=None):
    if shr is not None:
        rig["sh_r"].rotation_euler = shr
    if elr is not None:
        rig["el_r"].rotation_euler = elr
    if shl is not None:
        rig["sh_l"].rotation_euler = shl
    if ell is not None:
        rig["el_l"].rotation_euler = ell


def pose_style(rig, style, mode, t, swing):
    """A fegyveres pózok. swing: a járás karlengése (-1..1). Visszaad:
    (grip Euler, grip eltolás, torkolattűz-e)."""
    fire = False
    g, off = (0, 0, 0), (0, 0, 0)
    if style in ("sword", "sword_shield", "dagger"):
        if mode == "attack":
            k = [(-2.6, -0.4, R(-35)), (-1.7, -0.2, R(55)), (-0.8, -0.1, R(110)), (-1.2, -0.5, R(40))][int(round(t * 3))]
            arms_set(rig, (k[0], 0, 0.15), (k[1], 0, 0))
            rig["pelvis"].rotation_euler = (0.12, 0, -0.1)
            g = (k[2], 0, 0)
        elif mode == "idle":
            arms_set(rig, (0.05, 0, 0.2), (-0.1, 0, 0))
            g = (R(165), 0, 0)
        else:
            arms_set(rig, (-0.45 - swing * 0.2, 0, 0.18), (-0.8, 0, 0))
            g = (R(20), 0, 0)
        if style == "sword_shield":
            arms_set(rig, shl=(-0.55, 0, -0.25), ell=(-1.1, 0, 0))
    elif style == "polearm":
        if mode == "attack":
            k = [(-0.7, -1.0, 0.0), (-1.35, -0.1, 3.0), (-1.4, 0.0, 3.4), (-1.0, -0.7, 1.0)][int(round(t * 3))]
            arms_set(rig, (k[0], 0, 0.1), (k[1], 0, 0), (-1.1, 0, 0.35), (-0.6, 0, 0))
            rig["pelvis"].rotation_euler = (0.2, 0, 0)
            rig["hip_l"].rotation_euler = (-0.5, 0, 0)
            rig["knee_l"].rotation_euler = (0.45, 0, 0)
            rig["hip_r"].rotation_euler = (0.35, 0, 0)
            g = (R(86), 0, 0)
            off = (0, -k[2] * 0.0, 0)
        elif mode == "idle":
            arms_set(rig, (-0.35, 0, 0.12), (-1.1, 0, 0))
            g = (0, 0, 0)
        else:
            arms_set(rig, (-0.3 - swing * 0.1, 0, 0.12), (-1.0, 0, 0))
            g = (R(-8), 0, 0)
    elif style == "halberd":
        if mode == "attack":
            k = [(-2.8, -0.3, R(-20)), (-2.0, -0.2, R(40)), (-1.1, -0.2, R(95)), (-1.4, -0.6, R(50))][int(round(t * 3))]
            arms_set(rig, (k[0], 0, 0.1), (k[1], 0, 0), (k[0] + 0.3, 0, -0.1), (k[1] - 0.3, 0, 0))
            rig["pelvis"].rotation_euler = (0.15, 0, 0)
            g = (k[2], 0, 0)
        elif mode == "idle":
            arms_set(rig, (-0.35, 0, 0.12), (-1.1, 0, 0))
            g = (0, 0, 0)
        else:
            arms_set(rig, (-0.3 - swing * 0.1, 0, 0.12), (-1.0, 0, 0))
            g = (R(-10), 0, 0)
    elif style == "crossbow":
        if mode == "attack":
            k = int(round(t * 3))
            if k <= 1:
                arms_set(rig, (-1.35, 0, 0.45), (-0.9, 0, 0), (-1.45, 0, -0.1), (-0.15, 0, 0))
                g, off = (R(90), 0, 0), (0, -0.4, 0.2)
            else:
                arms_set(rig, (-0.6, 0, 0.3), (-1.1, 0, 0), (-0.9, 0, -0.1), (-1.0, 0, 0))
                g = (R(140 if k == 3 else 115), 0, 0)
        else:
            arms_set(rig, (-0.55, 0, 0.3), (-1.0, 0, 0), (-0.75, 0, -0.1), (-1.0, 0, 0))
            g = (R(125 if mode != "idle" else 150), 0, 0)
    elif style in ("longgun", "rifle"):
        if mode == "attack":
            k = int(round(t * 3))
            if k <= 2:
                arms_set(rig, (-1.2, 0, 0.5), (-1.1, 0, 0), (-1.5, 0, -0.1), (-0.1, 0, 0))
                g, off = (R(90 - (6 if k == 1 else 0)), 0, 0), (0, -0.2, 0.3)
                fire = (k == 1)
            else:
                arms_set(rig, (-0.5, 0, 0.25), (-1.3, 0, 0), (-0.9, 0, -0.1), (-1.3, 0, 0))
                g = (R(10), 0, 0)
        elif mode == "idle":
            arms_set(rig, (-0.1, 0, 0.15), (-0.4, 0, 0))
            g = (0, 0, 0)
        else:
            arms_set(rig, (-0.5, 0, 0.3), (-1.1, 0, 0), (-0.9, 0, -0.1), (-1.2, 0, 0))
            g = (R(-25), R(-40), 0)
    elif style == "charge":          # szuronyroham (pikás/gránátos puskával)
        if mode == "attack":
            k = int(round(t * 3))
            ext = [0.0, 1.0, 1.0, 0.3][k]
            arms_set(rig, (-0.8 - ext * 0.5, 0, 0.3), (-1.0 + ext * 0.8, 0, 0), (-1.2, 0, -0.1), (-0.5, 0, 0))
            rig["pelvis"].rotation_euler = (0.2 + ext * 0.1, 0, 0)
            rig["hip_l"].rotation_euler = (-0.5, 0, 0)
            rig["knee_l"].rotation_euler = (0.45, 0, 0)
            g = (R(88), 0, 0)
        elif mode == "idle":
            arms_set(rig, (-0.1, 0, 0.15), (-0.4, 0, 0))
            g = (0, 0, 0)
        else:
            arms_set(rig, (-0.5, 0, 0.3), (-1.1, 0, 0), (-0.9, 0, -0.1), (-1.2, 0, 0))
            g = (R(-20), R(-35), 0)
    elif style == "bazooka":
        arms_set(rig, (-1.3, 0, 0.35), (-0.8, 0, 0), (-1.1, 0, -0.2), (-0.6, 0, 0))
        g, off = (R(88), 0, 0), (0.3, 0.6, 0.9)
        if mode == "attack":
            fire = int(round(t * 3)) == 1
        elif mode in ("walk", "idle"):
            g = (R(60), 0, 0)
    elif style == "tool":
        if mode == "attack":
            k = [(-2.8, -0.5, R(-50)), (-1.9, -0.2, R(40)), (-0.9, -0.2, R(115)), (-1.5, -0.4, R(60))][int(round(t * 3))]
            arms_set(rig, (k[0], 0, 0.1), (k[1], 0, 0), (k[0] + 0.3, 0, -0.1), (k[1] - 0.2, 0, 0))
            rig["pelvis"].rotation_euler = (0.18, 0, 0)
            g = (k[2], 0, 0)
        elif mode == "idle":
            arms_set(rig, (-0.5, 0, 0.2), (-0.9, 0, 0))
            g = (R(180), 0, 0)
        else:
            arms_set(rig, (-0.2 - swing * 0.2, 0, 0.12), (-0.9, 0, 0))
            g = (R(-65), 0, 0)
    elif style == "staff":
        if mode == "attack":
            up = [0.4, 1.0, 1.0, 0.6][int(round(t * 3))]
            arms_set(rig, (-1.2 - up * 1.4, 0, 0.2), (-0.3, 0, 0), (-1.0 - up * 1.3, 0, -0.35), (-0.3, 0, 0))
            g = (R(10), 0, 0)
        else:
            arms_set(rig, (-0.4 - swing * 0.1, 0, 0.12), (-1.0, 0, 0))
            g = (0, 0, 0)
    elif style == "book":
        if mode == "attack":
            up = [0.4, 1.0, 1.0, 0.6][int(round(t * 3))]
            arms_set(rig, (-1.2 - up * 0.8, 0, 0.3), (-0.6, 0, 0), (-1.3 - up * 1.2, 0, -0.35), (-0.2, 0, 0))
            g = (R(90), 0, 0)
        else:
            arms_set(rig, (-0.7, 0, 0.2), (-1.2, 0, 0), (-0.7, 0, -0.2), (-1.2, 0, 0))
            g = (R(60), 0, 0)
    elif style == "pistol":
        if mode == "attack":
            k = int(round(t * 3))
            arms_set(rig, (-1.5 + (0.3 if k == 3 else 0), 0, 0.15), (0.0, 0, 0))
            g = (R(90), 0, 0)
            fire = k == 1
        else:
            arms_set(rig, (0.0 - swing * 0.2, 0, 0.15), (-0.3, 0, 0))
            g = (R(170), 0, 0)
    elif style == "medic":
        if mode == "attack":         # letérdel és bekötöz
            rig["hip_l"].rotation_euler = (-1.5, 0, 0)
            rig["knee_l"].rotation_euler = (1.6, 0, 0)
            rig["hip_r"].rotation_euler = (0.2, 0, 0)
            rig["knee_r"].rotation_euler = (1.8, 0, 0)
            rig["body"].location = (0, 0, -1.9)
            rig["pelvis"].rotation_euler = (0.35, 0, 0)
            w = [0.0, 0.3, 0.6, 0.3][int(round(t * 3))]
            arms_set(rig, (-1.2 - w, 0, 0.2), (-0.8, 0, 0), (-1.3 + w, 0, -0.2), (-0.7, 0, 0))
            g = (R(180), 0, 0)
        else:
            arms_set(rig, (0.0 - swing * 0.3, 0, 0.12), (-0.2, 0, 0))
            g = (R(180), 0, 0)
    return g, off, fire


def death_pose(rig, t):
    """Hátraesés 4 kockában (t = 0, 1/3, 2/3, 1)."""
    k = int(round(t * 3))
    ang = [-18, -48, -78, -90][k]
    # átlósan hátra-oldalra dől: így egyik irányból se a nézés tengelyében fekszik
    rig["fall"].rotation_euler = (R(ang * 0.72), R(-ang * 0.72), 0)
    rig["fall"].location = (0, 0, [0.0, 0.1, 0.35, 0.55][k])
    kb = [0.4, 0.9, 0.5, 0.15][k]
    rig["hip_l"].rotation_euler = (-kb * 0.6, 0, 0)
    rig["hip_r"].rotation_euler = (-kb * 0.4, 0, 0.1)
    rig["knee_l"].rotation_euler = (kb, 0, 0)
    rig["knee_r"].rotation_euler = (kb * 0.8, 0, 0)
    arms_set(rig, (-1.8 * (k + 1) / 4, 0, 0.5), (-0.3, 0, 0), (-1.5 * (k + 1) / 4, 0, -0.6), (-0.3, 0, 0))
    rig["neck"].rotation_euler = (R([10, 25, 15, -10][k]), 0, 0)


# ---------------------------------------------------------------- gyalogos

class Infantry:
    ANIM = HUMAN_ANIM
    H = 20.0
    cell = (56, 56, 28, 40)          # w, h, ox, oy (világképpont)
    spec = {}
    weapon = None                    # WEAPONS kulcs a jobb kézben
    style = "sword"
    left = None                      # "shield" | "bag" | "book" | None
    back = None                      # "pavise" | "rifle" | "quiver" | None

    def build(self):
        self.root = empty("root")
        self.root.scale = (self.H / 10.0,) * 3
        self.rig = Rig()
        self.rig.j["root"] = self.root
        human(self.rig, self.root, self.spec)
        self.w = None
        if self.weapon:
            self.w = weapon_root("fegyver_g")
            WEAPONS[self.weapon](self.w)
        self.lw = None
        if self.left == "shield":
            sp = empty("pajzs_g", (-0.55, -0.2, -0.8), self.rig["el_l"])
            sp.rotation_euler = (0, R(90), 0)
            s2 = empty("pajzs_g2", (0, 0, 0), sp)
            s2.rotation_euler = (0, 0, R(90))
            shield_heater(s2, 3.6, 4.4)
        elif self.left in ("bag", "book"):
            self.lw = weapon_root("bal_g")
            WEAPONS[self.left](self.lw)
        pel = self.rig["pelvis"]
        if self.back == "pavise":
            pv = empty("paveze_g", (0, 1.35, 3.2), pel)
            pv.rotation_euler = (R(8), 0, 0)
            pavise(pv)
            box("tegez", (0.8, 0.8, 2.0), (1.3, 0.3, -1.6), 'leather', bevel=0.1, parent=pel)
        elif self.back == "rifle":
            g = empty("hat_puska", (0.3, 1.1, 1.0), pel)
            g.rotation_euler = (0, R(-30), 0)
            w_rifle(g)
        elif self.back == "basket":
            box("puttony", (1.9, 1.0, 2.4), (0, 1.25, 0.9), 'wood_l', bevel=0.2, parent=pel)
        self.extras()
        self.flash = None
        if self.w is not None and self.style in ("longgun", "rifle", "bazooka", "pistol"):
            tip = {"longgun": 7.6, "rifle": 7.0, "bazooka": 4.3, "pistol": 1.3}[self.style]
            self.flash = fx_flash("tuz", self.w, (0, 0, tip), 1.0 if self.style != "pistol" else 0.6)
            self.smoke = fx_smoke("fust", (0, 0, tip + 1.6), 1.2, parent=self.w)
            if self.style == "bazooka":
                self.back_flash = fx_smoke("fust_h", (0, 0, -5.5), 1.6, parent=self.w)
            else:
                self.back_flash = None
        self.bolt = None

    def extras(self):
        pass

    def set_dir(self, k):
        self.root.rotation_euler = (0, 0, dir_rot(k))

    def pose(self, mode, t=0.0, k=0):
        r = self.rig
        stand_pose(r)
        swing = 0.0
        if mode == "walk":
            swing = walk_legs(r, t)
            arms_set(r, shl=(swing * 0.45, 0, -0.08), ell=(-0.35, 0, 0))
        fire = False
        if mode == "death":
            death_pose(r, t)
            g, off = (R(150), 0, 0), (0, 0, 0)
        else:
            g, off, fire = pose_style(r, self.style, mode, t, swing)
        if self.w is not None:
            if mode == "death" and t > 0.9:
                # a fegyver kiesett a kézből: a földön fekszik mellette
                bpy.context.view_layer.update()
                rm = self.root.matrix_world.to_3x3().normalized()
                sc = self.root.matrix_world.to_scale()[0]
                p = self.root.matrix_world.translation + rm @ Vector((2.2, -1.5, 0.3)) * sc
                m = rm @ Euler((R(90), 0, R(70))).to_matrix()
                self.w.matrix_world = Matrix.Translation(p) @ m.to_4x4() @ Matrix.Diagonal((sc, sc, sc, 1.0))
            else:
                grip_to(self.w, r["hand_r"], self.root, g, off)
        if self.lw is not None:
            if mode == "death":
                grip_to(self.lw, r["hand_l"], self.root, (R(180), 0, 0))
            elif self.left == "book":
                grip_to(self.lw, r["hand_l"], self.root, (R(60), 0, 0))
            else:
                grip_to(self.lw, r["hand_l"], self.root, (0, 0, 0))
        if self.flash is not None:
            self.flash.hide_render = not fire
            self.smoke.hide_render = not (fire or (mode == "attack" and int(round(t * 3)) == 2))
            if self.back_flash is not None:
                self.back_flash.hide_render = not fire


def S(**kw):
    return kw


# --- munkás ---
class Worker0(Infantry):
    H = 18.0
    spec = S(torso='team', skirt='team', arm='linen', legs='hose', hat='straw', hat_band='accent', shoulder='team')
    weapon, style, back = "axe", "tool", "basket"


class Worker1(Infantry):
    H = 18.0
    spec = S(torso='linen', skirt='brown', arm='linen', legs='brown', hat='felt', hat_band='team',
             sash='team', boots='boot')
    weapon, style, back = "axe", "tool", "basket"


class Worker2(Infantry):
    H = 18.0
    spec = S(torso='linen', skirt='grey', arm='linen', legs='grey', hat='cap', cap_mat='team',
             apron='leather', boots='boot')
    weapon, style = "pickaxe", "tool"


class Worker3(Infantry):
    H = 18.0
    spec = S(torso='navy', skirt='navy', arm='linen', legs='navy', hat='cap', cap_mat='team',
             boots='boot', crossbelt='leather', armband='team')
    weapon, style = "shovel", "tool"


# --- közelharcos ---
class Melee0(Infantry):
    H = 22.0
    spec = S(torso='mail', skirt='mail', arm='mail', forearm='steel', tabard='team', tabard_trim='accent',
             legs='mail', shin='steel', hat='bascinet', boots='steel_d', hand='steel_d', shoulder='steel')
    weapon, style, left = "sword", "sword_shield", "shield"


class Melee1(Infantry):
    H = 22.0
    spec = S(torso='team', skirt='team', arm='team', breast='steel', legs='team', hat='morion',
             boots='boot', gaiters='white', cuffs='accent')
    weapon, style = "halberd", "halberd"


class Melee2(Infantry):          # utász: medvebőr süveg, bőrkötény, nagy fejsze
    H = 22.0
    spec = S(torso='team', skirt='team', arm='team', legs='white', hat='bearskin', apron='leather',
             crossbelt='white', boots='boot', gaiters='black', beard=True, cuffs='accent')
    weapon, style = "bigaxe", "tool"


class Spear0(Infantry):
    H = 21.0
    spec = S(torso='gambeson', skirt='gambeson', arm='gambeson', tabard='team', tabard_trim='accent',
             legs='hose', hat='kettle', boots='boot', boots_tall=True)
    weapon, style = "spear", "polearm"


class Spear1(Infantry):          # pikás: morion, mellvért, hosszú pika
    H = 21.0
    spec = S(torso='team', skirt='team', arm='team', breast='steel', legs='brown', hat='morion',
             boots='boot', cuffs='accent')
    weapon, style = "pike", "polearm"


class Spear2(Infantry):          # gránátos szuronnyal
    H = 21.0
    spec = S(torso='team', skirt='team', skirt_len=2.4, arm='team', legs='white', hat='shako',
             hat_band='accent', crossbelt='white', boots='boot', gaiters='black', lapels='accent',
             cuffs='accent')
    weapon, style = "musket_bay", "charge"


class Spear3(Infantry):          # páncéltörő rakétavetős
    H = 21.0
    spec = S(torso='olive', skirt='olive', arm='olive', legs='olive', hat='ww2', hat_band='team',
             boots='boot', boots_tall=True, backpack='olive_d', armband='team')
    weapon, style = "bazooka", "bazooka"


class Ranged0(Infantry):
    H = 20.0
    spec = S(torso='gambeson', skirt='gambeson', arm='gambeson', tabard='team', tabard_trim='accent',
             legs='hose', hat='sallet', boots='boot')
    weapon, style, back = "crossbow", "crossbow", "pavise"


class Ranged1(Infantry):         # muskétás: széles kalap tollal, vállszíj
    H = 20.0
    spec = S(torso='team', skirt='team', skirt_len=2.2, arm='team', legs='brown', hat='plumed',
             hat_band='team', plume='accent', crossbelt='leather', boots='boot', boots_tall=True, cuffs='accent')
    weapon, style = "musket", "longgun"


class Ranged2(Infantry):         # vadász (lövész) kepivel
    H = 20.0
    spec = S(torso='team', skirt='team', skirt_len=2.2, arm='team', legs='navy', hat='kepi', kepi_team=True,
             hat_band='team', crossbelt='black', boots='boot', cuffs='accent', backpack='leather')
    weapon, style = "rifle", "rifle"


class Ranged3(Infantry):
    H = 21.0
    spec = S(torso='olive', skirt='olive', arm='olive', legs='olive', hat='ww2', hat_band='team',
             boots='boot', boots_tall=True, backpack='olive_d', armband='team')
    weapon, style = "rifle", "rifle"


class Hero0(Infantry):
    H = 23.0
    spec = S(torso='steel', skirt='mail', arm='steel', forearm='steel', tabard='team', tabard_trim='accent',
             legs='steel', hat='crownhelm', boots='steel_d', hand='steel_d', shoulder='steel', cape='team')
    weapon, style, left = "sword", "sword_shield", "shield"


class Hero1(Infantry):
    H = 23.0
    spec = S(torso='team', skirt='team', skirt_len=2.4, arm='team', breast='steel', legs='brown',
             hat='plumed', hat_band='accent', plume='white', sash='accent', boots='boot', boots_tall=True,
             cape='team', cuffs='white')
    weapon, style = "rapier", "sword"


class Hero2(Infantry):
    H = 23.0
    spec = S(torso='team', skirt='team', skirt_len=2.6, arm='team', legs='white', hat='bicorne',
             sash='accent', epaulette='gold', boots='black', boots_tall=True, lapels='accent', cuffs='gold',
             braid='gold')
    weapon, style = "sabre", "sword"


class Hero3(Infantry):
    H = 23.0
    spec = S(torso='olive', skirt='olive', skirt_len=2.8, arm='olive', legs='olive', hat='peaked',
             hat_band='team', cap_mat='olive', crossbelt='leather', boots='black', boots_tall=True,
             epaulette='gold', lapels='team')
    weapon, style = "pistol", "pistol"


class Priest0(Infantry):
    H = 19.0
    spec = S(torso='brown', skirt='brown', skirt_len=4.4, arm='brown', legs='brown', hat='monk',
             hood_mat='brown', belt='rope', sash='team', boots='boot')
    weapon, style = "staff", "staff"


class Priest1(Infantry):
    H = 19.0
    spec = S(torso='black', skirt='black', skirt_len=4.4, arm='black', legs='black', hat='felt',
             hat_band='black', sash='team', boots='boot', cuffs='white')
    weapon, style, left = "staff", "staff", None


class Priest2(Infantry):
    H = 19.0
    spec = S(torso='black', skirt='black', skirt_len=4.4, arm='black', legs='black', hat='biretta',
             hat_band='team', sash='team', boots='boot', cuffs='white')
    weapon, style = "book", "book"


class Priest3(Infantry):
    H = 19.0
    spec = S(torso='olive', skirt='olive', skirt_len=2.2, arm='olive', legs='olive', hat='peaked',
             cap_mat='olive', hat_band='team', sash='team', armband='white', boots='boot', boots_tall=True)
    weapon, style = "book", "book"


class Spy0(Infantry):
    H = 19.0
    spec = S(torso='team_s', skirt='grey', arm='grey', legs='grey', hat='hood', hood_mat='team_s',
             cloak='grey', boots='boot')
    weapon, style = "dagger", "dagger"


class Spy1(Infantry):
    H = 19.0
    spec = S(torso='grey', skirt='grey', arm='grey', legs='black', hat='tricorne', hat_band='team',
             cloak='black', boots='boot', boots_tall=True)
    weapon, style = "dagger", "dagger"


class Spy2(Infantry):
    H = 19.0
    spec = S(torso='black', skirt='black', skirt_len=3.0, arm='black', legs='grey', hat='tophat',
             hat_band='team', lapels='white', boots='black', cuffs='white')
    weapon, style = "pistol", "pistol"


class Spy3(Infantry):
    H = 19.0
    spec = S(torso='ochre', skirt='ochre', skirt_len=3.4, arm='ochre', legs='grey', hat='fedora',
             hat_band='team', belt='brown', boots='black', lapels='ochre')
    weapon, style = "pistol", "pistol"


class Medic0(Infantry):
    H = 19.0
    spec = S(torso='linen', skirt='linen', arm='linen', legs='hose', hat='surgcap', apron='white',
             sash='team', boots='boot')
    weapon, style, left = None, "medic", "bag"


class Medic1(Infantry):
    H = 19.0
    spec = S(torso='team', skirt='team', skirt_len=2.4, arm='team', legs='brown', hat='tricorne',
             hat_band='white', apron='white', boots='boot', boots_tall=True)
    weapon, style, left = None, "medic", "bag"


class Medic2(Infantry):
    H = 19.0
    spec = S(torso='team', skirt='team', skirt_len=2.2, arm='team', legs='navy', hat='kepi', kepi_team=True,
             armband='redcross', apron='white', boots='boot')
    weapon, style, left = None, "medic", "bag"


class Medic3(Infantry):
    H = 19.0
    spec = S(torso='olive', skirt='olive', arm='olive', legs='olive', hat='medhelm', armband='redcross',
             boots='boot', boots_tall=True, sash='team')
    weapon, style, left = None, "medic", "bag"


# ---------------------------------------------------------------- lovas

def horse(rig, root, cap):
    """Ló a rig-be (világképpont, a ló -Y felé néz). cap: "full" (lovagi
    takaró), "saddle" (nyeregtakaró)."""
    hb = rig.add("h_body", root, (0, 0, 0))
    sphere("lotest", 1.0, (0, 0.5, 11.2), 'horse', scale=(3.4, 8.6, 3.9), parent=hb, seg=16, rings=10)
    nk = rig.add("h_neck", hb, (0, -6.6, 13.0))
    cyl("lonyak", 2.1, 7.5, (0, 0, 0), 'horse', verts=10, r2=1.5, parent=nk)
    hd = rig.add("h_head", nk, (0, 0, 7.2))
    ob = box("lofej", (2.3, 2.5, 5.2), (0, 0.4, 0.2), 'horse', bevel=0.8, parent=hd)
    ob.rotation_euler = (R(104), 0, 0)
    sphere("lofej_orr", 1.3, (0, -4.7, -1.2), 'horse', parent=hd, seg=8, rings=6)
    for sd in (-1, 1):
        cone(f"lofül{sd}", 0.45, 1.6, (sd * 0.8, 0.4, 0.5), 'horse', verts=6, parent=hd)
    box("sorény", (0.7, 1.4, 7.5), (0, 1.5, 0.2), 'horse_d', bevel=0.3, parent=nk)
    tl = rig.add("h_tail", hb, (0, 8.6, 12.6))
    cyl("lofarok", 0.9, 7.0, (0, 0, -7.0), 'horse_d', verts=8, r2=0.6, parent=tl)
    for nm, x, y in (("fl", -1.6, -4.6), ("fr", 1.6, -4.6), ("bl", -1.6, 5.4), ("br", 1.6, 5.4)):
        up = rig.add("h_" + nm, hb, (x, y, 10.0))
        limb("lc_" + nm, up, 1.1, 0.7, 5.2, 'horse', verts=8)
        lo = rig.add("h_" + nm + "2", up, (0, 0, -5.2))
        limb("ll_" + nm, lo, 0.62, 0.5, 4.2, 'horse', verts=8)
        cyl("lp_" + nm, 0.62, 0.7, (0, 0, -4.8), 'horse_d', verts=8, parent=lo)
    if cap == "full":
        ob = cyl("takaro", 3.9, 4.0, (0, 0.5, 8.4), 'team', verts=18, r2=3.7, parent=hb)
        ob.scale = (1.0, 2.25, 1.0)
        ob = cyl("takaro_sz", 4.0, 0.7, (0, 0.5, 8.2), 'accent', verts=18, r2=3.95, parent=hb)
        ob.scale = (1.0, 2.25, 1.0)
    else:
        ob = box("nyeregtakaro", (7.6, 6.0, 4.2), (0, 0.4, 10.6), 'team', bevel=0.6, parent=hb)
        box("nyeregtakaro_sz", (7.8, 6.2, 0.6), (0, 0.4, 10.5), 'accent', bevel=0.2, parent=hb)
    box("nyereg", (4.2, 4.4, 1.2), (0, 0.0, 14.6), 'leather', bevel=0.4, parent=hb)
    return hb


class Cavalry:
    ANIM = HUMAN_ANIM
    cell = (84, 84, 42, 62)
    H_RIDER = 18.0
    rider = {}
    weapon, style, cap, shield = "lance", "lance", "full", True
    back_rifle = False

    def build(self):
        self.root = empty("root")
        self.rig = Rig()
        self.rig.j["root"] = self.root
        self.fall = self.rig.add("fall", self.root, (0, 0, 0))
        horse(self.rig, self.fall, self.cap)
        rr = empty("lovas_g", (0, 0.6, 15.2 - 4.8 * self.H_RIDER / 10.0 + 0.3), self.rig["h_body"])
        rr.scale = (self.H_RIDER / 10.0,) * 3
        self.rider_root = rr
        self.hr = Rig()
        self.hr.j["root"] = rr
        human(self.hr, rr, self.rider)
        self.w = weapon_root("fegyver_g")
        WEAPONS[self.weapon](self.w)
        if self.shield:
            sp = empty("pajzs_g", (-0.55, -0.2, -0.8), self.hr["el_l"])
            sp.rotation_euler = (0, R(90), 0)
            s2 = empty("pajzs_g2", (0, 0, 0), sp)
            s2.rotation_euler = (0, 0, R(90))
            shield_heater(s2)
        if self.back_rifle:
            g = empty("hat_puska", (0.3, 1.1, 1.0), self.hr["pelvis"])
            g.rotation_euler = (0, R(-30), 0)
            w_rifle(g)

    def set_dir(self, k):
        self.root.rotation_euler = (0, 0, dir_rot(k))

    def pose(self, mode, t=0.0, k=0):
        r, h = self.rig, self.hr
        r.rest()
        h.rest()
        r["fall"].location = (0, 0, 0)
        r["h_neck"].rotation_euler = (R(38), 0, 0)
        r["h_tail"].rotation_euler = (R(25), 0, 0)
        r["h_body"].location = (0, 0, 0)
        for nm, sd in (("l", -1), ("r", 1)):
            h["hip_" + nm].rotation_euler = (-1.35, sd * -0.35, 0)
            h["knee_" + nm].rotation_euler = (1.45, 0, 0)
        h["sh_l"].rotation_euler = (-0.6, 0, -0.35)
        h["el_l"].rotation_euler = (-1.0, 0, 0)
        h["sh_r"].rotation_euler = (-0.35, 0, 0.15)
        h["el_r"].rotation_euler = (-1.0, 0, 0)
        grip = (R(-14), 0, 0) if self.style == "lance" else (R(30), 0, 0)
        if mode == "walk":
            ph = 2 * math.pi * t
            s = math.sin(ph)
            c = math.cos(ph)
            for nm, sg in (("fl", 1), ("br", 1), ("fr", -1), ("bl", -1)):
                r["h_" + nm].rotation_euler = (sg * s * 0.42, 0, 0)
                front = nm[0] == "f"
                bend = max(0.0, sg * c) * (0.9 if front else -0.7)
                r["h_" + nm + "2"].rotation_euler = (bend, 0, 0)
            r["h_body"].location = (0, 0, abs(s) * 0.5)
            r["h_neck"].rotation_euler = (R(38) + c * 0.06, 0, 0)
            r["h_tail"].rotation_euler = (R(25) + s * 0.1, 0, s * 0.15)
        elif mode == "attack":
            kk = int(round(t * 3))
            r["h_fl"].rotation_euler = (-0.5 - 0.2 * (kk % 2), 0, 0)
            r["h_fl2"].rotation_euler = (1.0, 0, 0)
            r["h_fr"].rotation_euler = (-0.3, 0, 0)
            r["h_fr2"].rotation_euler = (0.7, 0, 0)
            r["h_body"].rotation_euler = (0.06, 0, 0)
            if self.style == "lance":
                h["sh_r"].rotation_euler = (-0.25, 0, 0.35)
                h["el_r"].rotation_euler = (-1.35, 0, 0)
                h["pelvis"].rotation_euler = (0.18, 0, 0)
                grip = (R(84 - [6, 0, 0, 10][kk]), 0, R(8))
            else:
                a = [(-2.7, -0.3, R(-30)), (-1.8, -0.2, R(60)), (-0.8, -0.1, R(120)), (-1.3, -0.5, R(50))][kk]
                h["sh_r"].rotation_euler = (a[0], 0, 0.3)
                h["el_r"].rotation_euler = (a[1], 0, 0)
                h["pelvis"].rotation_euler = (0.1, 0, -0.15)
                grip = (a[2], 0, 0)
        elif mode == "idle":
            r["h_neck"].rotation_euler = (R(62), 0, 0)
            grip = (R(-4), 0, 0) if self.style == "lance" else (R(160), 0, 0)
        elif mode == "death":
            kk = int(round(t * 3))
            roll = [12, 40, 70, 86][kk]
            r["fall"].rotation_euler = (0, R(roll), 0)
            r["fall"].location = (0, 0, [0.0, 0.3, 1.4, 2.8][kk])
            for nm in ("fl", "fr", "bl", "br"):
                r["h_" + nm].rotation_euler = ([-0.3, -0.6, -0.4, -0.2][kk] * (1 if nm[0] == "f" else -1), 0, 0)
                r["h_" + nm + "2"].rotation_euler = (0.6 * (1 if nm[0] == "f" else -1), 0, 0)
            r["h_neck"].rotation_euler = (R([50, 70, 80, 90][kk]), 0, 0)
            h["sh_r"].rotation_euler = (-2.0, 0, 0.6)
            h["sh_l"].rotation_euler = (-1.6, 0, -0.8)
            h["pelvis"].rotation_euler = (R(-20 * kk), 0, 0)
            grip = (R(150), 0, R(40))
        grip_to(self.w, h["hand_r"], self.rider_root, grip)


class Cav0(Cavalry):
    rider = S(torso='mail', skirt='team', arm='mail', forearm='steel', tabard='team', tabard_trim='accent',
              legs='mail', shin='steel', hat='greathelm', plume='team', boots='steel_d', hand='steel_d',
              shoulder='steel')


class Cav1(Cavalry):             # vértes: mellvért, homárfarkú sisak, egyenes kard
    rider = S(torso='team', skirt='team', arm='team', breast='steel', legs='brown', hat='lobster',
              boots='boot', boots_tall=True, cuffs='accent', sash='accent')
    weapon, style, cap, shield = "rapier", "sabre", "saddle", False


class Cav2(Cavalry):             # huszár: kalpag, zsinóros mente, szablya
    rider = S(torso='team', skirt='team', arm='team', legs='navy', hat='kalpak', plume='accent',
              boots='black', boots_tall=True, braid='accent', cuffs='accent', epaulette='accent')
    weapon, style, cap, shield = "sabre", "sabre", "saddle", False


class Cav3(Cavalry):             # 20. századi lovas: rohamsisak, szablya, puska a háton
    rider = S(torso='olive', skirt='olive', arm='olive', legs='olive', hat='ww2', hat_band='team',
              boots='black', boots_tall=True, armband='team', crossbelt='leather')
    weapon, style, cap, shield = "sabre", "sabre", "saddle", False
    back_rifle = True


# ---------------------------------------------------------------- gépek

class Machine:
    """Tárgyakból összerakott gép (harckocsi, ostromgép, faltörő). A
    gyökér alatti "parts" lista elemeit a roncs-póz szórja szét."""
    ANIM = MACHINE_ANIM
    cell = (72, 72, 36, 46)

    def set_dir(self, k):
        self.root.rotation_euler = (0, 0, dir_rot(k))

    def wreck(self, t):
        """Roncs: szétdőlő részek, kiégett anyag, tűz és füst."""
        kk = int(round(t * 3))
        rnd = random.Random(7)
        if not hasattr(self, "_rest"):
            self._rest = {}
        for p in self.parts:
            if p.name not in self._rest:
                self._rest[p.name] = (tuple(p.location), tuple(p.rotation_euler))
            base = self._rest[p.name]
            f = [0.25, 0.6, 0.9, 1.0][kk]
            dx, dy = rnd.uniform(-1, 1), rnd.uniform(-1, 1)
            p.location = (base[0][0] + dx * 2.0 * f, base[0][1] + dy * 2.0 * f, base[0][2] - 0.6 * f)
            p.rotation_euler = (base[1][0] + rnd.uniform(-0.4, 0.4) * f, base[1][1] + rnd.uniform(-0.4, 0.4) * f,
                                base[1][2] + rnd.uniform(-0.3, 0.3) * f)
        self.set_burnt(kk >= 2)
        for i, fx in enumerate(self.wreck_fx):
            fx.hide_render = not (i <= kk + 1)

    def set_burnt(self, on):
        """Kiégett anyag a roncson (és vissza, a következő irány kockáihoz)."""
        if not hasattr(self, "_orig"):
            self._orig = {}
            rnd = random.Random(11)
            for ob in bpy.context.scene.objects:
                if ob.type == 'MESH' and not ob.get("fx") and not ob.get("catcher") and not ob.get("talaj") \
                        and not ob.get("elo"):
                    if ob.data.users > 1:
                        ob.data = ob.data.copy()
                    mats = list(ob.data.materials)
                    self._orig[ob.name] = (mats, [rnd.random() < 0.75 for _ in mats])
        burnt = M('burnt')
        for name, (mats, pick) in self._orig.items():
            ob = bpy.data.objects.get(name)
            if ob is None:
                continue
            for i, mt in enumerate(mats):
                hit = mt is not None and (mt.get("mask", [0, 0])[0] > 0.5 or pick[i])
                ob.data.materials[i] = burnt if (on and hit) else mt

    def reset_wreck(self):
        if hasattr(self, "_rest"):
            for p in self.parts:
                if p.name in self._rest:
                    base = self._rest[p.name]
                    p.location = base[0]
                    p.rotation_euler = base[1]
        if hasattr(self, "_orig"):
            self.set_burnt(False)

    def make_wreck_fx(self, h=8.0):
        self.wreck_fx = []
        for i, (x, y, z, r, m) in enumerate([(0, 0, h * 1.05, 3.0, 'fire'), (0.5, 0.5, h * 1.3, 2.2, 'ember'),
                                             (-1, 1, h * 1.4, 3.2, 'smoke'), (1, 2, h * 2.0, 4.0, 'smoke')]):
            if m in ('fire', 'ember'):
                ob = sphere(f"roncs_fx{i}", r, (x, y, z), m, scale=(1, 1, 1.3), seg=8, rings=6)
                ob["fx"] = True
            else:
                ob = fx_smoke(f"roncs_fx{i}", (x, y, z), r, light=False)
            ob.hide_render = True
            self.wreck_fx.append(ob)


class Tank(Machine):
    def build(self):
        self.root = empty("root")
        R_ = self.root
        L, W = 30.0, 16.0
        self.parts = []
        self.wheels = []
        for sd in (-1, 1):
            x = sd * (W / 2 - 2.2)
            self.parts.append(box(f"talp{sd}", (4.4, L, 4.8), (x, 0, 0.3), 'track', bevel=1.2, parent=R_))
            for i in range(5):
                w = cyl(f"kerek{sd}{i}", 1.8, 0.8, (x + sd * 2.3, -L / 2 + 4 + i * (L - 8) / 4, 2.5), 'tank_d',
                        verts=10, rot=(0, math.pi / 2, 0), base=False, parent=R_)
            box(f"sarvedo{sd}", (5.0, L + 1.0, 0.5), (x, 0, 5.1), 'tank', bevel=0.2, parent=R_)
        v = [(-W / 2 + 2.6, -L / 2 + 0.5, 4.0), (W / 2 - 2.6, -L / 2 + 0.5, 4.0), (W / 2 - 2.6, L / 2, 4.0),
             (-W / 2 + 2.6, L / 2, 4.0),
             (-W / 2 + 1.0, -L / 2 + 6.0, 9.0), (W / 2 - 1.0, -L / 2 + 6.0, 9.0), (W / 2 - 1.0, L / 2 - 1.0, 9.0),
             (-W / 2 + 1.0, L / 2 - 1.0, 9.0)]
        f = [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 6, 7), (3, 2, 1, 0)]
        mesh("test", v, f, (0, 0, 0), 'tank', parent=R_, bevel=0.5)
        box("motorracs", (8.0, 6.0, 0.4), (0, L / 2 - 5, 9.0), 'tank_d', bevel=0.1, parent=R_)
        tr = empty("torony_g", (0, 1.0, 9.0), R_)
        self.turret = tr
        self.parts.append(tr)
        cyl("torony", 6.2, 5.2, (0, 0, 0), 'tank', verts=18, r2=5.2, parent=tr, bevel=0.4)
        cyl("kupola", 1.9, 1.4, (1.6, 1.5, 5.2), 'tank', verts=12, r2=1.6, parent=tr)
        box("pajzs", (4.0, 2.0, 3.2), (0, -5.8, 0.9), 'tank', bevel=0.5, parent=tr)
        g = empty("cso_g", (0, -6.6, 2.4), tr)
        self.gun = g
        cyl("cso", 0.55, 12.0, (0, -6.0, 0), 'tank_d', verts=8, rot=(math.pi / 2, 0, 0), base=False, parent=g)
        cyl("cso_v", 0.8, 1.2, (0, -12.0, 0), 'tank_d', verts=8, rot=(math.pi / 2, 0, 0), base=False, parent=g)
        for sd in (-1, 1):
            cyl(f"jel{sd}", 1.8, 0.3, (sd * 5.75, 0, 2.6), 'accent', verts=14, rot=(0, math.pi / 2, 0), base=False,
                parent=tr)
            cyl(f"jel_b{sd}", 1.3, 0.35, (sd * 5.8, 0, 2.6), 'team', verts=14, rot=(0, math.pi / 2, 0), base=False,
                parent=tr)
            box(f"jel_t{sd}", (0.35, 3.2, 1.8), (sd * 6.9, 7.0, 6.8), 'team', bevel=0.1, parent=R_)
        cyl("jel_felul", 2.0, 0.2, (-1.8, -1.0, 5.2), 'team', verts=14, parent=tr)
        cyl("antenna", 0.1, 9.0, (-3.5, 3.5, 5.0), 'iron', verts=4, parent=tr)
        for i in range(3):
            box(f"tartaly{i}", (2.4, 2.0, 1.6), (-5.2 + i * 2.6, L / 2 - 1.8, 9.0), 'olive_d', bevel=0.3, parent=R_)
        self.flash = sphere("tuz", 1.0, (0, -13.8, 0), 'fire', scale=(1.6, 2.6, 1.6), parent=g)
        self.flash["fx"] = True
        self.smoke = [fx_smoke(f"fust{i}", (0, -15 - i * 2.5, 0.5 + i), 1.8 + i * 0.8, parent=g) for i in range(3)]
        self.dust = [fx_smoke(f"por{i}", (sd * 6.0, L / 2 + 2 + i, 1.2), 1.4, parent=R_)
                     for i, sd in enumerate((-1, 1))]
        self.make_wreck_fx(10)

    def pose(self, mode, t=0.0, k=0):
        self.reset_wreck()
        kk = int(round(t * 3))
        self.flash.hide_render = not (mode == "attack" and kk == 0)
        for i, s in enumerate(self.smoke):
            s.hide_render = not (mode == "attack" and 1 <= kk and i < kk)
        for d in self.dust:
            d.hide_render = mode != "walk"
        self.gun.location = (0, -6.6 + (1.0 if (mode == "attack" and kk <= 1) else 0.0), 2.4)
        self.root.location = (0, 0, (0.25 if (mode == "walk" and kk % 2) else 0.0))
        if mode == "death":
            self.wreck(t)
            self.turret.rotation_euler = (R(-8 * kk), R(10 * kk), R(25 * kk))
        else:
            for fx in self.wreck_fx:
                fx.hide_render = True


def wheel(name, r, w, loc, material, parent, spokes=6):
    """Küllős kerék az X tengelyre állítva."""
    g = empty(name, loc, parent)
    cyl(name + "_abr", r, w, (0, 0, 0), material, verts=16, rot=(0, math.pi / 2, 0), base=False, parent=g)
    # sötét belső tárcsa + világos küllőkereszt: ettől látszik, hogy a kerék forog
    gumi = material == 'rubber'
    cyl(name + "_koz", r * 0.78, w * 1.15, (0, 0, 0), 'tank_d' if gumi else 'iron', verts=14,
        rot=(0, math.pi / 2, 0), base=False, parent=g)
    for i in range(2):
        box(f"{name}_kullo{i}", (w * 1.3, r * 1.62, r * 0.24), (0, 0, 0), 'tank' if gumi else 'wood_l',
            bevel=0.0, parent=g, rot=(i * math.pi / 2, 0, 0), base=False)
    cyl(name + "_agy", r * 0.25, w * 1.6, (0, 0, 0), 'iron', verts=8, rot=(0, math.pi / 2, 0), base=False, parent=g)
    return g


# Az ostromgép kezelője korszakonként (fegyvertelen tüzér).
CREW_SPEC = [
    dict(torso='gambeson', skirt='gambeson', arm='gambeson', tabard='team', tabard_trim='accent',
         legs='hose', hat='kettle', boots='boot'),
    dict(torso='team', skirt='team', skirt_len=2.2, arm='team', legs='brown', hat='felt', hat_band='accent',
         boots='boot', boots_tall=True, cuffs='accent'),
    dict(torso='team', skirt='team', skirt_len=2.2, arm='team', legs='white', hat='shako', hat_band='accent',
         crossbelt='white', boots='boot', gaiters='black', cuffs='accent'),
    dict(torso='olive', skirt='olive', arm='olive', legs='olive', hat='ww2', hat_band='team', boots='boot',
         boots_tall=True, armband='team'),
]


def crew(name, loc, parent, spec, H=19.0):
    """Kezelő a gép mellé: saját bábu (Rig), a gép gyökeréhez kötve. A
    testrészei "elo" jelet kapnak, hogy a roncs kiégett anyaga ne fogja be."""
    root = empty(name, loc, parent)
    root.scale = (H / 10.0,) * 3
    rig = Rig()
    rig.j["root"] = root
    human(rig, root, spec)
    for ob in root.children_recursive:
        ob["elo"] = True
    return rig


def crew_pose(rig, mode, t, k, pull=False):
    """A kezelő pózai: tolja a gépet, elsüti (vagy kioldja), majd elesik."""
    stand_pose(rig)
    kk = int(round(t * 3))
    if mode == "walk":
        walk_legs(rig, k / 4.0, leg_amp=0.45)
        arms_set(rig, (-1.15, 0, 0.1), (-0.35, 0, 0), (-1.15, 0, -0.1), (-0.35, 0, 0))
        rig["pelvis"].rotation_euler = (0.22, 0, 0)
    elif mode == "attack":
        if pull:         # hajítógép: megrántja a kioldókötelet
            a = [(-1.5, -0.2), (-0.5, -1.2), (-0.3, -1.0), (-0.9, -0.6)][kk]
            arms_set(rig, (a[0], 0, 0.1), (a[1], 0, 0), (a[0], 0, -0.1), (a[1], 0, 0))
            rig["pelvis"].rotation_euler = ([0.2, -0.15, -0.1, 0.05][kk], 0, 0)
        else:            # ágyú: kanóc a gyújtólyukhoz, aztán elfordul a dörrenéstől
            a = [(-1.3, -0.1), (-0.6, -1.9), (-0.6, -1.9), (-0.3, -0.8)][kk]
            arms_set(rig, (a[0], 0, -0.25), (a[1], 0, 0), (-0.2 if kk == 0 else -0.6, 0, -0.1),
                     (-0.3 if kk == 0 else -1.9, 0, 0))
            rig["pelvis"].rotation_euler = ([0.15, -0.12, -0.1, 0.0][kk], 0, 0)
    elif mode == "death":
        death_pose(rig, t)
    else:
        arms_set(rig, (0.05, 0, 0.15), (-0.3, 0, 0), (0.05, 0, -0.15), (-0.3, 0, 0))


class Siege(Machine):
    """0 = hajítógép, 1 = bronzágyú lafétán, 2 = tábori löveg, 3 = vontatott
    löveg lövegpajzzsal."""
    age = 0

    def build(self):
        self.root = empty("root")
        a = self.age
        # A gép saját csomópont alatt van: az ágyú 1,3-szeres, hogy a mellette
        # álló kezelőhöz képest ne legyen játékszer (a kerék derékig érjen).
        R_ = empty("gep", (0, 0, 0), self.root)
        if a > 0:
            R_.scale = (1.3,) * 3
        self.parts = []
        self.wheels = []
        if a == 0:
            # alváz
            for sd in (-1, 1):
                self.parts.append(box(f"gerenda{sd}", (1.4, 20, 1.6), (sd * 4.0, 0, 2.2), 'wood', bevel=0.3, parent=R_))
                for i, y in enumerate((-7, 7)):
                    self.wheels.append(wheel(f"kerek{sd}{i}", 2.4, 1.0, (sd * 5.2, y, 2.4), 'wood', R_))
            for y in (-8, 0, 8):
                box(f"kereszt{y}", (9.4, 1.2, 1.2), (0, y, 2.6), 'wood', bevel=0.2, parent=R_)
            for sd in (-1, 1):
                ob = box(f"allvany{sd}", (1.2, 1.2, 10), (sd * 3.6, 1.5, 3.0), 'wood', bevel=0.2, parent=R_)
                ob.rotation_euler = (R(-12), 0, 0)
            box("tengely", (8.6, 1.0, 1.0), (0, 0.5, 12.2), 'iron', bevel=0.1, parent=R_)
            arm = empty("kar_g", (0, 0.5, 12.2), R_)
            self.arm = arm
            box("kar", (1.2, 1.2, 18), (0, 0, -3.0), 'wood', bevel=0.3, parent=arm)
            cyl("kanal", 1.9, 1.2, (0, 0, 14.5), 'wood', verts=10, r2=2.3, parent=arm)
            sphere("ko", 1.4, (0, 0, 16.0), 'stone', parent=arm, seg=8, rings=6)
            box("ellensuly", (4.5, 3.4, 3.4), (0, 0, -4.6), 'wood_l', bevel=0.5, parent=arm)
            self.parts.append(arm)
        else:
            # laféta és kerekek
            wr = 4.2 if a < 3 else 3.2
            wm = 'wood' if a < 3 else 'rubber'
            for sd in (-1, 1):
                self.wheels.append(wheel(f"kerek{sd}", wr, 0.8, (sd * 4.6, 1.0, wr), wm, R_))
            box("tengely", (9.8, 1.0, 1.0), (0, 1.0, wr), 'iron', bevel=0.1, parent=R_)
            trail_m = 'wood' if a < 3 else 'tank'
            if a < 3:
                # a lafétafarok hátrafelé a földre ereszkedik
                ob = box("farok", (2.4, 14, 1.8), (0, 8.0, 2.4), trail_m, bevel=0.3, parent=R_)
                ob.rotation_euler = (R(-13), 0, 0)
                self.parts.append(ob)
                box("farok_vas", (2.7, 1.2, 0.5), (0, 14.3, 0.9), 'iron', bevel=0.1, parent=R_)
            else:
                for sd in (-1, 1):
                    ob = box(f"farok{sd}", (1.4, 14, 1.4), (sd * 2.5, 8.0, 1.6), trail_m, bevel=0.3, parent=R_)
                    ob.rotation_euler = (R(-7), 0, sd * R(12))
                    self.parts.append(ob)
            box("bolcso", (3.4, 6.0, 2.4), (0, 0.5, wr + 0.6), trail_m, bevel=0.4, parent=R_)
            g = empty("cso_g", (0, 0.5, wr + 1.8), R_)
            self.gun = g
            bm = 'bronze' if a == 1 else ('iron' if a == 2 else 'tank_d')
            Lg = [0, 14, 15, 17][a]
            cyl("cso", 1.2 if a == 1 else 0.9, Lg, (0, 3.0, 0), bm, verts=12, r2=0.8 if a == 1 else 0.6,
                rot=(math.pi / 2, 0, 0), base=True, parent=g)
            cyl("cso_far", 1.3, 2.0, (0, 3.0, 0), bm, verts=12, rot=(-math.pi / 2, 0, 0), base=True, parent=g)
            if a == 1:
                cyl("cso_v", 1.1, 1.0, (0, -Lg + 3.4, 0), bm, verts=12, rot=(math.pi / 2, 0, 0), base=True, parent=g)
            if a == 3:
                box("lovegpajzs", (9.0, 0.5, 6.0), (0, -1.2, -2.0), 'tank', bevel=0.3, parent=g)
                cyl("csofek", 1.0, 1.6, (0, -Lg + 3.2, 0), 'tank_d', verts=8, rot=(math.pi / 2, 0, 0), base=True,
                    parent=g)
            g.rotation_euler = (R(-8 if a < 3 else -12), 0, 0)
            self.parts.append(g)
            # csapatszín: jelvény a laféta oldalán
            for sd in (-1, 1):
                cyl(f"jel{sd}", 1.1, 0.25, (sd * (1.35 if a < 3 else 1.8), 5.0, 3.6 if a < 3 else 2.6), 'team',
                    verts=12, rot=(0, math.pi / 2, 0), base=False, parent=R_)
            self.flash = sphere("tuz", 1.3, (0, -Lg + 1.5, 0), 'fire', scale=(1.5, 2.4, 1.5), parent=g)
            self.flash["fx"] = True
            self.smoke = [fx_smoke(f"fust{i}", (0, -Lg - 1 - i * 3, 0.8 + i), 2.2 + i, parent=g) for i in range(3)]
        if a == 0:
            # zászlócska a hajítógépen
            flag_small("zaszlo", (4.0, 9.5, 3.8), R_, h=9.0)
        # a kezelő a gép bal hátsó oldalánál áll
        self.crew = crew("kezelo", (-8.5, 9.0, 0) if a == 0 else (-9.5, 9.5, 0), self.root, CREW_SPEC[a])
        self.make_wreck_fx(8)

    def pose(self, mode, t=0.0, k=0):
        self.reset_wreck()
        kk = int(round(t * 3))
        crew_pose(self.crew, mode, t, k, pull=(self.age == 0))
        for i, w in enumerate(self.wheels):
            w.rotation_euler = (R((k * 22.5) if mode == "walk" else 0), 0, 0)
        if self.age == 0:
            ang = [-62, -62, 40, 10][kk] if mode == "attack" else -62
            self.arm.rotation_euler = (R(ang), 0, 0)
        else:
            self.flash.hide_render = not (mode == "attack" and kk == 0)
            for i, s in enumerate(self.smoke):
                s.hide_render = not (mode == "attack" and 1 <= kk and i < kk)
            base = R(-8 if self.age < 3 else -12)
            self.gun.location = (0, 0.5 + (1.2 if (mode == "attack" and kk <= 1) else 0.0),
                                 self.gun.location[2])
        if mode == "death":
            self.wreck(t)
        else:
            for fx in self.wreck_fx:
                fx.hide_render = True


def flag_small(name, loc, parent, h=8.0, material='team'):
    cyl(name + "_rud", 0.3, h, loc, 'wood', verts=6, parent=parent)
    v = [(0, 0, h), (0, 0, h - 3.0), (0, 4.0, h - 2.0), (0, 4.4, h - 0.6)]
    ob = mesh(name, v, [(0, 1, 2, 3)], loc, material, parent=parent)
    ob.modifiers.new("V", 'SOLIDIFY').thickness = 0.2


class Ram(Machine):
    """0-1 = fedett faltörő kos, 2 = vasalt kos-szekér, 3 = tolólapos
    páncélozott műszaki jármű."""
    age = 0

    def build(self):
        self.root = empty("root")
        R_ = self.root
        a = self.age
        self.parts = []
        self.wheels = []
        if a <= 2:
            wm = 'wood'
            for sd in (-1, 1):
                for i, y in enumerate((-7, 0, 7)):
                    self.wheels.append(wheel(f"kerek{sd}{i}", 2.4, 1.0, (sd * 5.6, y, 2.4), wm, R_))
            box("alvaz", (10.4, 22, 1.4), (0, 0, 2.6), 'wood', bevel=0.3, parent=R_)
            for sd in (-1, 1):
                for y in (-9, -3, 3, 9):
                    box(f"oszlop{sd}{y}", (1.0, 1.0, 9), (sd * 4.8, y, 3.8), 'wood', bevel=0.2, parent=R_)
            roof_m = 'hay' if a == 0 else ('leather' if a == 1 else 'iron')
            ob = gable_roof("teto", 10.2, 22.0, 5.5, (0, 0, 12.6), roof_m, over=0.8, thick=0.6, ridge_x=False, parent=R_)
            self.parts.append(ob)
            if a == 2:
                for y in (-8, -2, 4, 10):
                    box(f"vaspant{y}", (11.0, 0.6, 0.6), (0, y, 12.8), 'iron', bevel=0.0, parent=R_)
            log = empty("kos_g", (0, 0, 8.0), R_)
            self.log = log
            cyl("kos", 1.3, 26, (0, 4.0, 0), 'wood', verts=10, rot=(math.pi / 2, 0, 0), base=True, parent=log)
            cone("kos_fej", 1.8, 3.4, (0, -22.0, 0), 'iron', verts=10, parent=log).rotation_euler = (math.pi / 2, 0, 0)
            for sd in (-1, 1):
                cyl(f"lanc{sd}", 0.15, 4.6, (0, sd * 6.0, 0), 'iron', verts=4, parent=log)
            for sd in (-1, 1):
                box(f"pajzs{sd}", (0.3, 8.0, 3.0), (sd * 5.3, -6, 8.4), 'team', bevel=0.1, parent=R_)
            flag_small("zaszlo", (0, 9.0, 15.5), R_, h=7.0)
        else:
            L, W = 26.0, 14.0
            for sd in (-1, 1):
                x = sd * (W / 2 - 1.8)
                self.parts.append(box(f"talp{sd}", (3.6, L, 4.0), (x, 0, 0.3), 'track', bevel=1.0, parent=R_))
            v = [(-W / 2 + 2, -L / 2 + 2, 3.5), (W / 2 - 2, -L / 2 + 2, 3.5), (W / 2 - 2, L / 2, 3.5),
                 (-W / 2 + 2, L / 2, 3.5), (-W / 2 + 1, -L / 2 + 7, 9.5), (W / 2 - 1, -L / 2 + 7, 9.5),
                 (W / 2 - 1, L / 2 - 1, 9.5), (-W / 2 + 1, L / 2 - 1, 9.5)]
            f = [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 6, 7), (3, 2, 1, 0)]
            mesh("test", v, f, (0, 0, 0), 'tank', parent=R_, bevel=0.5)
            box("kabin", (6.0, 6.0, 3.0), (0, 2.0, 9.5), 'tank', bevel=0.5, parent=R_)
            box("reses", (4.0, 0.3, 0.6), (0, -1.1, 11.0), 'window', bevel=0.0, parent=R_)
            log = empty("kos_g", (0, -L / 2 - 1.0, 3.0), R_)
            self.log = log
            box("tololap", (W + 2, 1.2, 5.5), (0, -1.5, -1.0), 'tank_d', bevel=0.3, parent=log)
            for sd in (-1, 1):
                ob = box(f"kar{sd}", (1.0, 7.0, 1.0), (sd * 5, 3.0, 0.5), 'tank_d', bevel=0.2, parent=log)
            for sd in (-1, 1):
                box(f"jel{sd}", (0.3, 3.2, 2.0), (sd * (W / 2 - 0.9), 4.0, 6.5), 'team', bevel=0.1, parent=R_)
            cyl("jel_f", 1.8, 0.2, (0, 5.0, 11.2), 'team', verts=12, parent=R_)
        # a fedett kosnál a tűz a tető fölé kerül, különben a tető eltakarja
        self.make_wreck_fx(15 if a <= 2 else 9)

    def pose(self, mode, t=0.0, k=0):
        self.reset_wreck()
        kk = int(round(t * 3))
        for w in self.wheels:
            w.rotation_euler = (R((k * 22.5) if mode == "walk" else 0), 0, 0)
        if self.age <= 2:
            push = [2.0, -3.5, -2.0, 0.5][kk] if mode == "attack" else 0.0
            self.log.location = (0, push, 8.0)
        else:
            push = [0.0, -1.5, -1.0, 0.0][kk] if mode == "attack" else 0.0
            self.log.location = (0, -14.0 + push, 3.0)
        if mode == "death":
            self.wreck(t)
        else:
            for fx in self.wreck_fx:
                fx.hide_render = True


def _siege(a):
    return type(f"Siege{a}", (Siege,), {"age": a, "cell": (96, 88, 48, 54)})


def _ram(a):
    return type(f"Ram{a}", (Ram,), {"age": a, "cell": (72, 72, 36, 48)})


UNITS = {
    "worker_0": Worker0, "worker_1": Worker1, "worker_2": Worker2, "worker_3": Worker3,
    "melee_0": Melee0, "melee_1": Melee1, "melee_2": Melee2, "melee_3": Tank,
    "spear_0": Spear0, "spear_1": Spear1, "spear_2": Spear2, "spear_3": Spear3,
    "ranged_0": Ranged0, "ranged_1": Ranged1, "ranged_2": Ranged2, "ranged_3": Ranged3,
    "cav_0": Cav0, "cav_1": Cav1, "cav_2": Cav2, "cav_3": Cav3,
    "hero_0": Hero0, "hero_1": Hero1, "hero_2": Hero2, "hero_3": Hero3,
    "priest_0": Priest0, "priest_1": Priest1, "priest_2": Priest2, "priest_3": Priest3,
    "spy_0": Spy0, "spy_1": Spy1, "spy_2": Spy2, "spy_3": Spy3,
    "medic_0": Medic0, "medic_1": Medic1, "medic_2": Medic2, "medic_3": Medic3,
    "siege_0": _siege(0), "siege_1": _siege(1), "siege_2": _siege(2), "siege_3": _siege(3),
    "ram_0": _ram(0), "ram_1": _ram(1), "ram_2": _ram(2), "ram_3": _ram(3),
}
