extends SceneTree
## 每个区域的实际画幅截图（正常镜头）：在起点和各检查点各拍一张，每个区域一行，
## 拼成 screenshots/eval_region_frames.png。运行：tools/run_test.sh tests/region_frames.gd --fixed-fps 60

const W := 480
const H := 270
const PER := 4

var main: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(load("res://tests/test_window.gd").new())
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var sheet := Image.create(W * PER, H * 5, false, Image.FORMAT_RGBA8)
	for i in 5:
		main.load_level("d13", i)
		for f in 10:
			await physics_frame
		var cps: Array = main.region.checkpoints
		var picks := []
		for k in PER:
			picks.append(cps[mini(int(round(float(k) * (cps.size() - 1) / maxf(PER - 1, 1))), cps.size() - 1)])
		for k in picks.size():
			main.place(picks[k] + Vector2(-40, 0))
			# 往右走一小段，让镜头前瞻和动画进入状态
			var inp = load("res://scripts/player/scripted_input.gd").new([{"frames": 50, "move": Vector2(1, 0)}])
			main.controller.input = inp
			main.player.input = inp
			while not inp.done:
				await physics_frame
			for f in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			# HDR 2D 下读回的是线性颜色，转回 sRGB 才和屏幕上看到的一样
			img.linear_to_srgb()
			img.resize(W, H, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(k * W, i * H))
		main.controller.input = load("res://scripts/player/device_input.gd").new()
		main.player.input = main.controller.input
	sheet.save_png("res://screenshots/eval_region_frames.png")
	print("region frames saved")
	quit(0)
