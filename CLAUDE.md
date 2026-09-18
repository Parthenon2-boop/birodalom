# Birodalom – Godot 4 Port

## A FELADAT
Epitsd fel a teljes Godot 4 projektet elolrol. Ez egy 1400-1945 strategiai
RTS jatek portja HTML5/Canvas+JS-bol. Minden fajlt te hozol letre es irsz meg.
Ha valami hianyzik, kerdezz – de altalaban elegendo informacio van itt.

---

## PROJEKT ALAPADATOK

- **Motor**: Godot 4.x, GDScript
- **Platform**: Windows 10+ es macOS 12+
- **Vilag merete**: 3400 x 2400 pixel
- **Kod cella**: 32 pixel (fog of war rács)
- **Korszakok**: 4 db (index 0-3)
  - 0 = 15. szazad (Kozepkor, LPC sprite-ok)
  - 1 = 17. szazad (Napoleoni, sajat sprite-ok)
  - 2 = 19-20. szazad (WW2, WW2 sprite-ok)
  - 3 = Modern kor (WW2 alap, mas statisztikak)
- **Eroforrasok**: wood, stone, gold, food, coal, rum

---

## PROJEKT BEALLITASOK (project.godot)

```
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[application]
config/name="Birodalom"
run/main_scene="res://scenes/Main.tscn"

[autoload]
GameState="*res://scripts/globals/GameState.gd"
SFX="*res://scripts/globals/SFX.gd"
SaveManager="*res://scripts/globals/SaveManager.gd"
```

Input Map (Project Settings > Input Map):
- move_left: A, Left
- move_right: D, Right
- move_up: W, Up
- move_down: S, Down
- select: Left Mouse Button
- deselect: Escape
- pause: Space, P
- scroll_zoom_in: Mouse Wheel Up
- scroll_zoom_out: Mouse Wheel Down
- pan_drag: Middle Mouse Button

---

## MAPPASTRUKTURA

Az alabbi struktura PONTOSAN igy kell (hozd letre):

```
res://
|-- scenes/
|   |-- Main.tscn
|   |-- units/
|   |   |-- Unit.tscn
|   |   `-- Projectile.tscn
|   |-- buildings/
|   |   `-- Building.tscn
|   |-- world/
|   |   |-- Terrain.tscn
|   |   `-- FogOfWar.tscn
|   `-- ui/
|       |-- HUD.tscn
|       |-- Menu.tscn
|       `-- Tooltip.tscn
|-- scripts/
|   |-- globals/
|   |   |-- GameState.gd     <- AUTOLOAD
|   |   |-- SFX.gd           <- AUTOLOAD
|   |   `-- SaveManager.gd   <- AUTOLOAD
|   |-- world/
|   |   |-- WorldGen.gd
|   |   |-- Terrain.gd
|   |   `-- FogOfWar.gd
|   |-- units/
|   |   |-- Unit.gd
|   |   |-- UnitSprite.gd
|   |   `-- Combat.gd
|   |-- buildings/
|   |   `-- Building.gd
|   |-- ai/
|   |   `-- BotAI.gd
|   |-- systems/
|   |   |-- ResourceSystem.gd
|   |   `-- NavSystem.gd
|   `-- ui/
|       |-- HUD.gd
|       `-- Menu.gd
|-- assets/
|   |-- sprites/
|   |   |-- lpc/
|   |   |-- napoleon/
|   |   |-- ww2/
|   |   `-- ship/
|   |-- audio/
|   `-- shaders/
|       |-- water.gdshader
|       `-- fog.gdshader
`-- Main.gd
```

---

## AUTOLOAD SCRIPTEK

### res://scripts/globals/GameState.gd

```gdscript
extends Node

# === VILAG ===
const WORLD_W: int = 3400
const WORLD_H: int = 2400
const FOG_CELL: int = 32

# === JATEKALLPOT ===
var start_age: int = 0
var nation: String = "hu"
var on: bool = false
var over: bool = false
var t: float = 0.0
var sim_mag: int = 0
var diff: int = 0
var pirate: bool = false

# === OLDALAK ===
var oldalak: Array[Dictionary] = []
var en_id: int = 0

signal resources_changed
signal era_changed(owner_id: int, new_age: int)

func new_game(nation_key: String, chosen_age: int) -> void:
    sim_mag = (Time.get_ticks_msec() ^ randi()) & 0x7FFFFFFF
    nation = nation_key
    start_age = chosen_age
    on = true
    over = false
    t = 0.0
    oldalak.clear()
    en_id = 0
    add_oldal("ember", true,  nation_key, 0, chosen_age)
    add_oldal("bot",   false, "de",       1, chosen_age)

func add_oldal(tipus: String, helyi: bool, nemzet: String,
               csapat: int, age: int) -> Dictionary:
    var o := {
        "i": oldalak.size(),
        "tipus": tipus,
        "helyi": helyi,
        "nemzet": nemzet,
        "csapat": csapat,
        "age": age,
        "res": default_res(age),
        "upg": {"weapon": 0, "armor": 0, "supply": 0},
        "wave": 0,
        "waveT": 115.0,
        "rate": 1.0,
    }
    oldalak.append(o)
    return o

func get_side(id: int = -1) -> Dictionary:
    var idx := en_id if id < 0 else id
    return oldalak[idx] if idx < oldalak.size() else {}

func get_age(owner_id: int = -1) -> int:
    return get_side(owner_id).get("age", 0)

func advance_era(owner_id: int) -> void:
    var side := get_side(owner_id)
    if side.is_empty() or side["age"] >= 3: return
    side["age"] += 1
    era_changed.emit(owner_id, side["age"])

func get_res(owner_id: int = -1) -> Dictionary:
    return get_side(owner_id).get("res", default_res(0))

func add_res(owner_id: int, resource: String, amount: float) -> void:
    var res := get_res(owner_id)
    res[resource] = maxf(0.0, res.get(resource, 0.0) + amount)
    resources_changed.emit()

func pay(owner_id: int, costs: Dictionary) -> bool:
    var res := get_res(owner_id)
    for key in costs:
        if res.get(key, 0.0) < costs[key]: return false
    for key in costs:
        res[key] -= costs[key]
    resources_changed.emit()
    return true

