class_name BotBrain
extends RefCounted
## A bot camper's head, run on the host. Each tick it looks at the match the
## way a player would (who's in sight, where the loose darts are, where the
## flags are) and returns what a controller would: a move direction, an aim,
## and whether to fire or dive. Skill changes how well it aims, how fast it
## reacts and how often it dodges.

const SKILLS := [
	{"name": "Easy", "aim_error": 0.32, "reaction": 0.75, "speed": 0.85, "dodge": 0.12, "fire_gap": 0.55, "sight": 13.0},
	{"name": "Normal", "aim_error": 0.17, "reaction": 0.42, "speed": 0.94, "dodge": 0.35, "fire_gap": 0.2, "sight": 16.0},
	{"name": "Hard", "aim_error": 0.07, "reaction": 0.22, "speed": 1.0, "dodge": 0.65, "fire_gap": 0.0, "sight": 20.0},
]
## Practice bots wander slowly and fire rarely, so a new player can learn.
const PRACTICE := {"name": "Practice", "aim_error": 0.45, "reaction": 1.2, "speed": 0.6, "dodge": 0.0, "fire_gap": 1.6, "sight": 10.0}

var host: MatchHost
var id := 0
var skill := {}
var speed_scale := 1.0

var _path := PackedVector2Array()
var _path_i := 0
var _goal := Vector2.INF
var _repath_t := 0.0
var _target := 0
var _target_seen := 0.0
var _last_target_pos := Vector2.ZERO
var _target_vel := Vector2.ZERO
var _aim_offset := 0.0
var _aim_offset_t := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _fire_wait := 0.0
var _stuck_t := 0.0
var _stuck_from := Vector2.ZERO
var _wander := Vector2.INF
var _dodge_cd := 0.0


func setup(p_host: MatchHost, p_id: int, level: int, practice: bool) -> void:
	host = p_host
	id = p_id
	skill = PRACTICE if practice else SKILLS[clampi(level, 0, SKILLS.size() - 1)]
	speed_scale = float(skill.speed)
	_strafe = 1.0 if host.rng.randf() < 0.5 else -1.0


func think(dt: float) -> Dictionary:
	var me: Dictionary = host.actors[id]
	var grid := host.grid
	_repath_t -= dt
	_strafe_t -= dt
	_fire_wait = maxf(_fire_wait - dt, 0.0)
	_dodge_cd = maxf(_dodge_cd - dt, 0.0)
	_aim_offset_t -= dt
	if _aim_offset_t <= 0.0:
		_aim_offset_t = host.rng.randf_range(0.4, 0.9)
		_aim_offset = host.rng.randf_range(-1.0, 1.0) * float(skill.aim_error)
	if _strafe_t <= 0.0:
		_strafe_t = host.rng.randf_range(0.6, 1.8)
		_strafe = -_strafe

	_pick_target(me, dt)
	var target: Dictionary = host.actors.get(_target, {})
	var b := Rules.blaster(me.blaster)
	var want_range := float(b.range) * (0.35 if b.darts > 1 else 0.6)

	# Where to go
	var goal := _choose_goal(me, target, want_range)
	var move := Vector2.ZERO
	if goal != Vector2.INF:
		move = _steer(me.pos, goal)
	if not target.is_empty() and me.ammo > 0 and _target_seen > 0.0:
		var to_t: Vector2 = target.pos - me.pos
		var dist := to_t.length()
		# Circle the target at a comfortable range.
		var side := Vector2(-to_t.y, to_t.x).normalized() * _strafe
		if dist < want_range * 0.6:
			move = (side - to_t.normalized()).normalized()
		elif dist < want_range * 1.2:
			move = (move * 0.4 + side).normalized()
	# Unstick
	if me.moving and me.pos.distance_to(_stuck_from) < 0.15:
		_stuck_t += dt
		if _stuck_t > 0.8:
			_stuck_t = 0.0
			_wander = grid.random_floor(host.rng)
			_repath_t = 0.0
			_strafe = -_strafe
	else:
		_stuck_t = 0.0
		_stuck_from = me.pos

	# Aim and fire
	var yaw: float = me.yaw
	var fire := false
	if not target.is_empty() and _target_seen > 0.0:
		var dist: float = me.pos.distance_to(target.pos)
		var lead: Vector2 = target.pos + _target_vel * (dist / float(b.speed))
		yaw = Rules.dir_yaw(lead - me.pos) + _aim_offset
		if _target_seen >= float(skill.reaction) and me.ammo > 0 and dist <= float(b.range) * 0.95 and _fire_wait <= 0.0:
			fire = true
			_fire_wait = float(skill.fire_gap) + host.rng.randf() * float(skill.fire_gap)
	elif move.length() > 0.1:
		yaw = lerp_angle(me.yaw, Rules.dir_yaw(move), 0.2)

	# Dodge an incoming dart now and then.
	var dive := false
	if _dodge_cd <= 0.0 and _dart_incoming(me):
		_dodge_cd = 1.0
		if host.rng.randf() < float(skill.dodge):
			dive = true
	me.moving = move.length() > 0.1
	return {"move": move, "yaw": yaw, "fire": fire, "dive": dive}


