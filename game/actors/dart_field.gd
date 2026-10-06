class_name DartField
extends Node3D
## Every foam dart on screen: the ones in flight and the ones lying on the
## floor waiting to be picked up. Each kind is one MultiMesh.
##
## Darts in flight are simulated here from the host's "fired" message (start,
## direction, speed, range) so they move smoothly without a network update
## per frame; the host's "landed" message removes them.

const DART_SCENE := "res://assets/kenney/blaster-kit/bullet-foam.glb"
const DART_SCALE := 7.0
const SFX_WALL := ["res://assets/kenney/audio/sfx/impactGeneric_light_000.ogg",
	"res://assets/kenney/audio/sfx/impactGeneric_light_001.ogg",
	"res://assets/kenney/audio/sfx/impactGeneric_light_002.ogg"]
const SFX_HIT := ["res://assets/kenney/audio/sfx/impactSoft_medium_000.ogg",
	"res://assets/kenney/audio/sfx/impactSoft_medium_001.ogg",
	"res://assets/kenney/audio/sfx/impactSoft_medium_002.ogg"]

var grid: ArenaGrid
## id -> {pos, dir, speed, left, stop, yaw, owner}
var flying := {}
## id -> Vector2
var floor_darts := {}

var _fly_mm: MultiMesh
var _floor_mm: MultiMesh
var _floor_dirty := true
var _puffs: Array[CPUParticles3D] = []
var _puff_i := 0
var _listener: Callable
## No sounds (the menu backdrop).
var quiet := false


func setup(p_grid: ArenaGrid, listener_pos: Callable) -> void:
	grid = p_grid
	_listener = listener_pos
	var mesh := _dart_mesh()
	_fly_mm = _make_mm(mesh, Rules.MAX_DARTS_IN_FLIGHT + 16)
	_floor_mm = _make_mm(mesh, Rules.MAX_PICKUPS + 8)
	for i in 8:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = 14
		p.lifetime = 0.45
		p.explosiveness = 1.0
		p.direction = Vector3.UP
		p.spread = 80.0
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 4.5
		p.gravity = Vector3(0, -9.0, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.2
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.09
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		box.material = mat
		p.mesh = box
		p.color = Color("fff3d6")
		add_child(p)
		_puffs.append(p)


func _dart_mesh() -> Mesh:
	var root := (load(DART_SCENE) as PackedScene).instantiate()
	var found := root.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (found[0] as MeshInstance3D).mesh if not found.is_empty() else BoxMesh.new()
	root.free()
	return mesh


func _make_mm(mesh: Mesh, count: int) -> MultiMesh:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


## [id, owner, x, z, yaw, speed, range] per dart.
func fired(list: Array, match_time: float) -> void:
	for e in list:
		var start := Vector2(e[2], e[3])
		var dir := Rules.yaw_dir(e[4])
		var hit := grid.raycast(start, start + dir * float(e[6]), match_time)
		var stop: float = start.distance_to(hit.point) if hit.hit else float(e[6])
		flying[int(e[0])] = {"pos": start, "dir": dir, "speed": float(e[5]), "left": stop, "yaw": float(e[4]), "owner": int(e[1])}


## [id, x, z, victim] per dart.
func landed(list: Array) -> void:
	for e in list:
		var d: Dictionary = flying.get(int(e[0]), {})
		flying.erase(int(e[0]))
		var at := Vector3(e[1], Rules.DART_HEIGHT, e[2])
		if int(e[3]) != 0:
			_puff(at, Color("fff3d6"))
			_sound(SFX_HIT, at, -2.0)
		elif not d.is_empty():
			_sound(SFX_WALL, at, -10.0)


func pickups_changed(added: Array, removed: Array) -> void:
	for e in added:
		floor_darts[int(e[0])] = Vector2(e[1], e[2])
	for e in removed:
		floor_darts.erase(int(e[0]))
	_floor_dirty = true


func clear() -> void:
	flying.clear()
	floor_darts.clear()
	_floor_dirty = true


func puff(at: Vector3, color: Color) -> void:
	_puff(at, color)


func _process(delta: float) -> void:
	var i := 0
	for id in flying:
		var d: Dictionary = flying[id]
		var step := minf(d.speed * delta, d.left)
		d.pos += d.dir * step
		d.left -= step
		if i < _fly_mm.instance_count:
			var basis := Basis(Vector3.UP, d.yaw) * Basis(Vector3.RIGHT, PI * 0.5)
			_fly_mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * DART_SCALE), Vector3(d.pos.x, Rules.DART_HEIGHT, d.pos.y)))
			i += 1
	_fly_mm.visible_instance_count = i
	if _floor_dirty:
		_floor_dirty = false
		var n := 0
		for id in floor_darts:
			if n >= _floor_mm.instance_count:
				break
			var p: Vector2 = floor_darts[id]
			# Each dart lies at its own angle; the id keeps it steady.
			var basis := Basis(Vector3.UP, float(id * 2654435761 % 6283) / 1000.0) * Basis(Vector3.RIGHT, PI * 0.5)
			_floor_mm.set_instance_transform(n, Transform3D(basis.scaled(Vector3.ONE * DART_SCALE), Vector3(p.x, 0.08, p.y)))
			n += 1
		_floor_mm.visible_instance_count = n


func _puff(at: Vector3, color: Color) -> void:
	var p := _puffs[_puff_i]
	_puff_i = (_puff_i + 1) % _puffs.size()
	p.position = at
	p.color = color
	p.restart()


func _sound(list: Array, at: Vector3, volume: float) -> void:
	if quiet:
		return
	var listener: Vector3 = _listener.call() if _listener.is_valid() else at
	var d := Vector2(at.x - listener.x, at.z - listener.z).length()
	if d > 30.0:
		return
	LGAudio.play_sfx(list[randi() % list.size()], volume - d * 0.4, 0.12)
