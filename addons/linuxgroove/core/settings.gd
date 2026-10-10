extends Node
## Persistent player settings shared by every LinuxGroove game (autoload: LGSettings).
##
## Values live in `user://settings.cfg`. Games register their own defaults with
## [method register_defaults] before reading them. Command-line arguments after
## `--` override any value for one run, e.g. `-- --set=lan/port=7000`.

signal changed(section: String, key: String, value: Variant)

const PATH := "user://settings.cfg"
## The pixels Auto resolution draws the 3D at, at most: 1920x1200's worth.
const AUTO_PIXELS := 1920.0 * 1200.0

const BASE_DEFAULTS := {
	"player": {
		"name": "",
		"look": 0,
	},
	"video": {
		"fullscreen": true,
		"vsync": true,
		"ui_scale": 1.0,
		# The share of the screen's resolution the 3D draws at, upscaled with
		# FSR; 0 is Auto (about 1920x1200's worth of pixels on bigger screens).
		"resolution": 0.0,
	},
	"audio": {
		"master": 0.9,
		"music": 0.6,
		"sfx": 0.9,
		"voice": true,
	},
	"input": {
		"stick_deadzone": 0.25,
		"vibration": true,
	},
	"lan": {
		"port": 24680,
		"beacon_port": 24681,
	},
	"online": {
		"enabled": false,
		"host": "127.0.0.1",
		"port": 7350,
		"scheme": "http",
		"server_key": "defaultkey",
	},
	"ai": {
		"mode": "auto",
		"external_url": "http://localhost:13305/api/v1",
		"model": "Qwen3-4B-Instruct-2507-GGUF",
	},
	"playtest": {
		"record": false,
	},
}

var _cfg := ConfigFile.new()
var _defaults := {}
var _overrides := {}


func _init() -> void:
	register_defaults(BASE_DEFAULTS)
	# The first autoload, so everything after sees the right version.
	LGVersion.stamp_from_source()


func _ready() -> void:
	load_settings()
	_parse_command_line()
	apply_video()
	apply_audio()


## Adds or replaces default values. `defaults` is {section: {key: value}}.
func register_defaults(defaults: Dictionary) -> void:
	for section in defaults:
		if not _defaults.has(section):
			_defaults[section] = {}
		for key in defaults[section]:
			_defaults[section][key] = defaults[section][key]


func get_value(section: String, key: String, fallback: Variant = null) -> Variant:
	var override_key := "%s/%s" % [section, key]
	if _overrides.has(override_key):
		return _overrides[override_key]
	var default: Variant = fallback
	if _defaults.has(section) and _defaults[section].has(key):
		default = _defaults[section][key]
	return _cfg.get_value(section, key, default)


## Every setting with its current value, as {section: {key: value}}.
func all_values() -> Dictionary:
	var out := {}
	for section in _defaults:
		out[section] = {}
		for key in _defaults[section]:
			out[section][key] = get_value(section, key)
	for section in _cfg.get_sections():
		if not out.has(section):
			out[section] = {}
		for key in _cfg.get_section_keys(section):
			out[section][key] = get_value(section, key)
	return out


func set_value(section: String, key: String, value: Variant, persist := true) -> void:
	_cfg.set_value(section, key, value)
	_overrides.erase("%s/%s" % [section, key])
	if persist:
		save_settings()
	changed.emit(section, key, value)
	if section == "video":
		apply_video()
	elif section == "audio":
		apply_audio()


func load_settings() -> void:
	if FileAccess.file_exists(PATH):
		var err := _cfg.load(PATH)
		if err != OK:
			push_warning("Settings: could not read %s (error %d), using defaults" % [PATH, err])
			_cfg = ConfigFile.new()


func save_settings() -> void:
	var err := _cfg.save(PATH)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [PATH, err])


func apply_video() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_tree().root if is_inside_tree() else null
	if window == null:
		return
	var fullscreen: bool = get_value("video", "fullscreen")
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if get_value("video", "vsync") else DisplayServer.VSYNC_DISABLED)
	window.content_scale_factor = float(get_value("video", "ui_scale"))
	scale_3d(window)
	if not window.size_changed.is_connected(_on_window_resized):
		window.size_changed.connect(_on_window_resized)


func _on_window_resized() -> void:
	scale_3d(get_tree().root)


## The share of the screen's resolution 3D draws at: the Resolution setting,
## or for Auto as much as keeps it near 1920x1200 (all of it on smaller
## screens, where nothing is gained).
func resolution_scale() -> float:
	var r := float(get_value("video", "resolution"))
	if r > 0.0:
		return clampf(r, 0.25, 1.0)
	var size := DisplayServer.window_get_size()
	return clampf(sqrt(AUTO_PIXELS / float(maxi(size.x * size.y, 1))), 0.5, 1.0)


## Draws a viewport's 3D at [method resolution_scale], upscaled with FSR where
## the renderer has it. The root viewport is done for you; a game that draws
## 3D in SubViewports of its own (split screen) calls this for each of them.
func scale_3d(viewport: Viewport) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var s := resolution_scale()
	viewport.scaling_3d_scale = s
	var fsr := s < 0.99 and RenderingServer.get_current_rendering_method() != "gl_compatibility"
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if fsr else Viewport.SCALING_3D_MODE_BILINEAR


func apply_audio() -> void:
	_set_bus_volume("Master", float(get_value("audio", "master")))
	_set_bus_volume("Music", float(get_value("audio", "music")))
	_set_bus_volume("SFX", float(get_value("audio", "sfx")))


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


## Supports `--set=section/key=value` (repeatable), plus `--windowed`.
func _parse_command_line() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg == "--windowed":
			_overrides["video/fullscreen"] = false
		elif arg.begins_with("--set="):
			var spec: String = arg.substr(6)
			var eq := spec.find("=")
			if eq <= 0:
				continue
			var path := spec.substr(0, eq)
			var raw := spec.substr(eq + 1)
			_overrides[path] = _coerce(path, raw)


func _coerce(path: String, raw: String) -> Variant:
	var parts := path.split("/")
	if parts.size() == 2 and _defaults.has(parts[0]) and _defaults[parts[0]].has(parts[1]):
		var default: Variant = _defaults[parts[0]][parts[1]]
		match typeof(default):
			TYPE_BOOL:
				return raw.to_lower() in ["1", "true", "yes", "on"]
			TYPE_INT:
				return raw.to_int()
			TYPE_FLOAT:
				return raw.to_float()
	return raw
