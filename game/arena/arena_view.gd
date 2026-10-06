class_name ArenaView
extends Node3D
## Builds an arena on screen from its ArenaGrid with Kenney kit pieces. The
## grid decides everything about play; this only draws it. Repeated pieces
## (floor tiles, wall blocks) are drawn as one MultiMesh each.

const MINI := "res://assets/kenney/mini-arena/"
const PROTO := "res://assets/kenney/prototype-kit/"
const BLASTER := "res://assets/kenney/blaster-kit/"
const T := ArenaGrid.TILE

var grid: ArenaGrid
## Door i -> {node, anim, lamp, closed}
var doors := []
var base_pads: Array[Node3D] = []

var _batches := {}
var _rng := RandomNumberGenerator.new()


## Draws the arena; `bases` adds the team flag pads (Capture the Flag).
func build(p_grid: ArenaGrid, bases := false) -> void:
	grid = p_grid
	_rng.seed = hash(grid.id)
	_ground()
	if grid.kit == "prototype-kit":
		_build_lab()
	else:
		_build_gym()
	if bases:
		_bases()
	_flush_batches()


## Opens and shuts the doors to match the host's clock.
func update_doors(match_time: float, play_sounds := true) -> void:
	for i in doors.size():
		var d: Dictionary = doors[i]
		var closed := grid.door_closed(i, match_time)
		if closed == d.closed:
			continue
		d.closed = closed
		if d.anim:
			d.anim.play("close" if closed else "open")
		var mat: StandardMaterial3D = d.lamp.material_override
		mat.albedo_color = Color("ff4a3d") if closed else Color("4dff7a")
		mat.emission = mat.albedo_color
		if play_sounds:
			LGAudio.play_sfx("res://assets/kenney/audio/sfx/%s.ogg" % ("doorClose_000" if closed else "doorOpen_000"), -14.0, 0.05)


func _ground() -> void:
	var size := grid.world_size()
	var under := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size + Vector2(80, 80)
	under.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("1d2638") if grid.kit == "prototype-kit" else Color("3a2a22")
	mat.roughness = 1.0
	under.material_override = mat
	under.position = Vector3(size.x * 0.5, -0.05, size.y * 0.5)
	add_child(under)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = mat.albedo_color.darkened(0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.8, 0.95) if grid.kit == "prototype-kit" else Color(0.95, 0.85, 0.75)
	env.environment.ambient_light_energy = 0.45
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, -28, 0)
	sun.light_energy = 0.85
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)


func _build_gym() -> void:
	for y in grid.height:
		for x in grid.width:
			var c := Vector2i(x, y)
			var ch := grid.char_at(c)
			var pos := _pos(c)
			if ch != "#":
				var floor_piece := "floor-detail" if (x + y) % 5 == 0 else "floor"
				_batch(MINI + floor_piece + ".glb", Transform3D(Basis().scaled(Vector3.ONE * T), pos))
			match ch:
				"#":
					_gym_wall(c, pos)
				"C":
					_batch(MINI + "column.glb", Transform3D(Basis().scaled(Vector3(2.8, 2.2, 2.8)), pos))
				"c":
					var yaw := 0.0 if (x + y) % 2 == 0 else PI * 0.5
					_batch(BLASTER + "crate-medium.glb", Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(3.3, 2.6, 1.9)), pos))
				"S":
					var face := 1.0 if x < grid.width / 2 else -1.0
					_batch(MINI + "statue.glb", Transform3D(Basis(Vector3.UP, face * PI * 0.5).scaled(Vector3.ONE * 2.4), pos))


func _gym_wall(c: Vector2i, pos: Vector3) -> void:
	var border := c.x == 0 or c.y == 0 or c.x == grid.width - 1 or c.y == grid.height - 1
	if not border:
		# Free-standing blocks: two bricks high.
		for level in 2:
			_batch(MINI + "block.glb", Transform3D(Basis().scaled(Vector3.ONE * T), pos + Vector3(0, level * 0.5 * T, 0)))
		return
	var corner := (c.x == 0 or c.x == grid.width - 1) and (c.y == 0 or c.y == grid.height - 1)
	if corner:
		_batch(MINI + "block.glb", Transform3D(Basis().scaled(Vector3(T, T * 2.0, T)), pos))
		return
	var along_x := c.y == 0 or c.y == grid.height - 1
	var basis := Basis() if along_x else Basis(Vector3.UP, PI * 0.5)
	_batch(MINI + "wall.glb", Transform3D(basis.scaled(Vector3(T, T * 1.4, T * 1.4)), pos))
	# Banners along the long walls, facing in.
	if along_x and c.x % 4 == 2:
		var face := Basis(Vector3.UP, PI) if c.y == 0 else Basis()
		var inward := Vector3(0, 0, 0.5 * T if c.y == 0 else -0.5 * T) * 0.85
		_batch(MINI + "banner.glb", Transform3D(face.scaled(Vector3.ONE * T), pos + inward + Vector3(0, 0.25, 0)))