func default_res(age: int) -> Dictionary:
    var mul := [1.0, 1.9, 3.1, 4.6][clamp(age, 0, 3)]
    return {
        "wood":  int(500 * mul),
        "stone": int(380 * mul),
        "gold":  int(300 * mul),
        "food":  int(420 * mul),
        "coal":  int(150 * mul) if age >= 2 else 0,
        "rum":   0,
    }
```

### res://scripts/globals/SFX.gd

```gdscript
extends Node

var _players: Dictionary = {}
var _music: AudioStreamPlayer = null

const SOUNDS := ["click","age","attack","build","death","cannon","sword","arrow"]

func _ready() -> void:
    for s in SOUNDS:
        var p := AudioStreamPlayer.new()
        p.bus = "SFX"
        add_child(p)
        _players[s] = p
        var path := "res://assets/audio/%s.ogg" % s
        if ResourceLoader.exists(path):
            p.stream = load(path)
    _music = AudioStreamPlayer.new()
    _music.bus = "Music"
    add_child(_music)

func play(sound: String, vol_db: float = 0.0) -> void:
    if _players.has(sound) and _players[sound].stream:
        _players[sound].volume_db = vol_db
        _players[sound].play()

func set_sfx_on(on: bool) -> void:
    AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not on)

func set_music_on(on: bool) -> void:
    AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not on)
```

### res://scripts/globals/SaveManager.gd

```gdscript
extends Node

const SAVE_PATH := "user://save.json"

func save_game() -> void:
    var data := {
        "version": "1.0",
        "start_age": GameState.start_age,
        "nation": GameState.nation,
        "diff": GameState.diff,
        "oldalak": GameState.oldalak,
        "t": GameState.t,
        "sim_mag": GameState.sim_mag,
    }
    var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if f:
        f.store_string(JSON.stringify(data, "\t"))
        f.close()

func load_game() -> bool:
    if not FileAccess.file_exists(SAVE_PATH): return false
    var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if not f: return false
    var data = JSON.parse_string(f.get_as_text())
    f.close()
    if not data is Dictionary: return false
    GameState.start_age = data.get("start_age", 0)
    GameState.nation    = data.get("nation", "hu")
    GameState.diff      = data.get("diff", 0)
    GameState.oldalak   = data.get("oldalak", [])
    GameState.t         = data.get("t", 0.0)
    return true

func has_save() -> bool:
    return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
    DirAccess.remove_absolute(SAVE_PATH)
```

---

## EGYSEG ADATOK

### Egyseg tipusok es statisztikak korszakonkent [age0, age1, age2, age3]

```
Tipus       HP                  DMG               Speed            Naval
worker      [45,50,58,66]       [3,3,4,4]         [64,66,70,76]    false
melee       [95,125,160,340]    [11,15,20,38]     [72,74,76,60]    false
ranged      [55,70,88,105]      [8,14,19,7]       [62,62,64,62]    false
spear       [78,98,118,124]     [9,13,17,30]      [58,60,62,56]    false
cav         [80,100,120,190]    [10,14,18,26]     [118,124,132,150] false
priest      [55,70,85,100]      [0,0,0,0]         [60,62,64,66]    false
spy         [40,50,60,70]       [15,22,30,40]     [90,95,100,110]  false
ram         [340,420,520,620]   [30,42,56,72]     [26,28,32,36]    false
hero        [420,520,640,780]   [34,46,60,78]     [86,88,92,96]    false
siege       [110,130,155,180]   [26,38,52,68]     [30,32,36,40]    false
medic       [60,75,90,110]      [0,0,0,0]         [68,70,72,74]    false
fisher      [80,100,125,155]    [6,9,13,18]       [54,58,64,70]    true
warship     [190,250,330,430]   [16,26,38,54]     [58,62,68,74]    true
galleon     [340,420,520,640]   [26,38,52,68]     [46,50,54,58]    true
transport   [150,190,240,300]   [10,14,19,25]     [54,58,64,70]    true
fighter     [1,1,1,140]         [0,0,0,26]        [0,0,0,132]      false (kor3)
bomber      [1,1,1,230]         [0,0,0,64]        [0,0,0,86]       false (kor3)
```

### Sprite rendszerek korszakonkent

- age=0 (Kozepkor): LPC sprite sheet, 64x64px, 4 irany x 6 frame
  - Sor 0=Eszak (hát), 1=Nyugat, 2=Del (arc), 3=Kelet
  - Col 0=idle, 1-4=járás, 5=támadás
- age=1 (Napoleoni): sajat 64x64 sheet, ugyanolyan sorrend
- age>=2 (WW2/Modern): WW2 sheet, 64x64px, 5 frame x 4 sor
  - Sor 0=Del, 1=Nyugat, 2=Eszak, 3=Kelet (MAS SORREND mint LPC!)

---

## EPULET ADATOK

```
Tipus     Meret    HP[0-3]              Trainol                  Kulcsadatok
hq        104x104  [1600,1950,2400,2900] worker                  drop=true
barracks   80x80   [820,980,1180,1450]   melee,ranged,spear,hero
stable     76x68   [620,720,860,1050]    cav
farm       56x56   [300,340,400,470]     -                        food termel: [0.85,1.05,1.35,1.75]/mp
tower      50x50   [540,680,850,1050]    -                        tamad: dmg[14,20,27,28] range[155,180,205,200]
house      56x44   [320,420,520,700]     -                        +5 pop limit, max 10 db
harbor     74x54   [540,660,800,960]     fisher,warship,galleon,transport  shore=true
temple     70x60   [560,690,830,990]     priest
barracks   80x80   [820,980,1180,1450]   melee,ranged,spear,hero
airfield  104x74   [1,1,1,1150]          scout,fighter,bomber    minAge=3
goldmine   62x52   [420,520,640,780]     -                        gold termel: 0.8/mp
```

---

## SCENE STRUKTURAK

### Main.tscn

```
Main [Node2D]                    <- Main.gd script
|-- WorldRoot [Node2D]           <- Camera2D ezt koveti
|   |-- WaterLayer [Node2D]
|   |   `-- WaterSprite [Sprite2D]  <- water.gdshader material
|   |-- TerrainLayer [Node2D]
|   |   `-- Terrain [Node2D]     <- Terrain.gd
|   |-- DecoLayer [Node2D]       <- fak, bokrok
|   |-- BuildingLayer [Node2D]   <- epuletek ide kerulnek
|   `-- UnitLayer [Node2D]       <- egysegek ide kerulnek
|-- FogLayer [CanvasLayer]       <- layer=5
|   `-- FogOfWar [Node2D]        <- FogOfWar.gd
|-- UILayer [CanvasLayer]        <- layer=10
|   |-- HUD [Control]            <- HUD.gd
|   `-- SelectionRect [Control]  <- kijelolo teglalap
|-- BotAI [Node]                 <- BotAI.gd
`-- Camera2D                     <- CameraController.gd
    Limit Left=0, Top=0
    Limit Right=3400, Bottom=2400
    Position Smoothing: be, Speed=5.0
