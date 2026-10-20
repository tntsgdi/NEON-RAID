extends SceneTree
## M4 验收（headless，脚本输入，不碰键鼠也不写任何文件）。
## 运行：Godot --headless --path . -s tests/m4_test.gd --fixed-fps 60

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

	await _hurtboxes()
	await _stomp()
	await _aim_interrupt()
	await _crowd()
	await _combo_magnet()

	if failures.is_empty():
		print("M4 TEST PASS")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		print("M4 TEST FAIL (%d)" % failures.size())
		quit(1)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok  ", what)
	else:
		failures.append(what)


func _fresh() -> void:
	if main.arena == null:
		main.load_level("arena")
		arena = main.arena
	main.restart()
	arena.auto_waves = false
	for e in arena.get_children():
		if e.is_in_group("enemy"):
			e.queue_free()
	await physics_frame


func _bot(pos: Vector2, shielded := false, watching := true, facing := -1):
	var e = arena.spawn(pos, shielded, 0.0)
	e.facing = facing
	e._grace = 0.0
	if not watching:
		e.player = null
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


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## 敌人有头 / 身 / 腿三块物理受击框；刀光扇形扫到头部判为"head"
func _hurtboxes() -> void:
	await _fresh()
	var e = _bot(Vector2(200, 0), false, false)
	await _frames(5)
	var hb = e.hurtboxes
	_check(hb.parts.has("head") and hb.parts.has("body") and hb.parts.has("legs"), "敌人有头/身/腿三块受击框（%s）" % str(hb.parts.keys()))
	var head_y: float = hb.parts.head[0].global_position.y
	var legs_y: float = hb.parts.legs[0].global_position.y
	_check(head_y < hb.parts.body[0].global_position.y and hb.parts.body[0].global_position.y < legs_y, "头在身上面、身在腿上面")
	var hurt = load("res://scripts/combat/hurtboxes.gd")
	var at_head: Array = hurt.sector(Vector2(170, head_y), 34.0, deg_to_rad(-10.0), deg_to_rad(10.0))
	var at_legs: Array = hurt.sector(Vector2(170, -4), 34.0, deg_to_rad(-5.0), deg_to_rad(5.0))
	_check(hurt.sweep_hit(e, at_head) == "head", "刀光扫到头 → head（%s）" % hurt.sweep_hit(e, at_head))
	_check(hurt.sweep_hit(e, at_legs) == "legs", "刀光贴地扫 → legs（%s）" % hurt.sweep_hit(e, at_legs))
	var miss: Array = hurt.sector(Vector2(100, -20), 30.0, deg_to_rad(-10.0), deg_to_rad(10.0))
	_check(hurt.sweep_hit(e, miss) == "", "够不着就不判定")


## 踩头：伤 1、踩趴、自己弹起
func _stomp() -> void:
	await _fresh()
	var e = _bot(Vector2(330, 0), false, false)
	e.patrol_range = 0.0
	await _frames(3)
	var log := await _drive(Vector2(330, -70), [{"frames": 36}])
	var bounced := log.any(func(x): return x.vel.y < -250.0)
	_check(e.hp == e.MAX_HP - 1, "踩头伤 1（血 %d）" % e.hp)
	_check(bounced, "踩头后自己弹起")
	_check(e._down > 0.0 or e.state != 0, "被踩趴（倒地 %.2f 秒）" % e._down)


## 射手瞄准（锁定框收紧）时被砍中：锁定被打断，不开枪
func _aim_interrupt() -> void:
	await _fresh()
	var e = _bot(Vector2(200, 0), false, true, -1)
	main.place(Vector2(120, 0))
	await physics_frame
	var n := 0
	while e.state != 1 and n < 120:
		await physics_frame
		n += 1
	_check(e.state == 1, "射手看见玩家进入瞄准")
	var before := get_nodes_in_group_count("enemy_bullets")
	await _drive(Vector2(120, 0), [{"frames": 1, "press": ["slash"]}, {"frames": 50}])
	var after := get_nodes_in_group_count("enemy_bullets")
	_check(after <= before, "瞄准中被砍，锁定打断、没开枪（子弹 %d → %d）" % [before, after])


func get_nodes_in_group_count(g: String) -> int:
	return root.get_tree().get_nodes_in_group(g).size()


## 两台敌人叠在一起会互相推开
func _crowd() -> void:
	await _fresh()
	var a = _bot(Vector2(300, 0), false, false)
	var b = _bot(Vector2(302, 0), false, false)
	main.place(Vector2(-200, 0))
	await _frames(60)
	_check(absf(a.global_position.x - b.global_position.x) > 6.0, "叠在一起的敌人互相推开（间距 %.1f）" % absf(a.global_position.x - b.global_position.x))


## 连击吸附：三连击把敌人打退，后两刀也贴上去打中
func _combo_magnet() -> void:
	await _fresh()
	var e = _bot(Vector2(200, 0), false, false)
	e.make_elite()
	var hp0: int = e.hp
	await _frames(3)
	var steps := [{"frames": 1, "move": R}, {"frames": 3}]
	for i in 3:
		steps.append({"frames": 1, "press": ["slash"]})
		steps.append({"until": func(p): return p.slash_step == i and p._slash_time > 0.08, "max": 120})
	steps.append({"frames": 40})
	await _drive(Vector2(150, 0), steps)
	var hits: int = hp0 - (e.hp if is_instance_valid(e) and e.alive() else -99)
	_check(not is_instance_valid(e) or not e.alive() or hp0 - e.hp >= 3, "三连击三刀都打中被击退的敌人（掉血 %d）" % hits)
