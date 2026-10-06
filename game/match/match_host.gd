class_name MatchHost
extends Node
## Runs a match on the hosting device: the clock, every dart and pickup,
## tags, flags, respawns and the bots. Players' devices move their own
## campers and ask to fire or dive; the host checks each request, decides
## what happens and tells everyone (see Game for the messages).
##
## Nothing here needs a screen or the physics engine: the arena grid answers
## every collision question, so tests run whole matches with [method step].

signal ended(result: Dictionary)

enum Ev { TAG, FLAG_TAKEN, FLAG_DROPPED, FLAG_RETURNED, CAPTURE, OVERTIME, TAUNT, LEAD }

const SNAPSHOT_EVERY := 1.0 / 20.0
const STATUS_EVERY := 0.5
const OVERTIME_MAX := 60.0
## The countdown starts once every device has loaded the arena, or after this
## long for a device that is slow or stuck.
const LOAD_TIMEOUT := 15.0
## Snapshot flag bits
const F_ALIVE := 1
const F_DIVE := 2
const F_SHIELD := 4
const F_MOVING := 8
const F_FLAG := 16
const F_FIRED := 32
const F_TAUNT := 64

## The match config from Session (see setup).
var config := {}
## Anything with send(peer, method, args) and broadcast(method, args): the
## Game scene, or a stub in tests.
var net: Object
## When false, nothing advances until step() is called (tests).
var auto_step := true

var grid: ArenaGrid
var settings := {}
var mode := Rules.Mode.FFA
var practice := false
var rng := RandomNumberGenerator.new()
var phase := Rules.Phase.LOADING
var countdown := Rules.COUNTDOWN
## Seconds of play so far; doors run on this clock.
var time := 0.0
## Seconds left (INF when the match has no time limit).
var clock := INF
var overtime := false
var actors := {}
var darts := {}
var pickups := {}
## One per team in Capture the Flag: {state, pos, carrier, dropped_t}
## state 0 = at base, 1 = carried, 2 = dropped.
var flags: Array = []
var team_scores := [0, 0]
var target := 0
var result := {}

var _bots := {}
var _next_dart := 1
var _next_pickup := 1
var _snap_t := 0.0
var _status_t := 0.0
var _new_darts := []
var _dart_ends := []
var _pick_added := []
var _pick_removed := []
var _status_dirty := true
var _overtime_t := 0.0
var _leader := 0
var _load_t := 0.0


## Deals the match: teams, bots, flags and everyone's first spawn.
func setup(p_config: Dictionary, p_net: Object) -> void:
	config = p_config
	net = p_net
	settings = Rules.DEFAULT_SETTINGS.duplicate()
	settings.merge(config.get("settings", {}), true)
	mode = int(settings.mode)
	practice = bool(config.get("practice", false))
	rng.seed = int(config.get("seed", 1))
	grid = ArenaGrid.make(str(settings.arena))
	target = Rules.target_score(settings)
	var minutes := int(settings.minutes)
	clock = minutes * 60.0 if minutes > 0 and not practice else INF
	var players: Dictionary = config.get("players", {})
	var teams := Rules.assign_teams(players.keys(), mode)
	for id in players:
		var p: Dictionary = players[id]
		actors[id] = {
			"id": id, "name": p.name, "look": int(p.look), "slot": int(p.get("slot", 0)),
			"team": int(teams[id]), "blaster": int(p.get("blaster", 0)), "bot": bool(p.get("bot", false)),
			"peer": int(p.get("peer", 0)),
			"pos": Vector2.ZERO, "yaw": 0.0, "hp": Rules.HP, "ammo": 0, "alive": false,
			"respawn": 0.0, "shield": 0.0, "dive": 0.0, "dive_cd": 0.0, "fire_cd": 0.0,
			"burst_left": 0, "burst_t": 0.0, "moving": false, "fired_t": 0.0, "taunt_t": 0.0,
			"flag": -1, "score": 0, "last_report": 0.0, "out": false,
			"stats": {"tags": 0, "outs": 0, "shots": 0, "hits": 0, "pickups": 0, "captures": 0, "returns": 0, "held": 0},
		}
		if actors[id].bot:
			var brain := BotBrain.new()
			brain.setup(self, id, int(p.get("skill", settings.bot_skill)), practice)
			_bots[id] = brain
	if mode == Rules.Mode.CTF:
		for team in 2:
			flags.append({"state": 0, "pos": grid.bases[team], "carrier": 0, "dropped_t": 0.0})
	for id in actors:
		_spawn(id, true)


