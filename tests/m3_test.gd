extends SceneTree
## M3 瞬间夺壳验收（headless，脚本输入 / 模拟按键事件，不碰真实键鼠也不写任何文件）。
## 运行：Godot --headless --path . -s tests/m3_test.gd --fixed-fps 60

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
	player = main.player
	T = root.get_node("Tuning").v

	await _walk_run_dash()
	await _stairs()
	await _lock_and_possess()
	await _drone_crossing()
	await _wisp()

	if failures.is_empty():
		print("M3 TEST PASS")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		print("M3 TEST FAIL (%d)" % failures.size())
		quit(1)


func _use(steps: Array):
	var inp = load("res://scripts/player/scripted_input.gd").new(steps)
	main.controller.input = inp
	main.controller.current.input = inp
	return inp


func _until_done(inp, max_frames := 900) -> Array:
	var log := []
	var n := 0
	while not inp.done and n < max_frames:
		await physics_frame
		var b = main.controller.current
		log.append({"pos": b.global_position, "vel": b.velocity if "velocity" in b else Vector2.ZERO, "shell": b})
		n += 1
	return log


func _restore_device() -> void:
	var dev = load("res://scripts/player/device_input.gd").new()
	main.controller.input = dev
	if is_instance_valid(main.controller.current):
		main.controller.current.input = dev


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## 走 / 跑 / 轻点 Shift 冲刺（用模拟按键事件走真实的键盘输入路径）
func _walk_run_dash() -> void:
	main.place(Vector2(60, 0))
	await physics_frame
	_restore_device()
	_key(KEY_D, true)
	await _frames(60)
	_check(absf(player.velocity.x) <= T.walk_speed + 1.0 and absf(player.velocity.x) > T.walk_speed * 0.8, "不按 Shift 是走路（%.0f）" % absf(player.velocity.x))
	_key(KEY_SHIFT, true)
	await _frames(70)
	_check(absf(player.velocity.x) >= T.run_speed * 0.9, "按住 Shift 跑起来（%.0f）" % absf(player.velocity.x))
	_key(KEY_SHIFT, false)
	_key(KEY_D, false)
	await _frames(30)
	main.place(Vector2(60, 0))
	await _frames(5)
	_key(KEY_SHIFT, true)
	await _frames(4)
	_key(KEY_SHIFT, false)
	var dashed := false
	for i in 10:
		await physics_frame
		if player.state == 2:
			dashed = true
	_check(dashed, "轻点 Shift 冲刺")
	_key(KEY_L, true)
	await physics_frame
	await physics_frame
	_key(KEY_L, false)
	await _frames(60)
	main.place(Vector2(60, 0))
	await _frames(2)
	_key(KEY_L, true)
	var l_dash := false
	for i in 6:
		await physics_frame
		if player.state == 2:
			l_dash = true
	_key(KEY_L, false)
	_check(l_dash, "L 键冲刺")


## 台阶：走路不跳也能一级一级迈上去（手感测试场的三级 32 像素台阶）
func _stairs() -> void:
	main.place(Vector2(700, 0))
	await physics_frame
	var inp = _use([{"frames": 300, "move": R, "walk": true}])
	var log := await _until_done(inp)
	var top := 0.0
	var airborne := 0
	for e in log:
		top = minf(top, e.pos.y)
	_check(top <= -95.0, "走路就能连上三级台阶（最高 y=%.0f）" % top)
	_restore_device()


## 锁定 + 夺壳：夺安保机、用它打别的敌人、再夺回基础机体
func _lock_and_possess() -> void:
	main.load_level("arena")
	var arena = main.arena
	arena.auto_waves = false
	await physics_frame
	var a = arena.spawn(Vector2(-200, 0), false, 0.0)
	var b = arena.spawn(Vector2(-60, 0), false, 0.0)
	a.player = null
	b.player = null
	main.place(Vector2(-330, 0))
	var inp = _use([{"frames": 1, "move": R}, {"frames": 10, "aim": R}])
	await _until_done(inp)
	_check(main.controller.lock == a and main.controller.lock_in_range, "软锁定到最近的敌人且在夺壳距离内")
	player.velocity = Vector2(300, 0)
	inp = _use([{"frames": 1, "press": ["possess"], "aim": R}, {"frames": 6, "aim": R}])
	await _until_done(inp)
	var cur = main.controller.current
	_check(cur == a and a.controlled and player.parked, "按 E 夺取锁定目标，基础机体跪下待机")
	_check(not a.is_in_group("enemy") and a.is_in_group("controlled"), "被夺的机体不再是敌人")
	# 冷却：刚夺完 0.7 秒内按 E 夺不了别的机体
	inp = _use([{"frames": 1, "aim": R}, {"frames": 1, "press": ["possess"], "aim": R}, {"frames": 2, "aim": R}])
	await _until_done(inp)
	_check(main.controller.current == a and main.controller.cooldown > 0.0, "夺壳后 0.7 秒冷却期间按 E 无效")
	await _frames(90)
	var hp0: int = b.hp
	inp = _use([{"frames": 2, "keys": true}, {"frames": 1, "press": ["shoot"], "keys": true}, {"frames": 40, "keys": true}])
	await _until_done(inp)
	_check(b.hp < hp0, "被夺的枪手用 K 打中锁定的敌人（血 %d→%d）" % [hp0, b.hp])
	# 回头夺回基础机体
	inp = _use([{"frames": 10, "move": L, "aim": L}, {"frames": 1, "press": ["possess"], "aim": L}, {"frames": 6, "aim": L}])
	await _until_done(inp)
	_check(main.controller.current == player and not player.parked, "对准跪着的基础机体按 E 能夺回来")
	_check(not is_instance_valid(a) or not a.alive(), "离开的敌人机体断电报废")
	_restore_device()


