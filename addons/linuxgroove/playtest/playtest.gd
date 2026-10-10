class_name LGPlaytest
extends Node
## Records a play test while someone plays with nobody watching: a small
## picture every few seconds (and every second around the moments that
## matter), what happens in the game, how smoothly it runs and which controls
## are used. The player notes moments as they play (F8, or "Note this moment"
## in a pause menu) and answers a short survey when they finish. Everything
## goes into one zip in user://playtest/ for them to send on; nothing leaves
## the computer.
##
## Games call [method setup] once at startup. Recording starts when the "Play
## test recording" setting is on (or with `-- --playtest`), and ends with the
## survey when the game quits through LGScenes.quit(), when the window is
## closed or when the setting is turned off. Games add their own events with
## [method event] and [method moment], and [method follow] the player so the
## recording knows where they were.

signal recording_changed(on: bool)

const DIR := "user://playtest"
## Above every game's menus, below the on-screen keyboard and scene fades.
const LAYER := 90
const NOTE_KEY := KEY_F8
## Seconds between pictures (most are only kept for a while), between
## performance lines and between position samples.
const GRAB_EVERY := 1.0
const PERF_EVERY := 5.0
const FOLLOW_EVERY := 1.0
## Pictures are saved every second for this long after a mark or moment.
const DENSE_FOR := 5.0
const IDLE_AFTER := 60.0
## Frames longer than this count as hitches in each performance line; ones
## longer than FREEZE_MS get their own event, at most one every FREEZE_GAP.
const HITCH_MS := 100.0
const FREEZE_MS := 500.0
const FREEZE_GAP := 10.0
## Setting keys that never go into a recording.
const SECRET := ["key", "token", "password", "secret"]

static var _current: LGPlaytest

var game_id := ""
## "questions": extra survey questions, [{"id", "text", "kind": "rating" or
## "text"}]. "skip": ids of standard questions that don't fit the game.
var options := {}
## Where sessions and zips go (tests point it elsewhere).
var dir := DIR
var capture: LGPlaytestCapture
## Sessions a crash cut short, packed when the game started.
var recovered: Array[String] = []

var _session := ""
var _log: FileAccess
var _t0 := 0
var _finishing := false
var _overlay: CanvasLayer
var _dot: Label
var _open: Control
var _was_paused := false
var _was_mouse := Input.MOUSE_MODE_VISIBLE
var _was_focus: Control
var _follow: WeakRef
var _path: Array = []
var _frames := PackedFloat32Array()
var _last_tick := 0
var _last_freeze := -FREEZE_GAP
var _next_grab := 0.0
var _next_perf := 0.0
var _next_follow := 0.0
var _last_input := 0.0
var _idle := false
var _device := ""
var _presses := {}
var _paused := false
var _marks := 0
var _intro_pending := false


## Adds the recorder to the game. Call once at startup, after the game's
## setting defaults are registered.
static func setup(p_game_id: String, p_options := {}) -> LGPlaytest:
	if current():
		return _current
	var p := LGPlaytest.new()
	p.game_id = p_game_id
	p.options = p_options
	_current = p
	var tree := Engine.get_main_loop() as SceneTree
	# Deferred: callers are usually in the middle of their own _ready.
	tree.root.add_child.call_deferred(p)
	return p


static func current() -> LGPlaytest:
	return _current if is_instance_valid(_current) else null


## Whether a play test is being recorded right now.
static func recording() -> bool:
	var p := current()
	return p != null and p.is_recording()


## Something that happened in the game, such as "died" or "deck_saved".
## Values should be plain: numbers, strings, arrays and dictionaries.
static func event(type: String, data := {}) -> void:
	var p := current()
	if p and p.is_recording():
		p.log_event(type, data)


## An event worth seeing, such as dying or an ending: the pictures from just
## before and after it are kept as well, and its line says "moment": true.
static func moment(type: String, data := {}) -> void:
	var p := current()
	if p and p.is_recording():
		p.log_event(type, data.merged({"moment": true}))
		p._keep_pictures()


## Where the player is (a Node3D or Node2D), sampled every second.
static func follow(node: Node) -> void:
	var p := current()
	if p:
		p._follow = weakref(node) if node else null


func _ready() -> void:
	name = "LGPlaytest"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = CanvasLayer.new()
	_overlay.layer = LAYER
	add_child(_overlay)
	var settings := get_node_or_null("/root/LGSettings")
	if settings:
		settings.changed.connect(_on_setting_changed)
	var scenes := get_node_or_null("/root/LGScenes")
	if scenes:
		scenes.scene_changed.connect(_on_scene_changed)
	recovered = LGPlaytestPack.recover(dir)
	if asked() and DisplayServer.get_name() != "headless":
		begin()
		# The card waits for the first screen, so that screen can't take its focus.
		_intro_pending = scenes != null
		if not _intro_pending:
			show_intro()