```

### Unit.tscn

```
Unit [CharacterBody2D]           <- Unit.gd
    CollisionLayer=1, CollisionMask=1
|-- Sprite2D                     <- UnitSprite.gd
|-- CollisionShape2D
|   `-- CircleShape2D radius=9.0
|-- NavigationAgent2D
|   Target Desired Distance=8.0
|   Path Desired Distance=8.0
|   Navigation Layers=1 (szarazfold) VAGY 2 (viz)
|-- SelectionRing [Node2D]
|   `-- Sprite2D                 <- ring.png
|-- HPBar [Control]
|   `-- ProgressBar
|       Size=(36,4), Position=(-18,-16)
`-- AttackTimer [Timer]
    Wait Time=1.2, One Shot=false, Autostart=false
```

### Building.tscn

```
Building [StaticBody2D]          <- Building.gd
    CollisionLayer=2
|-- Sprite2D
|-- CollisionShape2D
|   `-- RectangleShape2D         <- meretenként allitjuk
|-- HPBar [Control]
|   `-- ProgressBar
|-- ProductionTimer [Timer]
|   Wait Time=8.0, One Shot=false, Autostart=false
`-- RallyPoint [Marker2D]        <- egysegek ide gyulekeznek
```

### FogOfWar.tscn

```
FogOfWar [Node2D]                <- FogOfWar.gd
`-- FogSprite [Sprite2D]
    Centered=false
    Material=New ShaderMaterial -> fog.gdshader
```

### HUD.tscn

```
HUD [Control]                    <- HUD.gd, Anchor=Full Rect
|-- TopBar [PanelContainer]      <- Anchor=Top Wide
|   `-- HBoxContainer
|       |-- WoodBox [HBoxContainer]
|       |   |-- Icon [TextureRect]
|       |   `-- WoodLabel [Label]       unique name: WoodLabel
|       |-- StoneBox [HBoxContainer]
|       |   |-- Icon [TextureRect]
|       |   `-- StoneLabel [Label]      unique name: StoneLabel
|       |-- GoldBox [HBoxContainer]
|       |   |-- Icon [TextureRect]
|       |   `-- GoldLabel [Label]       unique name: GoldLabel
|       |-- FoodBox [HBoxContainer]
|       |   |-- Icon [TextureRect]
|       |   `-- FoodLabel [Label]       unique name: FoodLabel
|       `-- ArmyBox [HBoxContainer]
|           |-- Icon [TextureRect]
|           `-- ArmyLabel [Label]       unique name: ArmyLabel
|-- EraBar [Label]                      unique name: EraBar
|   Anchor=Top Center, Min Size=(300,30)
|-- SelectionPanel [PanelContainer]
|   Anchor=Bottom Left, Size=(280,120)
|   Visible=false
|   `-- VBoxContainer
|       |-- SelTitle [Label]            unique name: SelTitle
|       |-- SelHPBar [ProgressBar]      unique name: SelHPBar
|       `-- ActionButtons [HBoxContainer]
|           |-- MoveBtn [Button]   "Mozgas"
|           |-- AttackBtn [Button] "Tamadas"
|           `-- StopBtn [Button]   "Megall"
|-- BuildPanel [VBoxContainer]
|   Anchor=Bottom Right, Visible=false  unique name: BuildPanel
`-- PauseOverlay [ColorRect]
    Color=(0,0,0,0.5), Anchor=Full Rect, Visible=false
    unique name: PauseOverlay
```

### Menu.tscn

```
Menu [Control]                   <- Menu.gd, Anchor=Full Rect
|-- Background [ColorRect]
|   Color=(0.06,0.06,0.14,1.0), Anchor=Full Rect
`-- CenterContainer [CenterContainer]
    Anchor=Full Rect
    `-- VBoxContainer
        Min Size=(500,0), Alignment=Center
        |-- TitleLabel [Label]   "BIRODALOM"
        |   Font Size=42, H Align=Center
        |-- HSeparator
        |-- EraSection [VBoxContainer]
        |   |-- Label "Valassz korszakot:"
        |   `-- EraButtons [GridContainer]   unique name: EraButtons
        |       Columns=2
        |       |-- EraBtn0 [Button] "15. szazad"
        |       |-- EraBtn1 [Button] "17. szazad"
        |       |-- EraBtn2 [Button] "19-20. szazad"
        |       `-- EraBtn3 [Button] "Modern kor"
        |-- NationSection [VBoxContainer]
        |   |-- Label "Valassz nemzetet:"
        |   `-- NationButtons [HBoxContainer]  unique name: NationButtons
        |       |-- BtnHU [Button] "Magyar"
        |       |-- BtnDE [Button] "Nemet"
        |       |-- BtnEN [Button] "Angol"
        |       `-- BtnFR [Button] "Francia"
        |-- DiffSection [VBoxContainer]
        |   |-- Label "Nehezseg:"
        |   `-- DiffButtons [HBoxContainer]   unique name: DiffButtons
        |       |-- DiffEasy   [Button] "Konnyu"
        |       |-- DiffMedium [Button] "Kozepes"
        |       `-- DiffHard   [Button] "Nehez"
        |-- HSeparator
        `-- StartButton [Button] "JATEK INDITASA"  unique name: StartButton
            Min Size=(300,52), Font Size=18
```

---

## SCRIPTEK

### res://scripts/world/WorldGen.gd

```gdscript
class_name WorldGen
extends RefCounted

