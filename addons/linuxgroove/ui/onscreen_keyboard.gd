class_name OnScreenKeyboard
extends PanelContainer
## A controller-friendly keyboard for typing names and join codes on devices
## with no physical keyboard (handhelds, Ubuntu Core kiosks).
##
## Usage: OnScreenKeyboard.open(line_edit) from a LineEdit's focus handler.
## D-pad or stick moves between keys, A types, B deletes, Start or Done closes.

signal closed(text: String)

const ROWS_LETTERS := ["1234567890", "QWERTYUIOP", "ASDFGHJKL-", "ZXCVBNM_.'"]

var target: LineEdit
var uppercase_only := false
var _grid: GridContainer
var _shift := false
var _letter_buttons: Array[Button] = []
var _preview: Label


static func open(p_target: LineEdit, p_uppercase_only := false) -> OnScreenKeyboard:
	var kb := OnScreenKeyboard.new()
	kb.target = p_target
	kb.uppercase_only = p_uppercase_only
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.add_child(kb)
	p_target.get_tree().root.add_child(layer)
	return kb


func _ready() -> void:
	theme_type_variation = "DarkPanel"
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	position.y -= 24
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	# What is being typed is always shown here, on the keyboard itself, so it
	# stays readable even when the keyboard sits over the text field.
	var what := Label.new()
	what.name = "What"
	what.theme_type_variation = "HintLabel"
	what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	what.text = target.placeholder_text if target else ""
	box.add_child(what)
	var field := PanelContainer.new()
	var field_box := StyleBoxFlat.new()
	field_box.bg_color = Color(1, 1, 1, 0.92)
	field_box.set_corner_radius_all(8)
	field_box.set_content_margin_all(10)
	field.add_theme_stylebox_override("panel", field_box)
	box.add_child(field)
	var preview := Label.new()
	_preview = preview
	preview.name = "Preview"
	preview.theme_type_variation = "InkHeader"
	preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview.custom_minimum_size.y = 44
	preview.add_theme_font_override("font", ThemeDB.fallback_font)
	preview.add_theme_font_size_override("font_size", 32)
	field.add_child(preview)
	_grid = GridContainer.new()
	_grid.columns = 10
	box.add_child(_grid)
	for row in ROWS_LETTERS:
		for ch in row:
			var b := _key(ch, _type.bind(ch))
			if ch.to_upper() != ch.to_lower():
				_letter_buttons.append(b)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(bottom)
	if not uppercase_only:
		bottom.add_child(_wide("Shift", _toggle_shift))
		bottom.add_child(_wide("Space", _type.bind(" ")))
	bottom.add_child(_wide("Delete", _backspace))
	bottom.add_child(_wide("Done", _close))
	_update_case()
	_update_preview()
	(_grid.get_child(10) as Button).grab_focus()
	_keep_field_visible.call_deferred()


## Moves the keyboard to the top of the screen when it would cover the field.
func _keep_field_visible() -> void:
	if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
		return
	var field := target.get_global_rect()
	if field.end.y > get_global_rect().position.y:
		set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		grow_vertical = Control.GROW_DIRECTION_END
		position.y += 24


func _key(ch: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = ch
	b.custom_minimum_size = Vector2(56, 52)
	# The game fonts draw 0 and O (and 1 and I, 5 and S...) the same; the
	# engine's own font keeps every key distinct.
	b.add_theme_font_override("font", ThemeDB.fallback_font)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(cb)
	_grid.add_child(b)
	return b


func _wide(label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(130, 52)
	b.pressed.connect(cb)
	return b


func _type(ch: String) -> void:
	if target == null:
		return
	var c := ch
	if not uppercase_only and not _shift:
		c = ch.to_lower()
	if target.max_length > 0 and target.text.length() >= target.max_length:
		return
	target.text += c
	target.text_changed.emit(target.text)
	if _shift:
		_shift = false
		_update_case()
	_update_preview()


func _backspace() -> void:
	if target and target.text.length() > 0:
		target.text = target.text.substr(0, target.text.length() - 1)
		target.text_changed.emit(target.text)
	_update_preview()


func _toggle_shift() -> void:
	_shift = not _shift
	_update_case()


func _update_case() -> void:
	for b in _letter_buttons:
		b.text = b.text.to_upper() if (uppercase_only or _shift) else b.text.to_lower()


func _update_preview() -> void:
	if _preview and target:
		_preview.text = target.text + "_"


func _close() -> void:
	var text := target.text if target else ""
	if target:
		target.text_submitted.emit(text)
		target.grab_focus()
	closed.emit(text)
	get_parent().queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_backspace()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		_close()
		get_viewport().set_input_as_handled()
