class_name SettingsPanel
extends VBoxContainer
## The shared settings rows: screen, sound, local AI players (in games that
## load the LGBrain autoload), the online server and play test recording (in
## games that set up LGPlaytest). Every row is an LGCycler or a text field, so
## it works by controller.

const VOLUMES := [[0.0, "Off"], [0.1, "10%"], [0.2, "20%"], [0.3, "30%"], [0.4, "40%"], [0.5, "50%"],
	[0.6, "60%"], [0.7, "70%"], [0.8, "80%"], [0.9, "90%"], [1.0, "100%"]]
const ON_OFF := [[true, "On"], [false, "Off"]]
const AI_MODES := [["auto", "Automatic"], ["embedded", "Built-in only"], ["external", "Lemonade on this PC"], ["off", "Off (scripted bots)"]]
const AI_MODELS := [["Qwen3-4B-Instruct-2507-GGUF", "Qwen3 4B (best talk)"], ["LFM2.5-1.2B-Instruct-GGUF", "LFM2.5 1.2B (lighter)"]]

var _ai_state: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_row("Fullscreen", ON_OFF, "video", "fullscreen")
	_row("Text size", [[0.85, "Small"], [1.0, "Normal"], [1.2, "Large"], [1.4, "Huge"]], "video", "ui_scale")
	_row("Volume", VOLUMES, "audio", "master")
	_row("Music", VOLUMES, "audio", "music")
	_row("Sounds", VOLUMES, "audio", "sfx")
	var brain := get_node_or_null("/root/LGBrain")
	if brain:
		_row("AI players", AI_MODES, "ai", "mode", func(_v): _restart_ai())
		_row("AI model", AI_MODELS, "ai", "model", func(_v): _restart_ai())
		_ai_state = LGUi.label("", "HintLabel")
		_ai_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_ai_state)
		_ai_state.text = _ai_text(brain.state, brain.detail)
		# A method, so the connection goes away with this panel.
		brain.state_changed.connect(_on_brain_state)
	_row("Online play", ON_OFF, "online", "enabled")
	var server := LineEdit.new()
	server.placeholder_text = "Game server address"
	server.text = str(LGSettings.get_value("online", "host"))
	server.custom_minimum_size = Vector2(440, 52)
	LGUi.gamepad_text_entry(server)
	server.text_changed.connect(func(t): LGSettings.set_value("online", "host", t.strip_edges()))
	add_child(server)
	if LGPlaytest.current():
		_row("Play test recording", ON_OFF, "playtest", "record")


func _on_brain_state(state: String, detail: String) -> void:
	_ai_state.text = _ai_text(state, detail)


func _row(label: String, options: Array, section: String, key: String, extra := Callable()) -> void:
	var c := LGCycler.make(label, options, LGSettings.get_value(section, key), func(v):
		LGSettings.set_value(section, key, v)
		if extra.is_valid():
			extra.call(v))
	add_child(c)


func _restart_ai() -> void:
	var brain := get_node_or_null("/root/LGBrain")
	if brain:
		brain.stop()


static func _ai_text(state: String, detail: String) -> String:
	match state:
		"ready":
			return "AI players think with %s." % detail
		"downloading", "loading", "starting":
			return "AI players: %s" % detail
		"unavailable", "error":
			return "AI players use scripted talk (%s)." % detail
	return "AI players start when a game with bots begins."