var rng := RandomNumberGenerator.new()

func seed_rng(seed_value: int) -> void:
    rng.seed = seed_value

func srange_int(lo: int, hi: int) -> int:
    return rng.randi_range(lo, hi)

func srange(lo: float, hi: float) -> float:
    return rng.randf_range(lo, hi)

func generate(seed_value: int, terrain_node: Node) -> void:
    seed_rng(seed_value)
    var water_map := _gen_water_map()
    terrain_node.apply_water_map(water_map)
    _gen_mountains(terrain_node, water_map)
    _gen_forests(terrain_node, water_map)
    _gen_resources(terrain_node, water_map)

func _gen_water_map() -> Array:
    var noise := FastNoiseLite.new()
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
    noise.seed = rng.randi()
    noise.frequency = 0.0035
    noise.fractal_octaves = 4
    var W := GameState.WORLD_W
    var H := GameState.WORLD_H
    var map: Array = []
    map.resize(H)
    for y in range(H):
        map[y] = []
        map[y].resize(W)
        for x in range(W):
            map[y][x] = noise.get_noise_2d(float(x), float(y)) < -0.05
    return map

func _is_water(map: Array, x: int, y: int) -> bool:
    if y < 0 or y >= map.size(): return true
    if x < 0 or x >= map[y].size(): return true
    return map[y][x]

func _gen_mountains(terrain: Node, wmap: Array) -> void:
    var count := srange_int(8, 14)
    for _i in range(count):
        var cx := srange(140, GameState.WORLD_W - 140)
        var cy := srange(140, GameState.WORLD_H - 140)
        if not _is_water(wmap, int(cx), int(cy)):
            var n := srange_int(3, 8)
            for _j in range(n):
                var angle := srange(0.0, TAU)
                var dist  := srange(20.0, 65.0)
                var rx := clampf(cx + cos(angle)*dist, 40, GameState.WORLD_W-40)
                var ry := clampf(cy + sin(angle)*dist, 40, GameState.WORLD_H-40)
                terrain.add_rock(Vector2(rx, ry))

func _gen_forests(terrain: Node, wmap: Array) -> void:
    var count := srange_int(12, 22)
    for _i in range(count):
        var cx := srange(120, GameState.WORLD_W - 120)
        var cy := srange(120, GameState.WORLD_H - 120)
        if not _is_water(wmap, int(cx), int(cy)):
            for _j in range(srange_int(3, 9)):
                var a := srange(0.0, TAU)
                var d := srange(10.0, 45.0)
                var tx := clampf(cx + cos(a)*d, 30, GameState.WORLD_W-30)
                var ty := clampf(cy + sin(a)*d, 30, GameState.WORLD_H-30)
                terrain.add_tree(Vector2(tx, ty))

func _gen_resources(terrain: Node, wmap: Array) -> void:
    for kind in ["wood_node","stone_node","gold_node","food_node"]:
        for _i in range(srange_int(4, 8)):
            var x := srange(80, GameState.WORLD_W - 80)
            var y := srange(80, GameState.WORLD_H - 80)
            if not _is_water(wmap, int(x), int(y)):
                terrain.add_resource(kind, Vector2(x, y))
```

### res://scripts/units/Unit.gd

```gdscript
class_name Unit
extends CharacterBody2D

@export var role      : String  = "melee"
@export var owner_id  : int     = 0
@export var age       : int     = 0
@export var max_hp    : float   = 100.0
@export var dmg       : float   = 12.0
@export var spd       : float   = 72.0
@export var radius    : float   = 9.0
@export var vision_r  : float   = 120.0
@export var naval     : bool    = false
@export var atk_range : float   = 32.0

var hp       : float   = 100.0
var face     : float   = 0.0
var walk     : float   = 0.0
var target   : Node2D  = null
var _sel     : bool    = false

# Egyseg statisztikak korszakonkent [age0,age1,age2,age3]
const UNIT_STATS := {
    "worker":  {"hp":[45,50,58,66],    "dmg":[3,3,4,4],      "speed":[64,66,70,76]},
    "melee":   {"hp":[95,125,160,340], "dmg":[11,15,20,38],  "speed":[72,74,76,60]},
    "ranged":  {"hp":[55,70,88,105],   "dmg":[8,14,19,7],    "speed":[62,62,64,62]},
    "spear":   {"hp":[78,98,118,124],  "dmg":[9,13,17,30],   "speed":[58,60,62,56]},
    "cav":     {"hp":[80,100,120,190], "dmg":[10,14,18,26],  "speed":[118,124,132,150]},
    "priest":  {"hp":[55,70,85,100],   "dmg":[0,0,0,0],      "speed":[60,62,64,66]},
    "spy":     {"hp":[40,50,60,70],    "dmg":[15,22,30,40],  "speed":[90,95,100,110]},
    "fisher":  {"hp":[80,100,125,155], "dmg":[6,9,13,18],    "speed":[54,58,64,70]},
    "warship": {"hp":[190,250,330,430],"dmg":[16,26,38,54],  "speed":[58,62,68,74]},
    "galleon": {"hp":[340,420,520,640],"dmg":[26,38,52,68],  "speed":[46,50,54,58]},
    "transport":{"hp":[150,190,240,300],"dmg":[10,14,19,25], "speed":[54,58,64,70]},
}

@onready var sprite    := $Sprite2D
@onready var nav       := $NavigationAgent2D as NavigationAgent2D
@onready var hp_bar    := $HPBar/ProgressBar as ProgressBar
@onready var sel_ring  := $SelectionRing as Node2D
@onready var atk_timer := $AttackTimer as Timer

func _ready() -> void:
    _apply_stats()
    hp = max_hp
    hp_bar.max_value = max_hp
    hp_bar.value = hp
    sel_ring.visible = false
    atk_timer.timeout.connect(_on_attack)
    add_to_group("units")
    if owner_id == GameState.en_id:
        add_to_group("player_units")
    else:
        add_to_group("enemy_units")
    if naval:
        nav.navigation_layers = 2
    # Sprite setup
    if sprite.has_method("setup"):
        sprite.setup(role, age, owner_id)

