extends SceneTree
## 敌人动作特写：巡逻走路、举枪瞄准、冲锋蓄力、冲锋、被上挑打飞
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
	main.place(Vector2(-400, 0))
	var walker = arena.spawn(Vector2(-200, 0), false, 60.0)
	walker.player = null
	var aimer = arena.spawn(Vector2(-60, 0), false, 0.0, "burst")
	var rusher = arena.spawn(Vector2(150, 0), false, 0.0, "rusher")
	var cell := Vector2i(300, 210)
	var sheet := Image.create(cell.x * 6, cell.y, false, Image.FORMAT_RGBA8)
	var picks := [[walker, 50], [walker, 8], [aimer, 30], [rusher, 30], [rusher, 22], [walker, 6]]
	for i in picks.size():
		var who = picks[i][0]
		if i == 3:
			main.place(Vector2(-10, 0))
		if i == 5 and is_instance_valid(walker):
			walker.take_hit(Vector2(0, -1), 1, "slash")
		for f in picks[i][1]:
			await physics_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		# HDR 2D 下读回的是线性颜色，转回 sRGB 才和屏幕上看到的一样
		img.linear_to_srgb()
		var scale := float(img.get_width()) / 640.0
		var at: Vector2 = who.get_global_transform_with_canvas().origin * scale + Vector2(0, -18 * scale) if is_instance_valid(who) else Vector2(960, 540)
		var c := Vector2i(at) - cell / 2
		c.x = clampi(c.x, 0, img.get_width() - cell.x)
		c.y = clampi(c.y, 0, img.get_height() - cell.y)
		sheet.blit_rect(img, Rect2i(c, cell), Vector2i(i * cell.x, 0))
	sheet.save_png("res://screenshots/eval_enemy.png")
	print("saved")
	quit(0)
