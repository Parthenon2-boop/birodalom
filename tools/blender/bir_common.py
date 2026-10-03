# -*- coding: utf-8 -*-
# BIRODALOM — BLENDERES GRAFIKAI CSŐVEZETÉK: KÖZÖS RÉSZ
#
# A jelenet (ortografikus 3/4-es kamera, meleg nap + égbolt-derítés, puha
# árnyék), az anyagok (kő, gerenda, cserép, zsúp, vakolat, posztó, fém...),
# a primitívek (lekerekített élű dobozok, hengerek, tetők) és a renderelés
# (Cycles színmenet + Workbench csapatszín-maszk + körvonal, levágás).
#
# EGYSÉG: 1 Blender-egység = 1 világképpont a játékban (Building.MERET és a
# Combat.RADIUS is ebben van). A render PPU képpont / egység (alapból 2, mint
# az assets/buildings_html 2x-es képei).
#
# KAMERA: észak felé néz (a Blender +Y = a játék "fel"), ELEV fokkal lefelé
# döntve, ortografikus. Így a talaj mélysége sin(ELEV)-vel rövidül: az épület
# telkét (w x h világképpont) ezért h / sin(ELEV) mélyre modellezzük, és a
# képen pontosan w x h lesz.
#
# CSAPATSZÍN-MASZK: minden anyagnak van (r, g) maszkértéke. A maszkmenet
# ezt rajzolja ki lapos színnel (R = csapatszín súlya, G = kiemelőszín súlya).
# A színmenetben a csapatszínű rész SEMLEGES világosszürke — a játék
# árnyalója színezi: rgb = mix(rgb, rgb * csapat * 1.6, m.r) (lásd a jelentést).

import bpy, bmesh, math, os, sys, json, time
import numpy as np
from mathutils import Vector, Matrix, Euler

ELEV = 50.0                     # a kamera dőlése a vízszinteshez (fok)
SIN_E = math.sin(math.radians(ELEV))
COS_E = math.cos(math.radians(ELEV))
PPU = 2.0                        # képpont / világképpont a renderen

# A nap iránya: BALRÓL-ELÖLRŐL süt (délnyugat, magasan) — a látható
# homlokzatok világosak, a vetett árnyék jobbra-hátra esik.
SUN_AZ = 215.0                   # fok, a +X tengelytől az óramutatóval ellentétesen (a nap FELÉ)
SUN_ALT = 52.0


# ---------------------------------------------------------------- jelenet

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for c in (bpy.data.meshes, bpy.data.materials, bpy.data.objects, bpy.data.images):
        for x in list(c):
            c.remove(x)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = int(os.environ.get('BIR_SAMPLES', '32'))
    sc.render.use_persistent_data = os.environ.get('BIR_PERSIST', '0') == '1'
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.03
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    sc.cycles.max_bounces = int(os.environ.get('BIR_BOUNCE', '4'))
    sc.cycles.diffuse_bounces = min(2, sc.cycles.max_bounces)
    sc.cycles.glossy_bounces = 1
    sc.cycles.transmission_bounces = 0
    sc.cycles.transparent_max_bounces = 4
    sc.cycles.filter_width = 1.0            # élesebb, mint az alap 1,5
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.image_settings.color_depth = '8'
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.0
    sc.render.resolution_percentage = 100
    # égbolt: halvány kék derítés (a háttér átlátszó, csak megvilágít)
    w = bpy.data.worlds.new("Eg")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.55, 0.68, 0.95, 1.0)
    bg.inputs[1].default_value = 0.8
    # nap
    sd = bpy.data.lights.new("Nap", 'SUN')
    sd.energy = 2.5
    sd.color = (1.0, 0.92, 0.80)
    sd.angle = math.radians(6.0)            # puha árnyékszél
    sun = bpy.data.objects.new("Nap", sd)
    sc.collection.objects.link(sun)
    d = sun_dir()
    sun.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    # kamera
    cd = bpy.data.cameras.new("Kamera")
    cd.type = 'ORTHO'
    cd.clip_start = 1.0
    cd.clip_end = 4000.0
    cam = bpy.data.objects.new("Kamera", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.rotation_euler = (math.radians(90.0 - ELEV), 0.0, 0.0)
    return sc


def sun_dir():
    """Egységvektor a nap FELÉ."""
    az, al = math.radians(SUN_AZ), math.radians(SUN_ALT)
    return Vector((math.cos(al) * math.cos(az), math.cos(al) * math.sin(az), math.sin(al)))


def cam_axes():
    e = math.radians(ELEV)
    fwd = Vector((0.0, math.cos(e), -math.sin(e)))
    up = Vector((0.0, math.sin(e), math.cos(e)))
    right = Vector((1.0, 0.0, 0.0))
    return fwd, up, right


def shadow_catcher(size=400.0):
    me = bpy.data.meshes.new("Talaj")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=size / 2)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Talaj", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.is_shadow_catcher = True
    ob["catcher"] = True
    return ob