func _physics_process(delta: float) -> void:
	if auto_step:
		step(delta)


## Advances the match by dt seconds.
func step(dt: float) -> void:
	if phase == Rules.Phase.ENDED:
		return
	if phase == Rules.Phase.LOADING:
		_load_t += dt
		if _load_t >= LOAD_TIMEOUT or not net.has_method("everyone_loaded") or net.everyone_loaded():
			phase = Rules.Phase.COUNTDOWN
			_status_dirty = true
	if phase == Rules.Phase.COUNTDOWN:
		countdown -= dt
		if countdown <= 0.0:
			phase = Rules.Phase.PLAY
			_status_dirty = true
	if phase == Rules.Phase.PLAY:
		time += dt
		if clock != INF:
			clock = maxf(clock - dt, 0.0)
		if overtime:
			_overtime_t += dt
		for id in _bots:
			_drive_bot(id, dt)
		for id in actors:
			_tick_actor(actors[id], dt)
		_tick_darts(dt)
		_tick_pickups()
		if mode == Rules.Mode.CTF:
			_tick_flags(dt)
		if mode == Rules.Mode.HOARDER:
			_hoarder_scores()
		_check_end()
	_flush(dt)


# --- Requests from players' devices -------------------------------------

## A device reports where its camper is. Movement is the device's own, but
## the host pulls back anything faster than a camper can go or inside a wall.
func on_state(peer: int, id: int, pos: Vector2, yaw: float, moving: bool) -> void:
	var a: Dictionary = actors.get(id, {})
	if a.is_empty() or a.bot or a.peer != peer or not a.alive or phase != Rules.Phase.PLAY:
		return
	var elapsed := clampf(time - float(a.last_report), 0.0, 0.5)
	var speed := Rules.DIVE_SPEED if a.dive > 0.0 else Rules.MOVE_SPEED
	var allowed := speed * (elapsed + 0.1) + Rules.MOVE_SLACK
	if pos.distance_to(a.pos) > allowed or grid.blocked(pos, Rules.CAMPER_RADIUS * 0.5, time):
		net.send(peer, "_h_correct", [id, a.pos])
		return
	a.pos = pos
	a.yaw = yaw
	a.moving = moving
	a.last_report = time


func on_fire(peer: int, id: int, origin: Vector2, yaw: float) -> void:
	var a: Dictionary = actors.get(id, {})
	if a.is_empty() or a.peer != peer or a.bot:
		return
	if origin.distance_to(a.pos) < Rules.MOVE_SLACK:
		a.pos = grid.move(a.pos, origin - a.pos, Rules.CAMPER_RADIUS, time)
	a.yaw = yaw
	try_fire(id)


func on_dive(peer: int, id: int) -> void:
	var a: Dictionary = actors.get(id, {})
	if a.is_empty() or a.peer != peer or a.bot:
		return
	try_dive(id)


func on_taunt(peer: int, id: int) -> void:
	var a: Dictionary = actors.get(id, {})
	if a.is_empty() or a.peer != peer or not a.alive or a.taunt_t > 0.0:
		return
	a.taunt_t = 1.2
	net.broadcast("_h_event", [Ev.TAUNT, id, 0])


## A player's device dropped out mid-match: their campers leave the arena,
## dropping any flag they carried.
func on_player_left(peer: int) -> void:
	for id in actors:
		var a: Dictionary = actors[id]
		if not a.bot and a.peer == peer and not a.out:
			_drop_flag(a)
			a.out = true
			a.alive = false
			a.respawn = INF


# --- Actions (players and bots) --------------------------------------------

func can_act(a: Dictionary) -> bool:
	return phase == Rules.Phase.PLAY and a.alive and not a.out


## Pulls the trigger for an actor at its current position and aim.
func try_fire(id: int) -> bool:
	var a: Dictionary = actors[id]
	if not can_act(a) or a.fire_cd > 0.05 or a.ammo <= 0 or a.burst_left > 0:
		return false
	var b := Rules.blaster(a.blaster)
	a.fire_cd = float(b.cooldown)
	a.shield = 0.0
	a.fired_t = 0.25
	_fire_volley(a, b)
	if int(b.burst) > 1:
		a.burst_left = int(b.burst) - 1
		a.burst_t = float(b.burst_gap)
	return true