func _pick_target(me: Dictionary, dt: float) -> void:
	var best := 0
	var best_d := float(skill.sight)
	for oid in host.actors:
		var o: Dictionary = host.actors[oid]
		if oid == id or not o.alive or (o.team >= 0 and o.team == me.team):
			continue
		var d: float = me.pos.distance_to(o.pos)
		# Flag carriers are worth chasing further.
		if o.flag >= 0:
			d *= 0.6
		if d < best_d and host.grid.clear_line(me.pos, o.pos, host.time):
			best_d = d
			best = oid
	if best != _target:
		_target = best
		_target_seen = 0.0
		_target_vel = Vector2.ZERO
		if best != 0:
			_last_target_pos = host.actors[best].pos
	elif best != 0:
		_target_seen += dt
		var p: Vector2 = host.actors[best].pos
		if dt > 0.0:
			_target_vel = _target_vel.lerp((p - _last_target_pos) / dt, 0.2)
		_last_target_pos = p


func _choose_goal(me: Dictionary, target: Dictionary, want_range: float) -> Vector2:
	var grid := host.grid
	if host.mode == Rules.Mode.CTF and me.team >= 0:
		var enemy_flag: Dictionary = host.flags[1 - me.team]
		var own_flag: Dictionary = host.flags[me.team]
		if me.flag >= 0:
			return grid.bases[me.team]
		if own_flag.state != 0 and (id % 2 == 0 or me.ammo > 0):
			return own_flag.pos
		if enemy_flag.state != 1 and me.ammo > 0 and (id % 3 != 0 or target.is_empty()):
			return enemy_flag.pos
	if me.ammo <= 1 or (target.is_empty() and me.ammo < 4) or host.mode == Rules.Mode.HOARDER and me.ammo < Rules.MAX_AMMO and target.is_empty():
		var pk := _nearest_pickup(me.pos)
		if pk != Vector2.INF:
			return pk
	if not target.is_empty():
		if me.pos.distance_to(target.pos) > want_range:
			return target.pos
		return Vector2.INF
	# Head towards whoever is nearest, or wander.
	var nearest := Vector2.INF
	var nd := INF
	for oid in host.actors:
		var o: Dictionary = host.actors[oid]
		if oid == id or not o.alive or (o.team >= 0 and o.team == me.team):
			continue
		var d: float = me.pos.distance_to(o.pos)
		if d < nd:
			nd = d
			nearest = o.pos
	if nearest != Vector2.INF and me.ammo > 0:
		return nearest
	if _wander == Vector2.INF or me.pos.distance_to(_wander) < 1.5:
		_wander = grid.random_floor(host.rng)
	return _wander


func _nearest_pickup(from: Vector2) -> Vector2:
	var best := Vector2.INF
	var bd := INF
	for pid in host.pickups:
		var p: Vector2 = host.pickups[pid].pos
		var d := from.distance_squared_to(p)
		if d < bd:
			bd = d
			best = p
	return best


## A direction towards `goal`: straight when the way is clear, otherwise
## along a path over the grid.
func _steer(from: Vector2, goal: Vector2) -> Vector2:
	var grid := host.grid
	if from.distance_to(goal) < 0.3:
		return Vector2.ZERO
	if grid.clear_line(from, goal, host.time) and _wide_clear(from, goal):
		_path = PackedVector2Array()
		return (goal - from).normalized()
	if _repath_t <= 0.0 or _goal.distance_to(goal) > 2.0 or _path_i >= _path.size():
		_repath_t = 0.7
		_goal = goal
		_path = grid.path(from, goal)
		_path_i = 1 if _path.size() > 1 else 0
	while _path_i < _path.size() and from.distance_to(_path[_path_i]) < 0.45:
		_path_i += 1
	if _path_i >= _path.size():
		return (goal - from).normalized()
	return (_path[_path_i] - from).normalized()


## Checks both edges of the body's sweep, so bots don't snag on corners.
func _wide_clear(a: Vector2, b: Vector2) -> bool:
	var n := (b - a).normalized()
	var side := Vector2(-n.y, n.x) * Rules.CAMPER_RADIUS
	return host.grid.clear_line(a + side, b + side, host.time) and host.grid.clear_line(a - side, b - side, host.time)


func _dart_incoming(me: Dictionary) -> bool:
	for did in host.darts:
		var d: Dictionary = host.darts[did]
		if d.owner == id or (d.team >= 0 and d.team == me.team and not bool(host.settings.friendly_fire)):
			continue
		var to_me: Vector2 = me.pos - d.pos
		var dist := to_me.length()
		if dist > 4.5 or dist < 0.01:
			continue
		if to_me.normalized().dot(d.dir) > 0.93:
			return true
	return false
