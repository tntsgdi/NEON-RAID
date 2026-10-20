extends SceneTree
## 丝滑探针：用一长串覆盖各种动作的脚本输入跑一遍，逐帧记录机体关键关节在屏幕上的位置（世界坐标减镜头），
## 找出单帧位移最大的跳变，附上当时的动作切换，方便逐个消掉。
## 运行：Godot --headless --path . -s tests/smooth_probe.gd --fixed-fps 60

const R := Vector2(1, 0)
const L := Vector2(-1, 0)
const NAMES := ["ground", "air", "dash", "slide", "wall"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var p = main.player
	main.place(Vector2(60, 0))
	await physics_frame
	var steps := [
		{"frames": 40, "move": R, "walk": true},          # 走
		{"frames": 120, "move": R},                       # 跑 → 疾驰
		{"frames": 30, "move": L},                        # 高速急停转身
		{"frames": 40, "move": R},
		{"frames": 1, "move": R, "press": ["jump"], "hold": ["jump"]},
		{"frames": 50, "move": R, "hold": ["jump"]},      # 跳、落地
		{"frames": 1, "move": R, "press": ["dash"]},
		{"frames": 30, "move": R},                        # 冲刺 → 跑
		{"frames": 1, "move": R, "press": ["slide"], "hold": ["slide"]},
		{"frames": 20, "move": R, "hold": ["slide"]},
		{"frames": 1, "move": R, "press": ["jump"], "hold": ["jump"]},   # 滑铲跳
		{"frames": 60, "move": R},
		{"frames": 20},                                    # 停下
		{"frames": 1, "press": ["slash"]}, {"frames": 14}, {"frames": 1, "press": ["slash"]}, {"frames": 14}, {"frames": 1, "press": ["slash"]}, {"frames": 50},
		{"frames": 10, "move": L, "walk": true},           # 慢速转身
		{"frames": 10, "move": R, "walk": true},
		{"frames": 1, "press": ["shoot"]}, {"frames": 30},
	]
	var log := await _record(main, p, Vector2(60, 0), steps)
	# 墙面行走：走上竖井、翻上平台
	log += await _record(main, p, Vector2(2000, 0), [{"frames": 260, "move": R, "walk": true}, {"frames": 30, "move": R}])
	# 空中下落接墙、墙上往下走、蹬开
	log += await _record(main, p, Vector2(2040, -200), [{"frames": 30, "move": R}, {"frames": 30, "move": Vector2(0, 1)}, {"frames": 1, "press": ["jump"], "hold": ["jump"]}, {"frames": 40}])

	var spikes := []
	for i in range(1, log.size()):
		var a: Dictionary = log[i - 1]
		var b: Dictionary = log[i]
		if a.seg != b.seg:
			continue
		for k in b.keys:
			if k == "_dbg" or not a.keys.has(k):
				continue
			var d: float = (b.keys[k] - a.keys[k]).length()
			var limit := 14.0 if k == "blade_tip" else 7.0
			if d > limit:
				spikes.append([d, k, i, "%s→%s" % [NAMES[a.state], NAMES[b.state]], b.slash])
	if OS.get_cmdline_user_args().has("--dump"):
		for i in [806, 807, 808, 809, 810, 323, 324, 325, 326, 327, 896, 897, 898, 899]:
			print(i, " ", NAMES[log[i].state], " pos ", log[i].pos.round(), " rig ", log[i].rig, " ", log[i].keys._dbg)
	spikes.sort_custom(func(x, y): return x[0] > y[0])
	print("frames=%d spikes=%d" % [log.size(), spikes.size()])
	var shown := {}
	for s in spikes:
		var tag: String = s[1] + " " + s[3]
		if shown.has(tag):
			continue
		shown[tag] = true
		print("  %5.1fpx  %-9s frame %4d  %s  slash=%d  pos %s→%s rig %s→%s" % [s[0], s[1], s[2], s[3], s[4], str(log[s[2] - 1].pos.round()), str(log[s[2]].pos.round()), str(log[s[2] - 1].rig), str(log[s[2]].rig)])
		if shown.size() >= 20:
			break
	quit(0)


func _record(main, p, start: Vector2, steps: Array) -> Array:
	main.place(start)
	await physics_frame
	var inp = load("res://scripts/player/scripted_input.gd").new(steps)
	main.controller.input = inp
	p.input = inp
	var log := []
	var seg := randi()
	while not inp.done:
		await physics_frame
		var screen := {}
		var cam: Vector2 = main.camera.global_position
		for k in p.rig.keys:
			screen[k] = p.global_position + p.rig.keys[k] - cam
		if OS.get_cmdline_user_args().has("--dump"):
			screen["_dbg"] = [p.rig._blade_angle, p.rig.hull_angle, p.rig._pelvis_y, p.rig.turn, p.velocity.round(), p._run_phase, p.rig._last_mode, p.rig.keys.knee_b.round(), p.rig.keys.toe_b.round()]
		log.append({"keys": screen, "state": p.state, "slash": p.slash_step, "seg": seg, "pos": p.global_position, "rig": [p.rig.position, p.rig.scale, p.rig.rotation, p.rig._pelvis_y]})
	return log
