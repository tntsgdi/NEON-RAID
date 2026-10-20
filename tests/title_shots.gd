extends SceneTree
## 标题菜单截图：主页 + 选择区域页，拼成 screenshots/eval_title.png。
## 运行：tools/run_test.sh tests/title_shots.gd --fixed-fps 60

var main: Node


func _initialize() -> void:
	_run.call_deferred()


func _snap() -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
	return img


func _run() -> void:
	root.add_child(load("res://tests/test_window.gd").new())
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	main.load_level("d13", 0)
	for i in 10:
		await physics_frame
	main.open_title()
	for i in 70:
		await process_frame
	var a: Image = await _snap()
	main.title._sel = 1
	main.title._confirm()
	for i in 40:
		await process_frame
	var b: Image = await _snap()
	var out := Image.create(960, 1080, false, Image.FORMAT_RGBA8)
	out.blit_rect(a, Rect2i(0, 0, 960, 540), Vector2i(0, 0))
	out.blit_rect(b, Rect2i(0, 0, 960, 540), Vector2i(0, 540))
	out.save_png("res://screenshots/eval_title.png")
	print("title shots saved")
	quit(0)
