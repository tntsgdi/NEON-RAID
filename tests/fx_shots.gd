extends SceneTree
## 特效对照表：同一时刻把各种像素特效并排放出来拍一张（640×360 原生 ×3）：
## 刀光（普通 / 重击）、命中闪光 + 火花、玩家电磁弹、敌方电磁弹、破盾碎片、冲击环、夺壳意识流、
## 重装机冲撞尘埃 + 火星、冲刺残影。→ screenshots/eval_fx.png
## 运行：tools/run_test.sh tests/fx_shots.gd --fixed-fps 60

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
	main.hide_hud = true
	main.place(Vector2(-400, 0))
	await physics_frame
	var w: Node = main.region
	var y := -40.0
	var x0 := 300.0
	var SF = load("res://scripts/fx/slash_fx.gd")
	var FX = load("res://scripts/fx/fx.gd")
	var BU = load("res://scripts/combat/bullet.gd")
	var SO = load("res://scripts/fx/soul_flow.gd")
	SF.spawn(w, Vector2(x0, y), -115.0, 70.0, 1, 34.0, false)
	SF.spawn(w, Vector2(x0 + 70, y), -165.0, 195.0, 1, 46.0, true)
	FX.flash(w, Vector2(x0 + 140, y), Color(2.8, 2.9, 3.0), 12.0)
	FX.sparks(w, Vector2(x0 + 140, y), Vector2(1, -0.3), 14, Color(1, 1, 1))
	BU.fire(w, Vector2(x0 + 180, y), Vector2(700, 0), 0, 1, null)
	BU.fire(w, Vector2(x0 + 230, y + 10), Vector2(-280, 0), 1, 1, null)
	FX.debris(w, Vector2(x0 + 290, y), Vector2(1, 0), 12, Color(1.25, 0.26, 0.32))
	FX.sparks(w, Vector2(x0 + 290, y), Vector2(1, 0), 12, Color(1, 0.6, 0.6))
	FX.ring(w, Vector2(x0 + 350, y), 22.0)
	var tgt := Node2D.new()
	tgt.set_script(null)
	var dummy = load("res://scripts/level/target_dummy.gd").new()
	dummy.position = Vector2(x0 + 470, 0)
	w.add_child(dummy)
	await physics_frame
	SO.spawn(w, Vector2(x0 + 380, y - 30), dummy)
	FX.dust(w, Vector2(x0 + 520, 0), 0.0, 14)
	FX.sparks(w, Vector2(x0 + 520, -10), Vector2.UP, 14, Color(2.2, 1.6, 0.8))
	main.place(Vector2(x0 + 240, 0))
	main.player.rig.spawn_ghost(w, 0.5)
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.linear_to_srgb()
	img.save_png("res://screenshots/eval_fx.png")
	print("fx saved")
	quit(0)
