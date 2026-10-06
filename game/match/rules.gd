class_name Rules
extends RefCounted
## Match rules shared by the host and every player: blasters, modes, house
## rules, timings and scoring. Pure data and functions, so tests can use them
## without a scene.

enum Mode { FFA, TEAMS, CTF, HOARDER }
enum Blaster { PISTOL, BURST, SHOTGUN, RAPID }
enum Phase { LOADING, COUNTDOWN, PLAY, ENDED }

const MODE_NAMES := ["Free-for-all", "Team Battle", "Capture the Flag", "Dart Hoarder"]
## How the game server names each mode in match reports.
const MODE_KEYS := ["ffa", "teams", "ctf", "hoarder"]
const MODE_BLURBS := [
	"Every camper for themselves. Most tags wins.",
	"Red against Blue. The team with the most tags wins.",
	"Grab the other team's flag and bring it home while yours is safe.",
	"Hold the most darts when the buzzer goes.",
]
const TEAM_MODES := [Mode.TEAMS, Mode.CTF]

## Fired darts fly at chest height. Speeds and ranges are in metres.
const BLASTERS := [
	{"name": "Pocket Pistol", "model": "blaster-b", "darts": 1, "burst": 1, "burst_gap": 0.0,
		"spread": 2.0, "cooldown": 0.3, "speed": 22.0, "range": 18.0,
		"about": "Quick and accurate. One dart a shot."},
	{"name": "Triple Tap", "model": "blaster-h", "darts": 1, "burst": 3, "burst_gap": 0.08,
		"spread": 4.0, "cooldown": 0.7, "speed": 21.0, "range": 16.0,
		"about": "Three darts in a quick burst."},
	{"name": "Foam Cannon", "model": "blaster-l", "darts": 5, "burst": 1, "burst_gap": 0.0,
		"spread": 28.0, "cooldown": 0.95, "speed": 17.0, "range": 9.0,
		"about": "Five darts in a wide spread. Short range, hungry for darts."},
	{"name": "Dart Hose", "model": "blaster-d", "darts": 1, "burst": 1, "burst_gap": 0.0,
		"spread": 7.0, "cooldown": 0.12, "speed": 20.0, "range": 14.0,
		"about": "Sprays darts as fast as you can find them."},
]

const DEFAULT_SETTINGS := {
	"mode": Mode.FFA,
	"arena": "gym",
	"minutes": 3,
	# 0 means the mode's usual target (see target_score).
	"target": 0,
	"bot_skill": 1,
	"darts_per_life": 6,
	"friendly_fire": false,
}

const CAMPER_RADIUS := 0.45
const MOVE_SPEED := 6.0
const DIVE_SPEED := 13.0
const DIVE_TIME := 0.28
const DIVE_COOLDOWN := 1.1
const HP := 3
const MAX_AMMO := 20
const RESPAWN_TIME := 3.0
## Just respawned: can't be tagged until this runs out or they fire.
const SPAWN_SHIELD := 1.6
const PICKUP_RADIUS := 0.95
const PICKUP_LIFE := 35.0
const MAX_PICKUPS := 100
const MAX_DARTS_IN_FLIGHT := 96
const DART_HEIGHT := 1.0
const DART_RADIUS := 0.12
const COUNTDOWN := 3.0
const FLAG_RETURN_TIME := 12.0
const FLAG_RADIUS := 1.3
## How far ahead of a camper its darts start (the blaster's muzzle).
const MUZZLE := 0.6
## A camper's reported position may run ahead of the host by this much
## (lag, rounding) before the host pulls it back.
const MOVE_SLACK := 1.2


static func blaster(i: int) -> Dictionary:
	return BLASTERS[clampi(i, 0, BLASTERS.size() - 1)]


static func is_team_mode(mode: int) -> bool:
	return mode in TEAM_MODES


## The score that ends a match early (0 for none).
static func target_score(settings: Dictionary) -> int:
	var t := int(settings.get("target", 0))
	if t > 0:
		return t
	match int(settings.get("mode", Mode.FFA)):
		Mode.FFA:
			return 15
		Mode.TEAMS:
			return 30
		Mode.CTF:
			return 3
	return 0


## Splits players into two balanced teams in roster order. `ids` is sorted
## first so every device agrees.
static func assign_teams(ids: Array, mode: int) -> Dictionary:
	var sorted := ids.duplicate()
	sorted.sort()
	var out := {}
	for i in sorted.size():
		out[sorted[i]] = (i % 2) if is_team_mode(mode) else -1
	return out


## The direction of each dart in one trigger pull (yaw in radians, 0 = +z).
## Spread is random within the blaster's cone; shotgun darts are fanned out
## evenly with a little jitter.
static func dart_yaws(b: Dictionary, yaw: float, rng: RandomNumberGenerator) -> Array:
	var out := []
	var n := int(b.darts)
	var spread := deg_to_rad(float(b.spread))
	if n == 1:
		out.append(yaw + rng.randf_range(-spread, spread) * 0.5)
	else:
		for i in n:
			var f := (float(i) / float(n - 1)) - 0.5
			out.append(yaw + f * spread + rng.randf_range(-0.03, 0.03))
	return out


static func yaw_dir(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


static func dir_yaw(dir: Vector2) -> float:
	return atan2(dir.x, dir.y)


## Who won: {"winner": actor id or -1, "team": team or -1, "tie": bool}.
## `scores` is actor id -> score, `teams` actor id -> team.
static func winner(mode: int, scores: Dictionary, teams: Dictionary, team_scores: Array) -> Dictionary:
	if is_team_mode(mode):
		if team_scores[0] == team_scores[1]:
			return {"winner": -1, "team": -1, "tie": true}
		return {"winner": -1, "team": 0 if team_scores[0] > team_scores[1] else 1, "tie": false}
	var best := -1
	var best_score := -1
	var tie := false
	for id in scores:
		var s := int(scores[id])
		if s > best_score:
			best = id
			best_score = s
			tie = false
		elif s == best_score:
			tie = true
	return {"winner": -1 if tie else best, "team": -1, "tie": tie}


## Awards at the end of a match. `stats` is actor id -> stats dictionary
## (tags, outs, shots, hits, pickups, captures, held). Each medal goes to one
## player, and only when someone actually earned it.
static func medals(mode: int, stats: Dictionary) -> Array:
	var out := []
	var award := func(key: String, title: String, icon: int, pick: Callable, min_value: float) -> void:
		var best := 0
		var best_v := -INF
		var found := false
		for id in stats:
			var v: float = pick.call(stats[id])
			if v > best_v:
				best_v = v
				best = id
				found = true
		if found and best_v >= min_value:
			out.append({"key": key, "title": title, "icon": icon, "id": best})
	award.call("tagger", "Top Tagger", 1, func(s): return float(s.get("tags", 0)), 1.0)
	award.call("sharp", "Sharpshooter", 2, func(s):
		var shots := int(s.get("shots", 0))
		return float(s.get("hits", 0)) / float(shots) if shots >= 8 else -1.0, 0.0)
	award.call("magnet", "Dart Magnet", 3, func(s): return float(s.get("pickups", 0)), 5.0)
	award.call("untouchable", "Untouchable", 4, func(s): return -float(s.get("outs", 0)), -INF)
	if mode == Mode.CTF:
		award.call("runner", "Flag Runner", 5, func(s): return float(s.get("captures", 0)), 1.0)
	if mode == Mode.HOARDER:
		award.call("hoarder", "Hoarder", 6, func(s): return float(s.get("held", 0)), 1.0)
	return out
