class_name Scoreboard
extends PanelContainer
## Everyone's score while the scoreboard button is held: tags, outs and the
## mode's score, grouped by team in team modes.

const REFRESH_EVERY := 0.25

var game: Game
var _grid: GridContainer
var _title: Label
var _t := 0.0


func setup(p_game: Game) -> void:
	game = p_game
	theme_type_variation = "DarkPanel"
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size.x = 620
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	_title = LGUi.label(Rules.MODE_NAMES[game.mode], "HeaderMedium")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 30)
	_grid.add_theme_constant_override("v_separation", 6)
	col.add_child(_grid)


func _process(delta: float) -> void:
	if not visible:
		_t = 0.0
		return
	_t -= delta
	if _t <= 0.0:
		_t = REFRESH_EVERY
		_refresh()


static func score_name(mode: int) -> String:
	match mode:
		Rules.Mode.HOARDER:
			return "Darts"
		Rules.Mode.CTF:
			return "Points"
	return "Tags"


func _refresh() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	# In free-for-all and Team Battle the score is the tag count.
	var extra := game.mode in [Rules.Mode.CTF, Rules.Mode.HOARDER]
	_grid.columns = 4 if extra else 3
	var heads := ["", score_name(game.mode), "Tags", "Outs"] if extra else ["", "Tags", "Outs"]
	for h in heads:
		_grid.add_child(LGUi.label(h, "HintLabel"))
	var ids: Array = game.roster.keys()
	ids.sort_custom(func(a, b):
		var ta := game.actor_team(a)
		var tb := game.actor_team(b)
		if ta != tb:
			return ta < tb
		return int(game.scores.get(a, 0)) > int(game.scores.get(b, 0)))
	for id in ids:
		var name := LGUi.label(game.actor_name(id) + ("  (you)" if game.is_local(id) else ""), "NameLabel")
		name.add_theme_color_override("font_color", game.actor_color(id).lightened(0.2))
		_grid.add_child(name)
		var t: Dictionary = game.tally.get(id, {})
		if extra:
			_grid.add_child(LGUi.label(str(int(game.scores.get(id, 0)))))
		_grid.add_child(LGUi.label(str(int(t.get("tags", 0)))))
		_grid.add_child(LGUi.label(str(int(t.get("outs", 0)))))
