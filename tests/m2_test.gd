extends SceneTree
## M2 基础战斗验收（headless，脚本输入，不碰键鼠也不写任何文件）。
## 运行：Godot --headless --path . -s tests/m2_test.gd --fixed-fps 60

## 测试脚本在自动加载之前编译，所以这里不直接引用项目里的 class_name
const AIR_STATE := 1
const R := Vector2(1, 0)
const L := Vector2(-1, 0)

var main: Node
var arena: Node
var player
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	main.load_level("arena")
	arena = main.arena
	arena.auto_waves = false
	player = main.player
	await physics_frame

	await _gun()
	await _enemy_fire()
	await _dash_through()
	await _deflect()
	await _shield()
	await _launch()
	await _rusher()
	await _death()
	await _waves()

	if failures.is_empty():
		print("M2 TEST PASS")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		print("M2 TEST FAIL (%d)" % failures.size())
		quit(1)


func _fresh() -> void:
	main.restart()
	arena.auto_waves = false
	for e in arena.get_children():
		if e.is_in_group("enemy"):
			e.queue_free()
	await physics_frame


func _bot(pos: Vector2, shielded := false, watching := true, facing := -1):
	var e = arena.spawn(pos, shielded, 0.0)
	e.facing = facing
	if not watching:
		e.player = null
		e.set_physics_process(false)
	return e


func _drive(start: Vector2, steps: Array, max_frames := 900) -> Array:
	main.place(start)
	await physics_frame
	var inp = load("res://scripts/player/scripted_input.gd").new(steps)
	player.input = inp
	var log := []
	var n := 0
	while not inp.done and n < max_frames:
		await physics_frame
		log.append({"state": player.state, "pos": player.global_position, "vel": player.velocity, "hp": player.hp})
		n += 1
	player.input = load("res://scripts/player/player_input.gd").new()
	return log


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _nearest_enemy_bullet():
	var best = null
	var d := INF
	for b in player.get_tree().get_nodes_in_group("enemy_bullets"):
		var dd: float = b.global_position.distance_to(player.global_position + Vector2(0, -26))
		if dd < d:
			d = dd
			best = b
	return best


func _bullet_within(px: float) -> Callable:
	return func(p):
		var b = _nearest_enemy_bullet()
		return b != null and b.global_position.distance_to(p.global_position + Vector2(0, -26)) < px


## 左键点射打掉敌人血；8 格能量打空就打不出
func _gun() -> void:
	await _fresh()
	var e = _bot(Vector2(-250, 0), false, false)
	var steps := [{"frames": 1, "move": R}, {"frames": 10, "aim": R}]
	for i in 3:
		steps.append({"frames": 1, "press": ["shoot"], "aim": R})
		steps.append({"frames": 20, "aim": R})
	await _drive(Vector2(-370, 0), steps)
	_check(e.hp <= e.MAX_HP - 3, "点射三发都打中（敌人血 %d）" % e.hp)
	var fired := 0
	var seen := {}
	steps = []
	for i in 10:
		steps.append({"frames": 1, "press": ["shoot"], "aim": Vector2(0, -1)})
		steps.append({"frames": 16, "aim": Vector2(0, -1)})
	main.place(Vector2(-370, 0))
	await physics_frame
	player.input = load("res://scripts/player/scripted_input.gd").new(steps)
	for f in 220:
		await physics_frame
		for b in player.get_tree().get_nodes_in_group("player_bullets"):
			if not seen.has(b.get_instance_id()):
				seen[b.get_instance_id()] = true
				fired += 1
	player.input = load("res://scripts/player/player_input.gd").new()
	_check(fired == 8, "能量 8 格：快速连按 10 次只打出 8 发（实际 %d）" % fired)


## 敌人先拉瞄准线再开火，站着不动会掉 1 血
func _enemy_fire() -> void:
	await _fresh()
	var e = _bot(Vector2(-200, 0))
	var aimed := false
	main.place(Vector2(-330, 0))
	for f in 240:
		await physics_frame
		if e.state == e.State.AIM:
			aimed = true
		if player.hp < 3:
			break
	_check(aimed, "敌人开火前有瞄准阶段")
	_check(player.hp == 2, "被敌弹打中掉 1 血（剩 %d）" % player.hp)
	_check(player.invulnerable(), "受伤后有无敌时间")


## 朝子弹冲刺：全程无敌，开头 0.12 秒内擦过 = 精准闪避 → 神经超频
func _dash_through() -> void:
	await _fresh()
	_bot(Vector2(-150, 0))
	var oc := [false]
	var cb := func(): oc[0] = true
	player.overclocked.connect(cb)
	var log := await _drive(Vector2(-330, 0), [
		{"until": _bullet_within(48.0), "max": 400},
		{"frames": 1, "move": R, "press": ["dash"]},
		{"frames": 30},
	])
	player.overclocked.disconnect(cb)
	_check(log[-1].hp == 3, "冲刺穿过子弹不掉血（剩 %d）" % log[-1].hp)
	_check(oc[0], "冲刺开头擦过子弹触发神经超频")


## 用刀把子弹弹回去，一发打死射手
func _deflect() -> void:
	await _fresh()
	var e = _bot(Vector2(-180, 0))
	await _drive(Vector2(-330, 0), [
		{"frames": 1, "move": R},
		{"until": _bullet_within(40.0), "max": 400},
		{"frames": 1, "press": ["slash"]},
		{"frames": 90},
	])
	_check(not is_instance_valid(e) or not e.alive(), "弹回的子弹一发打死射手")
	_check(player.hp == 3, "弹反时自己没掉血（剩 %d）" % player.hp)