func _apply_stats() -> void:
    var st := UNIT_STATS.get(role, {})
    var a  := clamp(age, 0, 3)
    if st:
        max_hp = float(st["hp"][a])
        dmg    = float(st["dmg"][a])
        spd    = float(st["speed"][a])

func _physics_process(delta: float) -> void:
    if not GameState.on: return
    _move(delta)
    if sprite.has_method("update_anim"):
        sprite.update_anim(face, walk, velocity.length() > 2.0, false)

func _move(delta: float) -> void:
    if nav.is_navigation_finished():
        velocity = Vector2.ZERO
    else:
        var next := nav.get_next_path_position()
        var dir  := (next - global_position).normalized()
        face = dir.angle()
        velocity = dir * spd
        walk += delta * spd * 0.09
    move_and_slide()

func move_to(pos: Vector2) -> void:
    nav.target_position = pos
    target = null
    if not atk_timer.is_stopped(): atk_timer.stop()

func start_attacking(enemy: Node) -> void:
    target = enemy
    if atk_timer.is_stopped(): atk_timer.start()

func _on_attack() -> void:
    if not is_instance_valid(target):
        atk_timer.stop(); target = null; return
    if global_position.distance_to(target.global_position) > atk_range * 3:
        atk_timer.stop(); target = null; return
    if target.has_method("take_damage"):
        target.take_damage(dmg)

func take_damage(amount: float) -> void:
    hp -= amount
    hp_bar.value = hp
    if hp <= 0.0: queue_free()

func set_selected(val: bool) -> void:
    _sel = val
    sel_ring.visible = val
```

### res://scripts/units/UnitSprite.gd

```gdscript
extends Sprite2D

# LPC: sor 0=Eszak, 1=Nyugat, 2=Del, 3=Kelet
# WW2: sor 0=Del,   1=Nyugat, 2=Eszak, 3=Kelet  <- MAS!
const LPC_FW  := 64
const LPC_FH  := 64
const WW2_FW  := 64
const WW2_FH  := 64

var _age: int = 0

func setup(role: String, age: int, owner_id: int) -> void:
    _age = age
    region_enabled = true
    match age:
        0: _load_lpc(role, owner_id)
        1: _load_napoleon(role, owner_id)
        _: _load_ww2(owner_id)

func _load_lpc(role: String, owner_id: int) -> void:
    var side := "ally" if owner_id == 0 else "enemy"
    var path := "res://assets/sprites/lpc/%s_%s.png" % [role, side]
    if ResourceLoader.exists(path):
        texture = load(path)
        region_rect = Rect2(0, 0, LPC_FW, LPC_FH)

func _load_napoleon(role: String, owner_id: int) -> void:
    var side := "ally" if owner_id == 0 else "enemy"
    var path := "res://assets/sprites/napoleon/%s_%s.png" % [role, side]
    if not ResourceLoader.exists(path):
        _load_lpc(role, owner_id)
        return
    texture = load(path)
    region_rect = Rect2(0, 0, LPC_FW, LPC_FH)

func _load_ww2(owner_id: int) -> void:
    var side := "ally" if owner_id == 0 else "axis"
    var path := "res://assets/sprites/ww2/%s.png" % side
    if ResourceLoader.exists(path):
        texture = load(path)
        region_rect = Rect2(0, 0, WW2_FW, WW2_FH)

func update_anim(face: float, walk: float, moving: bool, fired: bool) -> void:
    if not texture: return
    var row := _face_to_row(face)
    var col := _walk_to_col(walk, moving, fired)
    region_rect = Rect2(col * LPC_FW, row * LPC_FH, LPC_FW, LPC_FH)

func _face_to_row(face: float) -> int:
    var deg := fmod(rad_to_deg(face) + 360.0, 360.0)
    if   deg > 315.0 or deg <= 45.0:  return 3  # Kelet
    elif deg <= 135.0:                 return 2  # Del (LPC)/Del (WW2)
    elif deg <= 225.0:                 return 1  # Nyugat
    else:                              return 0  # Eszak (LPC hát / WW2 hát)

func _walk_to_col(walk: float, moving: bool, fired: bool) -> int:
    if fired:    return 5
    if not moving: return 0
    return 1 + (int(walk * 2.5) % 4)
```

### res://scripts/buildings/Building.gd

```gdscript
class_name Building
extends StaticBody2D

@export var tipus    : String = "hq"
@export var owner_id : int    = 0
@export var age      : int    = 0

const BUILD_STATS := {
    "hq":       {"hp":[1600,1950,2400,2900], "trains":["worker"]},
    "barracks": {"hp":[820,980,1180,1450],   "trains":["melee","ranged","spear","hero"]},
    "stable":   {"hp":[620,720,860,1050],    "trains":["cav"]},
    "farm":     {"hp":[300,340,400,470],     "food":[0.85,1.05,1.35,1.75]},
    "tower":    {"hp":[540,680,850,1050],    "dmg":[14,20,27,28]},
    "house":    {"hp":[320,420,520,700],     "pop":5},
    "harbor":   {"hp":[540,660,800,960],     "trains":["fisher","warship","galleon","transport"]},
    "temple":   {"hp":[560,690,830,990],     "trains":["priest"]},
    "goldmine": {"hp":[420,520,640,780],     "gold":0.8},
    "airfield": {"hp":[1,1,1,1150],          "trains":["fighter","bomber"]},
}

const TRAIN_TIME := {
    "worker":8.0,"melee":8.0,"ranged":10.0,"spear":9.0,"cav":14.0,
    "priest":16.0,"hero":20.0,"fisher":20.0,"warship":30.0,
    "galleon":40.0,"transport":25.0,"fighter":14.0,"bomber":18.0,
}

const TRAIN_COST := {
    "worker":  {"wood":30,"food":40},
    "melee":   {"wood":50,"food":30},
    "ranged":  {"wood":40,"stone":20,"food":25},
    "spear":   {"wood":45,"food":28},
    "cav":     {"wood":80,"food":60,"gold":20},
    "priest":  {"wood":60,"gold":80,"food":30},
    "hero":    {"wood":120,"gold":150,"food":80},
    "fisher":  {"wood":90,"stone":30},
    "warship": {"wood":200,"stone":80,"gold":60},
    "galleon": {"wood":320,"stone":130,"gold":100},
    "transport":{"wood":150,"stone":60},
    "fighter": {"gold":120,"wood":90,"coal":40},
    "bomber":  {"gold":180,"wood":140,"coal":60},
}

