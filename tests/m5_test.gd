extends SceneTree
## 附身强化验收（headless，脚本输入，不碰键鼠也不写任何文件）。
## 运行：Godot --headless --path . -s tests/m5_test.gd --fixed-fps 60

const R := Vector2(1, 0)
const L := Vector2(-1, 0)

var main: Node
var arena: Node
var player
var failures: Array[String] = []
var EB: Script
var DB: Script
var HB: Script
var SI: Script


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	EB = load("res://scripts/combat/enemy_bot.gd")
	DB = load("res://scripts/combat/drone_bot.gd")
	HB = load("res://scripts/combat/heavy_bot.gd")
	SI = load("res://scripts/player/scripted_input.gd")
	main.load_level("arena")
	arena = main.arena
	arena.auto_waves = false
	player = main.player
	await physics_frame

	await _growth_and_wall()
	await _rail()
	await _swarm()
	await _chain_ram()
	await _shield()
	await _grapple()
	await _heavy()
	await _overload()

	if failures.is_empty():
		print("M5 TEST PASS")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		print("M5 TEST FAIL (%d)" % failures.size())
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


func _bot(pos: Vector2, kind := "gunner", shielded := false, hostile := false):
	var e = EB.new()
	e.kind = kind
	e.shielded = shielded
	e.position = pos
	e.patrol_range = 0.0
	e.player = player if hostile else null
	e.fx_parent = arena
	e._grace = 0.0
	arena.add_child(e)
	return e


func _possess(shell) -> void:
	main.place(shell.global_position + Vector2(-60, 0))
	await physics_frame
	main.controller.possess(shell)
	for i in 80:
		await physics_frame


func _drive(shell, steps: Array, max_frames := 2000) -> void:
	var inp = SI.new(steps)
	main.controller.input = inp
	shell.input = inp
	var n := 0
	while not inp.done and n < max_frames:
		await physics_frame
		n += 1
	var idle = load("res://scripts/player/player_input.gd").new()
	main.controller.input = idle
	if is_instance_valid(shell):
		shell.input = idle


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## 异体生长 + 灌注的墙面行走：被夺的枪手 0.3 秒长出电磁长矛；朝墙推能走上墙
func _growth_and_wall() -> void:
	await _fresh()
	var g = _bot(Vector2(380, 0))
	await _frames(3)
	await _possess(g)
	_check(g.mut_k >= 1.0 and g.rig.mut_k >= 1.0, "夺壳 0.3 秒内长出异体（%.2f）" % g.mut_k)
	var y0: float = g.global_position.y
	await _drive(g, [{"frames": 140, "move": R}])
	_check(g.global_position.y < y0 - 60.0, "被夺的枪手也能飞檐走壁（爬高 %.0f）" % (y0 - g.global_position.y))


## 电磁长矛：按住 K 蓄满，松开贯穿一条线上的两个敌人（盾也挡不住）
func _rail() -> void:
	await _fresh()
	var g = _bot(Vector2(-200, 0))
	var a = _bot(Vector2(-80, 0), "gunner", true)
	var b = _bot(Vector2(0, 0))
	a.facing = -1
	await _frames(3)
	await _possess(g)
	var ha: int = a.hp
	var hb: int = b.hp
	await _drive(g, [{"frames": 1, "aim": R}, {"frames": 1, "press": ["shoot"], "hold": ["shoot"], "aim": R}, {"frames": 90, "hold": ["shoot"], "aim": R}, {"frames": 20, "aim": R}])
	_check((not is_instance_valid(a) or a.hp < ha) and (not is_instance_valid(b) or b.hp < hb), "电磁长矛一发贯穿两个敌人（含正面持盾的）")


## 蜂群：K 一次放出 6 发追踪弹
func _swarm() -> void:
	await _fresh()
	var s = _bot(Vector2(-200, 0), "burst")
	var t = _bot(Vector2(100, 0))
	await _frames(3)
	await _possess(s)
	var before := root.get_tree().get_nodes_in_group("player_bullets").size()
	await _drive(s, [{"frames": 1, "press": ["shoot"], "aim": R}, {"frames": 2}])
	var homing := 0
	for bl in root.get_tree().get_nodes_in_group("player_bullets"):
		if bl.homing != null:
			homing += 1
	_check(homing >= 6, "三连发异体一次放出 6 发追踪弹（%d）" % homing)