## 盾兵：正面子弹弹开、刀砍 3 下破盾；背后和头上直接伤本体
func _shield() -> void:
	await _fresh()
	var e = _bot(Vector2(-200, 0), true, false, -1)
	await _drive(Vector2(-300, 0), [{"frames": 1, "move": R}, {"frames": 5}, {"frames": 1, "press": ["shoot"], "aim": R}, {"frames": 30}])
	_check(e.hp == e.MAX_HP and e.shield_hp == e.SHIELD_HP, "正面子弹被盾弹开（血 %d 盾 %d）" % [e.hp, e.shield_hp])
	var cuts := [{"frames": 1, "move": R}, {"frames": 5}]
	for i in 3:
		cuts.append({"frames": 1, "press": ["slash"]})
		cuts.append({"frames": 26})
	await _drive(Vector2(-228, 0), cuts)
	_check(e.shield_hp <= 0, "刀砍 3 下破盾（盾 %d）" % e.shield_hp)
	var back = _bot(Vector2(100, 0), true, false, -1)
	await _drive(Vector2(128, 0), [{"frames": 1, "move": L}, {"frames": 5}, {"frames": 1, "press": ["slash"]}, {"frames": 30}])
	_check(back.hp < back.MAX_HP and back.shield_hp == back.SHIELD_HP, "从背后砍直接伤本体（血 %d 盾 %d）" % [back.hp, back.shield_hp])
	var top = _bot(Vector2(300, 0), true, false, -1)
	await _drive(Vector2(300, -50), [{"frames": 2, "move": Vector2(0, 1)}, {"frames": 1, "move": Vector2(0, 1), "press": ["slash"]}, {"frames": 30, "move": Vector2(0, 1)}])
	_check(top.hp < top.MAX_HP and top.shield_hp == top.SHIELD_HP, "从头上下劈直接伤本体（血 %d 盾 %d）" % [top.hp, top.shield_hp])


## 上挑把敌人打上天
func _launch() -> void:
	await _fresh()
	var e = _bot(Vector2(-200, 0))
	e.player = null
	var up := [false]
	main.place(Vector2(-226, 0))
	await physics_frame
	player.input = load("res://scripts/player/scripted_input.gd").new([{"frames": 1, "move": R}, {"frames": 4}, {"frames": 1, "move": Vector2(0, -1), "press": ["slash"]}, {"frames": 30, "move": Vector2(0, -1)}])
	for f in 40:
		await physics_frame
		if is_instance_valid(e) and e.state == e.State.AIR and e.velocity.y < -100.0:
			up[0] = true
	player.input = load("res://scripts/player/player_input.gd").new()
	_check(up[0], "上挑把敌人打上天")


## 冲锋机：站着会被撞掉血；冲刺穿过不掉血；正面一刀招架
func _rusher() -> void:
	await _fresh()
	arena.spawn(Vector2(-200, 0), false, 0.0, "rusher")
	main.place(Vector2(-300, 0))
	for f in 240:
		await physics_frame
		if player.hp < 3:
			break
	_check(player.hp == 2, "站着不动被冲锋机撞掉 1 血（剩 %d）" % player.hp)
	await _fresh()
	var r = arena.spawn(Vector2(-200, 0), false, 0.0, "rusher")
	var log := await _drive(Vector2(-300, 0), [
		{"until": func(p): return r.state == r.State.CHARGE and absf(r.global_position.x - p.global_position.x) < 40.0, "max": 300},
		{"frames": 1, "move": R, "press": ["dash"]},
		{"frames": 40},
	])
	_check(log[-1].hp == 3, "冲刺穿过冲锋机不掉血（剩 %d）" % log[-1].hp)
	await _fresh()
	r = arena.spawn(Vector2(-200, 0), false, 0.0, "rusher")
	var oc := [false]
	var cb := func(): oc[0] = true
	player.overclocked.connect(cb)
	log = await _drive(Vector2(-300, 0), [
		{"frames": 1, "move": R},
		{"until": func(p): return r.state == r.State.CHARGE and absf(r.global_position.x - p.global_position.x) < 40.0, "max": 300},
		{"frames": 1, "press": ["slash"]},
		{"frames": 30},
	])
	player.overclocked.disconnect(cb)
	_check(oc[0] and log[-1].hp == 3, "正面一刀招架冲锋：不掉血并触发神经超频（血 %d）" % log[-1].hp)


## 血打空：很快回到起点，血加满，当前这一波重来
func _death() -> void:
	await _fresh()
	_bot(Vector2(-200, 0))
	main.place(Vector2(-260, 0))
	player.hp = 1
	var died := false
	for f in 300:
		await physics_frame
		if player.hp <= 0:
			died = true
		if died and player.hp == 3:
			break
	await _wait(5)
	_check(died, "被打到 0 血")
	_check(player.hp == 3 and player.global_position.distance_to(arena.START) < 5.0, "0.3 秒内回到起点、血加满（%s，血 %d）" % [str(player.global_position.round()), player.hp])


## 三波：清完一波刷下一波，三波清完算训练完成
func _waves() -> void:
	await _fresh()
	arena.auto_waves = true
	arena.reset()
	var max_wave := 0
	for f in 2000:
		await physics_frame
		max_wave = maxi(max_wave, arena.wave)
		for e in arena.enemies:
			if is_instance_valid(e) and e.alive() and e._spawn_pop <= 0.0:
				e.take_hit(Vector2(0, 1), 99, "slash")
		if arena.cleared:
			break
	_check(max_wave == 3 and arena.cleared, "三波依次刷出，清完算训练完成（到第 %d 波，完成=%s）" % [max_wave, str(arena.cleared)])


func _check(ok: bool, what: String) -> void:
	print(("  ok  " if ok else "  NO  ") + what)
	if not ok:
		failures.append(what)
