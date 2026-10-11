class_name LGUi
extends RefCounted
## Small helpers that keep every menu usable with a controller alone.


## How close an Enter press must be to A to count as the controller's own.
const PAD_ENTER_MSEC := 150


## Opens the on-screen keyboard when a gamepad user presses A on the field.
## It opens on release: opening on press focuses the first key while A is
## still held, and that same press then types it. A release whose press went
## to another control (e.g. the button that moved focus here) is ignored.
##
## Some controllers also send Enter with A (handhelds and pad mappers that
## pretend to be a keyboard), and on Linux that Enter arrives a frame before
## the A. Enter submits a field that's being typed in, which would close the
## page before the keyboard opens. So Enter waits a moment here and is
## dropped if A comes with it.
static func gamepad_text_entry(edit: LineEdit, uppercase_only := false) -> void:
	edit.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A:
			edit.accept_event()
			if event.pressed:
				edit.set_meta("_lg_a_down", true)
				edit.set_meta("_lg_a_at", Time.get_ticks_msec())
			elif edit.get_meta("_lg_a_down", false):
				edit.set_meta("_lg_a_down", false)
				OnScreenKeyboard.open(edit, uppercase_only)
		elif event.is_action_pressed("ui_text_submit") and edit.is_editing():
			edit.accept_event()
			var now := Time.get_ticks_msec()
			if now - int(edit.get_meta("_lg_a_at", -100000)) > PAD_ENTER_MSEC:
				_submit_unless_a(edit, now)
	)
	edit.focus_exited.connect(func() -> void: edit.set_meta("_lg_a_down", false))


## Submits the field as its own Enter would have, unless A comes within
## PAD_ENTER_MSEC of `at` (counted on the clock, and at least a frame, since a
## slow frame would otherwise end the wait before the A is read).
## `field` is untyped: the page may be freed while Enter waits.
static func _submit_unless_a(field, at: int) -> void:
	var tree: SceneTree = field.get_tree()
	await tree.process_frame
	while Time.get_ticks_msec() - at < PAD_ENTER_MSEC:
		await tree.process_frame
	if not is_instance_valid(field) or not field.is_inside_tree():
		return
	var edit: LineEdit = field
	if int(edit.get_meta("_lg_a_at", -100000)) >= at:
		return
	edit.text_submitted.emit(edit.text)
	if edit.is_editing() and not edit.keep_editing_on_text_submit:
		edit.unedit()
		edit.editing_toggled.emit(false)


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
