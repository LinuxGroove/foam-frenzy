class_name LGFocusPause
extends Node
## Opens the game's pause menu when its window loses focus: alt-tab, another
## window coming up over the game, a handheld's own menu. A play scene adds
## one with [method watch] and the function that opens its pause menu, which
## already knows when the menu can't open and whether the game really pauses
## (not with players on other devices). The game stays paused when focus
## comes back, so the player picks up when they're ready.
##
## Nothing happens when the Pause when switching away setting is off, while
## the game is already paused, while the on-screen keyboard or a play test
## panel is up, or when focus comes back within [constant GRACE_MSEC] (a
## window blinking as it goes fullscreen).

## How long focus has to stay away before the menu opens.
const GRACE_MSEC := 300

## Opens the game's pause menu.
var open_pause: Callable
var _lost_at := -1


## Adds a watcher under `parent`, which goes when `parent` does.
static func watch(parent: Node, p_open_pause: Callable) -> LGFocusPause:
	var w := LGFocusPause.new()
	w.name = "FocusPause"
	w.open_pause = p_open_pause
	parent.add_child(w)
	return w


## Whether the Pause when switching away setting is on.
static func enabled() -> bool:
	return bool(LGSettings.get_value("video", "focus_pause", true))


func _init() -> void:
	# The wait below runs whether or not something else has paused the game.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			focus_lost()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			focus_back()


## The window lost focus: the menu opens unless it comes back in time.
func focus_lost() -> void:
	_lost_at = Time.get_ticks_msec()
	set_process(true)


func focus_back() -> void:
	_lost_at = -1
	set_process(false)


func _process(_delta: float) -> void:
	if _lost_at >= 0 and Time.get_ticks_msec() - _lost_at >= GRACE_MSEC:
		_lost_at = -1
		set_process(false)
		pause_now()


## Opens the pause menu unless something above says not to. True if it did.
func pause_now() -> bool:
	if not enabled() or not open_pause.is_valid() or not is_inside_tree() or get_tree().paused:
		return false
	if OnScreenKeyboard.current():
		return false
	var recorder := LGPlaytest.current()
	if recorder and recorder.has_panel():
		return false
	open_pause.call()
	return true
