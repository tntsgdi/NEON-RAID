extends SceneTree
## 第 1 关 001–005 的全景截图（镜头拉远看整张布局），拼成 screenshots/eval_regions.png。
## 运行：tools/run_test.sh tests/region_shots.gd --fixed-fps 60

var main: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(load("res://tests/test_window.gd").new())
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var sheet := Image.create(1600, 300 * 5, false, Image.FORMAT_RGBA8)
	for i in 5:
		main.load_level("d13", i)
		for f in 20:
			await physics_frame
		main.set_physics_process(false)
		var lim: Rect2 = main.region.limits()
		var cam: Camera2D = main.camera
		cam.limit_left = -100000
		cam.limit_right = 100000
		cam.limit_top = -100000
		cam.limit_bottom = 100000
		var z := minf(640.0 / lim.size.x, 360.0 / lim.size.y) * 0.98
		cam.zoom = Vector2(z, z)
		cam.position = lim.get_center()
		cam.offset = Vector2.ZERO
		cam.reset_smoothing()
		for f in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(1600, 900, Image.INTERPOLATE_BILINEAR)
		var crop := img.get_region(Rect2i(0, 300, 1600, 300)) if lim.size.x / lim.size.y > 5.0 else img
		crop.resize(1600, 300, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(crop, Rect2i(0, 0, 1600, 300), Vector2i(0, i * 300))
		main.set_physics_process(true)
	sheet.save_png("res://screenshots/eval_regions.png")
	print("region shots saved")
	quit(0)
