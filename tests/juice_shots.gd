extends SceneTree
## 爽感冲刺对照图：连击数字 + 击毁零件四散（juice_kill）、电磁长矛闪白（juice_rail）、
## 重击撞墙反弹（juice_bounce）。→ screenshots/juice_*.png
## 运行：tools/run_test.sh tests/juice_shots.gd --fixed-fps 60

var main: Node
var EB: Script
var CAP: Script


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(load("res://tests/test_window.gd").new())
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	EB = load("res://scripts/combat/enemy_bot.gd")
	CAP = load("res://tests/capture.gd")
	main.load_level("d13", 1)
	for i in 10:
		await physics_frame
	var w: Node = main.region
	for e in w.get_children():
		if e.is_in_group("enemy"):
			e.queue_free()
	await physics_frame

	# 1) 连击 + 击毁零件：打 7 下，最后一下重击打碎
	main.place(Vector2(300, 0))
	var a = _bot(w, Vector2(360, 0))
	var b = _bot(w, Vector2(420, 0))
	await _frames(20)
	a.hp = 40
	for i in 6:
		a.take_hit(Vector2.RIGHT, 1, "slash")
		await _frames(6)
	b.take_hit(Vector2.RIGHT, 9, "slash")
	await _frames(12)
	await _shot("juice_kill")

	# 2) 电磁长矛：附身枪手蓄满后松开，拍闪白那一帧
	for e in w.get_children():
		if e.is_in_group("enemy"):
			e.queue_free()
	await _frames(40)
	var g = _bot(w, Vector2(700, 0))
	_bot(w, Vector2(860, 0))
	_bot(w, Vector2(930, 0))
	await _frames(5)
	main.place(Vector2(640, 0))
	await physics_frame
	main.controller.possess(g)
	await _frames(80)
	# 真实输入：按住 K 蓄满，松开
	var SI = load("res://scripts/player/scripted_input.gd")
	var inp = SI.new([{"frames": 1, "aim": Vector2.RIGHT}, {"frames": 1, "press": ["shoot"], "hold": ["shoot"], "aim": Vector2.RIGHT}, {"frames": 80, "hold": ["shoot"], "aim": Vector2.RIGHT}, {"frames": 60, "aim": Vector2.RIGHT}])
	main.controller.input = inp
	g.input = inp
	for i in 82:
		await physics_frame
	await _shot("juice_rail_full")
	for i in 3:
		await physics_frame
	await _shot("juice_rail")
	for i in 30:
		await physics_frame
	await _shot("juice_rail_after")
	var idle = load("res://scripts/player/player_input.gd").new()
	main.controller.input = idle
	g.input = idle

	# 3) 撞墙反弹：靠墙的敌人被重击打飞，反弹那一刻
	main.controller.return_to_base(Vector2(300, 0))
	for e in w.get_children():
		if e.is_in_group("enemy"):
			e.queue_free()
	await _frames(40)
	var wall_x := _find_wall(w, 300.0)
	var c = _bot(w, Vector2(wall_x - 50.0, 0))
	main.place(Vector2(wall_x - 90.0, 0))
	await _frames(20)
	c.hp = 20
	c.take_hit(Vector2.RIGHT, 2, "slash")
	for i in 40:
		await physics_frame
		if c.velocity.x < -50.0:
			break
	await _frames(2)
	await _shot("juice_bounce")
	quit(0)


func _bot(w: Node, pos: Vector2):
	var e = EB.new()
	e.kind = "gunner"
	e.position = pos
	e.patrol_range = 0.0
	e.player = null
	e.fx_parent = w
	e._grace = 0.0
	w.add_child(e)
	return e


func _find_wall(w: Node, from_x: float) -> float:
	var x := from_x
	while x < from_x + 3000.0:
		if w.solid_at(Vector2(x, -12)):
			return x
		x += 8.0
	return from_x + 200.0


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _shot(name: String) -> void:
	# 屏幕外的窗口偶尔会晚一两帧才出图：多等几帧再读，免得拍到旧画面
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	CAP.native(main).save_png("res://screenshots/%s.png" % name)
	print(name, " saved")
