extends SceneTree
## 重装机姿势截图：停放 / 敌对走路 / 举锤 / 冲撞 / 瘫痪 / 被夺，拼成 screenshots/eval_heavy.png。
## 运行：tools/run_test.sh tests/heavy_shots.gd --fixed-fps 60

var main: Node
var HB: Script


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(load("res://tests/test_window.gd").new())
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	HB = load("res://scripts/combat/heavy_bot.gd")
	main.load_level("arena")
	main.arena.auto_waves = false
	await physics_frame
	var sheet := Image.create(300 * 6, 220, false, Image.FORMAT_RGBA8)
	var poses := ["parked", "walk", "windup_slam", "ram", "stunned", "controlled"]
	for i in poses.size():
		for c in main.arena.get_children():
			if c.get_script() == HB:
				c.free()
		var h = HB.new()
		h.hostile = poses[i] != "parked"
		h.position = Vector2(0, 0)
		h.fx_parent = main.arena
		main.arena.add_child(h)
		main.place(Vector2(-300, 0))
		await physics_frame
		match poses[i]:
			"walk":
				h.patrol_range = 200.0
			"windup_slam":
				h.state = 3
				h._t = 0.25
			"ram":
				h.state = 2
				h._t = 5.0
			"stunned":
				h._stun()
				h._t = 99.0
			"controlled":
				main.controller.possess(h)
		for f in (40 if poses[i] != "windup_slam" else 22):
			await physics_frame
		main.set_physics_process(false)
		main.camera.position = h.global_position + Vector2(0, -30)
		main.camera.offset = Vector2.ZERO
		main.camera.reset_smoothing()
		for f in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		# HDR 2D 下读回的是线性颜色，转回 sRGB 才和屏幕上看到的一样
		img.linear_to_srgb()
		var vp := img.get_size()
		var crop := img.get_region(Rect2i(vp.x / 2 - vp.x / 8, vp.y / 2 - vp.y / 6, vp.x / 4, vp.y / 3))
		crop.resize(300, 220, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(crop, Rect2i(0, 0, 300, 220), Vector2i(i * 300, 0))
		main.set_physics_process(true)
		main.controller.return_to_base(Vector2(-300, 0))
	sheet.save_png("res://screenshots/eval_heavy.png")
	print("heavy shots saved")
	quit(0)
