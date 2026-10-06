class_name ArenaGrid
extends RefCounted
## An arena as a grid of square tiles: walls, cover, doors, spawn points and
## flag bases. Movement, dart flight and bot paths all use this grid instead
## of the physics engine, so the host and every player get the same answers
## and the tests can run the whole game without a screen.
##
## Layouts are written as the left half and mirrored, so both sides are fair.
## Tile x runs left to right, tile y runs top to bottom; in the world a tile
## (x, y) covers x*TILE..(x+1)*TILE on the X axis and y*TILE.. on the Z axis.
##
##   #  wall           C  column        c  crate        S  statue
##   D  sliding door (shut half the time)
##   1-8  spawn points (odd on the left, even on the right)
##   A B  the flag bases (left and right)
##   .  floor

const TILE := 2.0
const SOLID := "#CcSD"
const MIRROR := {"1": "2", "2": "1", "3": "4", "4": "3", "5": "6", "6": "5",
	"7": "8", "8": "7", "A": "B", "B": "A"}
## A door is open for half of each cycle; doors are staggered.
const DOOR_CYCLE := 7.0
const DOOR_STAGGER := 1.75

const ARENA_IDS := ["gym", "lab"]
const LAYOUTS := {
	"gym": {
		"name": "The Gym",
		"kit": "mini-arena",
		"about": "Columns, crates and a pair of statues under the bleacher lights.",
		"half": [
			"###########",
			"#1....c....",
			"#..........",
			"#..CC....##",
			"#..C.......",
			"#.......c..",
			"#5..##.....",
			"#A..##....S",
			"#7..##.....",
			"#.......c..",
			"#..C.......",
			"#..CC....##",
			"#..........",
			"#3....c....",
			"###########",
		],
	},
	"lab": {
		"name": "The Test Lab",
		"kit": "prototype-kit",
		"about": "Two labs and a hall, joined by sliding doors that open and shut on a timer.",
		"half": [
			"###########",
			"#1.....#...",
			"#......D...",
			"#..cc..#..c",
			"#..c...#...",
			"#5.........",
			"#......#.c.",
			"#A..C..D...",
			"#......#.c.",
			"#7.........",
			"#..c...#...",
			"#..cc..#..c",
			"#......D...",
			"#3.....#...",
			"###########",
		],
	},
}

var id := ""
var title := ""
var kit := ""
var width := 0
var height := 0
var rows: Array[String] = []
var doors: Array[Vector2i] = []
## "1".."8" -> world position
var spawns := {}
## [left base, right base] world positions
var bases: Array[Vector2] = []

var _solid := PackedByteArray()
var _door_index := {}
var _astar: AStarGrid2D


static func make(p_id: String) -> ArenaGrid:
	var g := ArenaGrid.new()
	var def: Dictionary = LAYOUTS.get(p_id, LAYOUTS["gym"])
	g.id = p_id if LAYOUTS.has(p_id) else "gym"
	g.title = def.name
	g.kit = def.kit
	g.rows = mirror_rows(def.half)
	g._build()
	return g


static func title_of(p_id: String) -> String:
	return str(LAYOUTS.get(p_id, LAYOUTS["gym"]).name)


## The full layout from its left half: each row followed by itself reversed,
## with left and right markers swapped.
static func mirror_rows(half: Array) -> Array[String]:
	var out: Array[String] = []
	for row in half:
		var right := ""
		for i in range(row.length() - 1, -1, -1):
			var ch: String = row[i]
			right += MIRROR.get(ch, ch)
		out.append(row + right)
	return out


func _build() -> void:
	height = rows.size()
	width = rows[0].length()
	_solid.resize(width * height)
	bases = [Vector2.ZERO, Vector2.ZERO]
	for y in height:
		for x in width:
			var ch := rows[y][x]
			var c := Vector2i(x, y)
			_solid[y * width + x] = 1 if ch in SOLID and ch != "D" else 0
			if ch == "D":
				_door_index[c] = doors.size()
				doors.append(c)
			elif ch in "12345678":
				spawns[ch] = center_of(c)
			elif ch == "A":
				bases[0] = center_of(c)
			elif ch == "B":
				bases[1] = center_of(c)
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, width, height)
	_astar.cell_size = Vector2(TILE, TILE)
	_astar.offset = Vector2(TILE, TILE) * 0.5
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for y in height:
		for x in width:
			if _solid[y * width + x] == 1:
				_astar.set_point_solid(Vector2i(x, y), true)


