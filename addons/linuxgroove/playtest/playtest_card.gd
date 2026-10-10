class_name LGPlaytestCard
extends Control
## A card over the game for the play test recorder: what's recorded when it
## starts, and where the recording went when it ends. Frees itself when closed.

signal closed(choice: String)

var column: VBoxContainer


## What's recorded and how to note moments. `recovered` is how many earlier
## sessions were saved after the game stopped suddenly.
static func intro(recovered := 0) -> LGPlaytestCard:
	var c := LGPlaytestCard.new()
	c.heading("Play test recording")
	c.text("Thanks for testing! While you play, the game keeps a small picture every few seconds and notes what happens, how smoothly it runs and which controls you use.")
	c.text("Whenever something is fun, boring, confusing, frustrating, broken or makes you feel unwell, press F8 or choose Note this moment in the pause menu.")
	c.text("When you quit, a few questions come up. Everything stays on this computer until you send it.")
	if recovered > 0:
		c.text("Your last play test stopped suddenly. It's saved with the others, so send that one too.", true)
	c.buttons([["Start playing", ""]])
	return c


## Where the zip is. `quitting` names the last button Quit, else Back to the game.
static func done(zip_path: String, quitting: bool) -> LGPlaytestCard:
	var c := LGPlaytestCard.new()
	var where := ProjectSettings.globalize_path(zip_path) if zip_path != "" else ""
	c.heading("Thank you!")
	if where == "":
		c.text("The play test couldn't be saved.")
	else:
		c.text("Your play test is saved here. Send this file to whoever asked you to test.")
		var path := c.text(where)
		path.name = "Where"
		path.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		path.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
		c.text("To stop recording, turn off Play test recording in the settings.", true)
	var row := c.buttons([])
	if where != "":
		row.add_child(LGUi.button("Show the file", OS.shell_show_in_file_manager.bind(where), 240))
		row.add_child(LGUi.button("Copy where it is", DisplayServer.clipboard_set.bind(where), 240))
	row.add_child(LGUi.button("Quit" if quitting else "Back to the game", c.close.bind("done"), 240))
	return c


func _init() -> void:
	column = frame(self, 680)


func _ready() -> void:
	LGUi.focus_first(column)


## Dims the game and adds a centred panel to `control`. Returns its column.
static func frame(control: Control, width: int) -> VBoxContainer:
	control.process_mode = Node.PROCESS_MODE_ALWAYS
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "DarkPanel"
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = width
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	LGScreenFit.center(panel)
	return col


func heading(t: String) -> void:
	column.add_child(LGUi.label(t, "HeaderMedium"))


func text(t: String, hint := false) -> Label:
	var l := LGUi.label(t, "HintLabel" if hint else "")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = column.custom_minimum_size.x
	column.add_child(l)
	return l


## A row of buttons, each [text, choice]; each one closes the card with its choice.
func buttons(list: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	for b in list:
		row.add_child(LGUi.button(b[0], close.bind(b[1]), 260))
	column.add_child(row)
	return row


func close(choice := "") -> void:
	closed.emit(choice)
	queue_free()


## Every button's text, for tests.
func button_texts() -> Array[String]:
	var out: Array[String] = []
	for b in find_children("*", "Button", true, false):
		out.append((b as Button).text)
	return out
