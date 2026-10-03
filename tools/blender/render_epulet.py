# -*- coding: utf-8 -*-
# Épületek renderelése.
#   blender --background --python render_epulet.py -- <kimeneti mappa> [típus_korszak ...]
#   pl.  ... -- out hq_0 house_2 barracks_3   (alapból mind a 57)
# Épületenként három kép (+ _m.png maszk mindegyikhez):
#   <t>_<k>.png       kész épület
#   <t>_<k>_epit.png  építkezés (állvány, félig kész falak)
#   <t>_<k>_rom.png   súlyosan sérült (beszakadt tető, korom, törmelék)
# és <t>_<k>.json: a talppont (ox, oy), a felbontás (s), a kéményfüst pontjai
# ("fust") és a főváros zászlórúdjának csúcsa ("zaszlo") képpontban.
import os, sys, json, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bir_common as C
import bir_buildings as B0
import bir_buildings2 as B

a = C.args()
out = a[0]
os.makedirs(out, exist_ok=True)
kulcsok = [x for x in a[1:] if not x.startswith("--")] or [f"{t}_{k}" for (t, k) in B.BUILDERS]


def pont_kep(ob, ox, oy):
    fwd, up, right = C.cam_axes()
    p = ob.matrix_world.translation
    return [round(ox + p.dot(right) * C.PPU, 1), round(oy - p.dot(up) * C.PPU, 1)]


for key in kulcsok:
    t, k = key.rsplit("_", 1)
    info = {}
    for variant in ("", "_epit", "_rom"):
        C.reset_mats()
        C.reset_scene()
        C.shadow_catcher(900)
        B.BUILDERS[(t, int(k))]()
        if variant == "_epit":
            B0.make_construction(0.42, flat=t in B.FLAT)
        elif variant == "_rom":
            B.make_damage()
        ox, oy = C.frame_auto(pad=4)
        sc = C.bpy.context.scene
        fust = [pont_kep(o, ox, oy) for o in sc.objects if o.get("fust")]
        zaszlo = [pont_kep(o, ox, oy) for o in sc.objects if o.get("zaszlo")]
        dt = C.render_sprite(os.path.join(out, key + variant))
        info[variant or "kesz"] = {"ox": ox, "oy": oy, "w": sc.render.resolution_x, "h": sc.render.resolution_y,
                                   "fust": fust, "zaszlo": zaszlo[0] if zaszlo else None, "sec": round(dt, 1)}
        print(f"[epulet] {key}{variant}: {sc.render.resolution_x}x{sc.render.resolution_y} {dt:.1f} mp", flush=True)
    info["s"] = C.PPU
    json.dump({key: info}, open(os.path.join(out, key + ".json"), "w", encoding="utf-8"), indent=1)
