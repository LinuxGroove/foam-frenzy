extends Node
## Controller-first input setup and button glyphs (autoload: LGInput).
##
## Games describe their actions once with [method register_actions], using
## short binding strings:
##   "key:E"        keyboard key (Godot key name)
##   "joy:a"        gamepad button by position: a (south), b (east), x (west),
##                  y (north), back, start, lb, rb, ls, rs, up, down, left, right
##   "axis:lx-"     stick axis and direction: lx, ly, rx, ry, lt, rt
##   "mouse:left"   mouse button
## The router remembers which kind of device was used last so prompts can show
## the matching glyphs (Xbox, PlayStation, Switch, Steam Deck or keyboard).

signal device_changed(family: String)

const FAMILIES := ["keyboard", "xbox", "playstation", "switch", "steamdeck"]
const GLYPH_DIR := "res://addons/linuxgroove/input/glyphs"

const JOY_NAMES := {
	"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "x": JOY_BUTTON_X, "y": JOY_BUTTON_Y,
	"back": JOY_BUTTON_BACK, "start": JOY_BUTTON_START,
	"lb": JOY_BUTTON_LEFT_SHOULDER, "rb": JOY_BUTTON_RIGHT_SHOULDER,
	"ls": JOY_BUTTON_LEFT_STICK, "rs": JOY_BUTTON_RIGHT_STICK,
	"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN,
	"left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT,
}
const AXIS_NAMES := {
	"lx": JOY_AXIS_LEFT_X, "ly": JOY_AXIS_LEFT_Y,
	"rx": JOY_AXIS_RIGHT_X, "ry": JOY_AXIS_RIGHT_Y,
	"lt": JOY_AXIS_TRIGGER_LEFT, "rt": JOY_AXIS_TRIGGER_RIGHT,
}

## Glyph file per positional button and controller family. Nintendo puts A on
## the east face, so the south button shows "B" there.
const BUTTON_GLYPHS := {
	JOY_BUTTON_A: {"xbox": "xbox_button_color_a", "playstation": "playstation_button_color_cross", "switch": "switch_button_b", "steamdeck": "steamdeck_button_a"},
	JOY_BUTTON_B: {"xbox": "xbox_button_color_b", "playstation": "playstation_button_color_circle", "switch": "switch_button_a", "steamdeck": "steamdeck_button_b"},
	JOY_BUTTON_X: {"xbox": "xbox_button_color_x", "playstation": "playstation_button_color_square", "switch": "switch_button_y", "steamdeck": "steamdeck_button_x"},
	JOY_BUTTON_Y: {"xbox": "xbox_button_color_y", "playstation": "playstation_button_color_triangle", "switch": "switch_button_x", "steamdeck": "steamdeck_button_y"},
	JOY_BUTTON_BACK: {"xbox": "xbox_button_view", "playstation": "playstation5_button_create", "switch": "switch_button_minus", "steamdeck": "steamdeck_button_view"},
	JOY_BUTTON_START: {"xbox": "xbox_button_menu", "playstation": "playstation5_button_options", "switch": "switch_button_plus", "steamdeck": "steamdeck_button_options"},
	JOY_BUTTON_LEFT_SHOULDER: {"xbox": "xbox_lb", "playstation": "playstation_trigger_l1", "switch": "switch_button_l", "steamdeck": "steamdeck_button_l1"},
	JOY_BUTTON_RIGHT_SHOULDER: {"xbox": "xbox_rb", "playstation": "playstation_trigger_r1", "switch": "switch_button_r", "steamdeck": "steamdeck_button_r1"},
	JOY_BUTTON_DPAD_UP: {"xbox": "xbox_dpad_up", "playstation": "playstation_dpad_up", "switch": "switch_dpad_up", "steamdeck": "steamdeck_dpad_up"},
	JOY_BUTTON_DPAD_DOWN: {"xbox": "xbox_dpad_down", "playstation": "playstation_dpad_down", "switch": "switch_dpad_down", "steamdeck": "steamdeck_dpad_down"},
	JOY_BUTTON_DPAD_LEFT: {"xbox": "xbox_dpad_left", "playstation": "playstation_dpad_left", "switch": "switch_dpad_left", "steamdeck": "steamdeck_dpad_left"},
	JOY_BUTTON_DPAD_RIGHT: {"xbox": "xbox_dpad_right", "playstation": "playstation_dpad_right", "switch": "switch_dpad_right", "steamdeck": "steamdeck_dpad_right"},
}
const STICK_GLYPHS := {
	"left": {"xbox": "xbox_stick_l", "playstation": "playstation_stick_l", "switch": "switch_stick_l", "steamdeck": "steamdeck_stick_l"},
	"right": {"xbox": "xbox_stick_r", "playstation": "playstation_stick_r", "switch": "switch_stick_r", "steamdeck": "steamdeck_stick_r"},
}

