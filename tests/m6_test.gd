extends SceneTree
## 爽感冲刺验收（headless，不碰键鼠也不写任何文件）。
## 运行：Godot --headless --path . -s tests/m6_test.gd --fixed-fps 60

var main: Node
var arena: Node
var player
var failures: Array[String] = []
var EB: Script


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	EB = load("res://scripts/combat/enemy_bot.gd")
	main.load_level("arena")
	arena = main.arena
	arena.auto_waves = false
	player = main.player
	await physics_frame

	await _combo_and_debris()
	await _wall_bounce()
	await _finisher()
	await _music_sets()

	if failures.is_empty():
		print("M6 TEST PASS")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		print("M6 TEST FAIL (%d)" % failures.size())
		quit(1)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok  ", what)
	else:
		failures.append(what)


func _fresh() -> void:
	main.controller.return_to_base(Vector2(-380, 0))
	main.restart()
	arena.auto_waves = false
	for e in arena.get_children():
		if e.is_in_group("enemy") or e.is_in_group("possessable") and e != player:
			e.queue_free()
	await physics_frame
	await physics_frame
	main.combo = 0
	main._finisher_cd = 0.0


func _bot(pos: Vector2):
	var e = EB.new()
	e.kind = "gunner"
	e.position = pos
	e.patrol_range = 0.0
	e.player = null
	e.fx_parent = arena
	e._grace = 0.0
	arena.add_child(e)
	return e


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## 连击：连续打中计数、HUD 跟着变；击毁时飞出像素零件（不是方块）
func _combo_and_debris() -> void:
	await _fresh()
	var a = _bot(Vector2(0, 0))
	await _frames(3)
	a.take_hit(Vector2.RIGHT, 1, "slash")
	await _frames(2)
	var b = _bot(Vector2(-100, 0))
	await _frames(3)
	b.take_hit(Vector2.RIGHT, 1, "slash")
	await _frames(2)
	_check(main.combo >= 2 and main.hud.combo >= 2, "连续打中两次，连击数 %d" % main.combo)
	var before := 0
	for n in arena.get_children():
		if n is RigidBody2D and n.get("sprite") != null:
			before += 1
	a.take_hit(Vector2.RIGHT, 9, "slash")
	await _frames(3)
	var parts := 0
	for n in arena.get_children():
		if n is RigidBody2D and n.get("sprite") != null:
			parts += 1
	_check(parts - before >= 5, "击毁后飞出像素零件 %d 块" % (parts - before))


## 重击打飞撞墙：反弹回来并多掉 1 点血
func _wall_bounce() -> void:
	await _fresh()
	var lim: Rect2 = arena.limits()
	var e = _bot(Vector2(lim.end.x - 60.0, 0))
	await _frames(20)
	e.hp = 20
	var hp0: int = e.hp
	e.take_hit(Vector2.RIGHT, 2, "slash")
	var bounced := false
	for i in 60:
		await physics_frame
		if is_instance_valid(e) and e.velocity.x < -50.0:
			bounced = true
	_check(bounced, "重击打到墙上弹回来")
	_check(is_instance_valid(e) and e.hp <= hp0 - 3, "撞墙多掉 1 点血（%d → %d）" % [hp0, e.hp if is_instance_valid(e) else -1])


## 清掉附近最后一个敌人 = 终结一击：短暂慢镜
func _finisher() -> void:
	await _fresh()
	var e = _bot(Vector2(0, 0))
	await _frames(3)
	e.take_hit(Vector2.RIGHT, 9, "slash")
	var slow := false
	for i in 20:
		await process_frame
		if Engine.time_scale < 0.5:
			slow = true
	_check(slow, "终结一击触发慢镜 / 停顿")
	for i in 90:
		await process_frame
	_check(Engine.time_scale > 0.99, "慢镜结束恢复正常速度")


## 进入第 1 关各区域换配乐；回训练场换回默认
func _music_sets() -> void:
	main.load_level("d13", 2)
	for i in 120:
		await process_frame
	_check(root.get_node("Music").current_set == "r3", "进入 003 区换成机库配乐（%s）" % root.get_node("Music").current_set)
	main.load_level("arena")
	for i in 120:
		await process_frame
	_check(root.get_node("Music").current_set == "", "回训练场换回默认配乐")