func try_dive(id: int) -> bool:
	var a: Dictionary = actors[id]
	if not can_act(a) or a.dive_cd > 0.05:
		return false
	a.dive = Rules.DIVE_TIME
	a.dive_cd = Rules.DIVE_COOLDOWN
	return true


func _fire_volley(a: Dictionary, b: Dictionary) -> void:
	for yaw in Rules.dart_yaws(b, a.yaw, rng):
		if a.ammo <= 0:
			break
		a.ammo -= 1
		a.stats.shots += 1
		_spawn_dart(a, yaw, b)


func _spawn_dart(a: Dictionary, yaw: float, b: Dictionary) -> void:
	var dir := Rules.yaw_dir(yaw)
	var origin: Vector2 = a.pos + dir * Rules.MUZZLE
	if not grid.clear_line(a.pos, origin, time):
		# Pressed against a wall: the dart drops at their feet.
		_add_pickup(grid.nearest_floor(a.pos) if grid.blocked(a.pos, 0.05, time) else a.pos)
		return
	if darts.size() >= Rules.MAX_DARTS_IN_FLIGHT:
		_end_dart(darts[darts.keys()[0]], darts[darts.keys()[0]].pos, 0)
	var d := {"id": _next_dart, "owner": a.id, "team": a.team, "pos": origin, "dir": dir,
		"speed": float(b.speed), "left": float(b.range)}
	_next_dart += 1
	darts[d.id] = d
	_new_darts.append([d.id, a.id, origin.x, origin.y, yaw, d.speed, d.left])


# --- Simulation --------------------------------------------------------------

func _tick_actor(a: Dictionary, dt: float) -> void:
	if a.out:
		return
	a.fire_cd = maxf(a.fire_cd - dt, 0.0)
	a.dive_cd = maxf(a.dive_cd - dt, 0.0)
	a.dive = maxf(a.dive - dt, 0.0)
	a.shield = maxf(a.shield - dt, 0.0)
	a.fired_t = maxf(a.fired_t - dt, 0.0)
	a.taunt_t = maxf(a.taunt_t - dt, 0.0)
	if not a.alive:
		a.respawn -= dt
		if a.respawn <= 0.0:
			_spawn(a.id, false)
		return
	# A door that shuts on a camper shoves them out of the doorway.
	if grid.blocked(a.pos, Rules.CAMPER_RADIUS * 0.5, time):
		a.pos = grid.unstick(a.pos, Rules.CAMPER_RADIUS, time)
		if not a.bot:
			net.send(int(a.peer), "_h_correct", [a.id, a.pos])
	if a.burst_left > 0:
		a.burst_t -= dt
		if a.burst_t <= 0.0:
			var b := Rules.blaster(a.blaster)
			a.burst_left -= 1
			a.burst_t = float(b.burst_gap)
			a.fired_t = 0.25
			_fire_volley(a, b)
			if a.ammo <= 0:
				a.burst_left = 0


func _tick_darts(dt: float) -> void:
	for id in darts.keys():
		var d: Dictionary = darts[id]
		var travel := minf(d.speed * dt, d.left)
		var from: Vector2 = d.pos
		var to: Vector2 = from + d.dir * travel
		var wall := grid.raycast(from, to, time)
		var stop: Vector2 = wall.point if wall.hit else to
		var victim := _first_hit(d, from, stop)
		if victim != 0:
			var hit_at := _closest_on_segment(from, stop, actors[victim].pos)
			if _hit(victim, d):
				_end_dart(d, hit_at, victim)
				continue
		if wall.hit:
			_end_dart(d, stop - d.dir * 0.35, 0)
			continue
		d.pos = to
		d.left -= travel
		if d.left <= 0.001:
			_end_dart(d, to, 0)