def shadow_disc(r):
    """Kis, kör alakú árnyékfogó a talppont körül, az árnyék irányába tolva.
    A teljes képet fedő fogó drága (minden képpont árnyéksugarat lő), a
    kis egységeknél ez négyszeres gyorsulás."""
    s = sun_dir()
    d = Vector((-s.x, -s.y, 0.0))
    d.normalize()
    me = bpy.data.meshes.new("Talaj")
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=24, radius=r)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Talaj", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = d * r * 0.4
    ob.is_shadow_catcher = True
    ob["catcher"] = True
    return ob


# ---------------------------------------------------------------- színek, anyagok

def srgb(h):
    """'#rrggbb' -> lineáris (r, g, b, 1)."""
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    lin = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return (lin[0], lin[1], lin[2], 1.0)


def _lin1(x):
    return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4


_MATS = {}


def _new_mat(name, mask):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    # a maszkmenet (Workbench, lapos) ezt a színt írja ki: R = csapat, G = kiemelő
    mb = mask[2] if len(mask) > 2 else 0.0
    m.diffuse_color = (_lin1(mask[0]), _lin1(mask[1]), _lin1(mb), 1.0)
    m["mask"] = list(mask)
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type != 'OUTPUT_MATERIAL':
            nt.nodes.remove(n)
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    out = [n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'][0]
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    return m, nt, bsdf


def _wall_vec(nt, sx=1.0, sy=1.0):
    """(x + y, z) — a függőleges falakon folytonos 2D koordináta."""
    geo = nt.nodes.new('ShaderNodeNewGeometry')
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(geo.outputs['Position'], sep.inputs[0])
    add = nt.nodes.new('ShaderNodeMath')
    add.operation = 'ADD'
    nt.links.new(sep.outputs[0], add.inputs[0])
    nt.links.new(sep.outputs[1], add.inputs[1])
    comb = nt.nodes.new('ShaderNodeCombineXYZ')
    mx = nt.nodes.new('ShaderNodeMath'); mx.operation = 'MULTIPLY'; mx.inputs[1].default_value = sx
    my = nt.nodes.new('ShaderNodeMath'); my.operation = 'MULTIPLY'; my.inputs[1].default_value = sy
    nt.links.new(add.outputs[0], mx.inputs[0])
    nt.links.new(sep.outputs[2], my.inputs[0])
    nt.links.new(mx.outputs[0], comb.inputs[0])
    nt.links.new(my.outputs[0], comb.inputs[1])
    return comb.outputs[0]


def _noise_mix(nt, vec, scale, c1, c2, detail=2.0):
    nz = nt.nodes.new('ShaderNodeTexNoise')
    nz.inputs['Scale'].default_value = scale
    nz.inputs['Detail'].default_value = detail
    if vec is not None:
        nt.links.new(vec, nz.inputs['Vector'])
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[0].color = c1
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = c2
    nt.links.new(nz.outputs['Fac'], ramp.inputs[0])
    return ramp.outputs[0]


def mat(key, kind='plain', col='#808080', col2=None, rough=0.85, metal=0.0, mask=(0.0, 0.0),
        scale=1.0, emit=None):
    """Anyag a gyorsítótárból (kulcs szerint)."""
    if key in _MATS:
        return _MATS[key]
    m, nt, bsdf = _new_mat(key, mask)
    c1 = srgb(col)
    c2 = srgb(col2) if col2 else tuple(min(1.0, x * 1.25) for x in c1[:3]) + (1.0,)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    base = None
    bump_in = None
    if kind == 'plain':
        bsdf.inputs['Base Color'].default_value = c1
    elif kind == 'noise':          # finom foltosság (vakolat, posztó, bőr)
        base = _noise_mix(nt, None, 0.35 * scale, c1, c2)
        geo = nt.nodes.new('ShaderNodeNewGeometry')
        nz = base.node.inputs[0].links[0].from_node
        nt.links.new(geo.outputs['Position'], nz.inputs['Vector'])
    elif kind in ('stone', 'brick', 'tiles'):
        vec = _wall_vec(nt, 1.0, 1.0)
        br = nt.nodes.new('ShaderNodeTexBrick')
        nt.links.new(vec, br.inputs['Vector'])
        if kind == 'stone':         # faragott kőtömbök
            br.inputs['Scale'].default_value = 0.16 * scale
            br.inputs['Mortar Size'].default_value = 0.035
            br.inputs['Brick Width'].default_value = 0.9
            br.inputs['Row Height'].default_value = 0.45
            br.inputs['Mortar'].default_value = srgb('#6b6358')
        elif kind == 'brick':       # tégla (19-20. század)
            br.inputs['Scale'].default_value = 0.42 * scale
            br.inputs['Mortar Size'].default_value = 0.04
            br.inputs['Brick Width'].default_value = 0.6
            br.inputs['Row Height'].default_value = 0.25
            br.inputs['Mortar'].default_value = srgb('#b8ad9c')
        else:                       # tetőcserép / zsindely
            br.inputs['Scale'].default_value = 0.30 * scale
            br.inputs['Mortar Size'].default_value = 0.06
            br.inputs['Brick Width'].default_value = 0.45
            br.inputs['Row Height'].default_value = 0.30
            br.inputs['Mortar'].default_value = tuple(x * 0.45 for x in c1[:3]) + (1.0,)
        br.offset = 0.5
        br.inputs['Color1'].default_value = c1
        br.inputs['Color2'].default_value = c2
        base = br.outputs['Color']
        bump_in = br.outputs['Fac']
    elif kind == 'wood':           # deszka/gerenda: nyújtott zaj
        geo = nt.nodes.new('ShaderNodeNewGeometry')
        mp = nt.nodes.new('ShaderNodeMapping')
        mp.inputs['Scale'].default_value = (0.25 * scale, 0.25 * scale, 2.5 * scale)
        nt.links.new(geo.outputs['Position'], mp.inputs[0])
        base = _noise_mix(nt, mp.outputs[0], 1.0, c1, c2, detail=4.0)
    elif kind == 'thatch':         # zsúp: függőleges csíkos
        geo = nt.nodes.new('ShaderNodeNewGeometry')
        mp = nt.nodes.new('ShaderNodeMapping')
        mp.inputs['Scale'].default_value = (2.2 * scale, 2.2 * scale, 0.25 * scale)
        nt.links.new(geo.outputs['Position'], mp.inputs[0])
        base = _noise_mix(nt, mp.outputs[0], 1.0, c1, c2, detail=5.0)
        nz = base.node.inputs[0].links[0].from_node
        bump_in = nz.outputs['Fac']
    elif kind == 'field':          # gabonatábla: sorok
        geo = nt.nodes.new('ShaderNodeNewGeometry')
        wv = nt.nodes.new('ShaderNodeTexWave')
        wv.wave_type = 'BANDS'
        wv.bands_direction = 'Y'
        wv.inputs['Scale'].default_value = 0.08 * scale
        wv.inputs['Distortion'].default_value = 1.5
        nt.links.new(geo.outputs['Position'], wv.inputs['Vector'])
        ramp = nt.nodes.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].color = c1
        ramp.color_ramp.elements[1].color = c2
        nt.links.new(wv.outputs['Fac'], ramp.inputs[0])
        base = ramp.outputs[0]
        bump_in = wv.outputs['Fac']
    if base is not None:
        nt.links.new(base, bsdf.inputs['Base Color'])
    if bump_in is not None:
        bump = nt.nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = 0.35
        nt.links.new(bump_in, bump.inputs['Height'])
        nt.links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    if emit:
        bsdf.inputs['Emission Color'].default_value = srgb(emit)
        bsdf.inputs['Emission Strength'].default_value = 2.0
    _MATS[key] = m
    return m