var hp           : float = 1000.0
var max_hp       : float = 1000.0
var train_queue  : Array = []

@onready var hp_bar   := $HPBar/ProgressBar as ProgressBar
@onready var prod_tmr := $ProductionTimer as Timer
@onready var rally    := $RallyPoint as Marker2D

func _ready() -> void:
    var st := BUILD_STATS.get(tipus, {})
    max_hp = float(st.get("hp", [500,600,700,800])[clamp(age,0,3)])
    hp = max_hp
    hp_bar.max_value = max_hp
    hp_bar.value = hp
    prod_tmr.timeout.connect(_produce)
    add_to_group("buildings")

func _process(delta: float) -> void:
    _tick_resources(delta)

func _tick_resources(delta: float) -> void:
    var st := BUILD_STATS.get(tipus, {})
    var a  := clamp(age, 0, 3)
    if st.has("food"):
        GameState.add_res(owner_id, "food",  st["food"][a] * delta)
    if st.has("gold"):
        GameState.add_res(owner_id, "gold",  st["gold"] * delta)

func enqueue_unit(role: String) -> bool:
    var cost := TRAIN_COST.get(role, {})
    if not GameState.pay(owner_id, cost): return false
    train_queue.append(role)
    if prod_tmr.is_stopped():
        prod_tmr.wait_time = TRAIN_TIME.get(role, 10.0)
        prod_tmr.start()
    return true

func _produce() -> void:
    if train_queue.is_empty(): return
    var role := train_queue.pop_front() as String
    var main := get_tree().get_first_node_in_group("main")
    if main and main.has_method("spawn_unit"):
        main.spawn_unit(role, owner_id, rally.global_position, age)
    if not train_queue.is_empty():
        prod_tmr.wait_time = TRAIN_TIME.get(train_queue[0], 10.0)
        prod_tmr.start()

func take_damage(amount: float) -> void:
    hp -= amount
    hp_bar.value = hp
    if hp <= 0: queue_free()
```

### res://scripts/ai/BotAI.gd

```gdscript
extends Node

const BOT_ID := 1

var wave_timer  : float = 60.0
var build_timer : float = 25.0
var seen := {"melee":0,"ranged":0,"spear":0,"cav":0,"warship":0}

func start() -> void:
    var side := GameState.get_side(BOT_ID)
    wave_timer = side.get("waveT", 115.0) * 0.5

func _process(delta: float) -> void:
    if not GameState.on or GameState.over: return
    wave_timer  -= delta
    build_timer -= delta
    if wave_timer  <= 0: _send_wave()
    if build_timer <= 0: _build_tick()
    _update_seen()

func _send_wave() -> void:
    var side := GameState.get_side(BOT_ID)
    wave_timer = side.get("waveT", 115.0) / side.get("rate", 1.0)
    var age    := side.get("age", 0)
    var main   := get_tree().get_first_node_in_group("main")
    if not main: return
    for role in _choose_composition(age):
        main.spawn_unit(role, BOT_ID, _bot_hq_pos(), age)

func _choose_composition(age: int) -> Array:
    var result : Array = []
    var count  := 3 + age * 2
    for i in range(count):
        var r := randf()
        if seen.get("cav", 0) > 2 and r < 0.4:
            result.append("spear")
        elif seen.get("ranged", 0) > 3 and r < 0.5:
            result.append("melee")
        elif r < 0.55:  result.append("melee")
        elif r < 0.82:  result.append("ranged")
        else:           result.append("spear")
    return result

func _update_seen() -> void:
    seen = {"melee":0,"ranged":0,"spear":0,"cav":0,"warship":0}
    for u in get_tree().get_nodes_in_group("player_units"):
        if u is Unit and seen.has(u.role):
            seen[u.role] += 1

func _build_tick() -> void:
    build_timer = 35.0

func _bot_hq_pos() -> Vector2:
    for b in get_tree().get_nodes_in_group("buildings"):
        if b is Building and b.owner_id == BOT_ID and b.tipus == "hq":
            return b.global_position
    return Vector2(GameState.WORLD_W - 300, 300)
```

### res://scripts/world/FogOfWar.gd

```gdscript
extends Node2D

const FOG_CELL := 32

var fog_w   : int
var fog_h   : int
var fog_img : Image
var fog_tex : ImageTexture

@onready var fog_sprite := $FogSprite as Sprite2D

func init() -> void:
    fog_w = GameState.WORLD_W / FOG_CELL
    fog_h = GameState.WORLD_H / FOG_CELL
    fog_img = Image.create(fog_w, fog_h, false, Image.FORMAT_RG8)
    fog_img.fill(Color(0, 0, 0, 1))
    fog_tex = ImageTexture.create_from_image(fog_img)
    fog_sprite.texture = fog_tex
    fog_sprite.scale = Vector2(
        float(GameState.WORLD_W) / fog_w,
        float(GameState.WORLD_H) / fog_h
    )
    fog_sprite.material.set_shader_parameter("fog_tex", fog_tex)

func tick(_delta: float) -> void:
    _clear_visible()
    for u in get_tree().get_nodes_in_group("player_units"):
        reveal_circle(u.global_position, u.vision_r if u.has("vision_r") else 120.0)
    fog_tex.update(fog_img)

func _clear_visible() -> void:
    for y in range(fog_h):
        for x in range(fog_w):
            var px := fog_img.get_pixel(x, y)
            fog_img.set_pixel(x, y, Color(px.r, 0, 0, 1))

func reveal_circle(world_pos: Vector2, radius: float) -> void:
    var cx := int(world_pos.x / FOG_CELL)
    var cy := int(world_pos.y / FOG_CELL)
    var cr := int(radius / FOG_CELL) + 1
    for dy in range(-cr, cr+1):
        for dx in range(-cr, cr+1):
            if dx*dx + dy*dy > cr*cr: continue
            var fx := cx + dx
            var fy := cy + dy
            if fx < 0 or fy < 0 or fx >= fog_w or fy >= fog_h: continue
            fog_img.set_pixel(fx, fy, Color(1, 1, 0, 1))

