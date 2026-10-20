extends SceneTree
## 样片展示截图：区域 002 雨巷检查站的几个位置，各拍一张完整画面（640×360 原生 ×3 = 1920×1080），
## 不显示界面：screenshots/showcase_<n>.png。可选 -- --hud 带界面拍。
## 运行：tools/run_test.sh tests/showcase_shots.gd --fixed-fps 60

const SPOTS := [
	[160.0, [{"frames": 40, "move": Vector2(1, 0)}]],
	[700.0, [{"frames": 30, "move": Vector2(1, 0)}, {"frames": 1, "press": ["slash"]}, {"frames": 8}]],
	[1500.0, [{"frames": 50, "move": Vector2(1, 0)}]],
	[2380.0, [{"frames": 20, "move": Vector2(1, 0)}]],
]

var main: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(load("res://tests/test_window.gd").new())
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	main.load_level("d13", 1)
	for i in 10:
		await physics_frame
	main.hide_hud = not OS.get_cmdline_user_args().has("--hud")
	if OS.get_cmdline_user_args().has("--novig"):
		main._post.set_shader_parameter("vignette", 0.0)
	var n := 0
	var spots := SPOTS.duplicate()
	for d in main.region.decor:
		if d[0] == "B":
			spots.insert(0, [d[1].x - 170.0, [{"frames": 24, "move": Vector2(1, 0)}]])
	# 中继过沟：夺侦察机飞到沟上空
	var relay = main.get_tree().get_first_node_in_group("relay")
	if relay != null:
		spots.append([relay.global_position.x - 10.0, [{"frames": 6}, {"frames": 1, "press": ["possess"], "aim": Vector2(0.95, -0.3).normalized()}, {"frames": 70, "move": Vector2(1, -0.2)}]])
	for spot in spots:
		main.place(Vector2(spot[0], 0))
		var inp = load("res://scripts/player/scripted_input.gd").new(spot[1])
		main.controller.input = inp
		main.player.input = inp
		while not inp.done:
			await physics_frame
		for f in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.linear_to_srgb()
		img.save_png("res://screenshots/showcase_%d.png" % n)
		n += 1
	print("showcase saved (%d)" % n)
	quit(0)
