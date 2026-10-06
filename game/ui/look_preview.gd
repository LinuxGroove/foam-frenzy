class_name LookPreview
extends SubViewportContainer
## A small turning view of a camper's look and blaster, so players can see
## what they'll look like while they pick in the lobby.

const TURN_SPEED := 0.7

var _view: CamperView
var _pivot: Node3D
var _look := -1
var _blaster := -1
var _color := Color.WHITE


static func make(look: int, blaster: int, color: Color, size := Vector2(170, 200)) -> LookPreview:
	var p := LookPreview.new()
	p.custom_minimum_size = size
	p.stretch = true
	p._color = color
	p.set_camper(look, blaster)
	return p


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 38.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.25, 3.9), Vector3(0, 0.72, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.95)
	env.environment.ambient_light_energy = 0.7
	vp.add_child(env)
	_pivot = Node3D.new()
	vp.add_child(_pivot)


func set_camper(look: int, blaster: int) -> void:
	if look == _look and blaster == _blaster:
		return
	_look = look
	_blaster = blaster
	if _view:
		_pivot.remove_child(_view)
		_view.queue_free()
	_view = CamperView.new()
	_pivot.add_child(_view)
	_view.setup(0, "", look, _color, -1, blaster, true)
	_view.set_local(Vector2.ZERO, 0.0, false, false)
	_view.alive = true
	for c in _view.get_children():
		if c is Label3D or (c is MeshInstance3D and c != _view.rig):
			c.visible = false


func set_color(color: Color) -> void:
	_color = color
	var look := _look
	_look = -1
	set_camper(look, _blaster)


func _process(delta: float) -> void:
	_pivot.rotation.y = wrapf(_pivot.rotation.y + TURN_SPEED * delta, -PI, PI)
