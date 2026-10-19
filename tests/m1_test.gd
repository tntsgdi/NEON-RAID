extends SceneTree
## M1 手感验收（headless，脚本输入，不碰键鼠也不写任何文件）。
## 运行：Godot --headless --path . -s tests/m1_test.gd --fixed-fps 60

## 测试脚本在自动加载之前编译，所以这里不直接引用项目里的 class_name
const GROUND := 0
const AIR := 1
const DASH := 2
const SLIDE := 3
const WALL := 4
const NAMES := ["ground", "air", "dash", "slide", "wall"]
const R := Vector2(1, 0)
const L := Vector2(-1, 0)

var main: Node
var player
var failures: Array[String] = []
var T: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	player = main.player
	T = root.get_node("Tuning").v
	_check(root.get_node("Tuning").testing, "测试运行应被识别（不读写 tuning.json）")

	await _combo()
	await _tunnel()
	await _gap()
	await _shaft()
	await _slash()

	if failures.is_empty():
		print("M1 TEST PASS")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		print("M1 TEST FAIL (%d)" % failures.size())
		quit(1)


## 跑一段脚本输入，返回每个物理帧的记录
func _drive(start: Vector2, steps: Array, vel := Vector2.ZERO, max_frames := 1200) -> Array:
	main.place(start, vel)
	await physics_frame
	var inp = load("res://scripts/player/scripted_input.gd").new(steps)
	player.input = inp
	var log := []
	var n := 0
	while not inp.done and n < max_frames:
		await physics_frame
		log.append({
			"state": player.state,
			"pos": player.global_position,
			"vel": player.velocity,
			"slash": player.slash_step,
			"floor": player.is_on_floor(),
		})
		n += 1
	player.input = load("res://scripts/player/player_input.gd").new()
	return log


## 疾跑 → 滑铲 → 跳跃 → 空中冲刺 → 挥刀 → 落地继续跑
func _combo() -> void:
	var log := await _drive(Vector2(60, 0), [
		{"frames": 40, "move": R},
		{"frames": 16, "move": R, "press": ["slide"], "hold": ["slide"]},
		{"frames": 20, "move": R, "press": ["jump"], "hold": ["jump"]},
		{"frames": 4, "move": R, "press": ["dash"]},
		{"frames": 1, "move": R, "press": ["slash"]},
		{"until": func(p): return p.is_on_floor() and p.state == GROUND, "max": 240, "move": R},
		{"frames": 30, "move": R},
	])
	# 0.3 秒内到全速
	var reached := -1
	for i in log.size():
		if absf(log[i].vel.x) >= T.run_speed * 0.95:
			reached = i
			break
	_check(reached >= 0 and reached <= 38, "起步 0.3 秒内到全速（实际 %d 帧 @120Hz）" % reached)
	var seq := _states(log)
	_check(_has_order(seq, [GROUND, SLIDE, AIR, DASH, AIR, GROUND]),
		"状态顺序 地面→滑铲→空中→冲刺→空中→地面（实际 %s）" % str(seq.map(func(s): return NAMES[s])))
	var slash_in_dash := log.any(func(e): return e.state == DASH and e.slash >= 0)
	_check(slash_in_dash, "冲刺中挥刀不打断冲刺")
	var first_slide := -1
	for i in log.size():
		if log[i].state == SLIDE:
			first_slide = i
			break
	var min_speed := INF
	for i in range(maxi(first_slide, 0), log.size()):
		min_speed = minf(min_speed, absf(log[i].vel.x))
	_check(first_slide >= 0 and min_speed >= T.run_speed * 0.6, "滑铲到落地后速度不掉（最低 %.0f）" % min_speed)
	var last: Dictionary = log[-2]  # 最后一帧脚本已结束、松了方向键
	_check(last.state == GROUND and absf(last.vel.x) >= T.run_speed * 0.95, "落地后继续全速奔跑（%.0f）" % absf(last.vel.x))
	print("combo: 最低速度 %.0f，到全速 %d 帧，终点 x=%.0f" % [min_speed, reached, last.pos.x])


## 低矮通道：不滑铲过不去，滑铲能过去
func _tunnel() -> void:
	var log := await _drive(Vector2(1080, 0), [{"frames": 180, "move": R}], Vector2(260, 0))
	_check(log[-1].pos.x < 1200.0, "不滑铲进不了低矮通道（x=%.0f）" % log[-1].pos.x)
	log = await _drive(Vector2(1080, 0), [
		{"until": func(p): return p.global_position.x >= 1160.0, "max": 120, "move": R},
		{"frames": 1, "move": R, "press": ["slide"], "hold": ["slide"]},
		{"until": func(p): return p.global_position.x >= 1450.0, "max": 400, "move": R},
	], Vector2(260, 0))
	_check(log[-1].pos.x >= 1450.0, "滑铲穿过低矮通道（x=%.0f，用 %d 帧）" % [log[-1].pos.x, log.size()])


