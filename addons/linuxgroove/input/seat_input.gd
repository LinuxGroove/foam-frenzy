class_name LGSeat
extends RefCounted
## One local player's controls when several people share a device (couch
## play). A seat reads only its own devices, so two players on one screen
## never steer each other:
##   - the first seat (index 0) has the keyboard and mouse, plus any
##     controller that no other seat has claimed;
##   - every other seat has one claimed controller.
## Actions are the game's normal InputMap actions (see LGInput); a seat checks
## each binding against its own devices only. Call [method poll] once per
## frame before [method just_pressed].

const ANY_FREE_PAD := -2

var index := 0
## A joypad id, or ANY_FREE_PAD for the first seat.
var device := ANY_FREE_PAD
var keyboard := false
var deadzone := 0.2

var _held := {}
var _was := {}


static func primary() -> LGSeat:
	var s := LGSeat.new()
	s.index = 0
	s.device = ANY_FREE_PAD
	s.keyboard = true
	return s


static func for_pad(p_index: int, pad: int) -> LGSeat:
	var s := LGSeat.new()
	s.index = p_index
	s.device = pad
	s.keyboard = false
	return s


## The controllers this seat listens to right now.
func pads() -> Array:
	if device >= 0:
		return [device] if device in Input.get_connected_joypads() else []
	var router := _router()
	var claimed: Dictionary = router.claimed_pads if router else {}
	return Input.get_connected_joypads().filter(func(d): return not claimed.has(d))


func has_pad() -> bool:
	return not pads().is_empty()


## How far an action is pressed on this seat's devices, 0 to 1.
func strength(action: String) -> float:
	if not InputMap.has_action(action):
		return 0.0
	var best := 0.0
	var my_pads := pads()
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			if keyboard and Input.is_physical_key_pressed(ev.physical_keycode):
				return 1.0
		elif ev is InputEventMouseButton:
			if keyboard and Input.is_mouse_button_pressed(ev.button_index):
				return 1.0
		elif ev is InputEventJoypadButton:
			for pad in my_pads:
				if Input.is_joy_button_pressed(pad, ev.button_index):
					return 1.0
		elif ev is InputEventJoypadMotion:
			for pad in my_pads:
				var v := Input.get_joy_axis(pad, ev.axis) * signf(ev.axis_value)
				if v > deadzone:
					best = maxf(best, inverse_lerp(deadzone, 1.0, minf(v, 1.0)))
	return best


func held(action: String) -> bool:
	return strength(action) > 0.5


## True on the frame an action went down. Needs [method poll] every frame.
func just_pressed(action: String) -> bool:
	return bool(_held.get(action, false)) and not bool(_was.get(action, false))


## Remembers the state of `actions` so just_pressed works.
func poll(actions: Array) -> void:
	_was = _held.duplicate()
	for a in actions:
		_held[a] = held(a)


## A stick-style vector from four actions, with a round dead zone.
func vector(neg_x: String, pos_x: String, neg_y: String, pos_y: String) -> Vector2:
	var v := Vector2(strength(pos_x) - strength(neg_x), strength(pos_y) - strength(neg_y))
	return v.limit_length(1.0)


## True when this seat's last input came from the mouse (it aims at the cursor).
func uses_mouse() -> bool:
	if not keyboard:
		return false
	var router := _router()
	return router != null and router.mouse_recent()


static func _router() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("LGInput") if tree else null
