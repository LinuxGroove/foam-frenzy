class_name CamperView
extends Node3D
## A camper on screen: the animated Blocky Character holding its blaster, a
## coloured ring under its feet, its name, foam left (hit points) and, in
## Capture the Flag, the flag on its back. Remote campers glide towards the
## latest position the host sent; this device's own campers are placed
## directly by LocalCamper.

const MODEL_SCALE := 0.6
const FOLLOW_RATE := 16.0
const FLAG_SCENE := "res://assets/kenney/prototype-kit/flag.glb"

var id := 0
var color := Color.WHITE
var team := -1
var alive := false
var diving := false
var shielded := false
var carrying := false
var hp := Rules.HP
var ammo := 0
var rig: RigCharacter

var _remote := true
var _placed := false
var _target := Vector3.ZERO
var _target_yaw := 0.0
var _moving := false
var _tag: Label3D
var _name := ""
var _ring: MeshInstance3D
var _pips: Array[MeshInstance3D] = []
var _pip_on: StandardMaterial3D
var _pip_off: StandardMaterial3D
var _flag: Node3D
var _shield: MeshInstance3D
var _blaster: Node3D
var _dive_tilt := 0.0
var _blink := 0.0
var _show_ammo := false


func setup(p_id: int, p_name: String, look: int, p_color: Color, p_team: int, blaster: int, local: bool, show_ammo := false) -> void:
	id = p_id
	color = p_color
	team = p_team
	_remote = not local
	_show_ammo = show_ammo
	rig = RigCharacter.create(GameConfig.look_scene(look), MODEL_SCALE)
	add_child(rig)
	rig.set_looping("holding-right")
	_attach_blaster(blaster)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.48
	torus.outer_radius = 0.66
	torus.rings = 24
	torus.ring_segments = 6
	_ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = color
	_ring.material_override = ring_mat
	_ring.scale = Vector3(1, 0.15, 1)
	_ring.position.y = 0.04
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_tag = Label3D.new()
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	# The same size on screen however far the camera pulls back.
	_tag.fixed_size = true
	_tag.pixel_size = 0.0006
	_tag.font_size = 40
	_tag.outline_size = 12
	_tag.position.y = 2.25
	_name = p_name
	_tag.text = p_name
	_tag.modulate = color.lightened(0.2)
	add_child(_tag)
	_pip_on = StandardMaterial3D.new()
	_pip_on.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pip_on.albedo_color = Color("fff6e0")
	_pip_on.no_depth_test = true
	_pip_off = _pip_on.duplicate()
	_pip_off.albedo_color = Color(0.15, 0.15, 0.2, 0.8)
	_pip_off.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in Rules.HP:
		var pip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.2, 0.09, 0.09)
		pip.mesh = box
		pip.position = Vector3((i - (Rules.HP - 1) * 0.5) * 0.26, 1.95, 0)
		pip.material_override = _pip_on
		pip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pip)
		_pips.append(pip)
	_shield = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.95
	sphere.height = 1.9
	_shield.mesh = sphere
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(color, 0.18)
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield.material_override = sm
	_shield.position.y = 0.85
	_shield.visible = false
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shield)
	visible = false


func _attach_blaster(blaster: int) -> void:
	var sk := rig.skeleton()
	var path := "res://assets/kenney/blaster-kit/%s.glb" % Rules.blaster(blaster).model
	_blaster = (load(path) as PackedScene).instantiate()
	if sk == null:
		_blaster.position = Vector3(0.3, 0.9, 0.3)
		add_child(_blaster)
		return
	var attach := BoneAttachment3D.new()
	attach.bone_name = "arm-right"
	sk.add_child(attach)
	# In model units (the rig is scaled by MODEL_SCALE).
	_blaster.scale = Vector3.ONE * 2.2
	_blaster.position = Vector3(-0.05, -0.62, 0.42)
	_blaster.rotation_degrees = Vector3(0, 0, 0)
	attach.add_child(_blaster)


func set_team_color(c: Color) -> void:
	color = c
	(_ring.material_override as StandardMaterial3D).albedo_color = c
	_tag.modulate = c.lightened(0.2)


## This device's own camper.
func set_local(pos: Vector2, yaw: float, moving: bool, dive: bool) -> void:
	position = Vector3(pos.x, 0.0, pos.y)
	rotation.y = yaw
	_moving = moving
	diving = dive
	_placed = true


## One entry of the host's snapshot (see MatchHost._actor_snapshot).
func apply(entry: Array) -> void:
	var flags := int(entry[4])
	var was_alive := alive
	alive = flags & MatchHost.F_ALIVE != 0
	shielded = flags & MatchHost.F_SHIELD != 0
	carrying = flags & MatchHost.F_FLAG != 0
	hp = int(entry[5])
	ammo = int(entry[6])
	if _remote:
		diving = flags & MatchHost.F_DIVE != 0
		_moving = flags & MatchHost.F_MOVING != 0
		_target = Vector3(entry[1], 0.0, entry[2])
		_target_yaw = entry[3]
		if not _placed or (alive and not was_alive):
			position = _target
			rotation.y = _target_yaw
			_placed = true
	if flags & MatchHost.F_FIRED != 0 and _remote:
		show_fire()
	if flags & MatchHost.F_TAUNT != 0 and rig.current_clip() != "emote-yes":
		rig.play_once("emote-yes")
	if alive and not was_alive:
		rig.play("holding-right")
	_refresh()


func show_fire() -> void:
	if rig.current_clip() != "holding-right-shoot" or not rig.busy():
		rig.play_once("holding-right-shoot", 0.05, 1.6)


func show_out() -> void:
	rig.play_once("die", 0.05)
	alive = false


func set_carrying(team_flag: int) -> void:
	if team_flag < 0:
		if _flag:
			_flag.queue_free()
			_flag = null
		return
	if _flag == null:
		_flag = (load(FLAG_SCENE) as PackedScene).instantiate()
		_flag.scale = Vector3.ONE * 1.6
		_flag.position = Vector3(0, 0.6, -0.35)
		add_child(_flag)
		FlagView.tint(_flag, GameConfig.TEAM_COLORS[team_flag])


func _refresh() -> void:
	for i in _pips.size():
		_pips[i].material_override = _pip_on if i < hp else _pip_off
		_pips[i].visible = alive
	_tag.visible = alive
	# Dart Hoarder: everyone's darts show next to their name.
	_tag.text = "%s  %d" % [_name, ammo] if _show_ammo else _name
	_shield.visible = shielded and alive


func _process(delta: float) -> void:
	if not _placed:
		visible = false
		return
	if _remote:
		position = position.lerp(_target, minf(1.0, FOLLOW_RATE * delta))
		rotation.y = lerp_angle(rotation.y, _target_yaw, minf(1.0, FOLLOW_RATE * delta))
	# A dive tips the camper forward; there's no dive clip on the rig.
	var tilt_goal := 1.1 if diving else 0.0
	_dive_tilt = lerpf(_dive_tilt, tilt_goal, minf(1.0, 18.0 * delta))
	rig.rotation.x = _dive_tilt
	rig.position.y = -_dive_tilt * 0.35 + (0.35 if _dive_tilt > 0.05 else 0.0) * _dive_tilt
	if alive:
		visible = true
		if shielded:
			_blink += delta
			rig.visible = fmod(_blink, 0.2) < 0.13
		else:
			rig.visible = true
		if _moving:
			rig.play("walk", 0.12, 1.3)
		else:
			rig.play("holding-right")
	else:
		rig.visible = rig.current_clip() == "die" and rig.busy()
		visible = rig.visible
