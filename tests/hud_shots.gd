extends SceneTree
## HUD 截图：满血 / 刚掉血（白色残段）/ 残血 + 提示 + 结算卡，拼成一张写到 screenshots/hud.png。
## 运行：tools/run_test.sh tests/hud_shots.gd --fixed-fps 60

const OUT := "res://screenshots/"

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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var p = main.player
	main.place(Vector2(300, 0))
	for i in 50:
		await physics_frame
	var a: Image = await _snap()
	p.hurt(Vector2(-1, 0), 1)
	for i in 8:
		await process_frame
	var b: Image = await _snap()
	for i in 90:
		await physics_frame
	p._iframes = 0.0
	p.hurt(Vector2(-1, 0), 1)
	main.hud.show_tip(main.tr("TIP_SHELL_BOT"))
	main.hud.show_card("评级  A", "用时 00:52.10 · 受击 2 · 弹反 3")
	for i in 20:
		await process_frame
	var c: Image = await _snap()
	var out := Image.create(960, 540 * 3, false, Image.FORMAT_RGBA8)
	out.blit_rect(a, Rect2i(0, 0, 960, 540), Vector2i(0, 0))
	out.blit_rect(b, Rect2i(0, 0, 960, 540), Vector2i(0, 540))
	out.blit_rect(c, Rect2i(0, 0, 960, 540), Vector2i(0, 1080))
	out.save_png(ProjectSettings.globalize_path(OUT + "hud.png"))
	# 左上机体模块放大
	var z := Image.create(480, 210 * 3, false, Image.FORMAT_RGBA8)
	for k in 3:
		var src: Image = [a, b, c][k]
		var crop := src.get_region(Rect2i(0, 0, 240, 105))
		crop.resize(480, 210, Image.INTERPOLATE_NEAREST)
		z.blit_rect(crop, Rect2i(0, 0, 480, 210), Vector2i(0, 210 * k))
	z.save_png(ProjectSettings.globalize_path(OUT + "hud_zoom.png"))
	print("HUD SHOTS OK")
	quit(0)