## 深沟：只跳过不去，跳+空中冲刺能过去
func _gap() -> void:
	var plain := [
		{"until": func(p): return p.global_position.x >= 1592.0, "max": 120, "move": R},
		{"frames": 40, "move": R, "press": ["jump"], "hold": ["jump"]},
		{"until": func(p): return p.is_on_floor() or p.global_position.y > 150.0, "max": 300, "move": R},
	]
	var log := await _drive(Vector2(1545, 0), plain, Vector2(260, 0))
	_check(log[-1].pos.y > 100.0, "只跳不冲刺会掉进深沟（y=%.0f）" % log[-1].pos.y)
	var dash := [
		{"until": func(p): return p.global_position.x >= 1592.0, "max": 120, "move": R},
		{"frames": 34, "move": R, "press": ["jump"], "hold": ["jump"]},
		{"frames": 1, "move": R, "press": ["dash"]},
		{"until": func(p): return p.is_on_floor() or p.global_position.y > 150.0, "max": 300, "move": R},
	]
	log = await _drive(Vector2(1545, 0), dash, Vector2(260, 0))
	_check(log[-1].pos.y < 5.0 and log[-1].pos.x > 1810.0, "跳+空中冲刺越过深沟（落点 %s）" % str(log[-1].pos.round()))


## 双墙竖井：蹬墙爬到顶上平台
func _shaft() -> void:
	var steps := [{"frames": 14, "move": R, "press": ["jump"], "hold": ["jump"]}]
	for i in 6:
		var toward := L if i % 2 == 0 else R
		var wall := -1 if i % 2 == 0 else 1
		steps.append({"frames": 1, "move": toward, "press": ["jump"], "hold": ["jump"]})
		steps.append({"until": func(p): return p.touching_wall() == wall or p.global_position.y < -262.0, "max": 90, "move": toward, "hold": ["jump"]})
	steps.append({"until": func(p): return p.is_on_floor() and p.global_position.y < -250.0, "max": 240, "move": R, "hold": ["jump"]})
	var log := await _drive(Vector2(2055, 0), steps)
	var top: Dictionary = log[-1]
	_check(top.pos.y <= -255.0 and top.floor, "蹬墙爬上竖井顶（%s，%d 帧）" % [str(top.pos.round()), log.size()])
	var walls := log.filter(func(e): return e.state == WALL).size()
	print("shaft: 用 %d 帧爬上，贴墙帧 %d" % [log.size(), walls])
	# 贴墙下滑：空中按住朝墙的方向
	log = await _drive(Vector2(2058, -200), [{"frames": 50, "move": R}])
	var sliding := log.filter(func(e): return e.state == WALL)
	_check(sliding.size() > 20 and sliding[-1].vel.y <= T.wall_slide_speed + 1.0, "贴墙下滑限速（%d 帧，%.0f）" % [sliding.size(), sliding[-1].vel.y if sliding.size() > 0 else -1.0])


## 靶桩：挥刀命中、三段连击
func _slash() -> void:
	var d = main.range_.dummies[0]
	var before: int = d.hits
	var log := await _drive(Vector2(2228, -260), [
		{"frames": 2, "move": Vector2.ZERO, "aim": R},
		{"frames": 1, "press": ["slash"]},
		{"until": func(p): return p.slash_step == 0 and p._slash_time > 0.06, "max": 120},
		{"frames": 1, "press": ["slash"]},
		{"until": func(p): return p.slash_step == 1 and p._slash_time > 0.06, "max": 120},
		{"frames": 1, "press": ["slash"]},
		{"until": func(p): return p.slash_step == 2, "max": 120},
		{"frames": 60},
	])
	_check(d.hits - before >= 3, "三刀都命中靶桩（命中 %d）" % (d.hits - before))
	var steps_seen := {}
	for e in log:
		if e.slash >= 0:
			steps_seen[e.slash] = true
	_check(steps_seen.size() == 3, "三段连击都出现（%s）" % str(steps_seen.keys()))
	Engine.time_scale = 1.0


func _states(log: Array) -> Array:
	var out := []
	for e in log:
		if out.is_empty() or out[-1] != e.state:
			out.append(e.state)
	return out


func _has_order(seq: Array, want: Array) -> bool:
	var i := 0
	for s in seq:
		if i < want.size() and s == want[i]:
			i += 1
	return i == want.size()


func _check(ok: bool, what: String) -> void:
	print(("  ok  " if ok else "  NO  ") + what)
	if not ok:
		failures.append(what)
