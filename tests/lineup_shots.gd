extends SceneTree
## 像素规范板：调色板色块 + 全部单位并排（R-0、枪手、三连发、冲锋机、盾兵、侦察机 敌对/失控/被夺、
## 重装机 敌对/瘫痪/被夺），原生像素渲染，截成 1:1 和 3× 两张：screenshots/pixel_lineup.png / _x3.png
## 运行：tools/run_test.sh tests/lineup_shots.gd --fixed-fps 60

var main: Node


func _initialize() -> void:
	_run.call_deferred()


class Swatches extends Node2D:
	var names: Array = []
	var colors: Array = []

	func _draw() -> void:
		for i in colors.size():
			draw_rect(Rect2(i * 10, 0, 9, 9), colors[i])


func _run() -> void:
	root.add_child(load("res://tests/test_window.gd").new())
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	main.load_level("arena")
	main.arena.auto_waves = false
	await physics_frame
	var arena: Node = main.arena
	for e in arena.get_children():
		if e.is_in_group("enemy"):
			e.queue_free()
	var x := -250.0
	main.place(Vector2(x, 0))
	var units := []
	var EB = load("res://scripts/combat/enemy_bot.gd")
	var DB = load("res://scripts/combat/drone_bot.gd")
	var HB = load("res://scripts/combat/heavy_bot.gd")
	var mut := OS.get_cmdline_user_args().has("--mut")
	for spec in [["gunner", false], ["burst", false], ["rusher", false], ["gunner", true]]:
		x += 46.0
		var e = EB.new()
		e.kind = spec[0]
		e.shielded = spec[1]
		e.position = Vector2(x, 0)
		e.facing = -1
		e.patrol_range = 0.0
		e.fx_parent = arena
		arena.add_child(e)
		units.append(e)
		if mut:
			e.input = load("res://scripts/player/player_input.gd").new()
			e.controlled = true
			e.facing = 1
	for mode in (["controlled"] if mut else ["hostile", "wild", "controlled"]):
		x += 34.0
		var d = DB.new()
		d.wild = mode == "wild"
		d.position = Vector2(x, -30)
		d.fx_parent = arena
		arena.add_child(d)
		if mode == "controlled":
			d.input = load("res://scripts/player/player_input.gd").new()
			d.controlled = true
		units.append(d)
	for mode in (["controlled"] if mut else ["hostile", "stunned", "controlled"]):
		x += 60.0
		var h = HB.new()
		h.hostile = true
		h.position = Vector2(x, 0)
		h.fx_parent = arena
		arena.add_child(h)
		units.append(h)
		if mode == "stunned":
			h.call_deferred("_stun")
		elif mode == "controlled":
			h.input = load("res://scripts/player/player_input.gd").new()
			h.set_deferred("controlled", true)
	for i in 30:
		await physics_frame
	for u in units:
		u.set_physics_process(false)
		if u.has_method("set_process"):
			u.set_process(false)
	# 调色板
	var sw := Swatches.new()
	var pal := {"k0": "05060a", "k1": "0b0d13", "k2": "141821", "k3": "1e232e", "k4": "2b3240", "k5": "3d4656", "k6": "5a6478", "k7": "8a95a8",
		"c0": "0e3a44", "c1": "16707e", "c2": "2bc4d6", "c3": "9ef4ff", "r0": "3a0d14", "r1": "7a1824", "r2": "d63446", "r3": "ff9aa4",
		"y0": "5a3d0c", "y1": "c98a1c", "y2": "ffd77a", "w0": "f2f6fa", "m0": "4a1640", "m1": "b8348f", "b0": "0a1a2a", "b1": "173550"}
	for k in pal:
		sw.colors.append(Color.html(pal[k]))
	sw.position = Vector2(-260, -150)
	arena.add_child(sw)
	main.set_physics_process(false)
	main.camera.position = Vector2(30, -70)
	main.camera.zoom = Vector2.ONE
	main.camera.offset = Vector2.ZERO
	main.camera.reset_smoothing()
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.linear_to_srgb()
	var k: int = img.get_width() / 640
	var x3 := img.duplicate()
	x3.save_png("res://screenshots/pixel_lineup%s_x3.png" % ("_mut" if mut else ""))
	img.resize(640, 360, Image.INTERPOLATE_NEAREST)
	img.save_png("res://screenshots/pixel_lineup%s.png" % ("_mut" if mut else ""))
	print("lineup saved (scale %d)" % k)
	quit(0)
