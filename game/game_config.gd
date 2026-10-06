class_name GameConfig
extends RefCounted
## Game-wide constants: identity, version, input map, campers and colours.

const GAME_ID := "foam-frenzy"
## Bump PROTOCOL whenever network messages change; mismatched builds are told
## to update instead of desyncing.
const PROTOCOL := 1
const MAX_PLAYERS := 8
const MIN_PLAYERS := 2
## Players on one device (one keyboard and controllers).
const MAX_LOCAL := 4

## Blocky Characters, one per look.
const LOOKS := [
	"character-a", "character-b", "character-c", "character-d", "character-e", "character-f",
	"character-g", "character-h", "character-i", "character-j", "character-k", "character-l",
	"character-m", "character-n", "character-o", "character-p", "character-q", "character-r",
]
## One colour and one reticle shape per player slot, so players can be told
## apart by shape as well as colour.
const SLOT_COLORS := [
	Color("ffd23f"), Color("3ec1ff"), Color("ff6fb5"), Color("7ee36b"),
	Color("ff9a3c"), Color("b38cff"), Color("5ff0d0"), Color("ff5e5e"),
]
const CROSSHAIRS := ["006", "018", "035", "055", "080", "102", "086", "175"]
const TEAM_COLORS := [Color("ff5a4f"), Color("3e8bff")]
const TEAM_NAMES := ["Red", "Blue"]

const SETTING_DEFAULTS := {
	"tutorial": {
		"welcomed": false,
		"howto_seen": false,
		"practiced": false,
		"hints": true,
		"seen": "",
	},
	"play": {
		# 0 off, 1 a little, 2 a lot
		"aim_assist": 1,
		"auto_fire": false,
		"shake": true,
		"blaster": 0,
	},
}

const BOT_NAMES := [
	"Ace", "Bea", "Coop", "Dash", "Echo", "Fizz", "Gigi", "Hap", "Izzy", "Jinx",
	"Kip", "Lulu", "Moxie", "Nib", "Ozzy", "Pip", "Quinn", "Rex", "Sunny", "Taz",
]

## Every in-game action, with keyboard and controller bindings (see LGInput).
## Each local player reads them through their own LGSeat.
const ACTIONS := {
	"move_left": ["key:A", "axis:lx-"],
	"move_right": ["key:D", "axis:lx+"],
	"move_up": ["key:W", "axis:ly-"],
	"move_down": ["key:S", "axis:ly+"],
	"aim_left": ["key:Left", "axis:rx-"],
	"aim_right": ["key:Right", "axis:rx+"],
	"aim_up": ["key:Up", "axis:ry-"],
	"aim_down": ["key:Down", "axis:ry+"],
	"fire": ["mouse:left", "axis:rt+", "joy:rb"],
	"dive": ["key:Shift", "key:Space", "mouse:right", "axis:lt+", "joy:a", "joy:lb"],
	"taunt": ["key:E", "joy:y"],
	"scores": ["key:Tab", "joy:back"],
	"pause": ["key:Escape", "joy:start"],
}
## Actions each seat tracks for just_pressed. Pause and the scoreboard work
## from any device, so the HUD handles those.
const SEAT_ACTIONS := ["fire", "dive", "taunt"]


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


static func look_scene(look: int) -> PackedScene:
	var n: String = LOOKS[clampi(look, 0, LOOKS.size() - 1)]
	return load("res://assets/kenney/blocky-characters/%s.glb" % n)


static func slot_color(slot: int) -> Color:
	return SLOT_COLORS[posmod(slot, SLOT_COLORS.size())]


static func crosshair(slot: int) -> Texture2D:
	return load("res://assets/kenney/crosshairs/crosshair-%s.png" % CROSSHAIRS[posmod(slot, CROSSHAIRS.size())])