## 夺壳训练场：夺失控侦察机飞过深渊
func _drone_crossing() -> void:
	main.load_level("possess")
	await physics_frame
	main.place(Vector2(300, 0))
	var pr = main.possess_range
	var drone = null
	for c in pr.get_children():
		if _is(c, "drone_bot") and c.wild and c.global_position.x > 300.0:
			drone = c
	var up: Vector2 = (drone.global_position - (player.global_position + Vector2(0, -18))).normalized()
	var inp = _use([{"frames": 4, "aim": up}, {"frames": 1, "press": ["possess"], "aim": up}, {"frames": 4, "aim": up}])
	await _until_done(inp)
	_check(_is(main.controller.current, "drone_bot"), "夺取失控侦察机")
	inp = _use([{"until": func(p): return p.global_position.x > 1000.0, "max": 600, "move": Vector2(1, -0.1)}])
	var log := await _until_done(inp, 700)
	_check(log[-1].pos.x > 1000.0 and _is(main.controller.current, "drone_bot"), "开着侦察机飞过深渊（x=%.0f）" % log[-1].pos.x)
	_restore_device()


## 紧急投射：侦察机被打坏 → 光球；超时 → 回检查点；按 E → 投进附近机体
func _wisp() -> void:
	var drone = main.controller.current
	if not _is(drone, "drone_bot"):
		_check(false, "紧急投射测试需要先在侦察机里")
		return
	var inp = _use([{"frames": 9999}])
	drone.hp = 1
	drone._hurt(Vector2.DOWN, 1)
	await physics_frame
	_check(_is(main.controller.current, "wisp"), "侦察机被打坏后弹出意识光球")
	await _frames(240)
	_check(main.controller.current == player and player.global_position.x > 960.0, "光球超时：在对岸检查点用基础机体重来（x=%.0f）" % player.global_position.x)
	# 再来一次：这次在光球里按 E 投进附近的机体
	var pr = main.possess_range
	var target = null
	for c in pr.get_children():
		if _is(c, "enemy_bot") and c.alive() and c.kind == "burst":
			target = c
	main.place(Vector2(1100, 0))
	await physics_frame
	var to: Vector2 = (target.center() - (player.global_position + Vector2(0, -18))).normalized()
	inp = _use([{"frames": 2, "aim": to}, {"frames": 1, "press": ["possess"], "aim": to}, {"frames": 4, "aim": to}])
	await _until_done(inp)
	var shell = main.controller.current
	_check(shell == target, "夺取三连发机")
	inp = _use([{"frames": 9999}])
	shell.hp = 1
	shell._controlled_hurt(Vector2.LEFT, 1)
	await physics_frame
	var w = main.controller.current
	_check(_is(w, "wisp"), "三连发机被打坏后弹出光球")
	# 光球附近最近的可夺机体
	var near = null
	var nd := INF
	for c in w.get_tree().get_nodes_in_group("possessable"):
		if c.alive() and c.center().distance_to(w.global_position) < nd:
			nd = c.center().distance_to(w.global_position)
			near = c
	var dir: Vector2 = (near.center() - w.global_position).normalized()
	inp = _use([{"frames": 3, "aim": dir}, {"frames": 1, "press": ["possess"], "aim": dir}, {"frames": 4}])
	await _until_done(inp)
	_check(main.controller.current == near, "光球按 E 投进附近的机体（紧急投射，距离 %.0f）" % nd)
	_restore_device()


## 测试脚本在自动加载之前编译，不能直接写 DroneBot / Wisp 这些类名，按脚本文件名判断
func _is(n, script_name: String) -> bool:
	return is_instance_valid(n) and n.get_script() != null and n.get_script().resource_path.get_file() == script_name + ".gd"


func _check(ok: bool, what: String) -> void:
	print(("  ok  " if ok else "  NO  ") + what)
	if not ok:
		failures.append(what)