## Whether this run should record: the setting, or `-- --playtest`.
func asked() -> bool:
	if "--playtest" in OS.get_cmdline_user_args():
		return true
	var settings := get_node_or_null("/root/LGSettings")
	return settings != null and bool(settings.get_value("playtest", "record", false))


func is_recording() -> bool:
	return _session != ""


## Whether the survey or the last card is showing.
func is_finishing() -> bool:
	return _finishing


## Seconds since the session started.
func elapsed() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


## The folder this session is written to, or "" when not recording.
func session_dir() -> String:
	return _session


## Starts a session.
func begin() -> void:
	if is_recording():
		return
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "-")
	var folder := dir.path_join(stamp)
	var n := 1
	while DirAccess.dir_exists_absolute(folder):
		n += 1
		folder = dir.path_join("%s-%d" % [stamp, n])
	DirAccess.make_dir_recursive_absolute(folder.path_join("frames"))
	_log = FileAccess.open(folder.path_join("events.jsonl"), FileAccess.WRITE)
	if _log == null:
		push_warning("Play test: could not write to %s" % folder)
		return
	_session = folder
	_t0 = Time.get_ticks_msec()
	_next_grab = 0.0
	_next_perf = PERF_EVERY
	_next_follow = 0.0
	_last_input = 0.0
	_idle = false
	_device = ""
	_presses = {}
	_frames = PackedFloat32Array()
	_last_tick = 0
	_last_freeze = -FREEZE_GAP
	_path = []
	_marks = 0
	_paused = get_tree().paused
	capture = LGPlaytestCapture.new(get_viewport(), folder.path_join("frames"))
	LGPlaytestPack.write_json(folder.path_join("session.json"), describe())
	var scene := get_tree().current_scene
	log_event("start", {"scene": _scene_name(scene) if scene else ""})
	# Closing the window ends the session with the survey (_notification).
	get_tree().auto_accept_quit = false
	_show_dot(true)
	recording_changed.emit(true)


## The game, build, computer and settings, for session.json.
func describe() -> Dictionary:
	var pads := []
	for i in Input.get_connected_joypads():
		pads.append(Input.get_joy_name(i))
	var memory: Dictionary = OS.get_memory_info()
	return {
		"game": game_id,
		"version": LGVersion.current(),
		"started": Time.get_datetime_string_from_system(true) + "Z",
		"os": OS.get_name(),
		"distro": OS.get_distribution_name(),
		"os_version": OS.get_version(),
		"arch": Engine.get_architecture_name(),
		"cpu": OS.get_processor_name(),
		"cpus": OS.get_processor_count(),
		"memory_mb": int(memory.get("physical", 0) / 1048576),
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"graphics": "%s %s (%s)" % [RenderingServer.get_current_rendering_driver_name(),
			RenderingServer.get_video_adapter_api_version(), RenderingServer.get_current_rendering_method()],
		"screen": _plain(DisplayServer.screen_get_size()),
		"window": _plain(DisplayServer.window_get_size()),
		"scale_3d": _finite(get_tree().root.scaling_3d_scale) if is_inside_tree() else 1.0,
		"refresh_rate": _finite(DisplayServer.screen_get_refresh_rate()),
		"pads": pads,
		"locale": OS.get_locale(),
		"settings": settings_snapshot(),
	}


## Every setting, without anything secret (the server key).
func settings_snapshot() -> Dictionary:
	var settings := get_node_or_null("/root/LGSettings")
	if settings == null or not settings.has_method("all_values"):
		return {}
	var all: Dictionary = settings.all_values()
	var out := {}
	for section in all:
		out[section] = {}
		for key in all[section]:
			if not _secret(str(key)):
				out[section][key] = _plain(all[section][key])
	return out


static func _secret(key: String) -> bool:
	for word in SECRET:
		if key.to_lower().contains(word):
			return true
	return false


## Writes one line to events.jsonl: seconds since the start, the type and the data.
func log_event(type: String, data := {}) -> void:
	if _log == null:
		return
	var line := {"t": snappedf(elapsed(), 0.01), "type": type}
	for k in data:
		if not line.has(k):
			line[k] = _plain(data[k])
	_log.store_line(JSON.stringify(line))
	# Flushed every line, so a crash loses nothing.
	_log.flush()


## Notes a moment the player picked: fun, bored, lost, frustrated, broken or sick.
func mark(tag: String, note := "") -> void:
	if not is_recording():
		return
	_marks += 1
	log_event("mark", {"tag": tag, "note": note.strip_edges()})
	_keep_pictures()


