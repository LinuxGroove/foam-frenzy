class_name LocalCamper
extends Node
## A camper played on this device: reads its player's own controller (or the
## keyboard and mouse), moves at once for responsiveness and tells the host,
## which may pull it back. Firing and diving are requests the host checks.

const SEND_EVERY := 1.0 / 20.0
const STEP_SOUNDS := [
	"res://assets/kenney/audio/sfx/footstep_concrete_000.ogg",
	"res://assets/kenney/audio/sfx/footstep_concrete_001.ogg",
	"res://assets/kenney/audio/sfx/footstep_concrete_002.ogg",
]
const SFX_FIRE := ["res://assets/kenney/audio/sfx/woosh1.ogg", "res://assets/kenney/audio/sfx/woosh2.ogg", "res://assets/kenney/audio/sfx/woosh5.ogg"]
const SFX_EMPTY := "res://assets/kenney/audio/sfx/drop_001.ogg"
const SFX_DIVE := "res://assets/kenney/audio/sfx/phaseJump1.ogg"
const RETICLE_DISTANCE := 4.5
const ARROW_KEYS := [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]

var game: Node
var id := 0
var seat: LGSeat
var view: CamperView
var pos := Vector2.ZERO
var yaw := 0.0
var aim := Vector2(0, 1)
var placed := false
var alive := false
var moving := false
var dive_t := 0.0
var dive_cd := 0.0
var fire_cd := 0.0
## What the HUD shows for this player: set from the host's snapshots.
var hp := Rules.HP
var ammo := 0
var respawn := 0.0
var carrying := false
var blaster := 0

var _dive_dir := Vector2.ZERO
var _send_t := 0.0
var _step_t := 0.0
var _empty_t := 0.0
var _reticle: Sprite3D
var _aim_line: MeshInstance3D


func setup(p_game: Node, p_id: int, p_seat: LGSeat, p_view: CamperView, slot: int, p_blaster: int) -> void:
	game = p_game
	id = p_id
	seat = p_seat
	view = p_view
	blaster = p_blaster
	var color := GameConfig.slot_color(slot)
	_reticle = Sprite3D.new()
	_reticle.texture = GameConfig.crosshair(slot)
	_reticle.modulate = color
	_reticle.pixel_size = 0.009
	_reticle.axis = Vector3.AXIS_Y
	_reticle.no_depth_test = true
	_reticle.render_priority = 10
	_reticle.visible = false
	game.add_child(_reticle)
	_aim_line = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 1.0)
	quad.orientation = PlaneMesh.FACE_Y
	_aim_line.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, 0.45)
	mat.no_depth_test = true
	_aim_line.material_override = mat
	_aim_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_line.visible = false
	game.add_child(_aim_line)


func place(p: Vector2, p_yaw: float) -> void:
	pos = p
	yaw = p_yaw
	aim = Rules.yaw_dir(p_yaw)
	placed = true
	alive = true
	dive_t = 0.0
	view.set_local(pos, yaw, false, false)


## The host's view of this camper (hit points, darts, alive).
func apply(entry: Array) -> void:
	var flags := int(entry[4])
	var now_alive := flags & MatchHost.F_ALIVE != 0
	if not placed and now_alive:
		place(Vector2(entry[1], entry[2]), entry[3])
	if alive and not now_alive:
		view.show_out()
	alive = now_alive
	hp = int(entry[5])
	ammo = int(entry[6])
	respawn = float(entry[7])
	carrying = flags & MatchHost.F_FLAG != 0