## One physical D-pad press can arrive as both a button and a stick axis
## (common on handhelds and some pads), which would move menu focus twice.
const NAV_ACTIONS := ["ui_up", "ui_down", "ui_left", "ui_right"]
const NAV_DEBOUNCE_MSEC := 90

var family := "keyboard"
## Controllers claimed by extra local players (couch play): device -> seat.
## See LGSeat. While [member filter_claimed_pads] is on, those controllers
## don't move menu focus, so player 2 joining doesn't steer player 1's menu.
var claimed_pads := {}
var filter_claimed_pads := false
## The controller that last moved menu focus (the menu player's own pad).
var last_menu_pad := -1
var _menu_by_pad := false
var _pad_t := -100000
var _glyph_cache := {}
var _last_nav := {}
var _mouse_t := -100000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Input.get_connected_joypads().size() > 0:
		family = family_for_joypad(Input.get_connected_joypads()[0])
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## `actions` is {action_name: [binding strings]}. Existing actions are
## replaced, so a game's map always wins over project defaults.
func register_actions(actions: Dictionary, deadzone := 0.25) -> void:
	for action in actions:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, deadzone)
		InputMap.action_set_deadzone(action, deadzone)
		for spec in actions[action]:
			var ev := make_event(spec)
			if ev:
				InputMap.action_add_event(action, ev)


## Adds gamepad bindings to Godot's built-in ui_* actions, which drive menu
## focus, so every menu is usable with a controller.
func extend_ui_actions() -> void:
	register_actions({
		"ui_accept": ["key:Enter", "key:Kp Enter", "key:Space", "joy:a"],
		"ui_cancel": ["key:Escape", "key:Backspace", "joy:b"],
		"ui_up": ["key:Up", "key:W", "joy:up", "axis:ly-"],
		"ui_down": ["key:Down", "key:S", "joy:down", "axis:ly+"],
		"ui_left": ["key:Left", "key:A", "joy:left", "axis:lx-"],
		"ui_right": ["key:Right", "key:D", "joy:right", "axis:lx+"],
		"ui_focus_next": ["key:Tab", "joy:rb"],
		"ui_focus_prev": ["key:Shift+Tab", "joy:lb"],
	}, 0.5)


static func make_event(spec: String) -> InputEvent:
	var colon := spec.find(":")
	if colon < 0:
		return null
	var kind := spec.substr(0, colon)
	var value := spec.substr(colon + 1)
	match kind:
		"key":
			var ev := InputEventKey.new()
			var mods := value.split("+")
			ev.physical_keycode = OS.find_keycode_from_string(mods[mods.size() - 1])
			for i in mods.size() - 1:
				match mods[i].to_lower():
					"shift": ev.shift_pressed = true
					"ctrl": ev.ctrl_pressed = true
					"alt": ev.alt_pressed = true
			return ev
		"joy":
			if not JOY_NAMES.has(value):
				push_warning("Input: unknown button %s" % value)
				return null
			var jb := InputEventJoypadButton.new()
			jb.button_index = JOY_NAMES[value]
			jb.device = -1
			return jb
		"axis":
			var axis_name := value.substr(0, value.length() - 1)
			var dir := value.substr(value.length() - 1)
			if not AXIS_NAMES.has(axis_name):
				push_warning("Input: unknown axis %s" % value)
				return null
			var jm := InputEventJoypadMotion.new()
			jm.axis = AXIS_NAMES[axis_name]
			jm.axis_value = -1.0 if dir == "-" else 1.0
			jm.device = -1
			return jm
		"mouse":
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_RIGHT if value == "right" else MOUSE_BUTTON_LEFT
			return mb
	return null


func is_gamepad() -> bool:
	return family != "keyboard"


## The glyph texture for an action's first binding on the current device.
func glyph_for_action(action: String) -> Texture2D:
	if not InputMap.has_action(action):
		return null
	var want_joy := is_gamepad()
	for ev in InputMap.action_get_events(action):
		if want_joy and ev is InputEventJoypadButton:
			return _button_glyph(ev.button_index)
		if want_joy and ev is InputEventJoypadMotion:
			return _stick_glyph(ev.axis)
		if not want_joy and ev is InputEventKey:
			return _key_glyph(ev)
	return null