func is_visible_at(world_pos: Vector2) -> bool:
    var fx := int(world_pos.x / FOG_CELL)
    var fy := int(world_pos.y / FOG_CELL)
    if fx < 0 or fy < 0 or fx >= fog_w or fy >= fog_h: return false
    return fog_img.get_pixel(fx, fy).g > 0.5
```

### res://scripts/ui/HUD.gd

```gdscript
extends Control

@onready var wood_label    := %WoodLabel    as Label
@onready var stone_label   := %StoneLabel   as Label
@onready var gold_label    := %GoldLabel    as Label
@onready var food_label    := %FoodLabel    as Label
@onready var army_label    := %ArmyLabel    as Label
@onready var era_bar       := %EraBar       as Label
@onready var sel_panel     := %SelectionPanel as PanelContainer
@onready var sel_title     := %SelTitle     as Label
@onready var sel_hp        := %SelHPBar     as ProgressBar
@onready var build_panel   := %BuildPanel   as VBoxContainer
@onready var pause_overlay := %PauseOverlay as ColorRect

const ERA_LABELS := [
    "15. szazad  –  Kozepkor",
    "17. szazad  –  Napoleoni kor",
    "19-20. szazad  –  Vilaghaboruk kora",
    "Modern kor"
]

func _ready() -> void:
    GameState.resources_changed.connect(_update_resources)
    GameState.era_changed.connect(_update_era)
    sel_panel.visible = false
    build_panel.visible = false
    _update_resources()
    _update_era(0, GameState.get_age())

func _update_resources() -> void:
    var res := GameState.get_res()
    wood_label.text  = str(int(res.get("wood",  0)))
    stone_label.text = str(int(res.get("stone", 0)))
    gold_label.text  = str(int(res.get("gold",  0)))
    food_label.text  = str(int(res.get("food",  0)))
    var cur := get_tree().get_nodes_in_group("player_units").size()
    army_label.text = "%d / 90" % cur

func _update_era(_owner_id: int, new_age: int) -> void:
    era_bar.text = ERA_LABELS[clamp(new_age, 0, 3)]

func update_selection(units: Array) -> void:
    sel_panel.visible = not units.is_empty()
    if units.is_empty(): return
    if units.size() == 1:
        var u := units[0]
        sel_title.text = (u.role if u.has("role") else "?").capitalize()
        sel_hp.max_value = u.max_hp
        sel_hp.value = u.hp
    else:
        sel_title.text = "%d egyseg" % units.size()
        sel_hp.visible = false
```

### res://scripts/ui/Menu.gd

```gdscript
extends Control

var chosen_era    : int    = 0
var chosen_nation : String = "hu"
var chosen_diff   : int    = 0

const NATIONS := ["hu","de","en","fr"]

@onready var era_btns  := %EraButtons      as GridContainer
@onready var nat_btns  := %NationButtons   as HBoxContainer
@onready var diff_btns := %DiffButtons     as HBoxContainer
@onready var start_btn := %StartButton     as Button

func _ready() -> void:
    for i in era_btns.get_child_count():
        var idx := i
        (era_btns.get_child(i) as Button).pressed.connect(func(): _sel_era(idx))
    for i in nat_btns.get_child_count():
        var n := NATIONS[i]
        (nat_btns.get_child(i) as Button).pressed.connect(func(): _sel_nation(n))
    for i in diff_btns.get_child_count():
        var idx := i
        (diff_btns.get_child(i) as Button).pressed.connect(func(): chosen_diff = idx)
    start_btn.pressed.connect(_on_start)
    _sel_era(0)
    _sel_nation("hu")

func _sel_era(idx: int) -> void:
    chosen_era = idx
    for i in era_btns.get_child_count():
        (era_btns.get_child(i) as Button).flat = (i != idx)

func _sel_nation(n: String) -> void:
    chosen_nation = n
    for i in nat_btns.get_child_count():
        (nat_btns.get_child(i) as Button).flat = (NATIONS[i] != n)

func _on_start() -> void:
    GameState.new_game(chosen_nation, chosen_era)
    GameState.diff = chosen_diff
    get_tree().change_scene_to_file("res://scenes/Main.tscn")
```

### res://Main.gd

```gdscript
extends Node2D

const UNIT_SCENE     := preload("res://scenes/units/Unit.tscn")
const BUILDING_SCENE := preload("res://scenes/buildings/Building.tscn")

@onready var unit_layer     := $WorldRoot/UnitLayer
@onready var building_layer := $WorldRoot/BuildingLayer
@onready var fog            := $FogLayer/FogOfWar as Node
@onready var hud            := $UILayer/HUD
@onready var camera         := $Camera2D
@onready var terrain        := $WorldRoot/TerrainLayer/Terrain
@onready var bot_ai         := $BotAI

var selected_units : Array[Node] = []
var _sel_start     : Vector2     = Vector2.ZERO
var _sel_dragging  : bool        = false

func _ready() -> void:
    add_to_group("main")
    GameState.resources_changed.connect(hud._update_resources)
    GameState.era_changed.connect(hud._update_era)
    if GameState.on:
        _start_world()

func _start_world() -> void:
    var gen := WorldGen.new()
    gen.generate(GameState.sim_mag, terrain)
    fog.init()
    _spawn_headquarters()
    bot_ai.start()

func _spawn_headquarters() -> void:
    spawn_building("hq", 0, Vector2(380, GameState.WORLD_H - 380))
    spawn_building("hq", 1, Vector2(GameState.WORLD_W - 380, 380))

func _process(delta: float) -> void:
    if GameState.on:
        fog.tick(delta)
        GameState.t += delta

func spawn_unit(role: String, owner_id: int,
                pos: Vector2, age: int) -> Node:
    var u := UNIT_SCENE.instantiate()
    u.role     = role
    u.owner_id = owner_id
    u.age      = age
    u.global_position = pos
    unit_layer.add_child(u)
    return u

func spawn_building(tipus: String, owner_id: int, pos: Vector2) -> Node:
    var b := BUILDING_SCENE.instantiate()
    b.tipus    = tipus
    b.owner_id = owner_id
    b.age      = GameState.get_age(owner_id)
    b.global_position = pos
    building_layer.add_child(b)
    return b

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_LEFT:
            if mb.pressed:
                _sel_start   = get_global_mouse_position()
                _sel_dragging = true
            else:
                _finish_sel(get_global_mouse_position())
                _sel_dragging = false
        elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
            var wp := get_global_mouse_position()
            for u in selected_units:
                if u.has_method("move_to"): u.move_to(wp)

