class_name PauseMenu
extends Control
## The pause menu. A match on this device alone (bots and couch players)
## really pauses; with players on other devices it carries on for them.

var game: Game
var _col: VBoxContainer
var _panel: PanelContainer
var _note: Label
var _help: VBoxContainer
var _paused_tree := false


func setup(p_game: Game) -> void:
	game = p_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "DarkPanel"
	center.add_child(_panel)
	LGScreenFit.center(_panel)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 10)
	_panel.add_child(_col)
	_col.add_child(LGUi.label("Paused", "HeaderMedium"))
	_note = LGUi.label("", "HintLabel")
	_col.add_child(_note)
	_col.add_child(LGUi.button("Resume", close, 440))
	_col.add_child(LGUi.button("How to play", _show_howto, 440))
	_col.add_child(LGUi.button("Controls", _toggle_help, 440))
	_help = VBoxContainer.new()
	_help.visible = false
	_col.add_child(_help)
	for row in [["Aim assist", "aim_assist", [[0, "Off"], [1, "A little"], [2, "A lot"]]],
			["Auto-fire with the right stick", "auto_fire", SettingsPanel.ON_OFF],
			["Screen shake", "shake", SettingsPanel.ON_OFF]]:
		var key: String = row[1]
		_col.add_child(LGCycler.make(row[0], row[2], LGSettings.get_value("play", key), _set_play.bind(key), 440))
	var leave := LGUi.button("Leave the match", _leave, 440)
	leave.theme_type_variation = "DangerButton"
	_col.add_child(leave)


func _set_play(value: Variant, key: String) -> void:
	LGSettings.set_value("play", key, value)


func open() -> void:
	visible = true
	_panel.visible = true
	_paused_tree = Session.mode == Session.Mode.SOLO
	_note.text = "The match is paused." if _paused_tree else "The match carries on for everyone else."
	if _paused_tree:
		get_tree().paused = true
	_help.visible = false
	LGUi.focus_first(_col)


func close() -> void:
	if not visible:
		return
	visible = false
	if _paused_tree:
		get_tree().paused = false
		_paused_tree = false
	var f := get_viewport().gui_get_focus_owner()
	if f:
		f.release_focus()


func _leave() -> void:
	close()
	if game.practice:
		LGSettings.set_value("tutorial", "practiced", true)
	Session.leave("")


func _toggle_help() -> void:
	_help.visible = not _help.visible
	if not _help.visible:
		return
	for c in _help.get_children():
		_help.remove_child(c)
		c.queue_free()
	for pair in HowToPanel.CONTROLS:
		_help.add_child(ActionPrompt.make(pair[0], pair[1], 30))


## How to play opens over the menu, which hides so focus stays on the pages.
func _show_howto() -> void:
	_panel.visible = false
	game.hud.howto.closed.connect(_back_from_howto, CONNECT_ONE_SHOT)
	game.hud.howto.open()


func _back_from_howto() -> void:
	if visible:
		_panel.visible = true
		LGUi.focus_first(_col)


func _unhandled_input(event: InputEvent) -> void:
	if visible and _panel.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