## A short text label for an action's binding, used when no glyph exists.
func label_for_action(action: String) -> String:
	if not InputMap.has_action(action):
		return action
	var want_joy := is_gamepad()
	for ev in InputMap.action_get_events(action):
		if not want_joy and ev is InputEventKey:
			return OS.get_keycode_string(ev.physical_keycode)
		if not want_joy and ev is InputEventMouseButton:
			return "Click" if ev.button_index == MOUSE_BUTTON_LEFT else "Right click"
		if want_joy and ev is InputEventJoypadButton:
			for n in JOY_NAMES:
				if JOY_NAMES[n] == ev.button_index:
					return n.to_upper()
	return action


## The glyph for a controller button (a JOY_BUTTON_* value) in a given
## family, e.g. for one couch player's controller.
func pad_glyph(p_family: String, button: int) -> Texture2D:
	if not BUTTON_GLYPHS.has(button):
		return null
	return _load_glyph(p_family, BUTTON_GLYPHS[button].get(p_family, ""))


func family_for_joypad(device: int) -> String:
	var joy_name := Input.get_joy_name(device).to_lower()
	if "playstation" in joy_name or "dualsense" in joy_name or "dualshock" in joy_name or "ps4" in joy_name or "ps5" in joy_name or "sony" in joy_name:
		return "playstation"
	if "nintendo" in joy_name or "switch" in joy_name or "joy-con" in joy_name or "pro controller" in joy_name:
		return "switch"
	if "steam deck" in joy_name:
		return "steamdeck"
	return "xbox"


func claim_pad(device: int, seat: int) -> void:
	claimed_pads[device] = seat


func release_pad(device: int) -> void:
	claimed_pads.erase(device)


## True if the mouse moved or clicked in the last few seconds.
## The controller that last drove the menus, or -1 if the keyboard or mouse
## was used since. In a lobby this is the first player's controller.
func menu_pad() -> int:
	return last_menu_pad if _menu_by_pad else -1


func mouse_recent() -> bool:
	return Time.get_ticks_msec() - _mouse_t < 4000


func _input(event: InputEvent) -> void:
	if filter_claimed_pads and (event is InputEventJoypadButton or event is InputEventJoypadMotion) and claimed_pads.has(event.device):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_mouse_t = Time.get_ticks_msec()
		if event is InputEventMouseButton:
			_menu_by_pad = false
	elif event is InputEventKey and event.pressed and Time.get_ticks_msec() - _pad_t > 150:
		# (Key events right after a pad event come from pads that also
		# pretend to be a keyboard.)
		_menu_by_pad = false
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_mouse_t = -100000
		_pad_t = Time.get_ticks_msec()
		if not claimed_pads.has(event.device):
			last_menu_pad = event.device
			_menu_by_pad = true
	if not event.is_echo():
		for a in NAV_ACTIONS:
			if event.is_action_pressed(a):
				var now := Time.get_ticks_msec()
				if now - int(_last_nav.get(a, -1000)) < NAV_DEBOUNCE_MSEC:
					get_viewport().set_input_as_handled()
					return
				_last_nav[a] = now
	var next := family
	var has_pad := Input.get_connected_joypads().size() > 0
	# Some pads (e.g. Xbox 360 clones) also expose virtual keyboard and mouse
	# devices, so with a controller connected those events don't count as
	# keyboard use.
	if (event is InputEventKey or event is InputEventMouseButton) and not has_pad:
		next = "keyboard"
	elif event is InputEventJoypadButton:
		next = family_for_joypad(event.device)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		next = family_for_joypad(event.device)
	if next != family:
		family = next
		device_changed.emit(family)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	var next := family
	if connected and family == "keyboard":
		next = family_for_joypad(device)
	elif not connected and Input.get_connected_joypads().is_empty():
		next = "keyboard"
	if next != family:
		family = next
		device_changed.emit(family)


func _button_glyph(button: int) -> Texture2D:
	if not BUTTON_GLYPHS.has(button):
		return null
	return _load_glyph(family, BUTTON_GLYPHS[button].get(family, ""))


func _stick_glyph(axis: int) -> Texture2D:
	var side := "left" if axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y] else "right"
	return _load_glyph(family, STICK_GLYPHS[side].get(family, ""))


func _key_glyph(ev: InputEventKey) -> Texture2D:
	var key_name := OS.get_keycode_string(ev.physical_keycode).to_lower().replace(" ", "_")
	match key_name:
		"up", "down", "left", "right":
			key_name = "arrows_" + key_name
	return _load_glyph("keyboard", "keyboard_" + key_name)


func _load_glyph(dir: String, file: String) -> Texture2D:
	if file == "":
		return null
	var path := "%s/%s/%s.png" % [GLYPH_DIR, dir, file]
	if not _glyph_cache.has(path):
		_glyph_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _glyph_cache[path]