func _keep_pictures() -> void:
	if capture:
		var ms := int(elapsed() * 1000)
		capture.keep_recent()
		capture.dense_until(ms + int(DENSE_FOR * 1000))


func _process(_delta: float) -> void:
	if not is_recording():
		return
	var now := Time.get_ticks_usec()
	if _last_tick > 0:
		var ms := (now - _last_tick) / 1000.0
		_frames.append(ms)
		if ms > FREEZE_MS and _open == null and elapsed() - _last_freeze > FREEZE_GAP:
			_last_freeze = elapsed()
			log_event("freeze", {"ms": roundi(ms)})
	_last_tick = now
	var t := elapsed()
	var paused := get_tree().paused
	if paused != _paused:
		_paused = paused
		log_event("paused" if paused else "resumed")
	# No pictures of the recorder's own cards and questions.
	if t >= _next_grab and _open == null:
		_next_grab = t + GRAB_EVERY
		capture.grab(int(t * 1000))
	if t >= _next_follow:
		_next_follow = t + FOLLOW_EVERY
		_sample_position()
	if t >= _next_perf:
		_next_perf = t + PERF_EVERY
		_perf_line()
	if not _idle and t - _last_input > IDLE_AFTER and get_window().has_focus():
		_idle = true
		log_event("idle", {"for": roundi(t - _last_input)})


func _sample_position() -> void:
	var node: Node = _follow.get_ref() if _follow else null
	if node is Node3D and node.is_inside_tree():
		var p: Vector3 = node.global_position
		_path.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)])
	elif node is Node2D and node.is_inside_tree():
		var p2: Vector2 = node.global_position
		_path.append([snappedf(p2.x, 0.1), snappedf(p2.y, 0.1)])


## One "perf" line: frame rate and frame times since the last one, memory,
## draw calls, button presses per device and where the player was.
func _perf_line() -> void:
	var f := _frames
	_frames = PackedFloat32Array()
	if f.is_empty():
		return
	var sorted := Array(f)
	sorted.sort()
	var total := 0.0
	var hitches := 0
	for ms in f:
		total += ms
		if ms > HITCH_MS:
			hitches += 1
	var data := {
		"fps": roundi(f.size() * 1000.0 / maxf(total, 0.001)),
		"p95_ms": snappedf(sorted[int(0.95 * (sorted.size() - 1))], 0.1),
		"max_ms": snappedf(sorted[-1], 0.1),
		"hitches": hitches,
		"vram_mb": roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		"draws": roundi(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"presses": _presses,
	}
	# Only debug builds track the game's own memory.
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC)
	if mem > 0.0:
		data["mem_mb"] = roundi(mem / 1048576.0)
	if not _path.is_empty():
		data["at"] = _path
	_presses = {}
	_path = []
	log_event("perf", data)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == NOTE_KEY:
		if is_recording():
			get_viewport().set_input_as_handled()
			open_note()
		return
	if not is_recording():
		return
	var device := device_of(event)
	if device == "":
		return
	_last_input = elapsed()
	if _idle:
		_idle = false
		log_event("active")
	# Keyboard and mouse are one way of playing; a line each time the hand
	# moves between them would bury everything else.
	var way := "pad" if device == "pad" else "keyboard and mouse"
	if way != _device:
		_device = way
		log_event("device", {"device": way, "name": Input.get_joy_name(event.device) if device == "pad" else ""})
	if _is_press(event):
		_presses[device] = int(_presses.get(device, 0)) + 1


## "keyboard", "mouse", "pad", or "" for events that don't show someone playing.
static func device_of(event: InputEvent) -> String:
	if event is InputEventKey:
		return "keyboard"
	if event is InputEventMouseButton:
		return "mouse"
	if event is InputEventMouseMotion:
		return "mouse" if (event as InputEventMouseMotion).relative.length() > 2.0 else ""
	if event is InputEventJoypadButton:
		return "pad"
	if event is InputEventJoypadMotion:
		return "pad" if absf((event as InputEventJoypadMotion).axis_value) > 0.5 else ""
	return ""


static func _is_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton or event is InputEventJoypadButton:
		return event.pressed
	return false


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			if _finishing:
				# Closed again during the survey: save what there is and go.
				_end("window", {})
				get_tree().quit()
			elif is_recording():
				_finish_and_quit()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if is_recording():
				log_event("focus_out")
		NOTIFICATION_APPLICATION_FOCUS_IN:
			if is_recording():
				log_event("focus_in")


