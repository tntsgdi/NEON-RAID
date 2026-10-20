extends SceneTree
## 战斗训练场截图：敌人拉瞄准线 + 玩家开枪；盾兵 + 神经超频泛青。写到 screenshots/m2_arena.png。
## 运行：tools/run_test.sh tests/shots_m2.gd --fixed-fps 60

const OUT := "res://screenshots/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(load("res://tests/test_window.gd").new())
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	main.load_level("arena")
	var arena = main.arena
	arena.auto_waves = false
	var p = main.player
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var sheet := Image.create(960 * 2, 540, false, Image.FORMAT_RGBA8)

	# 1：安保机、三连发机在拉瞄准线，带盾冲锋机在后面，玩家朝它们开枪
	main.place(Vector2(-300, 0))
	arena.spawn(Vector2(-120, 0), false, 0.0)
	arena.spawn(Vector2(-205, -80), false, 0.0, "burst")
	arena.spawn(Vector2(60, 0), true, 0.0, "rusher")
	var inp = load("res://scripts/player/scripted_input.gd").new([{"frames": 1, "move": Vector2(1, 0)}, {"frames": 30, "aim": Vector2(1, -0.1).normalized()}, {"frames": 1, "press": ["shoot"]}, {"frames": 4}, {"frames": 1, "press": ["shoot"]}, {"frames": 9999}])
	p.input = inp
	for i in 50:
		await physics_frame
	await _grab(sheet, 0)

	# 2：盾兵贴脸 + 神经超频
	main.restart()
	arena.auto_waves = false
	var s = arena.spawn(Vector2(-300, 0), true, 0.0)
	s.player = null
	main.place(Vector2(-340, 0))
	p.input = load("res://scripts/player/scripted_input.gd").new([{"frames": 1, "move": Vector2(1, 0)}, {"frames": 6}, {"frames": 1, "press": ["slash"]}, {"frames": 9999}])
	root.get_node("TimeFx").slowmo(5.0, 0.35)
	p.overclock_charge = 2.5
	for i in 16:
		await physics_frame
	for i in 10:
		await process_frame
	await _grab(sheet, 1)
	root.get_node("TimeFx").reset()
	sheet.save_png(OUT + "m2_arena.png")
	print("saved")
	quit(0)


func _grab(sheet: Image, i: int) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	# HDR 2D 下读回的是线性颜色，转回 sRGB 才和屏幕上看到的一样
	img.linear_to_srgb()
	img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
	sheet.blit_rect(img, Rect2i(0, 0, 960, 540), Vector2i(i * 960, 0))
