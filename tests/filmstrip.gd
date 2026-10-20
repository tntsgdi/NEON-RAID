extends SceneTree
## 评审材料：关键动作的连续帧（每张图一行，从左到右是时间顺序），写到 screenshots/eval_*.png。
## 运行：tools/run_test.sh tests/filmstrip.gd --fixed-fps 60

const OUT := "res://screenshots/"
const R := Vector2(1, 0)
const CROP := Vector2i(330, 240)

var main: Node
var p


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(load("res://tests/test_window.gd").new())
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	p = main.player
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	# 疾驰：一个完整步幅（先跑够进入疾驰档）
	_drive(Vector2(60, 0), Vector2(340, 0), [{"frames": 9999, "move": R}])
	await _frames(50)
	await _strip("eval_run.png", 8, 2)

	# 起步 → 跑 → 进入疾驰（每 6 帧一张，约 1.6 秒）
	_drive(Vector2(60, 0), Vector2.ZERO, [{"frames": 9999, "move": R}])
	await _strip("eval_accel.png", 10, 6)

	# 起步 → 急停转身
	_drive(Vector2(100, 0), Vector2.ZERO, [{"frames": 30, "move": R}, {"frames": 9999, "move": Vector2(-1, 0)}])
	await _strip("eval_start_skid.png", 8, 5)

	# 挥刀三连
	_drive(Vector2(352, 0), Vector2.ZERO, [{"frames": 1, "move": R}, {"frames": 12}, {"frames": 1, "press": ["slash"]}, {"frames": 14}, {"frames": 1, "press": ["slash"]}, {"frames": 14}, {"frames": 1, "press": ["slash"]}, {"frames": 9999}])
	await _frames(7)
	await _strip("eval_slash.png", 10, 3)

	# 跳 → 空中冲刺 → 落地
	_drive(Vector2(300, 0), Vector2(260, 0), [{"frames": 30, "move": R, "press": ["jump"], "hold": ["jump"]}, {"frames": 1, "move": R, "press": ["dash"]}, {"frames": 9999, "move": R}])
	await _strip("eval_jump_dash.png", 8, 5)

	# 爬墙
	var climb := []
	for i in 6:
		climb.append({"frames": 1, "move": R, "press": ["jump"], "hold": ["jump"]})
		climb.append({"frames": 26, "move": R, "hold": ["jump"]})
	climb.append({"frames": 9999, "move": R})
	_drive(Vector2(2055, 0), Vector2.ZERO, climb)
	await _strip("eval_wall.png", 8, 8)

	# 走路上台阶（不跳）
	_drive(Vector2(700, 0), Vector2.ZERO, [{"frames": 9999, "move": R, "walk": true}])
	await _strip("eval_stairs.png", 8, 10)

	# 夺壳训练场：锁定崖边的失控侦察机 → E 夺壳（光束）→ 开着它飞过深渊（整屏）
	main.load_level("possess")
	await physics_frame
	main.place(Vector2(300, 0))
	var drone = null
	for c in main.possess_range.get_children():
		if c.get_script() != null and c.get_script().resource_path.ends_with("drone_bot.gd") and c.wild and c.global_position.x > 300.0:
			drone = c
	var up: Vector2 = (drone.global_position - (p.global_position + Vector2(0, -18))).normalized()
	var inp = load("res://scripts/player/scripted_input.gd").new([{"frames": 20, "aim": up}, {"frames": 1, "press": ["possess"], "aim": up}, {"frames": 9999, "move": Vector2(1, -0.1)}])
	main.controller.input = inp
	p.input = inp
	await _frames(14)
	await _strip("eval_possess.png", 8, 12)

	# 战斗训练场：安保机瞄准 → 开火 → 挥刀弹反
	main.load_level("arena")
	main.place(Vector2(-330, 0))
	var arena = main.arena
	arena.auto_waves = false
	await physics_frame
	arena.spawn(Vector2(-180, 0), false, 0.0)
	_drive(Vector2(-330, 0), Vector2.ZERO, [
		{"frames": 1, "move": R},
		{"until": func(pl):
			for b in pl.get_tree().get_nodes_in_group("enemy_bullets"):
				if b.global_position.distance_to(pl.global_position + Vector2(0, -26)) < 40.0:
					return true
			return false, "max": 400},
		{"frames": 1, "press": ["slash"]},
		{"frames": 9999},
	])
	await _frames(20)
	await _strip("eval_combat.png", 8, 8, true)
	print("filmstrips saved")
	quit(0)


func _drive(start: Vector2, vel: Vector2, steps: Array) -> void:
	main.place(start, vel)
	var inp = load("res://scripts/player/scripted_input.gd").new(steps)
	main.controller.input = inp
	p.input = inp


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## 拍 count 帧，每隔 every 帧拍一次；wide = 整屏缩小，否则裁出机体周围
func _strip(file: String, count: int, every: int, wide := false) -> void:
	var cell := Vector2i(480, 270) if wide else CROP
	var sheet := Image.create(cell.x * count, cell.y, false, Image.FORMAT_RGBA8)
	for i in count:
		await _frames(every)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		if wide:
			img.resize(cell.x, cell.y, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, cell), Vector2i(i * cell.x, 0))
		else:
			var scale := float(img.get_width()) / 640.0
			var body: Node2D = main.controller.current if is_instance_valid(main.controller.current) else p
			var at: Vector2 = body.get_global_transform_with_canvas().origin * scale + Vector2(0, -20 * scale)
			var c := Vector2i(at) - cell / 2
			c.x = clampi(c.x, 0, img.get_width() - cell.x)
			c.y = clampi(c.y, 0, img.get_height() - cell.y)
			sheet.blit_rect(img, Rect2i(c, cell), Vector2i(i * cell.x, 0))
	sheet.save_png(OUT + file)