## The first camper the dart's path crosses this tick (0 for none). Darts
## pass through their owner, divers and (without friendly fire) teammates.
func _first_hit(d: Dictionary, from: Vector2, to: Vector2) -> int:
	var best := 0
	var best_t := INF
	var seg := to - from
	var len2 := maxf(seg.length_squared(), 1e-6)
	for id in actors:
		var a: Dictionary = actors[id]
		if id == d.owner or not a.alive or a.dive > 0.0:
			continue
		if a.team >= 0 and a.team == d.team and not bool(settings.friendly_fire):
			continue
		var t := clampf((a.pos - from).dot(seg) / len2, 0.0, 1.0)
		var closest := from + seg * t
		if closest.distance_to(a.pos) <= Rules.CAMPER_RADIUS + Rules.DART_RADIUS and t < best_t:
			best_t = t
			best = id
	return best


func _closest_on_segment(a: Vector2, b: Vector2, p: Vector2) -> Vector2:
	var seg := b - a
	var t := clampf((p - a).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
	return a + seg * t


## A dart reaches a camper. Returns true if the dart stops there.
func _hit(victim_id: int, d: Dictionary) -> bool:
	var v: Dictionary = actors[victim_id]
	if v.shield > 0.0:
		return true
	v.hp -= 1
	var shooter: Dictionary = actors.get(d.owner, {})
	if not shooter.is_empty():
		shooter.stats.hits += 1
	if v.hp <= 0:
		_tag_out(v, shooter)
	return true


func _tag_out(v: Dictionary, shooter: Dictionary) -> void:
	v.alive = false
	v.respawn = Rules.RESPAWN_TIME
	v.stats.outs += 1
	v.burst_left = 0
	v.dive = 0.0
	_drop_flag(v)
	# Everything they carried spills around them.
	for i in v.ammo:
		var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.3, 1.4)
		var p := grid.move(v.pos, off, 0.1, time)
		_add_pickup(p)
	v.ammo = 0
	if not shooter.is_empty() and shooter.id != v.id:
		shooter.stats.tags += 1
		if mode in [Rules.Mode.FFA, Rules.Mode.TEAMS]:
			shooter.score += 1
		elif mode == Rules.Mode.CTF:
			shooter.score += 1
		if mode == Rules.Mode.TEAMS and shooter.team >= 0:
			team_scores[shooter.team] += 1
	_status_dirty = true
	net.broadcast("_h_event", [Ev.TAG, int(shooter.get("id", 0)), v.id])


func _end_dart(d: Dictionary, at: Vector2, victim: int) -> void:
	darts.erase(d.id)
	var p := at
	if victim != 0:
		p = actors[victim].pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.2, 0.7)
	if grid.blocked(p, 0.05, time):
		p = grid.nearest_floor(p)
	_dart_ends.append([d.id, p.x, p.y, victim])
	_add_pickup(p)


func _add_pickup(p: Vector2) -> void:
	if pickups.size() >= Rules.MAX_PICKUPS:
		var oldest: int = pickups.keys()[0]
		pickups.erase(oldest)
		_pick_removed.append([oldest, 0])
	var id := _next_pickup
	_next_pickup += 1
	pickups[id] = {"id": id, "pos": p, "t": time}
	_pick_added.append([id, p.x, p.y])


func _tick_pickups() -> void:
	for pid in pickups.keys():
		var pk: Dictionary = pickups[pid]
		if time - float(pk.t) > Rules.PICKUP_LIFE:
			pickups.erase(pid)
			_pick_removed.append([pid, 0])
			continue
		# Darts still settling for a moment can't be grabbed.
		if time - float(pk.t) < 0.25:
			continue
		for id in actors:
			var a: Dictionary = actors[id]
			if not a.alive or a.ammo >= Rules.MAX_AMMO:
				continue
			if a.pos.distance_squared_to(pk.pos) <= Rules.PICKUP_RADIUS * Rules.PICKUP_RADIUS:
				a.ammo += 1
				a.stats.pickups += 1
				pickups.erase(pid)
				_pick_removed.append([pid, id])
				break


