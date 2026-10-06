extends SceneTree
## Runs bot-only matches headless and prints how they went:
##   godot --headless --path . -s tools/sim.gd -- [mode] [arena] [bots] [skill]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := int(args[0]) if args.size() > 0 else 0
	var arena := args[1] if args.size() > 1 else "gym"
	var n := int(args[2]) if args.size() > 2 else 6
	var skill := int(args[3]) if args.size() > 3 else 1
	var players := {}
	for i in n:
		players[-(i + 1)] = {"name": "Bot%d" % i, "look": i, "slot": i, "bot": true, "blaster": i % 4, "skill": skill}
	var host := MatchHost.new()
	host.auto_step = false
	host.setup({"seed": 7, "players": players, "settings": {"mode": mode, "arena": arena, "minutes": 3}}, NetStub.new())
	var steps := 0
	while host.phase != Rules.Phase.ENDED and steps < 60 * 60 * 5:
		host.step(1.0 / 60.0)
		steps += 1
	var r := host.result
	print("mode %d on %s: %.0f s, team scores %s, darts in flight %d, pickups %d" % [mode, arena, host.time, host.team_scores, host.darts.size(), host.pickups.size()])
	for row in r.get("standings", []):
		var a: Dictionary = host.actors[row[0]]
		print("  %-6s team %2d score %3d  %s  blaster %d" % [a.name, a.team, a.score, a.stats, a.blaster])
	for m in r.get("medals", []):
		print("  medal ", m.title, " -> ", host.actors[m.id].name)
	quit()