## 冲锋机连撞：J 冲撞，撞墙反弹继续撞
func _chain_ram() -> void:
	await _fresh()
	var r = _bot(Vector2(330, 0), "rusher")
	await _frames(3)
	await _possess(r)
	r.facing = 1
	var flips := 0
	var last: int = r.facing
	var inp = SI.new([{"frames": 1, "press": ["slash"], "move": R}, {"frames": 120}])
	main.controller.input = inp
	r.input = inp
	while not inp.done:
		await physics_frame
		if r.facing != last:
			flips += 1
			last = r.facing
	_check(flips >= 1, "冲锋机异体撞墙反弹继续撞（反弹 %d 次）" % flips)


## 盾兵：J 掷盾回旋打穿敌人，盾飞回手里；举盾时正面子弹原路弹回
func _shield() -> void:
	await _fresh()
	var s = _bot(Vector2(-200, 0), "gunner", true)
	var t = _bot(Vector2(-60, 0))
	await _frames(3)
	await _possess(s)
	s.facing = 1
	var ht: int = t.hp
	await _drive(s, [{"frames": 1, "press": ["slash"], "aim": R}, {"frames": 90}])
	_check(not is_instance_valid(t) or t.hp < ht, "掷出的晶化盾打中敌人")
	_check(not s._shield_out, "回旋盾飞回手里")
	var BU = load("res://scripts/combat/bullet.gd")
	s.facing = 1
	var bl = BU.fire(arena, s.center() + Vector2(60, 0), Vector2(-300, 0), 1, 1, null)
	await _frames(30)
	_check(not is_instance_valid(bl) or bl.team == 0, "举着晶化盾，正面子弹原路弹回")


## 侦察机线缆：J 抓住敌人，再按 J 甩出去砸中另一个敌人，两个都受伤
func _grapple() -> void:
	await _fresh()
	var d = DB.new()
	d.position = Vector2(-200, -60)
	d.fx_parent = arena
	arena.add_child(d)
	var a = _bot(Vector2(-110, 0))
	var b = _bot(Vector2(40, 0))
	await _frames(3)
	await _possess(d)
	d.global_position = Vector2(-160, -40)
	d.facing = 1
	var hb: int = b.hp
	await _drive(d, [{"frames": 1, "press": ["slash"], "aim": Vector2(1, 0.5).normalized()}, {"frames": 30}])
	_check(d.grab == a or d._flung == a, "线缆抓住了敌人")
	await _drive(d, [{"frames": 1, "press": ["slash"], "move": R}, {"frames": 60, "move": Vector2.ZERO}])
	_check(not is_instance_valid(b) or b.hp < hb, "甩出去的敌人砸中另一个敌人")


## 重装机鸟腿：跳得很高；空中砸地范围翻倍（200 像素外也被掀翻）
func _heavy() -> void:
	await _fresh()
	var h = HB.new()
	h.hostile = false
	h.position = Vector2(20, 0)
	h.fx_parent = arena
	arena.add_child(h)
	var far = _bot(Vector2(200, 0))
	await _frames(5)
	await _possess(h)
	var y0: float = h.global_position.y
	var top := y0
	var inp = SI.new([{"frames": 1, "press": ["jump"]}, {"frames": 24}, {"frames": 1, "press": ["shoot"]}, {"frames": 60}])
	main.controller.input = inp
	h.input = inp
	var hp0: int = far.hp
	while not inp.done:
		await physics_frame
		top = minf(top, h.global_position.y)
	_check(y0 - top > 75.0, "重装机长出鸟腿，跳高 %.0f 像素" % (y0 - top))
	_check(not is_instance_valid(far) or far.hp < hp0, "空中砸地范围翻倍：170 像素外的敌人也被砸到")
	_check(h.rig.mut_k >= 1.0, "重装机异体（鸟腿）长出来了")


## 意识负荷：枪手 20 秒满 → 壳过载自爆、炸伤旁边的敌人 → 光球 2.5 秒后自动飞回本体
func _overload() -> void:
	await _fresh()
	var g = _bot(Vector2(100, 0))
	var near = _bot(Vector2(140, 0))
	await _frames(3)
	await _possess(g)
	var hn: int = near.hp
	var n := 0
	while main.controller.load_k < 1.0 and is_instance_valid(g) and n < 3000:
		await physics_frame
		n += 1
	await _frames(2)
	_check(not is_instance_valid(g) or not g.alive(), "负荷满了，被夺的壳过载自爆（%.1f 秒）" % (n / 120.0))
	_check(not is_instance_valid(near) or near.hp < hn, "过载自爆炸伤旁边的敌人")
	_check(is_instance_valid(main.controller.current) and str(main.controller.current.get_script().resource_path).ends_with("wisp.gd"), "过载后意识光流弹出")
	var m := 0
	while main.controller.current != player and m < 1200:
		await physics_frame
		m += 1
	_check(main.controller.current == player, "光球超时后自动飞回本体（%.1f 秒）" % (m / 120.0))
