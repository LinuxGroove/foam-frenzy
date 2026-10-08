extends Node
## Boots the game: input map, theme and window, then the title screen.
##
## Developer shortcuts (after `--`):
##   --solo              skip the menus and start a match with bots
##   --mode=ctf          with --solo: ffa, teams, ctf or hoarder
##   --arena=lab         with --solo: gym or lab
##   --practice          skip the menus and start the practice round
##   --set=video/fullscreen=false   any setting, for one run

func _ready() -> void:
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGLaunchPing.send(GameConfig.GAME_ID)
	LGInput.register_actions(GameConfig.ACTIONS, float(LGSettings.get_value("input", "stick_deadzone")))
	LGInput.extend_ui_actions()
	LGTheme.apply(get_tree().root, 22)
	get_window().title = "Foam Frenzy"
	var args := OS.get_cmdline_user_args()
	var quick := "--solo" in args or "--practice" in args
	if quick and str(LGSettings.get_value("player", "name")).strip_edges() == "":
		LGSettings.set_value("player", "name", "Tester", false)
		Session.local_seats[0].name = "Tester"
	if "--practice" in args:
		LGSettings.set_value("tutorial", "howto_seen", true, false)
		Session.start_practice()
		return
	if "--solo" in args:
		LGSettings.set_value("tutorial", "howto_seen", true, false)
		Session.start_solo(5)
		for a in args:
			if a.begins_with("--mode="):
				var m := Rules.MODE_KEYS.find(a.trim_prefix("--mode="))
				if m >= 0:
					Session.set_setting("mode", m)
			elif a.begins_with("--arena="):
				Session.set_setting("arena", a.trim_prefix("--arena="))
		Session.start_match()
		return
	LGScenes.change_scene("res://game/ui/title.tscn")