func _spawn(id: int, first: bool) -> void:
	var a: Dictionary = actors[id]
	if a.out:
		return
	var points := grid.spawn_points(a.team)
	var best: Vector2 = points[0]
	var best_score := -INF
	for p in points:
		var nearest := 99.0
		for oid in actors:
			var o: Dictionary = actors[oid]
			if oid == id or not o.alive or (o.team >= 0 and o.team == a.team):
				continue
			nearest = minf(nearest, o.pos.distance_to(p))
		var score := nearest + rng.randf() * 3.0
		if first:
			# Everyone starts on a different spot.
			for oid in actors:
				if oid != id and actors[oid].alive and actors[oid].pos.distance_to(p) < 1.0:
					score -= 100.0
		if score > best_score:
			best_score = score
			best = p
	a.pos = grid.move(best, Vector2.from_angle(rng.randf() * TAU) * 0.3, Rules.CAMPER_RADIUS, time)
	a.yaw = Rules.dir_yaw(grid.world_size() * 0.5 - a.pos)
	a.hp = Rules.HP
	a.ammo = int(settings.darts_per_life)
	a.alive = true
	a.shield = Rules.SPAWN_SHIELD
	a.dive = 0.0
	a.burst_left = 0
	a.last_report = time
	net.broadcast("_h_respawn", [id, a.pos, a.yaw])


func _drive_bot(id: int, dt: float) -> void:
	var a: Dictionary = actors[id]
	if not a.alive or a.out:
		return
	var intent: Dictionary = _bots[id].think(dt)
	a.yaw = float(intent.get("yaw", a.yaw))
	if intent.get("dive", false):
		try_dive(id)
	var move: Vector2 = intent.get("move", Vector2.ZERO)
	var speed := Rules.MOVE_SPEED * float(_bots[id].speed_scale)
	if a.dive > 0.0:
		move = Rules.yaw_dir(a.yaw) if move.length() < 0.1 else move.normalized()
		speed = Rules.DIVE_SPEED
	elif a.flag >= 0:
		speed *= 0.9
	a.moving = move.length() > 0.1
	a.pos = grid.move(a.pos, move * speed * dt, Rules.CAMPER_RADIUS, time)
	if intent.get("fire", false):
		try_fire(id)


# --- Capture the Flag ---------------------------------------------------

func _tick_flags(dt: float) -> void:
	for team in 2:
		var f: Dictionary = flags[team]
		if f.state == 1:
			var c: Dictionary = actors.get(f.carrier, {})
			if c.is_empty() or not c.alive:
				continue
			f.pos = c.pos
			# Home with the enemy flag while ours is safe: a capture.
			var own: Dictionary = flags[c.team]
			if own.state == 0 and c.pos.distance_to(grid.bases[c.team]) <= Rules.FLAG_RADIUS:
				c.flag = -1
				c.stats.captures += 1
				c.score += 3
				team_scores[c.team] += 1
				f.state = 0
				f.pos = grid.bases[team]
				f.carrier = 0
				_status_dirty = true
				net.broadcast("_h_event", [Ev.CAPTURE, c.id, team])
			continue
		if f.state == 2:
			f.dropped_t += dt
			if f.dropped_t >= Rules.FLAG_RETURN_TIME:
				_return_flag(team, 0)
				continue
		for id in actors:
			var a: Dictionary = actors[id]
			if not a.alive or a.pos.distance_to(f.pos) > Rules.FLAG_RADIUS:
				continue
			if a.team == team:
				if f.state == 2:
					a.stats.returns += 1
					a.score += 1
					_return_flag(team, id)
					break
			elif a.flag < 0:
				f.state = 1
				f.carrier = id
				a.flag = team
				a.shield = 0.0
				net.broadcast("_h_event", [Ev.FLAG_TAKEN, id, team])
				break


func _return_flag(team: int, by: int) -> void:
	var f: Dictionary = flags[team]
	f.state = 0
	f.pos = grid.bases[team]
	f.carrier = 0
	f.dropped_t = 0.0
	net.broadcast("_h_event", [Ev.FLAG_RETURNED, by, team])


func _drop_flag(a: Dictionary) -> void:
	if a.flag < 0 or flags.is_empty():
		return
	var f: Dictionary = flags[a.flag]
	f.state = 2
	f.pos = grid.nearest_floor(a.pos) if grid.blocked(a.pos, 0.1, time) else a.pos
	f.carrier = 0
	f.dropped_t = 0.0
	net.broadcast("_h_event", [Ev.FLAG_DROPPED, a.id, a.flag])
	a.flag = -1


# --- Scores and the end --------------------------------------------------

