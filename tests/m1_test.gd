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
	await _sprint()
	await _smooth()
	await _tunnel()
	await _gap()
	await _shaft()
	await _wall_walk()
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


## 疾驰档：持续全速跑进入疾驰并继续加速；反方向立即掉档
func _sprint() -> void:
	var log := await _drive(Vector2(60, 0), [{"frames": 150, "move": R}])
	var top := 0.0
	for e in log:
		top = maxf(top, absf(e.vel.x))
	_check(player.sprinting and top >= T.sprint_speed * 0.95, "持续跑 1.25 秒进入疾驰档（最高 %.0f）" % top)
	await _drive(player.global_position, [{"frames": 2, "move": L}])
	_check(not player.sprinting, "反方向立即掉出疾驰档")
	# 疾驰中冲刺：出来不掉速，疾驰档保持
	log = await _drive(Vector2(60, 0), [{"frames": 150, "move": R}, {"frames": 1, "move": R, "press": ["dash"]}, {"frames": 40, "move": R}])
	var before_dash: float = absf(log[149].vel.x)
	var after_min := INF
	for i in range(175, log.size() - 1):
		after_min = minf(after_min, absf(log[i].vel.x))
	_check(after_min >= before_dash - 5.0 and player.sprinting, "疾驰中冲刺出来不掉速（冲刺前 %.0f，之后最低 %.0f）" % [before_dash, after_min])


## 动作衔接：一串跑→滑铲→跳→冲刺→挥刀→落地→急停转身里，脚尖每帧的位移不应突然跳变
func _smooth() -> void:
	main.place(Vector2(60, 0))
	await physics_frame
	var inp = load("res://scripts/player/scripted_input.gd").new([
		{"frames": 40, "move": R},
		{"frames": 16, "move": R, "press": ["slide"], "hold": ["slide"]},
		{"frames": 20, "move": R, "press": ["jump"], "hold": ["jump"]},
		{"frames": 4, "move": R, "press": ["dash"]},
		{"frames": 1, "move": R, "press": ["slash"]},
		{"until": func(p): return p.is_on_floor() and p.state == GROUND, "max": 240, "move": R},
		{"frames": 20, "move": R},
		{"frames": 30, "move": L},
	])
	player.input = inp
	var prev := []
	var worst := 0.0
	var hull_worst := 0.0
	var prev_hull: float = player.rig.hull_angle
	var blade_jump := 0.0
	var prev_slash: int = player.slash_step
	var prev_blade: float = player.rig._blade_angle
	while not inp.done:
		await physics_frame
		var toes: Array = player.rig._last_toes
		if not prev.is_empty():
			for i in 2:
				worst = maxf(worst, (toes[i] - prev[i]).length())
		prev = toes.duplicate()
		hull_worst = maxf(hull_worst, absf(player.rig.hull_angle - prev_hull))
		prev_hull = player.rig.hull_angle
		# 出刀 / 收刀那一帧刀臂角度的跳变
		if (player.slash_step >= 0) != (prev_slash >= 0):
			blade_jump = maxf(blade_jump, absf(rad_to_deg(angle_difference(deg_to_rad(prev_blade), deg_to_rad(player.rig._blade_angle)))))
		prev_slash = player.slash_step
		prev_blade = player.rig._blade_angle
	player.input = load("res://scripts/player/player_input.gd").new()
	print("smooth: 脚尖单帧最大 %.1f 像素，机身单帧最大 %.1f°，出刀/收刀那帧刀臂跳 %.1f°" % [worst, hull_worst, blade_jump])
	_check(worst <= 14.0, "动作切换时脚不跳变（单帧最大 %.1f 像素）" % worst)
	_check(hull_worst <= 6.0, "机身角度单帧变化不超过 6°（%.1f°）" % hull_worst)
	_check(blade_jump <= 25.0, "出刀/收刀时刀臂不一帧跳过去（%.1f°）" % blade_jump)


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
		{"until": func(p): return (p.is_on_floor() and p.global_position.x > 1810.0) or p.global_position.y > 150.0, "max": 400, "move": R},
	]
	var log := await _drive(Vector2(1545, 0), plain, Vector2(260, 0))
	# 墙面如履平地：跳不过去也能扒住对岸的侧壁走上来
	_check(log[-1].pos.y < 5.0 and log[-1].pos.x > 1810.0, "只跳不冲刺，扒住对岸的墙走上来（%s）" % str(log[-1].pos.round()))
	var dash := [
		{"until": func(p): return p.global_position.x >= 1592.0, "max": 120, "move": R},
		{"frames": 34, "move": R, "press": ["jump"], "hold": ["jump"]},
		{"frames": 1, "move": R, "press": ["dash"]},
		{"until": func(p): return p.is_on_floor() or p.global_position.y > 150.0, "max": 300, "move": R},
	]
	log = await _drive(Vector2(1545, 0), dash, Vector2(260, 0))
	_check(log[-1].pos.y < 5.0 and log[-1].pos.x > 1810.0, "跳+空中冲刺越过深沟（落点 %s）" % str(log[-1].pos.round()))


