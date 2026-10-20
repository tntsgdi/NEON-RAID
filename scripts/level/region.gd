class_name Region
extends Node2D
## 第 1 关「第十三街地下城」的一个区域（001–005）。关卡用字符地图写（scripts/level/d13_maps.gd），
## 一个字符 = 16 像素一格；'@' 那一格的底边是 y = 0。
##   #  实体        W 可破墙（重装机冲撞）  F 薄地板（重装机砸地）  D 安保门（只给安保机开）
##   @  起点        C 检查点               E 区域出口（终点线）     R 意识中继
##   g 射手  b 三连发  r 冲锋机  s 盾兵射手  d 敌对侦察机  w 失控侦察机（可夺）
##   k 钥匙安保机（射手，安保门要靠它；没了回检查点会补一台）
##   H 敌对精英重装机  h 停放的重装机  T 环境文字（按出现顺序取 texts）  ? 教学提示（按顺序取 tips）
## 区域结束：走过出口线；require_clear 的区域还要先把敌人清干净。

signal tip(key: String)

const CELL := 16.0
const PIT_MARGIN := 260.0

var index := 0
var player: Node2D
var data: Dictionary
var solids: Array[Rect2] = []
var start := Vector2.ZERO
var checkpoints: Array[Vector2] = []
var finish_x := 0.0
var _bounds := Rect2()
var _actors: Array = []
var _spawns: Array = []      # [字符, 位置]
var _tips: Array = []        # [x, key]
var _tips_shown := {}
var _breakables: Array = []  # [Rect2, kind]
var _doors: Array = []
var _relays: Array = []
var _texts: Array = []       # [位置, key]
var _keys: Array = []        # [字符, 位置, 机体]
var _rows: Array = []
var _base := 0
const KEY_CHARS := ["h", "k", "w"]


func _init(i: int = 0) -> void:
	index = i
	data = D13Maps.REGIONS[i]
	_parse(data.map)


func _ready() -> void:
	Blocks.build(self, solids)
	for p in _relays:
		var r := Relay.new()
		r.position = p
		add_child(r)
	for t in _texts:
		var b := Billboard.new()
		b.position = t[0]
		b.key = t[1]
		add_child(b)


## 把字符地图解析成方块（同一行连续的 # 合成一条，再把上下相同的条合成大矩形）和对象位置
func _parse(rows: Array) -> void:
	_rows = rows
	var base := 0
	for r in rows.size():
		if (rows[r] as String).contains("@"):
			base = r + 1
	_base = base
	var w := 0
	for row in rows:
		w = maxi(w, (row as String).length())
	var runs := {}   # "x0,x1" -> [起始行, 当前行]
	var finished: Array = []
	for r in rows.size():
		var row: String = rows[r]
		var y := (r - base) * CELL
		var this_runs := {}
		var c := 0
		while c < w:
			var ch := row[c] if c < row.length() else " "
			var pos := Vector2(c * CELL + CELL * 0.5, y + CELL)   # 这一格的底边中点
			match ch:
				"#":
					var c1 := c
					while c1 + 1 < w and c1 + 1 < row.length() and row[c1 + 1] == "#":
						c1 += 1
					this_runs["%d,%d" % [c, c1]] = true
					c = c1
				"W", "F":
					_breakables.append([Rect2(c * CELL, y, CELL, CELL), "wall" if ch == "W" else "floor"])
				"D":
					_doors.append(Rect2(c * CELL, y, CELL, CELL))
				"@":
					start = pos
				"C":
					checkpoints.append(pos)
				"E":
					finish_x = c * CELL
				"R":
					_relays.append(pos)
				"T":
					_texts.append([pos + Vector2(0, -CELL), ""])
				"?":
					_tips.append([c * CELL, ""])
				"g", "b", "r", "s", "d", "w", "H", "h", "k":
					_spawns.append([ch, pos])
			c += 1
		# 竖直合并：和上一行完全相同的条延长，否则结束
		for k in runs.keys():
			if this_runs.has(k):
				runs[k][1] = r
			else:
				finished.append([k, runs[k][0], runs[k][1]])
				runs.erase(k)
		for k in this_runs:
			if not runs.has(k):
				runs[k] = [r, r]
	for k in runs:
		finished.append([k, runs[k][0], runs[k][1]])
	for f in finished:
		var xs: PackedStringArray = (f[0] as String).split(",")
		var x0 := int(xs[0])
		var x1 := int(xs[1])
		solids.append(Rect2(x0 * CELL, (f[1] - base) * CELL, (x1 - x0 + 1) * CELL, (f[2] - f[1] + 1) * CELL))
	# 文字和提示按从左到右的顺序对应 texts / tips（不是按扫描的行顺序）
	_texts.sort_custom(func(a, b): return a[0].x < b[0].x)
	_tips.sort_custom(func(a, b): return a[0] < b[0])
	var keys: Array = data.get("texts", [])
	for i in _texts.size():
		_texts[i][1] = keys[i] if i < keys.size() else ""
	_texts = _texts.filter(func(t): return t[1] != "")
	var tk: Array = data.get("tips", [])
	for i in _tips.size():
		_tips[i][1] = tk[i] if i < tk.size() else ""
	_tips = _tips.filter(func(t): return t[1] != "")
	checkpoints.sort_custom(func(a, b): return a.x < b.x)
	checkpoints.insert(0, start)
	_bounds = Rect2(0, (0 - base) * CELL, w * CELL, rows.size() * CELL)
	if finish_x <= 0.0:
		finish_x = _bounds.end.x - CELL * 4.0


