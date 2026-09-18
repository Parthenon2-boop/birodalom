class_name NavSystem
extends RefCounted

# Navigációs segédfüggvények.
# 1-es réteg = szárazföld, 2-es réteg = víz (lásd Terrain.gd).

const LAYER_LAND  := 1
const LAYER_WATER := 2

static func layer_for(naval: bool) -> int:
	return LAYER_WATER if naval else LAYER_LAND

# A legközelebbi járható pont a megadott rétegen. Ha a cél járhatatlan
# (pl. szárazföldi egységet vízre küldünk), a part szélére teszi.
static func closest_point(tree: SceneTree, pos: Vector2, layer: int) -> Vector2:
	var map := tree.root.world_2d.navigation_map
	if map == RID():
		return pos
	NavigationServer2D.map_force_update(map)
	var p := NavigationServer2D.map_get_closest_point(map, pos)
	return p if p != Vector2.ZERO else pos

# Csoportos mozgás: a kijelölt egységeket rácsba rendezi a célpont körül,
# hogy ne egyetlen pontra törekedjenek.
static func formation_offsets(count: int, spacing: float = 30.0) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if count <= 0: return out
	var cols := int(ceil(sqrt(float(count))))
	for i in range(count):
		var cx := i % cols
		var cy := i / cols
		var rows := int(ceil(float(count) / cols))
		out.append(Vector2(
			(cx - (cols - 1) * 0.5) * spacing,
			(cy - (rows - 1) * 0.5) * spacing))
	return out

# Egyszerű "van-e akadálymentes látás" ellenőrzés lövésekhez.
static func has_line_of_sight(from: Node2D, to: Vector2, mask: int = 2) -> bool:
	var space := from.get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(from.global_position, to)
	params.collision_mask = mask
	params.exclude = [from.get_rid()]
	var hit := space.intersect_ray(params)
	return hit.is_empty()
