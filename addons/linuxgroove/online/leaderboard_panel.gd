class_name LGLeaderboardPanel
extends VBoxContainer
## A game's leaderboards from the shared server: pick a board, see the top ten
## and your own rank. Signs in on its own, so it works from any menu.
##
##   var panel := LGLeaderboardPanel.new()
##   panel.setup(GameConfig.GAME_ID, Session.player_name(),
##       [["wins_weekly", "Wins this week"], ["wins", "Wins, all time"]])
##   _col.add_child(panel)

const ROWS := 10

var _game_id := ""
var _display_name := ""
var _boards: Array = []  # [[board, title], ...] as LGCycler options
var _picker: LGCycler
var _list: VBoxContainer
var _mine: Label
## Bumped on every load, so a slow answer for an old board is dropped.
var _load_id := 0


func setup(game_id: String, display_name: String, boards: Array) -> void:
	_game_id = game_id
	_display_name = display_name
	_boards = boards


func _ready() -> void:
	build()
	_load()


## Makes the rows without loading anything (tests call this directly).
func build() -> void:
	add_theme_constant_override("separation", 12)
	_picker = LGCycler.make("Board", _boards, _boards[0][0], func(_v): _load(), 560)
	add_child(_picker)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "GlassPanel"
	panel.custom_minimum_size = Vector2(560, 0)
	add_child(panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	panel.add_child(_list)
	_mine = LGUi.label("", "HintLabel")
	_mine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_mine)


func _load() -> void:
	_load_id += 1
	var id := _load_id
	_show_message("Loading...")
	_mine.text = ""
	if not await LGOnline.connect_async(_display_name, _game_id):
		if id == _load_id:
			_show_message("Couldn't reach the game server.")
		return
	var res = await LGOnline.leaderboard_async(_game_id, str(_picker.value()), ROWS)
	if id != _load_id or not is_inside_tree():
		return
	if res == null:
		_show_message("Couldn't load this board.")
		return
	show_board(res)


## Shows one board from LGOnline.leaderboard_async().
func show_board(board: Dictionary) -> void:
	_clear_list()
	_mine.text = ""
	if board.top.is_empty():
		_show_message("Nobody is on this board yet.")
	for row in board.top:
		_list.add_child(_row(row))
	var mine = board.mine
	if mine == null:
		_mine.text = "You're not on this board yet."
	elif not board.top.any(func(r): return r.me):
		_mine.text = "You: #%d with %d" % [mine.rank, mine.score]


func _row(row: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	var rank := LGUi.label("#%d" % row.rank)
	rank.custom_minimum_size.x = 64
	var name := LGUi.label(str(row.name))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var score := LGUi.label(str(row.score))
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.custom_minimum_size.x = 80
	for l in [rank, name, score]:
		if row.me:
			l.add_theme_color_override("font_color", Color("ffd27a"))
		h.add_child(l)
	return h


func _show_message(text: String) -> void:
	_clear_list()
	var l := LGUi.label(text, "HintLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(l)


func _clear_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