def reset_mats():
    _MATS.clear()


# A közös anyagkészlet (a nevek a modellezőkben ezekre hivatkoznak).
def M(name):
    tbl = {
        # épületek
        'stone':    dict(kind='stone', col='#b9ae98', col2='#d6ccb4'),
        'stone_d':  dict(kind='stone', col='#8f8676', col2='#a79d8a'),
        'cobble':   dict(kind='stone', col='#9a9282', col2='#b4ab98', scale=1.8),
        'plaster':  dict(kind='noise', col='#e8dcc0', col2='#f3ead4', scale=1.0),
        'timber':   dict(kind='wood', col='#4a3220', col2='#654630'),
        'wood':     dict(kind='wood', col='#8a6034', col2='#a87a48'),
        'wood_l':   dict(kind='wood', col='#b08a58', col2='#c9a46e'),
        # cseréptető: SEMLEGES szürke, a nemzeti tetőszínt a játék árnyalója adja (maszk B)
        'roof':     dict(kind='tiles', col='#aaa49c', col2='#c4beb4', mask=(0.0, 0.0, 1.0)),
        'roof_red': dict(kind='tiles', col='#a2452e', col2='#bd5a3a'),
        'roof_d':   dict(kind='tiles', col='#5b5f6b', col2='#6e7380'),     # pala
        'shingle':  dict(kind='tiles', col='#6e4e32', col2='#86613f', scale=1.3),
        'thatch':   dict(kind='thatch', col='#b89250', col2='#d6b36a'),
        'door':     dict(kind='wood', col='#5a3a22', col2='#704a2c'),
        'window':   dict(kind='plain', col='#232a33', rough=0.3),
        'window_l': dict(kind='plain', col='#e6b760', emit='#ffb84a'),
        'iron':     dict(kind='plain', col='#4a4d52', rough=0.45, metal=0.7),
        'gold':     dict(kind='plain', col='#d9ae3c', rough=0.35, metal=0.9),
        'dirt':     dict(kind='noise', col='#8a7150', col2='#a08560', scale=0.6),
        'field':    dict(kind='field', col='#c9a24a', col2='#e2c46a'),
        'field_g':  dict(kind='field', col='#7a9a3a', col2='#a6bf55'),
        'hay':      dict(kind='thatch', col='#c9a44e', col2='#e6c96e'),
        'rope':     dict(kind='plain', col='#b79a5e'),
        'canvas':   dict(kind='noise', col='#e4dcc6', col2='#f2ecda'),
        'brick':    dict(kind='brick', col='#9c4a36', col2='#b35c42'),
        'concrete': dict(kind='noise', col='#a8a59c', col2='#bdbab0', scale=1.4),
        'sandbag':  dict(kind='noise', col='#b5a27a', col2='#c9b88e', scale=2.0),
        'tarpaper': dict(kind='noise', col='#3e4044', col2='#4c4f54'),
        # csapatszín (semleges világos; a játék színezi) és kiemelőszín
        'team':     dict(kind='noise', col='#dcdcdc', col2='#f0f0f0', mask=(1.0, 0.0), scale=2.0),
        'team_s':   dict(kind='noise', col='#c8c8c8', col2='#dedede', mask=(0.45, 0.0), scale=2.0),
        'accent':   dict(kind='plain', col='#e8e8e8', mask=(0.0, 1.0), rough=0.5),
        # alakok
        'skin':     dict(kind='plain', col='#e0ae84', rough=0.7),
        'hair':     dict(kind='plain', col='#4a3020'),
        'linen':    dict(kind='noise', col='#d8cfb8', col2='#e8e0cc', scale=3.0),
        'tunic':    dict(kind='noise', col='#7a6a4a', col2='#8e7c58', scale=3.0),
        'hose':     dict(kind='plain', col='#5a4a3a'),
        'leather':  dict(kind='plain', col='#6a4a2c', rough=0.6),
        'boot':     dict(kind='plain', col='#3a2a1c', rough=0.6),
        'steel':    dict(kind='plain', col='#b4b8bf', rough=0.3, metal=0.9),
        'steel_d':  dict(kind='plain', col='#7c8088', rough=0.35, metal=0.85),
        'mail':     dict(kind='noise', col='#8c9096', col2='#a4a8ae', rough=0.45, metal=0.7, scale=12.0),
        'gambeson': dict(kind='noise', col='#cfc3a2', col2='#ddd3b6', scale=3.0),
        'horse':    dict(kind='noise', col='#6b4428', col2='#7d5232', scale=2.0),
        'horse_d':  dict(kind='plain', col='#2e2018'),
        'olive':    dict(kind='noise', col='#5d6340', col2='#6b724c', scale=3.0, mask=(0.12, 0.0)),
        'olive_d':  dict(kind='plain', col='#454a32'),
        'helmet3':  dict(kind='plain', col='#565c42', rough=0.55, metal=0.3),
        'tank':     dict(kind='noise', col='#5f6647', col2='#6d7552', scale=0.5, mask=(0.1, 0.0), rough=0.6),
        'tank_d':   dict(kind='plain', col='#3c4030', rough=0.7),
        'track':    dict(kind='plain', col='#35332f', rough=0.8, metal=0.3),
        'rubber':   dict(kind='plain', col='#232322'),
        # --- bővítés (B fázis) ---
        'white':    dict(kind='noise', col='#e6e2d8', col2='#f4f1ea', scale=3.0),
        'black':    dict(kind='noise', col='#24232a', col2='#302f36', scale=3.0),
        'brown':    dict(kind='noise', col='#6b4a2e', col2='#7c5838', scale=3.0),
        'grey':     dict(kind='noise', col='#6e6c68', col2='#7e7c78', scale=3.0),
        'navy':     dict(kind='noise', col='#2c3550', col2='#36405e', scale=3.0),
        'felt':     dict(kind='plain', col='#2e2622', rough=0.9),
        'fur':      dict(kind='noise', col='#1c1a18', col2='#2e2a26', scale=6.0),
        'redcross': dict(kind='plain', col='#c8201e'),
        'brass':    dict(kind='plain', col='#c9a04a', rough=0.35, metal=0.85),
        'bronze':   dict(kind='plain', col='#9a6a3a', rough=0.4, metal=0.85),
        'glass':    dict(kind='plain', col='#8fb4c8', rough=0.1),
        'burnt':    dict(kind='noise', col='#1e1c1a', col2='#3a3430', scale=1.5),
        'ember':    dict(kind='plain', col='#ff8a2a', emit='#ff7a1a'),
        'fire':     dict(kind='plain', col='#ffcf5a', emit='#ffb040'),
        'smoke':    dict(kind='noise', col='#5a5856', col2='#8a8886', scale=1.0),
        'smoke_l':  dict(kind='noise', col='#bdbab4', col2='#e0ddd6', scale=1.0),
        'foam':     dict(kind='plain', col='#f4f8fa'),
        'hull':     dict(kind='wood', col='#6a4a2c', col2='#7e5a36'),
        'hull_d':   dict(kind='wood', col='#3e2c1c', col2='#4c3622'),
        'hull_b':   dict(kind='plain', col='#22221f', rough=0.6),
        'deck':     dict(kind='wood', col='#b08a5a', col2='#c49e6c', scale=0.6),
        'sail':     dict(kind='noise', col='#e8e0cc', col2='#f4eee0', scale=0.5, mask=(0.22, 0.0)),
        'sail_w':   dict(kind='noise', col='#e8e0cc', col2='#f4eee0', scale=0.5),
        'steel_h':  dict(kind='noise', col='#6f777f', col2='#7c848c', scale=0.3, rough=0.55, metal=0.4),
        'steel_hd': dict(kind='plain', col='#4c535a', rough=0.6, metal=0.4),
        'redhull':  dict(kind='plain', col='#7a2a22', rough=0.7),
        'funnel':   dict(kind='plain', col='#242424', rough=0.7),
        'plane':    dict(kind='noise', col='#5f6647', col2='#6a7152', scale=0.5, mask=(0.1, 0.0), rough=0.5),
        'plane_u':  dict(kind='plain', col='#8a98a4', rough=0.5),
        'prop':     dict(kind='plain', col='#b8b8b0', rough=0.5),
        'corrug':   dict(kind='brick', col='#7c8288', col2='#8c9298', scale=3.0),
        'asphalt':  dict(kind='noise', col='#4a4a48', col2='#565654', scale=0.8),
        'palm':     dict(kind='thatch', col='#7a8a3a', col2='#9aa84a'),
        'leaves':   dict(kind='noise', col='#4e7a2e', col2='#62923a', scale=0.5),
        'cane':     dict(kind='field', col='#6a9a34', col2='#8cbc4a'),
        'gold_ore': dict(kind='noise', col='#6a6258', col2='#d9ae3c', scale=2.0),
        'water':    dict(kind='plain', col='#3e6a8a', rough=0.15),
        'marble':   dict(kind='noise', col='#e8e4da', col2='#f6f3ec', scale=0.4),
        'copper':   dict(kind='noise', col='#5f9a82', col2='#72ae94', scale=0.4),
        'ochre':    dict(kind='noise', col='#d8b878', col2='#e6c88a', scale=1.0),    }
    return mat(name, **tbl[name])


