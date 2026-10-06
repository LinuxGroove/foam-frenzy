class_name ResultsPanel
extends Control
## The end of a match: who won, everyone's tags and outs, and the medals.
## The host picks what's next; everyone else waits for them or leaves.

const SHOW_AFTER := 1.4
const MEDAL := "res://assets/kenney/medals/shaded_medal%d.png"

var game: Game
var _title: Label
var _subtitle: Label
var _grid: GridContainer
var _medals: HFlowContainer
var _buttons: HBoxContainer
var _col: VBoxContainer


func setup(p_game: Game) -> void:
	game = p_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "ParchmentPanel"
	panel.custom_minimum_size = Vector2(820, 0)
	center.add_child(panel)
	LGScreenFit.center(panel)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 12)
	panel.add_child(_col)
	_title = LGUi.label("", "InkTitle")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(_title)
	_subtitle = LGUi.label("", "InkLabel")
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(_subtitle)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 34)
	_grid.add_theme_constant_override("v_separation", 4)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_col.add_child(_grid)
	_medals = HFlowContainer.new()
	_medals.alignment = FlowContainer.ALIGNMENT_CENTER
	_medals.add_theme_constant_override("h_separation", 22)
	_medals.add_theme_constant_override("v_separation", 8)
	_col.add_child(_medals)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 16)
	_col.add_child(_buttons)
	game.game_over.connect(_on_game_over)


func _on_game_over(res: Dictionary) -> void:
	await get_tree().create_timer(SHOW_AFTER).timeout
	if is_inside_tree():
		open(res)


func open(res: Dictionary) -> void:
	visible = true
	_title.text = title_for(res)
	_subtitle.text = _subtitle_for(res)
	_fill_standings(res)
	_fill_medals(res)
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	if Session.is_host():
		_buttons.add_child(LGUi.button("Play again", _play_again, 260))
		_buttons.add_child(LGUi.button("Back to lobby", _to_lobby, 260))
	else:
		_buttons.add_child(LGUi.label("Waiting for the host...", "InkLabel"))
		var leave := LGUi.button("Leave", _leave, 200)
		leave.theme_type_variation = "DangerButton"
		_buttons.add_child(leave)
	LGUi.focus_first(_buttons)


## The headline: who won, from this device's point of view when it can.
func title_for(res: Dictionary) -> String:
	if bool(res.get("tie", false)):
		return "It's a tie!"
	var team := int(res.get("team", -1))
	if team >= 0:
		return "%s team wins!" % GameConfig.TEAM_NAMES[team]
	var winner := int(res.get("winner", 0))
	if game.is_local(winner) and game.locals.size() == 1:
		return "You win!"
	return "%s wins!" % game.actor_name(winner)


func _subtitle_for(res: Dictionary) -> String:
	var mode := int(res.get("mode", 0))
	var line: String = Rules.MODE_NAMES[mode]
	if Rules.is_team_mode(mode):
		var ts: Array = res.get("team_scores", [0, 0])
		line += "   Red %d - %d Blue" % [int(ts[0]), int(ts[1])]
	return line


func _fill_standings(res: Dictionary) -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var mode := int(res.get("mode", 0))
	var extra := mode in [Rules.Mode.CTF, Rules.Mode.HOARDER]
	_grid.columns = 5 if extra else 4
	var heads := ["", "", Scoreboard.score_name(mode), "Tags", "Outs"] if extra else ["", "", "Tags", "Outs"]
	for h in heads:
		_grid.add_child(LGUi.label(h, "InkLabel"))
	var place := 0
	var last_score := INF
	var i := 0
	for row in res.get("standings", []):
		i += 1
		var id := int(row[0])
		if float(row[1]) != last_score:
			place = i
			last_score = float(row[1])
		_grid.add_child(LGUi.label("%d." % place, "InkLabel"))
		var name := LGUi.label(game.actor_name(id) + ("  (you)" if game.is_local(id) else ""), "InkHeader")
		name.add_theme_font_size_override("font_size", 22)
		name.add_theme_color_override("font_color", game.actor_color(id).darkened(0.35))
		_grid.add_child(name)
		if extra:
			_grid.add_child(LGUi.label(str(int(row[1])), "InkLabel"))
		_grid.add_child(LGUi.label(str(int(row[2])), "InkLabel"))
		_grid.add_child(LGUi.label(str(int(row[3])), "InkLabel"))


func _fill_medals(res: Dictionary) -> void:
	for c in _medals.get_children():
		_medals.remove_child(c)
		c.queue_free()
	for m in res.get("medals", []):
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		var icon := TextureRect.new()
		icon.texture = load(MEDAL % clampi(int(m.icon), 1, 9))
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(icon)
		var words := VBoxContainer.new()
		words.add_theme_constant_override("separation", -4)
		words.add_child(LGUi.label(str(m.title), "InkLabel"))
		var who := LGUi.label(game.actor_name(int(m.id)), "InkLabel")
		who.add_theme_color_override("font_color", game.actor_color(int(m.id)).darkened(0.35))
		words.add_child(who)
		box.add_child(words)
		_medals.add_child(box)
	_medals.visible = _medals.get_child_count() > 0


func _play_again() -> void:
	Session.restart_match()


func _to_lobby() -> void:
	Session.return_to_lobby()


func _leave() -> void:
	Session.leave("")
