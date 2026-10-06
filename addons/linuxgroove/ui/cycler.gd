class_name LGCycler
extends Button
## A "Label: value" option row that works with a controller.
##
## Rows are picked like any other button: up, down, left and right move focus
## between rows and panels. Press A on a row to edit it, then left and right
## change the value; A, B, up or down finish editing. With a mouse, a click
## steps the value forward.

signal value_changed(value: Variant)

const EDIT_COLOR := Color("ffd54a")

var label_text := ""
var options: Array = []  # [[value, text], ...]
var index := 0
var read_only := false
var editing := false

var _mouse_press := false


static func make(p_label: String, p_options: Array, current: Variant, on_change := Callable(), width := 440) -> LGCycler:
	var c := LGCycler.new()
	c.label_text = p_label
	c.options = p_options
	c.custom_minimum_size = Vector2(width, 52)
	c.alignment = HORIZONTAL_ALIGNMENT_LEFT
	c.set_value(current)
	if on_change.is_valid():
		c.value_changed.connect(on_change)
	c.pressed.connect(c._on_pressed)
	c.focus_exited.connect(func(): c.set_editing(false))
	return c


func value() -> Variant:
	return options[index][0] if index < options.size() else null


func set_value(v: Variant) -> void:
	index = 0
	for i in options.size():
		if options[i][0] == v:
			index = i
			break
	_refresh()


func set_read_only(on: bool) -> void:
	read_only = on
	disabled = on
	focus_mode = Control.FOCUS_NONE if on else Control.FOCUS_ALL
	if on:
		editing = false
	_refresh()


func set_editing(on: bool) -> void:
	on = on and not read_only
	if on == editing:
		return
	editing = on
	_refresh()


func step(dir: int) -> void:
	if read_only or options.is_empty():
		return
	index = wrapi(index + dir, 0, options.size())
	_refresh()
	LGUi.click()
	value_changed.emit(value())


func _on_pressed() -> void:
	if _mouse_press:
		_mouse_press = false
		step(1)
	else:
		set_editing(not editing)
		LGUi.click()


func _gui_input(event: InputEvent) -> void:
	if read_only:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_press = true
		return
	if not editing:
		return
	if event.is_action_pressed("ui_left", true):
		step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		step(1)
		accept_event()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		set_editing(false)
		LGUi.click()
		accept_event()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		# Leave edit mode and let focus move on as usual.
		set_editing(false)


func _refresh() -> void:
	var shown: String = str(options[index][1]) if index < options.size() else ""
	if read_only:
		text = "%s:  %s" % [label_text, shown]
	elif editing:
		text = "%s:  < %s >" % [label_text, shown]
	else:
		text = "%s:  %s" % [label_text, shown]
	for c in ["font_color", "font_focus_color", "font_hover_color"]:
		if editing:
			add_theme_color_override(c, EDIT_COLOR)
		else:
			remove_theme_color_override(c)
	if editing:
		add_theme_stylebox_override("focus", _edit_focus_box())
	else:
		remove_theme_stylebox_override("focus")


static func _edit_focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.1, 0.07, 0.04, 0.85)
	box.border_color = EDIT_COLOR
	box.set_border_width_all(5)
	box.set_corner_radius_all(10)
	box.set_expand_margin_all(5)
	return box