func char_at(c: Vector2i) -> String:
	if not in_bounds(c):
		return "#"
	return rows[c.y][c.x]


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func world_size() -> Vector2:
	return Vector2(width, height) * TILE


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func center_of(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * TILE


## Door i is shut for the second half of its cycle at match time t.
func door_closed(i: int, t: float) -> bool:
	return fposmod(t + i * DOOR_STAGGER, DOOR_CYCLE) >= DOOR_CYCLE * 0.5


func is_solid(c: Vector2i, t := 0.0) -> bool:
	if not in_bounds(c):
		return true
	if _solid[c.y * width + c.x] == 1:
		return true
	if _door_index.has(c):
		return door_closed(_door_index[c], t)
	return false


## Moves a round body of radius r by `motion`, sliding along walls. A body
## already overlapping a wall (a door that shut on it) may always move out.
func move(pos: Vector2, motion: Vector2, r: float, t := 0.0) -> Vector2:
	var p := pos
	if motion.x != 0.0:
		p.x = _sweep(p, motion.x, r, t, 0)
	if motion.y != 0.0:
		p.y = _sweep(p, motion.y, r, t, 1)
	return p


func _sweep(p: Vector2, d: float, r: float, t: float, axis: int) -> float:
	var q := p
	q[axis] += d
	var limit: float = q[axis]
	var lo := cell_of(q - Vector2(r, r))
	var hi := cell_of(q + Vector2(r, r) - Vector2(1e-5, 1e-5))
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			var c := Vector2i(cx, cy)
			if not is_solid(c, t) or _box_overlaps(p, r, c):
				continue
			if d > 0.0:
				limit = minf(limit, c[axis] * TILE - r - 0.001)
			else:
				limit = maxf(limit, (c[axis] + 1) * TILE + r + 0.001)
	return maxf(p[axis], limit) if d > 0.0 else minf(p[axis], limit)


func _box_overlaps(p: Vector2, r: float, c: Vector2i) -> bool:
	return p.x - r < (c.x + 1) * TILE and p.x + r > c.x * TILE \
		and p.y - r < (c.y + 1) * TILE and p.y + r > c.y * TILE


## True if a body of radius r at p overlaps any wall.
func blocked(p: Vector2, r: float, t := 0.0) -> bool:
	var lo := cell_of(p - Vector2(r, r))
	var hi := cell_of(p + Vector2(r, r) - Vector2(1e-5, 1e-5))
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			if is_solid(Vector2i(cx, cy), t):
				return true
	return false


## The first wall on the line from a to b:
## {"hit": bool, "point": Vector2, "normal": Vector2}.
func raycast(a: Vector2, b: Vector2, t := 0.0) -> Dictionary:
	var d := b - a
	var length := d.length()
	var c := cell_of(a)
	if is_solid(c, t):
		return {"hit": true, "point": a, "normal": Vector2.ZERO}
	if length < 1e-6:
		return {"hit": false, "point": b, "normal": Vector2.ZERO}
	var dir := d / length
	var step := Vector2i(int(signf(dir.x)), int(signf(dir.y)))
	var t_max := Vector2(INF, INF)
	var t_delta := Vector2(INF, INF)
	for axis in 2:
		if dir[axis] != 0.0:
			var edge := (c[axis] + (1 if step[axis] > 0 else 0)) * TILE
			t_max[axis] = (edge - a[axis]) / dir[axis]
			t_delta[axis] = TILE / absf(dir[axis])
	for i in 512:
		var axis := 0 if t_max.x < t_max.y else 1
		var dist: float = t_max[axis]
		if dist > length:
			break
		c[axis] += step[axis]
		t_max[axis] += t_delta[axis]
		if is_solid(c, t):
			var n := Vector2.ZERO
			n[axis] = -step[axis]
			return {"hit": true, "point": a + dir * dist, "normal": n}
	return {"hit": false, "point": b, "normal": Vector2.ZERO}


func clear_line(a: Vector2, b: Vector2, t := 0.0) -> bool:
	return not raycast(a, b, t).hit


## Tile centres from a to b avoiding walls (doors count as open).
func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := _nearest_open(cell_of(from))
	var b := _nearest_open(cell_of(to))
	if a == Vector2i(-1, -1) or b == Vector2i(-1, -1):
		return PackedVector2Array()
	return _astar.get_point_path(a, b)


## The closest walkable tile centre to p.
## The nearest spot to p where a body of radius r fits at time t, e.g. for
## someone standing in a doorway when the door shuts.
func unstick(p: Vector2, r: float, t: float) -> Vector2:
	if not blocked(p, r, t):
		return p
	for ring in range(1, 14):
		for k in 16:
			var q := p + Vector2.from_angle(k * TAU / 16.0) * (ring * 0.25)
			if not blocked(q, r, t):
				return q
	return nearest_floor(p)


func nearest_floor(p: Vector2) -> Vector2:
	var c := _nearest_open(cell_of(p))
	return center_of(c) if c != Vector2i(-1, -1) else world_size() * 0.5


func _nearest_open(c: Vector2i) -> Vector2i:
	for radius in 6:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var n := c + Vector2i(dx, dy)
				if in_bounds(n) and _solid[n.y * width + n.x] == 0:
					return n
	return Vector2i(-1, -1)


## Spawn points for a team (-1 for everyone): the left side for Red, the
## right side for Blue.
func spawn_points(team: int) -> Array:
	var keys := ["1", "2", "3", "4", "5", "6", "7", "8"]
	if team == 0:
		keys = ["1", "3", "5", "7"]
	elif team == 1:
		keys = ["2", "4", "6", "8"]
	var out := []
	for k in keys:
		if spawns.has(k):
			out.append(spawns[k])
	return out


func floor_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in height:
		for x in width:
			if _solid[y * width + x] == 0 and not _door_index.has(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


func random_floor(rng: RandomNumberGenerator) -> Vector2:
	var tiles := floor_tiles()
	return center_of(tiles[rng.randi_range(0, tiles.size() - 1)])