func _physics_process(delta: float) -> void:
	if game == null or seat == null:
		return
	seat.poll(GameConfig.SEAT_ACTIONS)
	fire_cd = maxf(fire_cd - delta, 0.0)
	dive_cd = maxf(dive_cd - delta, 0.0)
	dive_t = maxf(dive_t - delta, 0.0)
	var playing: bool = game.phase == Rules.Phase.PLAY and not game.hud.blocks_input()
	if not placed or not alive or not playing:
		moving = false
		_show_aim(false)
		if placed and alive:
			view.set_local(pos, yaw, false, false)
		return
	var move := seat.vector("move_left", "move_right", "move_up", "move_down")
	_update_aim(move)
	if seat.just_pressed("dive") and dive_cd <= 0.0:
		dive_t = Rules.DIVE_TIME
		dive_cd = Rules.DIVE_COOLDOWN
		_dive_dir = move.normalized() if move.length() > 0.2 else aim
		game.to_host("_c_dive", [id])
		LGAudio.play_sfx(SFX_DIVE, -8.0, 0.1)
	var vel := move * Rules.MOVE_SPEED * (0.9 if carrying else 1.0)
	if dive_t > 0.0:
		vel = _dive_dir * Rules.DIVE_SPEED
	pos = game.grid.move(pos, vel * delta, Rules.CAMPER_RADIUS, game.match_time)
	moving = vel.length() > 0.5
	if _wants_fire() and fire_cd <= 0.0:
		_fire()
	if seat.just_pressed("taunt"):
		game.to_host("_c_taunt", [id])
	view.set_local(pos, yaw, moving, dive_t > 0.0)
	_show_aim(true)
	_footsteps(delta)
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = SEND_EVERY
		game.to_host("_c_state", [id, pos, yaw, moving])


func _update_aim(move: Vector2) -> void:
	var dir := Vector2.ZERO
	if seat.uses_mouse() and game.camera:
		var vp: Viewport = game.get_viewport()
		var g: Vector3 = game.camera.ground_point(vp.get_mouse_position(), Rules.DART_HEIGHT)
		dir = Vector2(g.x, g.z) - pos
		if dir.length() < 0.3:
			dir = aim
	else:
		var stick := seat.vector("aim_left", "aim_right", "aim_up", "aim_down")
		if stick.length() > 0.3:
			dir = stick
		elif move.length() > 0.2:
			dir = move
	if dir.length() > 0.01:
		aim = dir.normalized()
		var assist := int(LGSettings.get_value("play", "aim_assist", 1))
		if not seat.uses_mouse() and assist > 0:
			aim = game.assisted_aim(id, pos, aim, assist)
		yaw = Rules.dir_yaw(aim)


func _wants_fire() -> bool:
	if seat.held("fire"):
		return true
	if seat.keyboard:
		for k in ARROW_KEYS:
			if Input.is_physical_key_pressed(k):
				return true
	if bool(LGSettings.get_value("play", "auto_fire", false)) and seat.has_pad():
		return seat.vector("aim_left", "aim_right", "aim_up", "aim_down").length() > 0.9
	return false


func _fire() -> void:
	var b := Rules.blaster(blaster)
	if ammo <= 0:
		fire_cd = 0.35
		if _empty_t <= 0.0:
			_empty_t = 1.0
			LGAudio.play_sfx(SFX_EMPTY, -6.0)
			game.hud.flash_empty(seat.index)
		return
	fire_cd = float(b.cooldown) + float(b.burst_gap) * (int(b.burst) - 1)
	game.to_host("_c_fire", [id, pos, yaw])
	view.show_fire()
	LGAudio.play_sfx(SFX_FIRE[randi() % SFX_FIRE.size()], -4.0, 0.12)


func _footsteps(delta: float) -> void:
	_empty_t = maxf(_empty_t - delta, 0.0)
	if not moving:
		return
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = 0.32
		LGAudio.play_sfx(STEP_SOUNDS[randi() % STEP_SOUNDS.size()], -18.0, 0.1)


func _show_aim(on: bool) -> void:
	_reticle.visible = on
	_aim_line.visible = on
	if not on:
		return
	var range_m := minf(float(Rules.blaster(blaster).range), RETICLE_DISTANCE if not seat.uses_mouse() else 99.0)
	var end := pos + aim * range_m
	var hit: Dictionary = game.grid.raycast(pos, end, game.match_time)
	if hit.hit:
		end = hit.point
	_reticle.position = Vector3(end.x, 0.06, end.y)
	var start := pos + aim * 0.7
	var mid := (start + end) * 0.5
	var length := maxf(start.distance_to(end), 0.01)
	_aim_line.position = Vector3(mid.x, 0.05, mid.y)
	_aim_line.rotation = Vector3(0, yaw, 0)
	_aim_line.scale = Vector3(1, 1, length)


func _exit_tree() -> void:
	if is_instance_valid(_reticle):
		_reticle.queue_free()
	if is_instance_valid(_aim_line):
		_aim_line.queue_free()