func _finish_sel(end_pos: Vector2) -> void:
    var rect := Rect2(_sel_start, end_pos - _sel_start).abs()
    for u in selected_units:
        if u.has_method("set_selected"): u.set_selected(false)
    selected_units.clear()
    for u in get_tree().get_nodes_in_group("player_units"):
        if rect.has_point(u.global_position):
            selected_units.append(u)
            if u.has_method("set_selected"): u.set_selected(true)
    hud.update_selection(selected_units)
```

### res://scripts/CameraController.gd

```gdscript
extends Camera2D

const PAN_SPEED   := 500.0
const ZOOM_MIN    := 0.25
const ZOOM_MAX    := 3.0
const ZOOM_STEP   := 0.12
const EDGE_PAN_PX := 20

var _drag_active : bool    = false
var _drag_start  : Vector2 = Vector2.ZERO
var _cam_start   : Vector2 = Vector2.ZERO

func _process(delta: float) -> void:
    if not GameState.on: return
    var dir := Vector2.ZERO
    if Input.is_action_pressed("move_left"):  dir.x -= 1
    if Input.is_action_pressed("move_right"): dir.x += 1
    if Input.is_action_pressed("move_up"):    dir.y -= 1
    if Input.is_action_pressed("move_down"):  dir.y += 1
    if dir != Vector2.ZERO:
        position += dir.normalized() * PAN_SPEED * delta / zoom.x
    var mp  := get_viewport().get_mouse_position()
    var vps := get_viewport().get_visible_rect().size
    var ep  := Vector2.ZERO
    if mp.x < EDGE_PAN_PX:        ep.x -= 1
    if mp.x > vps.x-EDGE_PAN_PX:  ep.x += 1
    if mp.y < EDGE_PAN_PX:        ep.y -= 1
    if mp.y > vps.y-EDGE_PAN_PX:  ep.y += 1
    if ep != Vector2.ZERO:
        position += ep.normalized() * PAN_SPEED * 0.5 * delta / zoom.x
    _clamp()

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        match mb.button_index:
            MOUSE_BUTTON_WHEEL_UP:
                if mb.pressed: _zoom_at_mouse(1.0 + ZOOM_STEP)
            MOUSE_BUTTON_WHEEL_DOWN:
                if mb.pressed: _zoom_at_mouse(1.0 - ZOOM_STEP)
            MOUSE_BUTTON_MIDDLE:
                _drag_active = mb.pressed
                if mb.pressed:
                    _drag_start = mb.global_position
                    _cam_start  = position
    elif event is InputEventMouseMotion and _drag_active:
        position = _cam_start - (event.global_position - _drag_start) / zoom.x

func _zoom_at_mouse(factor: float) -> void:
    var mw := get_global_mouse_position()
    var nz := clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
    position = mw - (mw - position) / (nz / zoom.x)
    zoom = Vector2(nz, nz)
    _clamp()

func _clamp() -> void:
    var half := get_viewport().get_visible_rect().size * 0.5 / zoom.x
    position.x = clampf(position.x, half.x, GameState.WORLD_W - half.x)
    position.y = clampf(position.y, half.y, GameState.WORLD_H - half.y)
```

---

## SHADEREK

### res://assets/shaders/water.gdshader

```glsl
shader_type canvas_item;

uniform float time_scale : float = 0.4;
uniform vec4 water_deep  : vec4 = vec4(0.12, 0.38, 0.68, 1.0);
uniform vec4 water_light : vec4 = vec4(0.28, 0.58, 0.85, 1.0);
uniform vec4 foam_color  : vec4 = vec4(0.88, 0.94, 1.0,  1.0);

void fragment() {
    float w = sin(UV.x * 14.0 + TIME * time_scale) * 0.04
            + sin(UV.y *  9.0 + TIME * time_scale * 0.8) * 0.03
            + cos(UV.x *  6.0 - TIME * time_scale * 0.5) * 0.025;
    float depth = smoothstep(0.0, 0.6, UV.y + w);
    vec4 base = mix(water_deep, water_light, depth);
    float foam = smoothstep(0.48, 0.52, UV.y + w * 2.0);
    COLOR = mix(base, foam_color, foam * 0.35);
}
```

### res://assets/shaders/fog.gdshader

```glsl
shader_type canvas_item;

uniform sampler2D fog_tex : filter_nearest;

void fragment() {
    vec4 fog = texture(fog_tex, UV);
    float explored = fog.r;
    float visible  = fog.g;
    if (visible > 0.5) {
        COLOR = vec4(0.0, 0.0, 0.0, 0.0);
    } else if (explored > 0.5) {
        COLOR = vec4(0.0, 0.0, 0.1, 0.55);
    } else {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    }
}
```

---

## FELÉPÍTÉSI SORREND

Ha minden egyszerre akarod megcsináltatni a Claude Code-dal,
add be sorban ezeket a promptokat:

1. "Hozd létre az összes mappát a projektstruktúra szerint"
2. "Írd meg a GameState.gd, SFX.gd és SaveManager.gd Autoload scripteket"
3. "Hozd létre a Main.tscn-t a scene struktúra szerint, és írd meg a Main.gd-t"
4. "Hozd létre a Unit.tscn-t és írd meg a Unit.gd és UnitSprite.gd scripteket"
5. "Hozd létre a Building.tscn-t és Building.gd-t"
6. "Írd meg a WorldGen.gd-t és a Terrain.gd-t"
7. "Hozd létre a FogOfWar.tscn-t és írd meg a FogOfWar.gd-t"
8. "Hozd létre a HUD.tscn-t és Menu.tscn-t a struktúra szerint"
9. "Írd meg a HUD.gd-t és Menu.gd-t"
10. "Írd meg a BotAI.gd-t és a CameraController.gd-t"
11. "Hozd létre a water.gdshader és fog.gdshader fájlokat"
12. "Add hozzá az Autoload-okat: Project > Project Settings > Autoload"
