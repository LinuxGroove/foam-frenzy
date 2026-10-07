class_name HowToPanel
extends Control
## The tutorial: a few pages on the goal, darts, moving and blasting, the
## modes, couch play and the controls. Opened from the title and pause menus,
## and by itself before a player's first match if they never opened it.

signal closed

const CONTROLS := [
	["move_up", "Move"],
	["aim_up", "Aim"],
	["fire", "Fire"],
	["dive", "Dive (you can't be hit mid-dive)"],
	["taunt", "Taunt"],
	["scores", "Scoreboard (hold)"],
	["pause", "Pause"],
]

var _title: Label
var _body: Label
var _extra: VBoxContainer
var _count: Label
var _prev: Button
var _next: Button
var _page := 0


static func pages() -> Array:
	var modes := []
	for i in Rules.MODE_NAMES.size():
		modes.append("%s: %s" % [Rules.MODE_NAMES[i], Rules.MODE_BLURBS[i]])
	return [
		{"title": "The goal", "body":
			"Tag the other campers with foam darts. Three hits and a camper is out, then they pop back in a few seconds later.\n\nIn a free-for-all, the most tags wins. Just-respawned campers blink for a moment and can't be tagged."},
		{"title": "Darts are precious", "body":
			"You start with only a few darts. Every dart you fire lands on the floor, and anyone can grab it by walking over it.\n\nWhen a camper is tagged out, every dart they were carrying spills on the floor. Running dry? Look for the darts lying around after a fight."},
		{"title": "Move, aim, blast", "body":
			"Move with the left stick and aim with the right stick. Fire with the right trigger. Dive with the left trigger or A to dodge: nothing can hit you mid-dive.\n\nOn a keyboard, WASD moves, the mouse aims and clicking fires. Shift or Space dives. The arrow keys aim and fire too, if you'd rather leave the mouse alone."},
		{"title": "Modes", "body": "\n\n".join(modes)},
		{"title": "Playing together", "body":
			"Up to four people can play on one screen. In the lobby, press Start on another controller to join.\n\nCouch players can team up with friends on your network or online, up to eight campers in a match. Bots fill the empty spots."},
		{"title": "Controls", "body": "", "controls": true},
	]


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "ParchmentPanel"
	panel.custom_minimum_size = Vector2(760, 500)
	center.add_child(panel)
	LGScreenFit.center(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	_title = LGUi.label("", "InkTitle")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_body = LGUi.label("", "InkLabel")
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 700
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	_extra = VBoxContainer.new()
	_extra.add_theme_constant_override("separation", 6)
	_extra.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_extra)
	_count = LGUi.label("", "InkLabel")
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_count)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	_prev = LGUi.button("Previous", _go.bind(-1), 200)
	row.add_child(_prev)
	_next = LGUi.button("Next", _go.bind(1), 200)
	row.add_child(_next)


func open() -> void:
	LGSettings.set_value("tutorial", "howto_seen", true)
	_page = 0
	visible = true
	_show_page()
	_next.grab_focus.call_deferred()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _go(dir: int) -> void:
	_page += dir
	if _page >= pages().size():
		close()
		return
	_page = maxi(_page, 0)
	_show_page()
	(_prev if dir < 0 and _prev.visible else _next).grab_focus.call_deferred()


func _show_page() -> void:
	var all := pages()
	var page: Dictionary = all[_page]
	_title.text = page.title
	_body.text = page.body
	_body.visible = page.body != ""
	for c in _extra.get_children():
		_extra.remove_child(c)
		c.queue_free()
	_extra.visible = page.get("controls", false)
	if _extra.visible:
		for pair in CONTROLS:
			var holder := PanelContainer.new()
			holder.theme_type_variation = "GlassPanel"
			holder.add_child(ActionPrompt.make(pair[0], pair[1], 32))
			_extra.add_child(holder)
	_count.text = "%d / %d" % [_page + 1, all.size()]
	_prev.visible = _page > 0
	_next.text = "Done" if _page == all.size() - 1 else "Next"


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