# ---------------------------------------------------------------- primitívek

def _link(me, name, material, parent=None, loc=(0, 0, 0)):
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if material is not None:
        ob.data.materials.append(M(material) if isinstance(material, str) else material)
    ob.location = loc
    if parent is not None:
        ob.parent = parent
    return ob


def _bevel(ob, w, seg=1):
    if w <= 0:
        return ob
    md = ob.modifiers.new("Bevel", 'BEVEL')
    md.width = w
    md.segments = seg
    md.limit_method = 'ANGLE'
    md.angle_limit = math.radians(35)
    md.harden_normals = False
    return ob


def box(name, size, loc=(0, 0, 0), material='stone', bevel=0.35, parent=None, rot=None, base=True):
    """Doboz; alapból a talpa van a loc magasságában (base=True)."""
    sx, sy, sz = size
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    if base:
        bmesh.ops.translate(bm, vec=(0, 0, sz / 2), verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    ob = _link(me, name, material, parent, loc)
    if rot:
        ob.rotation_euler = rot
    return _bevel(ob, min(bevel, min(size) * 0.3))


def cyl(name, r, h, loc=(0, 0, 0), material='stone', verts=16, r2=None, bevel=0.0, parent=None,
        rot=None, base=True, smooth=True):
    """Henger vagy csonkakúp (r2 = felső sugár). A talpa a loc-ban."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=verts,
                          radius1=r, radius2=(r if r2 is None else r2), depth=h)
    if base:
        bmesh.ops.translate(bm, vec=(0, 0, h / 2), verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    ob = _link(me, name, material, parent, loc)
    if rot:
        ob.rotation_euler = rot
    if smooth:
        _smooth(ob)
    return _bevel(ob, bevel)


def cone(name, r, h, loc=(0, 0, 0), material='roof', verts=16, parent=None, smooth=True):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=verts, radius1=r,
                          radius2=0.0, depth=h)
    bmesh.ops.translate(bm, vec=(0, 0, h / 2), verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    ob = _link(me, name, material, parent, loc)
    if smooth:
        _smooth(ob)
    return ob


def sphere(name, r, loc=(0, 0, 0), material='skin', scale=(1, 1, 1), parent=None, seg=12, rings=8):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    bmesh.ops.scale(bm, vec=scale, verts=bm.verts)
    bm.to_mesh(me)
    bm.free()
    ob = _link(me, name, material, parent, loc)
    _smooth(ob)
    return ob


def mesh(name, verts, faces, loc=(0, 0, 0), material='roof', parent=None, smooth=False, bevel=0.0):
    me = bpy.data.meshes.new(name)
    me.from_pydata([Vector(v) for v in verts], [], faces)
    me.validate()
    me.update()
    ob = _link(me, name, material, parent, loc)
    if smooth:
        _smooth(ob)
    return _bevel(ob, bevel)


def _smooth(ob):
    for p in ob.data.polygons:
        p.use_smooth = True


def gable_roof(name, w, d, h, loc, material='roof', over=2.0, thick=1.2, ridge_x=True, parent=None):
    """Nyeregtető: a gerinc az X (ridge_x) vagy az Y tengely mentén. loc = a tető talpa."""
    if ridge_x:
        hw, hd = w / 2 + over, d / 2 + over
        v = [(-hw, -hd, 0), (hw, -hd, 0), (hw, 0, h), (-hw, 0, h), (hw, hd, 0), (-hw, hd, 0),
             (-hw, -hd, -thick), (hw, -hd, -thick), (hw, hd, -thick), (-hw, hd, -thick)]
        f = [(0, 1, 2, 3), (3, 2, 4, 5), (0, 6, 7, 1), (5, 4, 8, 9), (1, 7, 8, 4, 2), (0, 3, 5, 9, 6),
             (6, 9, 8, 7)]
    else:
        hw, hd = w / 2 + over, d / 2 + over
        v = [(-hw, -hd, 0), (0, -hd, h), (0, hd, h), (-hw, hd, 0), (hw, -hd, 0), (hw, hd, 0),
             (-hw, -hd, -thick), (-hw, hd, -thick), (hw, hd, -thick), (hw, -hd, -thick)]
        f = [(0, 1, 2, 3), (1, 4, 5, 2), (0, 6, 9, 4, 1), (3, 2, 5, 8, 7), (0, 3, 7, 6), (4, 9, 8, 5),
             (6, 7, 8, 9)]
    return mesh(name, v, f, loc, material, bevel=0.25, parent=parent)


def gable_wall(name, w, h, loc, material='plaster', ridge_x=True, thick=1.0):
    """A nyeregtető alatti háromszögű oromfal-pár kitöltése."""
    if ridge_x:
        v = [(-w / 2, -thick / 2, 0), (w / 2, -thick / 2, 0), (0, -thick / 2, h)]
    obs = []
    return None


def hip_roof(name, w, d, h, loc, material='roof', over=2.0, parent=None):
    hw, hd = w / 2 + over, d / 2 + over
    r = max(0.0, hw - hd) if hw > hd else 0.0
    if hw >= hd:
        v = [(-hw, -hd, 0), (hw, -hd, 0), (hw, hd, 0), (-hw, hd, 0), (-hw + hd, 0, h), (hw - hd, 0, h)]
        f = [(0, 1, 5, 4), (1, 2, 5), (2, 3, 4, 5), (3, 0, 4), (0, 3, 2, 1)]
    else:
        v = [(-hw, -hd, 0), (hw, -hd, 0), (hw, hd, 0), (-hw, hd, 0), (0, -hd + hw, h), (0, hd - hw, h)]
        f = [(0, 1, 4), (1, 2, 5, 4), (2, 3, 5), (3, 0, 4, 5), (0, 3, 2, 1)]
    return mesh(name, v, f, loc, material, bevel=0.2, parent=parent)


def empty(name, loc=(0, 0, 0), parent=None):
    ob = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    if parent is not None:
        ob.parent = parent
    return ob


def parent_all(root, objs=None):
    """Minden szülő nélküli objektumot (a kamera, nap, talaj kivételével) a root alá tesz."""
    for ob in bpy.context.scene.objects:
        if ob is root or ob.parent is not None or ob.type in ('CAMERA', 'LIGHT') or ob.get("catcher"):
            continue
        ob.parent = root


# ---------------------------------------------------------------- keretezés

def _world_points(depsgraph=None):
    pts = []
    dg = bpy.context.evaluated_depsgraph_get()
    for ob in bpy.context.scene.objects:
        if ob.type != 'MESH' or ob.get("catcher") or ob.hide_render:
            continue
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ob.matrix_world
        for v in me.vertices:
            pts.append(mw @ v.co)
        ev.to_mesh_clear()
    return pts


def frame_auto(pad=3, with_shadow=True):
    """A kamerát és a felbontást a jelenet köré szabja. Visszaadja a talppont
    (világ-origó) képpont-helyét a képen: (ox, oy)."""
    bpy.context.view_layer.update()
    fwd, up, right = cam_axes()
    pts = _world_points()
    if with_shadow:
        s = sun_dir()
        extra = []
        for p in pts:
            if p.z > 0.01:
                t = p.z / s.z
                extra.append(Vector((p.x - s.x * t, p.y - s.y * t, 0.0)))
        pts += extra
    xs = [p.dot(right) for p in pts]
    ys = [p.dot(up) for p in pts]
    left = math.floor(min(xs) * PPU) - pad
    rightp = math.ceil(max(xs) * PPU) + pad
    bottom = math.floor(min(ys) * PPU) - pad
    top = math.ceil(max(ys) * PPU) + pad
    return frame_fixed(rightp - left, top - bottom, -left, top)


def frame_fixed(w, h, ox, oy):
    """w x h képpont, a világ-origó az (ox, oy) képponton (y lefelé)."""
    sc = bpy.context.scene
    sc.render.resolution_x = int(w)
    sc.render.resolution_y = int(h)
    cam = sc.camera
    cam.data.ortho_scale = max(w, h) / PPU
    fwd, up, right = cam_axes()
    cx = (w / 2 - ox) / PPU            # a kép közepe a jobbra-tengelyen
    cy = (oy - h / 2) / PPU            # ... és a fel-tengelyen
    cam.location = -fwd * 1500.0 + right * cx + up * cy
    return (int(ox), int(oy))


# ---------------------------------------------------------------- render

def _load_px(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]
    bpy.data.images.remove(img)
    return a


def save_px(arr, path):
    h, w = arr.shape[:2]
    img = bpy.data.images.new("tmp_save", w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(arr[::-1]).astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)


def _dilate(a, r=1):
    out = a.copy()
    h, w = a.shape
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx == 0 and dy == 0:
                continue
            sh = np.zeros_like(a)
            ys = slice(max(0, dy), h + min(0, dy))
            yd = slice(max(0, -dy), h + min(0, -dy))
            xs = slice(max(0, dx), w + min(0, dx))
            xd = slice(max(0, -dx), w + min(0, -dx))
            sh[yd, xd] = a[ys, xs]
            out = np.maximum(out, sh)
    return out


OUTLINE = (0.10, 0.08, 0.06)
OUTLINE_A = 0.75


def _mask_pass_setup(sc):
    sc.render.engine = 'BLENDER_WORKBENCH'
    sh = sc.display.shading
    sh.light = 'FLAT'
    sh.color_type = 'MATERIAL'
    sh.show_object_outline = False
    sh.show_cavity = False
    sh.show_shadows = False
    sh.show_specular_highlight = False
    sc.display.render_aa = '16'


def render_frame(tmp_base, outline=True, cycles_alpha=False):
    """Egy kocka: színmenet (Cycles, árnyékkal) + maszkmenet (Workbench, lapos).
    Visszaad: (szín RGBA, maszk RGBA) numpy tömbök (fentről lefelé sorokkal).
    A maszk R = csapatszín, G = kiemelőszín, B = nemzeti tetőszín súlya.
    Az "fx" jelű tárgyak (tűz, füst, torkolattűz) a maszkból kimaradnak.
    cycles_alpha: árnyékfogó nélküli jelenetben (hajó, repülő) a körvonal a
    színmenet alfájából jön — a víz alá merülő részt a maszkmenet nem látja."""
    sc = bpy.context.scene
    tmp_c = tmp_base + "__c.png"
    tmp_m = tmp_base + "__m.png"
    sc.render.engine = 'CYCLES'
    sc.render.filepath = tmp_c
    bpy.ops.render.render(write_still=True)
    _mask_pass_setup(sc)
    hidden = []
    for ob in sc.objects:
        if (ob.get("catcher") or ob.get("talaj") or ob.get("fx")) and not ob.hide_render:
            ob.hide_render = True
            hidden.append(ob)
    sc.render.filepath = tmp_m
    bpy.ops.render.render(write_still=True)
    for ob in hidden:
        ob.hide_render = False
    sc.render.engine = 'CYCLES'
    col = _load_px(tmp_c)
    mk = _load_px(tmp_m)
    for p in (tmp_c, tmp_m):
        try:
            os.remove(p)
        except OSError:
            pass
    obj_a = mk[..., 3]
    if cycles_alpha:
        obj_a = np.minimum(obj_a, col[..., 3])
    else:
        # az árnyékfogó a távoli talajra is halvány "égbolt-takarást" tesz —
        # ezt levágjuk, különben a sprite téglalapja látszana a talajon
        sa = col[..., 3]
        col[..., 3] = np.where(obj_a < 0.01, np.clip((sa - 0.07) / 0.93, 0.0, 1.0), sa)
    if outline:
        dil = _dilate((obj_a > 0.5).astype(np.float32), 1)
        ring = np.clip(dil - obj_a, 0.0, 1.0) * OUTLINE_A
        a0 = col[..., 3]
        out = np.empty_like(col)
        oa = ring + a0 * (1 - ring)
        out[..., 3] = oa
        for i in range(3):
            prem = col[..., i] * a0 * (1 - ring) + OUTLINE[i] * ring
            out[..., i] = np.where(oa > 1e-5, prem / np.maximum(oa, 1e-5), 0.0)
        k = obj_a[..., None]
        out[..., :3] = np.where(k > 0.99, col[..., :3], out[..., :3])
        out[..., 3] = np.where(obj_a > 0.99, col[..., 3], out[..., 3])
        col = out
    m = np.zeros_like(mk)
    for i in range(3):
        m[..., i] = mk[..., i] * mk[..., 3]
    m[..., 3] = 1.0
    return col, m


def render_sprite(path_base, outline=True, mask=True):
    """Egyetlen kép: <path_base>.png (RGBA) és <path_base>_m.png (RGB maszk).
    Visszaadja a render idejét mp-ben."""
    t0 = time.time()
    col, m = render_frame(path_base, outline)
    save_px(col, path_base + ".png")
    if mask:
        save_px(m, path_base + "_m.png")
    return time.time() - t0


def water_holdout(size=2000.0):
    """Vízfelszín a hajókhoz: minden, ami a z = 0 sík alatt van, átlátszó lesz."""
    me = bpy.data.meshes.new("Viz")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=size / 2)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Viz", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.is_holdout = True
    ob["talaj"] = True
    return ob

def args():
    a = sys.argv
    return a[a.index("--") + 1:] if "--" in a else []