## 世界坐标所在格子的原始字符（通关机器人看地形用；地图外 = " "）
func char_at(p: Vector2) -> String:
	var c := int(floor(p.x / CELL))
	var r := int(floor(p.y / CELL)) + _base
	if r < 0 or r >= _rows.size() or c < 0:
		return " "
	var row: String = _rows[r]
	return row[c] if c < row.length() else " "


## 这一格现在是不是实心（可破墙 / 地板被打碎、安保门打开后就不算）
func solid_at(p: Vector2) -> bool:
	var ch := char_at(p)
	if ch == "#":
		return true
	if ch == "W" or ch == "F" or ch == "D":
		var q := PhysicsPointQueryParameters2D.new()
		q.position = Vector2(floor(p.x / CELL) * CELL + CELL * 0.5, floor(p.y / CELL) * CELL + CELL * 0.5)
		q.collision_mask = 1
		return not get_world_2d().direct_space_state.intersect_point(q).is_empty()
	return false


func start_pos() -> Vector2:
	return start


func limits() -> Rect2:
	return Rect2(_bounds.position, _bounds.size + Vector2(0, 120))


func pit_y() -> float:
	return _bounds.end.y + 40.0


func label(x: float) -> String:
	return tr(data.name)


func timer_started(p: Node2D) -> bool:
	return p.global_position.distance_to(start) > 24.0


func is_finished(p: Node2D) -> bool:
	if p.global_position.x < finish_x:
		return false
	if data.get("require_clear", false):
		return enemies_left() == 0
	return true


## 要求清场的区域：只算出口前 clear_span 像素（默认 1200）里的敌人——
## 前面路过没打的敌人（比如砸穿地板掉下去以后再也回不去的上层）不会把关卡锁死
func required_enemies() -> Array:
	var span: float = data.get("clear_span", 1200.0)
	var out := []
	for a in _actors:
		if is_instance_valid(a) and a.is_in_group("enemy") and a.alive() and a.global_position.x >= finish_x - span:
			out.append(a)
	return out


func enemies_left() -> int:
	return required_enemies().size()


func checkpoint_for(x: float) -> Vector2:
	var best: Vector2 = checkpoints[0]
	for c in checkpoints:
		if c.x <= x + 1.0:
			best = c
	return best


func on_player_died() -> void:
	pass


## 重新摆好所有机体、可破坏物、安保门（重来 / 回检查点都会调用）
func reset() -> void:
	for a in _actors:
		if is_instance_valid(a):
			a.queue_free()
	_actors.clear()
	_tips_shown.clear()
	for b in get_children():
		if b is Breakable or b is SecurityDoor:
			b.queue_free()
	for b in _breakables:
		_actors.append(Breakable.make(self, b[0], b[1]))
	for d in _doors:
		var door := SecurityDoor.new()
		door.rect = d
		door.position = d.position
		add_child(door)
		_actors.append(door)
	_keys.clear()
	for s in _spawns:
		var n := _spawn(s[0], s[1])
		if s[0] in KEY_CHARS:
			_keys.append([s[0], s[1], n])


## 回到检查点：过关必需的"钥匙"机体（停放的重装机、钥匙安保机、失控侦察机）如果没了就补回原位
func on_checkpoint() -> void:
	for k in _keys:
		var n = k[2]
		if not is_instance_valid(n) or not n.alive():
			k[2] = _spawn(k[0], k[1])


func _spawn(ch: String, pos: Vector2) -> Node2D:
	var n: Node2D
	match ch:
		"g", "b", "r", "s", "k":
			var e := EnemyBot.new()
			e.kind = {"g": "gunner", "b": "burst", "r": "rusher", "s": "gunner", "k": "gunner"}[ch]
			e.shielded = ch == "s"
			e.patrol_range = 40.0
			e.player = player
			n = e
		"d", "w":
			var dr := DroneBot.new()
			dr.wild = ch == "w"
			dr.player = player
			n = dr
			pos += Vector2(0, -CELL * 0.5)
		"H", "h":
			var h := HeavyBot.new()
			h.hostile = ch == "H"
			h.player = player
			if ch == "H":
				h.patrol_range = 60.0
			n = h
	n.position = pos
	n.set("fx_parent", self)
	add_child(n)
	_actors.append(n)
	return n


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	var body := get_tree().get_first_node_in_group("controlled") as Node2D
	if body == null:
		return
	for t in _tips:
		if not _tips_shown.has(t[1]) and body.global_position.x >= t[0]:
			_tips_shown[t[1]] = true
			tip.emit(t[1])


func _draw() -> void:
	Blocks.draw(self, solids)
	# 出口线：青色斜纹
	for i in 14:
		var c := Color(0.25, 0.9, 1.0, 0.8) if i % 2 == 0 else Color(0.05, 0.25, 0.3, 0.8)
		draw_rect(Rect2(finish_x - 2, -140 + i * 10, 4, 10), c)
