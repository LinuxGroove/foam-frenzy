class_name Hints
extends Node
## One-time tips that appear the first time something comes up in a match,
## like running out of darts or getting tagged. What has been shown is
## remembered between matches, and Settings can turn the tips off.

const CHECK_EVERY := 0.5

var game: Game
var hud: Hud

var _seen := {}
var _check_t := 0.0
var _clock := 0.0
var _empty := false


func setup(p_game: Game, p_hud: Hud) -> void:
	game = p_game
	hud = p_hud
	for key in str(LGSettings.get_value("tutorial", "seen", "")).split(",", false):
		_seen[key] = true
	game.match_event.connect(_on_event)


## A local player tried to fire with no darts.
func on_empty() -> void:
	_empty = true


func _on_event(kind: int, _a: int, b: int) -> void:
	if kind == MatchHost.Ev.TAG and game.is_local(b):
		_once("tagged", "Tagged out! You'll be back in a moment. The darts you carried are on the floor now.")


func _process(delta: float) -> void:
	if game.phase != Rules.Phase.PLAY or game.locals.is_empty() or hud.blocks_input():
		return
	_clock += delta
	_check_t += delta
	if _check_t < CHECK_EVERY:
		return
	_check_t = 0.0
	if not bool(LGSettings.get_value("tutorial", "hints", true)):
		return
	if _empty:
		_once("pickup", "Out of darts! Walk over the darts on the floor to pick them up.")
	elif _clock >= 2.0 and game.mode == Rules.Mode.CTF:
		_once("ctf", "Grab the other team's flag and carry it to your base. Your own flag has to be at home to score.")
	elif _clock >= 2.0 and game.mode == Rules.Mode.HOARDER:
		_once("hoarder", "Hold the most darts when time runs out. Getting tagged spills every dart you carry.")
	elif _clock >= 2.0 and game.mode == Rules.Mode.TEAMS and not bool(game.settings.get("friendly_fire", false)):
		_once("teams", "Your team's colour is the ring under your feet. Your team's darts can't tag you.")
	elif _clock >= 3.0:
		_once("fire", "Aim and fire at the other campers.", "fire")
	if _clock >= 25.0:
		_once("dive", "Dive to dodge. Nothing can hit you mid-dive.", "dive")
	if _clock >= 60.0:
		_once("scores", "Hold to see everyone's score.", "scores")


func _once(key: String, text: String, action := "") -> void:
	if _seen.has(key) or hud._hint_t > 0.0 or not bool(LGSettings.get_value("tutorial", "hints", true)):
		return
	_seen[key] = true
	LGSettings.set_value("tutorial", "seen", ",".join(_seen.keys()))
	hud.show_hint(text, action)
