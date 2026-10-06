class_name MenuBackdrop
extends Node3D
## Behind the menus: bots having a foam fight in the gym, seen from a slowly
## circling camera. It's a real match run by a MatchHost on this device, drawn
## straight from the host's messages, with no network and no sound.

const BOTS := 6

var host: MatchHost
var grid: ArenaGrid
var _views := {}
var _darts: DartField
var _cam: Camera3D
var _t := 0.0


func _ready() -> void:
	grid = ArenaGrid.make("gym")
	var arena := ArenaView.new()
	add_child(arena)
	arena.build(grid)
	_darts = DartField.new()
	_darts.quiet = true
	add_child(_darts)
	_darts.setup(grid, Callable())
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var players := {}
	for i in BOTS:
		var id := -(i + 1)
		players[id] = {"name": GameConfig.BOT_NAMES[i], "look": (i * 3 + rng.randi() % 3) % GameConfig.LOOKS.size(),
			"blaster": i % Rules.BLASTERS.size(), "slot": i, "bot": true, "peer": 0, "seat": 0}
		var v := CamperView.new()
		add_child(v)
		v.setup(id, "", int(players[id].look), GameConfig.slot_color(i), -1, int(players[id].blaster), false)
		_views[id] = v
	host = MatchHost.new()
	add_child(host)
	var settings := Rules.DEFAULT_SETTINGS.duplicate()
	settings.minutes = 0
	settings.target = 100000
	host.setup({"seed": rng.randi(), "players": players, "settings": settings}, self)
	host.phase = Rules.Phase.PLAY
	_cam = Camera3D.new()
	_cam.fov = 50
	add_child(_cam)
	_cam.current = true
	_t = rng.randf() * TAU
	_place()


## The host's messages, applied directly.
func broadcast(method: String, args: Array) -> void:
	match method:
		"_h_snapshot":
			for e in args[1]:
				var v: CamperView = _views.get(int(e[0]))
				if v:
					v.apply(e)
		"_h_darts":
			_darts.fired(args[0], host.time)
			for e in args[0]:
				var v: CamperView = _views.get(int(e[1]))
				if v:
					v.show_fire()
		"_h_dart_ends":
			_darts.landed(args[0])
		"_h_pickups":
			_darts.pickups_changed(args[0], args[1])
		"_h_event":
			if int(args[0]) == MatchHost.Ev.TAG:
				var v: CamperView = _views.get(int(args[2]))
				if v:
					v.show_out()


func send(_peer: int, _method: String, _args: Array) -> void:
	pass


func _process(delta: float) -> void:
	_t += delta * 0.05
	_place()


func _place() -> void:
	var size := grid.world_size()
	var center := Vector3(size.x * 0.5, 0, size.y * 0.5)
	var r := size.x * 0.42
	_cam.position = center + Vector3(cos(_t) * r, 17.0, sin(_t) * r * 0.75)
	_cam.look_at(center + Vector3(0, 0.5, 0))