## 墙面行走：从地面直接走上竖井右墙、到顶翻上平台（不按跳）
func _wall_walk() -> void:
	var log := await _drive(Vector2(2000, 0), [{"until": func(p): return p.is_on_floor() and p.global_position.y < -250.0, "max": 400, "move": R, "walk": true}])
	var top: Dictionary = log[-1]
	_check(top.pos.y <= -255.0 and top.floor, "不按跳，走着就沿墙走上竖井顶（%s，%d 帧）" % [str(top.pos.round()), log.size()])
	# 墙上不按方向：扒住不滑
	log = await _drive(Vector2(2058, -150), [{"frames": 20, "move": R}, {"frames": 40}])
	var y0: float = log[20].pos.y
	_check(absf(log[-1].pos.y - y0) < 3.0 and log[-1].state == WALL, "墙上松手扒住不滑（%.0f→%.0f）" % [y0, log[-1].pos.y])
	# 墙上按 S：往下走
	log = await _drive(Vector2(2058, -150), [{"frames": 10, "move": R}, {"frames": 30, "move": Vector2(0, 1)}])
	_check(log[-1].pos.y > log[10].pos.y + 20.0, "墙上按 S 往下走")


## 竖井：只靠一面墙（右墙），按住朝墙方向连按跳，一路爬上顶上平台
func _shaft() -> void:
	var steps := []
	for i in 8:
		steps.append({"frames": 1, "move": R, "press": ["jump"], "hold": ["jump"]})
		steps.append({"frames": 26, "move": R, "hold": ["jump"]})
	steps.append({"until": func(p): return p.is_on_floor() and p.global_position.y < -250.0, "max": 240, "move": R})
	var log := await _drive(Vector2(2055, 0), steps)
	var top: Dictionary = log[-1]
	_check(top.pos.y <= -255.0 and top.floor, "单面墙按住朝墙连按跳爬上竖井顶（%s，%d 帧）" % [str(top.pos.round()), log.size()])
	var lowest_x := INF
	for e in log:
		lowest_x = minf(lowest_x, e.pos.x)
	print("shaft: 离墙最远 x=%.0f（墙面 x=2064）" % lowest_x)
	# 贴墙下滑：空中按住朝墙的方向
	log = await _drive(Vector2(2058, -200), [{"frames": 50, "move": R}])
	var sliding := log.filter(func(e): return e.state == WALL)
	_check(sliding.size() > 20 and sliding[-1].vel.y <= T.wall_slide_speed + 1.0, "按住朝墙就在墙上走（%d 帧，速度 %.0f）" % [sliding.size(), sliding[-1].vel.y if sliding.size() > 0 else -1.0])
	# 不按方向按跳：大力蹬开墙面
	log = await _drive(Vector2(2058, -200), [{"frames": 20, "move": R}, {"frames": 1, "press": ["jump"], "hold": ["jump"]}, {"frames": 30, "hold": ["jump"]}])
	_check(log[-1].pos.x < 2025.0, "不按方向蹬墙会被大力弹开（x=%.0f）" % log[-1].pos.x)


## 训练机：挥刀命中、三段连击、打碎后重生
func _slash() -> void:
	var d = main.range_.dummies[0]
	var before: int = d.hits
	var log := await _drive(Vector2(352, 0), [
		{"frames": 1, "move": R},
		{"frames": 20, "move": Vector2.ZERO},
		{"frames": 1, "press": ["slash"]},
		{"until": func(p): return p.slash_step == 0 and p._slash_time > 0.06, "max": 120},
		{"frames": 1, "press": ["slash"]},
		{"until": func(p): return p.slash_step == 1 and p._slash_time > 0.06, "max": 120},
		{"frames": 1, "press": ["slash"]},
		{"until": func(p): return p.slash_step == 2, "max": 120},
		{"frames": 60},
	])
	_check(d.hits - before >= 3, "三刀都命中训练机（命中 %d）" % (d.hits - before))
	var steps_seen := {}
	for e in log:
		if e.slash >= 0:
			steps_seen[e.slash] = true
	_check(steps_seen.size() == 3, "三段连击都出现（%s）" % str(steps_seen.keys()))
	# 上挑：按住上再挥刀，刀朝正上方
	await _drive(Vector2(352, 0), [{"frames": 2, "move": Vector2(0, -1)}, {"frames": 1, "move": Vector2(0, -1), "press": ["slash"]}, {"frames": 30, "move": Vector2(0, -1)}])
	_check(player._slash_aim == Vector2.UP, "按住上挥刀 = 上挑（%s）" % str(player._slash_aim))
	# 下劈：空中按住下挥刀，打中训练机会弹起来
	var pogo := await _drive(Vector2(380, -58), [{"frames": 3, "move": Vector2(0, 1)}, {"frames": 1, "move": Vector2(0, 1), "press": ["slash"]}, {"frames": 40, "move": Vector2(0, 1)}])
	var bounced := pogo.any(func(e): return e.vel.y < -300.0)
	_check(player._slash_aim == Vector2.DOWN and bounced, "空中按住下挥刀 = 下劈，打中后弹起（%s）" % str(player._slash_aim))
	# 打碎：一直砍到碎
	var spam := []
	for i in 12:
		spam.append({"frames": 1, "press": ["slash"], "aim": R})
		spam.append({"frames": 14, "aim": R})
	await _drive(Vector2(352, 0), [{"frames": 1, "move": R}] + spam)
	var broke: bool = not d.alive() or d.hp == d.MAX_HP
	_check(broke, "打满 HP 训练机会碎掉（hp=%d）" % d.hp)
	for i in 200:
		await physics_frame
	_check(d.alive(), "碎掉后会重生")
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