func _build_lab() -> void:
	for y in grid.height:
		for x in grid.width:
			var c := Vector2i(x, y)
			var ch := grid.char_at(c)
			var pos := _pos(c)
			if ch != "#":
				var piece := "floor-small-square" if (x + y) % 2 == 0 else "floor-square"
				_batch(PROTO + piece + ".glb", Transform3D(Basis().scaled(Vector3.ONE * T), pos))
			match ch:
				"#":
					var border := x == 0 or y == 0 or x == grid.width - 1 or y == grid.height - 1
					var h := 1.3 if border else 1.0
					_batch(PROTO + "shape-cube.glb", Transform3D(Basis().scaled(Vector3(T, T * h, T)), pos))
				"C":
					_batch(PROTO + "shape-cylinder.glb", Transform3D(Basis().scaled(Vector3(1.7, T, 1.7)), pos))
				"c":
					var piece := "crate-color" if (x * 7 + y) % 3 == 0 else "crate"
					_batch(PROTO + piece + ".glb", Transform3D(Basis(Vector3.UP, (x + y) * 0.3).scaled(Vector3.ONE * 3.5), pos))
				"D":
					_lab_door(c, pos)
				"1", "2", "3", "4", "5", "6", "7", "8":
					_batch(PROTO + "indicator-round-a.glb", Transform3D(Basis().scaled(Vector3(1.4, 0.3, 1.4)), pos + Vector3(0, 0.01, 0)))


func _lab_door(c: Vector2i, pos: Vector3) -> void:
	# The wall runs north-south through door tiles in this layout.
	var vertical := grid.is_solid(c + Vector2i(0, -1), 0.0) or grid.is_solid(c + Vector2i(0, 1), 0.0)
	var node: Node3D = (load(PROTO + "door-sliding-double.glb") as PackedScene).instantiate()
	node.scale = Vector3(T * 1.1, T * 1.25, T * 1.1)
	node.rotation.y = 0.0 if vertical else PI * 0.5
	node.position = pos
	add_child(node)
	var anim: AnimationPlayer = null
	var found := node.find_children("*", "AnimationPlayer", true, false)
	if not found.is_empty():
		anim = found[0]
	# A lamp over the door: red while shut, green while open.
	var lamp := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.25, 0.5)
	lamp.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.albedo_color = Color("4dff7a")
	mat.emission = mat.albedo_color
	lamp.material_override = mat
	lamp.position = pos + Vector3(0, T * 1.15, 0)
	add_child(lamp)
	doors.append({"node": node, "anim": anim, "lamp": lamp, "closed": false})
	if anim:
		anim.play("open")


func _bases() -> void:
	for team in 2:
		var p: Vector2 = grid.bases[team]
		var pad := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = Rules.FLAG_RADIUS
		disc.bottom_radius = Rules.FLAG_RADIUS
		disc.height = 0.06
		pad.mesh = disc
		var mat := StandardMaterial3D.new()
		mat.albedo_color = GameConfig.TEAM_COLORS[team]
		mat.emission_enabled = true
		mat.emission = GameConfig.TEAM_COLORS[team]
		mat.emission_energy_multiplier = 0.4
		pad.material_override = mat
		pad.position = Vector3(p.x, 0.04, p.y)
		add_child(pad)
		base_pads.append(pad)


func _pos(c: Vector2i) -> Vector3:
	var p := grid.center_of(c)
	return Vector3(p.x, 0.0, p.y)


# --- Batching ---------------------------------------------------------------

func _batch(path: String, xf: Transform3D) -> void:
	if not _batches.has(path):
		_batches[path] = []
	_batches[path].append(xf)


func _flush_batches() -> void:
	for path in _batches:
		var scene: PackedScene = load(path)
		var root := scene.instantiate()
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var local := _relative(mi, root)
			var mmi := MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = (mi as MeshInstance3D).mesh
			mm.instance_count = _batches[path].size()
			for i in _batches[path].size():
				mm.set_instance_transform(i, _batches[path][i] * local)
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mmi)
		root.free()
	_batches.clear()


static func _relative(node: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D()
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