func _hoarder_scores() -> void:
	for id in actors:
		var a: Dictionary = actors[id]
		if a.score != a.ammo:
			a.score = a.ammo
			_status_dirty = true


func scores() -> Dictionary:
	var out := {}
	for id in actors:
		out[id] = actors[id].score
	return out


func teams() -> Dictionary:
	var out := {}
	for id in actors:
		out[id] = actors[id].team
	return out


func _check_end() -> void:
	var w := Rules.winner(mode, scores(), teams(), team_scores)
	var lead := int(w.winner) if not Rules.is_team_mode(mode) else int(w.team) + 1000
	if not w.tie and lead != _leader and phase == Rules.Phase.PLAY and time > 5.0 and not practice:
		_leader = lead
		net.broadcast("_h_event", [Ev.LEAD, int(w.winner), int(w.team)])
	if overtime:
		if not w.tie or _overtime_t >= OVERTIME_MAX:
			_finish()
		return
	if target > 0:
		if Rules.is_team_mode(mode):
			if maxi(team_scores[0], team_scores[1]) >= target:
				_finish()
				return
		else:
			for id in actors:
				if mode != Rules.Mode.HOARDER and actors[id].score >= target:
					_finish()
					return
	if clock <= 0.0:
		if w.tie and not practice and actors.size() > 1:
			overtime = true
			_status_dirty = true
			net.broadcast("_h_event", [Ev.OVERTIME, 0, 0])
		else:
			_finish()


func _finish() -> void:
	phase = Rules.Phase.ENDED
	for id in actors:
		actors[id].stats.held = actors[id].ammo
	var w := Rules.winner(mode, scores(), teams(), team_scores)
	var stats := {}
	var standings := []
	for id in actors:
		var a: Dictionary = actors[id]
		stats[id] = a.stats.duplicate()
		standings.append([id, a.score, a.stats.tags, a.stats.outs, a.team])
	standings.sort_custom(func(x, y):
		if x[1] != y[1]:
			return x[1] > y[1]
		return x[3] < y[3])
	result = {
		"mode": mode, "winner": w.winner, "team": w.team, "tie": w.tie,
		"team_scores": team_scores.duplicate(), "standings": standings,
		"stats": stats, "medals": Rules.medals(mode, stats),
		"practice": practice, "time": time,
	}
	_flush(0.0)
	net.broadcast("_h_game_over", [result])
	ended.emit(result)


# --- Sending -------------------------------------------------------------------

func _flush(dt: float) -> void:
	if not _new_darts.is_empty():
		net.broadcast("_h_darts", [_new_darts])
		_new_darts = []
	if not _dart_ends.is_empty():
		net.broadcast("_h_dart_ends", [_dart_ends])
		_dart_ends = []
	if not _pick_added.is_empty() or not _pick_removed.is_empty():
		net.broadcast("_h_pickups", [_pick_added, _pick_removed])
		_pick_added = []
		_pick_removed = []
	_snap_t -= dt
	if _snap_t <= 0.0:
		_snap_t = SNAPSHOT_EVERY
		net.broadcast("_h_snapshot", [time, _actor_snapshot(), _flag_snapshot()])
	_status_t -= dt
	if _status_dirty or _status_t <= 0.0:
		_status_t = STATUS_EVERY
		_status_dirty = false
		net.broadcast("_h_status", [phase, countdown, clock if clock != INF else -1.0, scores(), team_scores, overtime])


func _actor_snapshot() -> Array:
	var out := []
	for id in actors:
		var a: Dictionary = actors[id]
		if a.out:
			continue
		var f := 0
		if a.alive:
			f |= F_ALIVE
		if a.dive > 0.0:
			f |= F_DIVE
		if a.shield > 0.0:
			f |= F_SHIELD
		if a.moving:
			f |= F_MOVING
		if a.flag >= 0:
			f |= F_FLAG
		if a.fired_t > 0.0:
			f |= F_FIRED
		if a.taunt_t > 0.0:
			f |= F_TAUNT
		out.append([id, a.pos.x, a.pos.y, a.yaw, f, a.hp, a.ammo, a.respawn if not a.alive else 0.0])
	return out


func _flag_snapshot() -> Array:
	var out := []
	for f in flags:
		out.append([f.state, f.pos.x, f.pos.y, f.carrier])
	return out
