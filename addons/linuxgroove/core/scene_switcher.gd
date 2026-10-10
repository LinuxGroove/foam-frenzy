extends CanvasLayer
## Fades between scenes (autoload: LGScenes).

signal scene_changed(scene: Node)

const FADE_TIME := 0.25

var _rect: ColorRect
var _busy := false
var _pending: Array = []


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


## Replaces the current scene. `setup` (optional) is called with the new
## scene's root before it enters the tree, so callers can pass data in.
##
## Requests made while a change is running are queued, and only the newest
## one runs: a double press or a burst of network messages never leaves two
## scenes in the tree at once.
func change_scene(path_or_packed: Variant, setup := Callable()) -> void:
	if _busy:
		_pending = [path_or_packed, setup]
		return
	_busy = true
	var next := [path_or_packed, setup]
	while not next.is_empty():
		await _swap(next[0], next[1])
		next = _pending
		_pending = []
	_busy = false


func is_busy() -> bool:
	return _busy


## Quits the game. A play test that's recording ends first, with its survey.
func quit() -> void:
	var playtest := LGPlaytest.current()
	if playtest and playtest.is_finishing():
		return
	if playtest and playtest.is_recording():
		await playtest.finish("quit")
	get_tree().quit()


func _swap(path_or_packed: Variant, setup: Callable) -> void:
	var packed: PackedScene = path_or_packed if path_or_packed is PackedScene else load(path_or_packed)
	await _fade(1.0)
	var tree := get_tree()
	var node := packed.instantiate()
	if setup.is_valid():
		setup.call(node)
	var old := tree.current_scene
	if old:
		old.queue_free()
		await old.tree_exited
	# The new scene is current as soon as it enters the tree, as with Godot's
	# own change_scene, so its _ready can use current_scene. In an exported
	# game a method call on a null current_scene crashes rather than erroring.
	node.tree_entered.connect(_make_current.bind(node), CONNECT_ONE_SHOT)
	tree.root.add_child(node)
	await _fade(0.0)
	scene_changed.emit(node)


func _make_current(node: Node) -> void:
	get_tree().current_scene = node


func _fade(target: float) -> void:
	if DisplayServer.get_name() == "headless":
		_rect.color.a = target
		await get_tree().process_frame
		return
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP if target > 0.0 else Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(_rect, "color:a", target, FADE_TIME)
	await tween.finished
