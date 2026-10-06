class_name LGUi
extends RefCounted
## Small helpers that keep every menu usable with a controller alone.


## Opens the on-screen keyboard when a gamepad user presses A on the field.
static func gamepad_text_entry(edit: LineEdit, uppercase_only := false) -> void:
	edit.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
			edit.accept_event()
			OnScreenKeyboard.open(edit, uppercase_only)
	)


## Focuses the first focusable control under `root` (call after building a menu).
static func focus_first(root: Node) -> void:
	var c := first_focusable(root)
	if c:
		c.grab_focus.call_deferred()


static func first_focusable(root: Node) -> Control:
	for child in root.get_children():
		if child is Control and child.visible:
			var ctl := child as Control
			if ctl.focus_mode == Control.FOCUS_ALL and not (ctl is BaseButton and (ctl as BaseButton).disabled):
				return ctl
			var inner := first_focusable(child)
			if inner:
				return inner
	return null


static func button(text: String, on_pressed: Callable, min_width := 320) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 56)
	b.pressed.connect(on_pressed)
	b.pressed.connect(func(): click())
	return b


static func label(text: String, variation := "") -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	return l


static func click() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var audio := tree.root.get_node_or_null("LGAudio")
	if audio:
		audio.play_sfx("res://addons/linuxgroove/ui/sounds/click.ogg", -6.0, 0.05)


## A centred column for menu screens.
static func centered_column(parent: Control, width := 520) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A column taller than the screen then overflows evenly at both edges.
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	parent.add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = width
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	return col