func _finish_and_quit() -> void:
	await finish("window")
	get_tree().quit()


func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section != "playtest" or key != "record" or _finishing:
		return
	if value and not is_recording():
		begin()
		show_intro()
	elif not value and is_recording():
		finish("settings")


func _on_scene_changed(scene: Node) -> void:
	if is_recording():
		log_event("scene", {"name": _scene_name(scene)})
	if _intro_pending:
		_intro_pending = false
		show_intro()
	elif _open:
		# The new screen focused its own menu; the card stays in charge.
		LGUi.focus_first(_open)


static func _scene_name(scene: Node) -> String:
	if scene.scene_file_path != "":
		return scene.scene_file_path.get_file().get_basename()
	return str(scene.name)


## Ends the session: the survey, then the zip, then where it went. `how` is
## "quit", "window" or "settings". Await it before quitting.
func finish(how: String) -> void:
	if not is_recording() or _finishing:
		return
	_finishing = true
	log_event("survey")
	var survey := LGPlaytestSurvey.make(options)
	_show(survey)
	var answers: Dictionary = await survey.done
	if not is_recording():
		# Closed during the survey and already saved.
		return
	var zip := _end(how, answers)
	var card := LGPlaytestCard.done(zip, how != "settings")
	_show(card)
	await card.closed
	_finishing = false


## Closes the session and packs it. Returns the zip's path.
func _end(how: String, answers: Dictionary) -> String:
	if not is_recording():
		return ""
	log_event("end", {"how": how, "marks": _marks})
	capture.finish()
	_log.close()
	_log = null
	var folder := _session
	_session = ""
	if not answers.is_empty():
		LGPlaytestPack.write_json(folder.path_join("survey.json"), answers)
	var info := LGPlaytestPack.read_json(folder.path_join("session.json"))
	info["ended"] = Time.get_datetime_string_from_system(true) + "Z"
	info["ended_how"] = how
	info["minutes"] = snappedf((Time.get_ticks_msec() - _t0) / 60000.0, 0.1)
	info["marks"] = _marks
	info["pictures"] = capture.saved
	LGPlaytestPack.write_json(folder.path_join("session.json"), info)
	capture = null
	var zip := LGPlaytestPack.pack(folder, LGPlaytestPack.current_log())
	get_tree().auto_accept_quit = true
	_show_dot(false)
	recording_changed.emit(false)
	return zip


## The card that says what's recorded and how to note moments.
func show_intro() -> void:
	if _open:
		return
	_show(LGPlaytestCard.intro(recovered.size()))


## Asks what's happening right now and notes it.
func open_note() -> void:
	if not is_recording() or _open != null or _finishing:
		return
	# The seconds before the press, before the card covers the game.
	_keep_pictures()
	var note := LGPlaytestNote.make()
	_show(note)
	var picked: Array = await note.done
	if picked.size() == 2:
		mark(picked[0], picked[1])


## Shows one of the recorder's panels over the game, pausing it when no one
## else is playing, until the panel frees itself.
func _show(panel: Control) -> void:
	if _open and is_instance_valid(_open):
		# One panel after another (the survey, then the last card): the game
		# goes back to how it was before the first.
		_open.queue_free()
	else:
		_was_paused = get_tree().paused
		_was_mouse = Input.mouse_mode
		_was_focus = get_viewport().gui_get_focus_owner()
	_open = panel
	if get_tree().get_multiplayer().get_peers().is_empty():
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.tree_exited.connect(_on_panel_closed.bind(panel), CONNECT_ONE_SHOT)
	_overlay.add_child(panel)


func _on_panel_closed(panel: Control) -> void:
	if _open != panel or not is_inside_tree():
		return
	_open = null
	get_tree().paused = _was_paused
	Input.mouse_mode = _was_mouse
	if is_instance_valid(_was_focus) and _was_focus.is_visible_in_tree():
		_was_focus.grab_focus()


func _show_dot(on: bool) -> void:
	if _dot == null:
		_dot = Label.new()
		_dot.text = "● Play test"
		_dot.theme_type_variation = "HintLabel"
		_dot.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3, 0.8))
		_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dot.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
		_dot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_overlay.add_child(_dot)
	_dot.visible = on


static func _finite(x: float) -> float:
	return snappedf(x, 0.01) if is_finite(x) else -1.0


## JSON-friendly copies of vectors and other engine values.
static func _plain(v: Variant) -> Variant:
	match typeof(v):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [v.x, v.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [v.x, v.y, v.z]
		TYPE_COLOR:
			return v.to_html()
		TYPE_OBJECT:
			return str(v)
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_plain(x))
			return a
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k)] = _plain(v[k])
			return d
	return v
