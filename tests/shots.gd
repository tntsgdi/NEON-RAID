extends SceneTree
## 姿势截图：把几个关键动作各拍一张，拼成两张图写到 screenshots/。
## 运行：tools/run_test.sh tests/shots.gd --fixed-fps 60
## （窗口在屏幕外、不抢焦点；不写任何存档或设置）

const R := Vector2(1, 0)
const OUT := "res://screenshots/"
const SCALE := 3

var main: Node
var player


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(load("res://tests/test_window.gd").new())
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	player = main.player
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	var shots := [
		["idle", Vector2(300, 0), Vector2.ZERO, [{"frames": 80, "aim": Vector2(0.8, -0.6)}]],
		["run", Vector2(100, 0), Vector2(260, 0), [{"frames": 47, "move": R}]],
		["jump", Vector2(300, 0), Vector2(260, 0), [{"frames": 9, "move": R, "press": ["jump"], "hold": ["jump"]}]],
		["fall", Vector2(300, 0), Vector2(260, 0), [{"frames": 52, "move": R, "press": ["jump"], "hold": ["jump"]}]],
		["dash", Vector2(200, 0), Vector2(260, 0), [{"frames": 12, "move": R, "press": ["dash"]}]],
		["slide", Vector2(300, 0), Vector2(260, 0), [{"frames": 14, "move": R, "press": ["slide"], "hold": ["slide"]}]],
		["wall", Vector2(2058, -200), Vector2.ZERO, [{"frames": 40, "move": R}]],
		["slash", Vector2(2228, -260), Vector2.ZERO, [
			{"frames": 2, "aim": R},
			{"frames": 1, "press": ["slash"]},
			{"until": func(p): return p.slash_step == 0 and p._slash_time > 0.09, "max": 120},
		]],
	]
	var full := Image.create(480 * 4, 270 * 2, false, Image.FORMAT_RGBA8)
	var zoom := Image.create(360 * 4, 240 * 2, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var s: Array = shots[i]
		main.place(s[1], s[2])
		await physics_frame
		# 末尾补一段同样的按住输入，拍照时手还按着键
		var steps: Array = s[3].duplicate()
		var last: Dictionary = steps[-1]
		steps.append({"frames": 9999, "move": last.get("move", Vector2.ZERO), "hold": last.get("hold", []), "aim": last.get("aim", R)})
		var inp = load("res://scripts/player/scripted_input.gd").new(steps)
		player.input = inp
		while inp._step < steps.size() - 1:
			await physics_frame
		# 停住画面：保持最后一帧的输入，不再推进
		player.set_physics_process(false)
		for k in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		var small := img.duplicate()
		small.resize(480, 270, Image.INTERPOLATE_BILINEAR)
		full.blit_rect(small, Rect2i(0, 0, 480, 270), Vector2i((i % 4) * 480, (i / 4) * 270))
		var at: Vector2 = player.get_global_transform_with_canvas().origin + Vector2(0, -20)
		var c := Vector2i(at * SCALE) - Vector2i(180, 120)
		c.x = clampi(c.x, 0, img.get_width() - 360)
		c.y = clampi(c.y, 0, img.get_height() - 240)
		zoom.blit_rect(img, Rect2i(c, Vector2i(360, 240)), Vector2i((i % 4) * 360, (i / 4) * 240))
		print("shot ", s[0], " state=", player.state, " at ", player.global_position.round())
		player.set_physics_process(true)
		Engine.time_scale = 1.0
	full.save_png(OUT + "m1_full.png")
	zoom.save_png(OUT + "m1_poses.png")
	print("saved ", ProjectSettings.globalize_path(OUT))
	quit(0)
