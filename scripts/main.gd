extends Node
## 灰盒测试：F4 在「手感测试场」（M1）、「战斗训练场」（M2）、「夺壳训练场」（M3）之间循环切换。
## 意识控制器（controller）决定当前操控哪具机体；镜头、HUD、掉坑、计时都跟着 controller.current 走。
## 镜头视野按 640×360 设计。默认高清平滑渲染（四肢转动、高速移动不闪锯齿）；
## F3 切到 640×360 像素渲染（整数倍放大）对比。界面始终在最上层清晰绘制。

var world: Node2D
var level: Node2D
## 当前是手感测试场时指向它（测试用），否则为 null
var range_: TestRange
var arena: CombatArena
var possess_range: PossessRange
## 第 1 关的区域（001–005）
var region: Region
var region_index := -1
var title: TitleMenu
## 拍展示截图时隐藏界面
var hide_hud := false
## 区域打完后自动进下一个区域的倒计时（真实时间，< 0 = 没在倒计时）
var _advance_t := -1.0
var _last_cp := Vector2.INF
## 整关累计（005 打完出总评）
var _total := {"time": 0.0, "hits": 0, "deflect": 0, "stomp": 0}
## 基础机体（R-0 原型机身）
var player: Player
var controller: Consciousness
var camera: Camera2D
var hud: Hud
var tuning_panel: TuningPanel
var pixel_mode := false

var run_time := 0.0
var running := false
var finished := false
var best := -1.0
var _look := 0.0
var _shake := 0.0
## 方向性的镜头冲击（沿挥刀/受击方向推一下再弹回）
var _kick := Vector2.ZERO
var _pixel_layer: CanvasLayer
var _viewport: SubViewport
var _tint: ColorRect
var _tips := {}
var _post: ShaderMaterial
var _ca := 0.0
var _shock_t := 1.0
var _rain: CPUParticles2D
var _splash: CPUParticles2D
var _env: Environment
var _wind: AudioStreamPlayer
var _zoom_pulse := 0.0
var settings_panel: SettingsPanel
## 本局技巧统计（评级用）
var stats := {"hits": 0, "deflect": 0, "parry": 0, "perfect_dodge": 0}
var _last_hp := 3
var _foreground: Node2D


func _ready() -> void:
	add_to_group("game")
	var theme := _make_theme()
	_setup_glow()

	# 像素模式用的 640×360 视口（默认隐藏）
	_pixel_layer = CanvasLayer.new()
	_pixel_layer.layer = -1
	_pixel_layer.visible = false
	add_child(_pixel_layer)
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pixel_layer.add_child(box)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(640, 360)
	_viewport.snap_2d_transforms_to_pixel = true
	_viewport.snap_2d_vertices_to_pixel = true
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.use_hdr_2d = true
	box.add_child(_viewport)

	world = Node2D.new()
	world.name = "World"
	add_child(world)
	var backdrop := CityBackdrop.make()
	world.add_child(backdrop)
	player = Player.new()
	player.fx_parent = world
	player.impact.connect(_on_impact)
	player.skill.connect(func(kind): stats[kind] = stats.get(kind, 0) + 1)
	player.sprint_started.connect(func(): _zoom_pulse = 0.05)
	_wind = AudioStreamPlayer.new()
	var wind: AudioStreamWAV = load("res://assets/sfx/wind.wav")
	wind.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wind.loop_end = wind.data.size() / 2
	_wind.stream = wind
	_wind.bus = &"SFX"
	_wind.volume_db = -60.0
	add_child(_wind)
	_wind.play()
	player.died.connect(_on_player_died, CONNECT_DEFERRED)
	world.add_child(player)
	_rain = _make_rain()
	world.add_child(_rain)
	_splash = _make_splash()
	world.add_child(_splash)
	# 旧的"复制骨架图形画倒影"已停用：像素部件按世界像素格绘制，不能再整体翻转压扁；
	# 积水倒影改由场景的屏幕空间反射统一处理（见 scripts/level/street_set.gd）
	_foreground = CityBackdrop.make_foreground()
	world.add_child(_foreground)
	Neon.add_light(player, Neon.CYAN, 0.2, 1.1, Vector2(0, -18))
	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	world.add_child(camera)
	controller = Consciousness.new()
	add_child(controller)
	controller.setup(player, world)
	controller.lost.connect(_on_lost)
	controller.shell_changed.connect(_on_shell_changed)

	# 屏幕后处理（色差、冲击波、暗角）：在世界之上、界面之下
	var post_layer := CanvasLayer.new()
	post_layer.layer = 5
	add_child(post_layer)
	var post_rect := ColorRect.new()
	post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post = ShaderMaterial.new()
	_post.shader = load("res://shaders/post.gdshader")
	post_rect.material = _post
	post_layer.add_child(post_rect)

	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = theme
	ui_layer.add_child(ui)
	# 神经超频时画面泛青
	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.color = Color(0.2, 0.9, 1.0, 0.0)
	ui.add_child(_tint)
	hud = Hud.new()
	ui.add_child(hud)
	tuning_panel = TuningPanel.new()
	tuning_panel.visible = false
	ui.add_child(tuning_panel)
	title = TitleMenu.new()
	ui.add_child(title)
	title.chosen.connect(_on_title_chosen)
	settings_panel = SettingsPanel.new()
	settings_panel.visible = false
	settings_panel.to_title.connect(open_title)
	ui.add_child(settings_panel)
	process_mode = Node.PROCESS_MODE_ALWAYS
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	# 正式像素美术：默认 640×360 原生像素渲染（整数倍放大）；F3 切回高清平滑渲染做对比
	set_pixel_mode(true)
	# 测试直接进手感测试场；正式运行：背后摆着区域 001，先打开标题菜单
	if Tuning.is_test_run():
		load_level("range")
	else:
		load_level("d13", 0)
		open_title()


## 打开标题菜单（游戏暂停）
func open_title() -> void:
	if settings_panel.is_open:
		settings_panel.toggle()
	_advance_t = -1.0
	title.open()
	get_tree().paused = true
	Music.intensity = 0.25


func _on_title_chosen(action: String, arg: int) -> void:
	match action:
		"continue":
			title.close()
			get_tree().paused = false
			var r := int(Progress.data.region)
			load_level("d13", r)
			var cp: Array = Progress.data.checkpoint
			if not cp.is_empty():
				place(Vector2(cp[0], cp[1]))
				_last_cp = Vector2(cp[0], cp[1])
		"region":
			title.close()
			get_tree().paused = false
			if arg == 0:
				_total = {"time": 0.0, "hits": 0, "deflect": 0, "stomp": 0}
			load_level("d13", arg)
		"training":
			title.close()
			get_tree().paused = false
			load_level(["range", "arena", "possess"][arg])
		"settings":
			settings_panel.toggle()
		"quit":
			get_tree().quit()


## HDR 辉光：只有超过 1.0 的颜色（Neon.*_HOT / *_GLOW）会发光，霓虹真正亮起来
func _setup_glow() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CANVAS
	e.glow_enabled = true
	e.glow_intensity = 0.22
	e.glow_strength = 1.0
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.0
	e.glow_hdr_scale = 2.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for lv in 7:
		# 像素画面：只用小半径的辉光（1–2 级），发光像素周围一圈，不糊成大光晕
		e.set_glow_level(lv, lv in [1, 2])
	env.environment = e
	add_child(env)
	_env = e


## 雨：落在机体身后，跟着镜头走（粒子留在世界坐标里）
func _make_rain() -> CPUParticles2D:
	var r := CPUParticles2D.new()
	r.amount = 220
	r.lifetime = 0.7
	# 像素雨丝：1 像素宽、5 像素长，雨点在原生像素格上落下
	var img := Image.create(1, 5, false, Image.FORMAT_RGBA8)
	for y in 5:
		img.set_pixel(0, y, Color(0.6, 0.75, 0.9, 0.35 + 0.13 * y))
	r.texture = ImageTexture.create_from_image(img)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	r.emission_rect_extents = Vector2(420, 10)
	r.direction = Vector2(-0.18, 1.0)
	r.spread = 2.0
	r.gravity = Vector2.ZERO
	r.initial_velocity_min = 700.0
	r.initial_velocity_max = 900.0
	r.particle_flag_align_y = true
	r.scale_amount_min = 1.0
	r.scale_amount_max = 1.0
	r.color = Color(1, 1, 1, 0.5)
	r.local_coords = false
	r.z_index = -5
	return r


## 雨滴落地的小水花：沿着镜头下方的地面一排随机溅起
func _make_splash() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 60
	p.lifetime = 0.25
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(380, 0.5)
	p.direction = Vector2(0, -1)
	p.spread = 50.0
	p.gravity = Vector2(0, 500)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	p.color = Color(0.55, 0.85, 1.0, 0.35)
	p.local_coords = false
	p.z_index = 3
	return p


## 冲击波（招架、弹反、打碎时）：world_pos 是世界坐标
func shockwave(world_pos: Vector2) -> void:
	var screen := (camera.get_canvas_transform() * world_pos) if not pixel_mode else (_viewport.canvas_transform * world_pos)
	var size := Vector2(get_viewport().get_visible_rect().size)
	if pixel_mode:
		size = Vector2(640, 360)
	_post.set_shader_parameter("shock_center", screen / size)
	_shock_t = 0.0


## 色差脉冲（重击、受伤、神经超频）
## 环境文字（Billboard 走近时调用）
func env_text(text: String) -> void:
	hud.terminal(text)


## 其他机体（重装机等）也能震屏
func impact(strength: float, dir: Vector2) -> void:
	_on_impact(strength, dir)


func aberrate(amount: float) -> void:
	_ca = maxf(_ca, amount)


func _make_theme() -> Theme:
	# 中文靠系统字体兜底；字体只在启动时建一次，之后不改
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "Source Han Sans SC"])
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 8
	return t


## kind："range"（手感测试场）、"arena"（战斗训练场）或 "possess"（夺壳训练场）
func load_level(kind: String, index := 0) -> void:
	# 先回到基础机体：夺来的机体属于旧场地，场地移除前要先让意识离开它
	controller.return_to_base(player.global_position)
	if level != null:
		world.remove_child(level)
		level.queue_free()
	range_ = null
	arena = null
	possess_range = null
	region = null
	region_index = -1
	_advance_t = -1.0
	_last_cp = Vector2.INF
	if kind == "d13":
		region = Region.new(index)
		region.player = player
		region.tip.connect(func(k): hud.show_tip(tr(k)))
		region_index = index
		level = region
	elif kind == "possess":
		possess_range = PossessRange.new()
		possess_range.player = player
		level = possess_range
	elif kind == "arena":
		arena = CombatArena.new()
		arena.player = player
		arena.training_clear.connect(_on_training_clear)
		arena.survival_over.connect(func(w): hud.show_card(tr("SURV_OVER") % [w, arena.best_survival], ""))
		level = arena
	else:
		range_ = TestRange.new()
		level = range_
	world.add_child(level)
	world.move_child(level, 1)  # 在远景之上、机体之下
	# 第 1 关的区域有自己的正式像素背景；训练场继续用灰盒远景
	world.get_node("Backdrop").visible = region == null
	_foreground.visible = region == null
	var lim: Rect2 = level.limits()
	camera.limit_left = int(lim.position.x)
	camera.limit_top = int(lim.position.y)
	camera.limit_right = int(lim.end.x)
	camera.limit_bottom = int(lim.end.y)
	best = -1.0
	restart()


func set_pixel_mode(on: bool) -> void:
	pixel_mode = on
	_pixel_layer.visible = on
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	world.reparent(_viewport if on else self, false)
	camera.make_current()
	camera.reset_physics_interpolation()
	# 像素画面不用渐变暗角：在很暗的雨夜画面上，8 位显示会把它的渐变显示成一圈可见的台阶
	_post.set_shader_parameter("vignette", 0.0 if on else 0.22)


func restart() -> void:
	TimeFx.reset()
	for b in get_tree().get_nodes_in_group("enemy_bullets") + get_tree().get_nodes_in_group("player_bullets"):
		b.queue_free()
	level.reset()
	place(level.start_pos())
	run_time = 0.0
	running = false
	finished = false
	for k in stats:
		stats[k] = 0
	_last_hp = player.hp


## 回到基础机体、放到某处并让镜头立刻跟上（测试也用它）
func place(pos: Vector2, vel := Vector2.ZERO) -> void:
	controller.return_to_base(pos)
	player.velocity = vel
	if level != null and level.has_method("on_checkpoint"):
		level.on_checkpoint()
	_look = 0.0
	camera.position = pos + Vector2(0, -40)
	camera.reset_smoothing()
	camera.reset_physics_interpolation()


## 第一次遇到某个机制时弹一条大字提示（每次启动游戏各提示一次）
func _update_tips() -> void:
	if controller.lock_in_range:
		_tip("TIP_POSSESS")
	if arena == null:
		if range_ == null:
			return
		if not _tips.has("TIP_RANGE"):
			_tip("TIP_RANGE")
		elif range_ != null and player.global_position.x > 1900.0 and player.global_position.x < 2100.0:
			_tip("TIP_WALL")
		return
	if arena.wave >= 1:
		_tip("TIP_ARENA")
	for e in arena.enemies:
		if not is_instance_valid(e):
			continue
		if e.kind == "rusher" and e.state == EnemyBot.State.WINDUP:
			_tip("TIP_RUSHER")
		elif e.shielded and e.has_shield() and absf(e.global_position.x - player.global_position.x) < 160.0:
			_tip("TIP_SHIELD")
	if TimeFx.slowmo_active():
		_tip("TIP_OVERCLOCK")


func _tip(key: String) -> void:
	if _tips.has(key):
		return
	_tips[key] = true
	hud.show_tip(tr(key))


func _on_impact(strength: float, dir: Vector2) -> void:
	var s: float = strength * Tuning.v.shake * Settings.v.shake
	if strength >= 5.0:
		aberrate(strength * 0.9)
	if dir == Vector2.ZERO:
		_shake = maxf(_shake, s)
	else:
		_kick += dir.normalized() * s
		_shake = maxf(_shake, s * 0.3)


## 换了机体：第一次换到某种机体时提示它的操作
func _on_shell_changed(shell: Node2D) -> void:
	_look = 0.0
	if shell is DroneBot:
		_tip("TIP_SHELL_DRONE")
	elif shell is EnemyBot:
		_tip("TIP_SHELL_BOT")
	elif shell is HeavyBot:
		_tip("TIP_SHELL_HEAVY")
	elif shell is Wisp:
		_tip("TIP_WISP")


## 光球没来得及投射出去：回检查点，用基础机体重来
func _on_lost() -> void:
	TimeFx.reset()
	var x: float = controller.current.global_position.x if is_instance_valid(controller.current) else player.last_floor_x
	place.call_deferred(level.checkpoint_for(x))


## 血打空：0.3 秒内回检查点（不黑屏不加载），当前这一段重来
func _on_player_died() -> void:
	TimeFx.reset()
	level.on_player_died()
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		b.queue_free()
	get_tree().create_timer(0.25, true, false, true).timeout.connect(func(): place(level.checkpoint_for(player.last_floor_x)))


## 区域里每帧：走过新检查点就存档；区域打完后倒计时进下一个区域
func _region_tick(delta: float, body: Node2D) -> void:
	var real := delta / maxf(Engine.time_scale, 0.0001)
	if _advance_t >= 0.0:
		_advance_t -= real
		if _advance_t < 0.0:
			if region_index < 4:
				load_level("d13", region_index + 1)
			else:
				open_title()
		return
	var on_floor: bool = body.is_on_floor() if body.has_method("is_on_floor") else false
	if on_floor:
		var cp: Vector2 = level.checkpoint_for(body.global_position.x)
		if cp != _last_cp:
			if _last_cp != Vector2.INF and cp.x > _last_cp.x:
				hud.toast(tr("HUD_CHECKPOINT"))
			_last_cp = cp
			if cp != level.start_pos() or region_index > 0:
				Progress.reach_checkpoint(region_index, cp)


func _grade(par: float) -> String:
	var score: float = 1000.0 - maxf(0.0, run_time - par) * 6.0 - stats.hits * 150.0 + stats.deflect * 80.0 + stats.parry * 100.0 + stats.perfect_dodge * 60.0 + stats.get("stomp", 0) * 40.0
	return "S" if score >= 1200.0 else ("A" if score >= 950.0 else ("B" if score >= 700.0 else "C"))


## 区域打完：小结算卡（用时、受击、弹反、踩头、评级），存档，2.6 秒后自动进下一个区域；005 打完出整关总评
func _on_region_clear() -> void:
	var record: bool = Progress.clear_region(region_index, run_time)
	_total.time += run_time
	_total.hits += stats.hits
	_total.deflect += stats.deflect + stats.parry
	_total.stomp += stats.get("stomp", 0)
	var grade := _grade(float(region.data.get("par", 50.0)))
	var body_text := tr("REGION_BODY") % [Hud._fmt(run_time), stats.hits, stats.deflect + stats.parry, stats.get("stomp", 0)]
	if record:
		body_text += "\n" + tr("REGION_RECORD")
	hud.show_card(tr("REGION_CLEAR") % [tr(region.data.name), grade], body_text)
	_advance_t = 2.8
	if region_index == 4:
		hud.show_card(tr("DEMO_CLEAR"), tr("DEMO_BODY") % [Hud._fmt(_total.time), _total.hits, _total.deflect, _total.stomp])
		_advance_t = 6.0


## 训练三波打完：弹评级卡，然后进入生存模式
func _on_training_clear() -> void:
	# 45 秒内打完不扣时间分；S 级大约要求一局里 3–4 次弹反/招架且不太挨打
	var score: float = 1000.0 - maxf(0.0, run_time - 45.0) * 6.0 - stats.hits * 150.0 + stats.deflect * 80.0 + stats.parry * 100.0 + stats.perfect_dodge * 60.0
	var grade := "S" if score >= 1200.0 else ("A" if score >= 950.0 else ("B" if score >= 700.0 else "C"))
	hud.show_card(tr("RATE_TITLE") % grade, tr("RATE_BODY") % [Hud._fmt(run_time), stats.hits, stats.deflect, stats.parry, stats.perfect_dodge])
	arena.start_survival()


func _process(delta: float) -> void:
	hud.visible = not title.visible and not hide_hud
	if Input.is_action_just_pressed("settings") and (not title.visible or settings_panel.is_open):
		settings_panel.toggle()
		get_tree().paused = settings_panel.is_open or title.visible
		TimeFx.reset()
	if get_tree().paused:
		return
	if player.hp < _last_hp:
		stats.hits += _last_hp - player.hp
	_last_hp = player.hp
	if Input.is_action_just_pressed("restart"):
		restart()
	if Input.is_action_just_pressed("tuning"):
		tuning_panel.visible = not tuning_panel.visible
	if Input.is_action_just_pressed("language"):
		I18n.toggle()
	if Input.is_action_just_pressed("render_mode"):
		set_pixel_mode(not pixel_mode)
	if Input.is_action_just_pressed("hitboxes"):
		Hurtboxes.show_debug = not Hurtboxes.show_debug
	if Input.is_action_just_pressed("switch_level"):
		load_level("arena" if range_ != null else ("possess" if arena != null else "range"))

	var body := _body()
	var x := body.global_position.x
	if not running and not finished and level.timer_started(body):
		running = true
	if running:
		run_time += delta
		if level.is_finished(body):
			running = false
			finished = true
			best = run_time if best < 0.0 else minf(best, run_time)
			if region != null:
				_on_region_clear()
	if region != null:
		_region_tick(delta, body)
	if body.global_position.y > level.pit_y():
		# 掉进深渊：基础机体回检查点；夺来的机体或光球掉下去也一样（不再弹光球）
		place(level.checkpoint_for(player.last_floor_x if body == player else x))
		body = player

	# 配乐：战斗训练场有敌人时战斗层全开，清场后回落；手感测试场高速跑动时稍微加一点
	if region != null:
		var near := 0
		for e in get_tree().get_nodes_in_group("enemy"):
			if e.alive() and e.global_position.distance_to(body.global_position) < 420.0:
				near += 1
		Music.intensity = 1.0 if near >= 3 or (near > 0 and player.hp == 1) else (0.75 if near > 0 else 0.35)
	elif possess_range != null:
		Music.intensity = 0.7 if x > 900.0 else 0.4
	elif arena != null:
		if arena.enemies.is_empty():
			Music.intensity = 0.3 if arena.cleared else 0.45
		elif arena.wave >= 3 or arena.enemies.size() >= 3 or player.hp == 1:
			Music.intensity = 1.0
		else:
			Music.intensity = 0.7
	else:
		Music.intensity = 0.35 if absf(player.velocity.x) > Tuning.v.run_speed * 0.9 else 0.0
	_update_tips()
	# 后处理：色差和冲击波按真实时间衰减
	var real := delta / maxf(Engine.time_scale, 0.0001)
	_ca = move_toward(_ca, 2.5 if TimeFx.slowmo_active() else 0.0, real * 30.0)
	_shock_t = minf(_shock_t + real * 2.2, 1.0)
	_post.set_shader_parameter("ca", _ca * Settings.v.aberration)
	var bvel: Vector2 = body.velocity if "velocity" in body else Vector2.ZERO
	var fast := clampf((absf(bvel.x) - Tuning.v.run_speed) / maxf(Tuning.v.sprint_speed - Tuning.v.run_speed, 1.0), 0.0, 1.0)
	_post.set_shader_parameter("speed_blur", fast * (1.0 if body == player and player.sprinting else 0.5))
	# 风声：越快越响
	var wind_k := clampf(bvel.length() / Tuning.v.sprint_speed, 0.0, 1.3)
	_wind.volume_db = linear_to_db(maxf(pow(wind_k, 2.0) * 0.9, 0.0001)) - 4.0
	_env.glow_intensity = 0.22 * Settings.v.glow
	_rain.emitting = Settings.v.rain > 0.5
	_splash.emitting = Settings.v.rain > 0.5
	_post.set_shader_parameter("shock_t", _shock_t)
	var vp := get_viewport().get_visible_rect().size
	_post.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	# 前景灯柱只在高速时淡入，平时不挡视线
	var spd := clampf((absf(bvel.x) / Tuning.v.run_speed - 0.6) / 0.5, 0.0, 1.0)
	_foreground.modulate.a = lerpf(_foreground.modulate.a, spd, 1.0 - exp(-4.0 * real))
	var slow := TimeFx.slowmo_active()
	_tint.color.a = lerpf(_tint.color.a, 0.14 if slow else 0.0, 1.0 - exp(-20.0 * delta / maxf(Engine.time_scale, 0.05)))
	hud.refresh(level.label(x), run_time, best, bvel.length(), finished,
		"HUD_MODE_PIXEL" if pixel_mode else "HUD_MODE_HD", tuning_panel.visible)
	hud.possess_k = 0.0 if body is Wisp else controller.cooldown / Consciousness.COOLDOWN
	if body == player:
		hud.set_shell(tr("SHELL_STRIDER"))
		hud.refresh_combat(player.hp, Player.MAX_HP, player.energy, Tuning.v.gun_energy, player.overclock_charge > 0.0)
	elif body is EnemyBot:
		hud.set_shell(tr("SHELL_BOT"))
		hud.refresh_combat(body.hp, EnemyBot.MAX_HP, 0.0, 0.0, false)
	elif body is DroneBot:
		hud.set_shell(tr("SHELL_DRONE"))
		hud.refresh_combat(body.hp, DroneBot.MAX_HP, 0.0, 0.0, false)
	elif body is HeavyBot:
		hud.set_shell(tr("SHELL_HEAVY"))
		hud.refresh_combat(body.hp, HeavyBot.CONTROL_HP, 0.0, 0.0, false)
	else:
		hud.set_shell(tr("SHELL_WISP"))
		hud.refresh_combat(0, 0, 0.0, 0.0, false)


## 当前被意识控制的机体
func _body() -> Node2D:
	return controller.current if is_instance_valid(controller.current) else player


## 镜头在物理帧里移动，和机体一起被物理插值，任何刷新率下都平滑
func _physics_process(delta: float) -> void:
	var T: Dictionary = Tuning.v
	var body := _body()
	var bvel: Vector2 = body.velocity if "velocity" in body else Vector2.ZERO
	_look = lerpf(_look, clampf(bvel.x * T.camera_look_ahead, -170.0, 170.0), 1.0 - exp(-5.0 * delta))
	# 镜头偏上：地面线落在画面约 75% 高度，少看一点空荡的地块
	var target := body.global_position + Vector2(_look, -86.0)
	if is_instance_valid(controller.flow) and not controller.flow.done:
		target = controller.flow.global_position + Vector2(0, -22.0)
	camera.position.x = lerpf(camera.position.x, target.x, 1.0 - exp(-12.0 * delta))
	camera.position.y = lerpf(camera.position.y, target.y, 1.0 - exp(-7.0 * delta))
	# 越快镜头拉得越远：跑档最多拉远 6%，疾驰档 12%；进入疾驰的一刻先猛缩一下再拉远
	var speed_k := clampf(absf(bvel.x) / T.run_speed - 0.5, 0.0, 1.0)
	var want_zoom := 1.0 - 0.04 * speed_k
	if body == player:
		want_zoom -= (0.04 if player.sprinting else 0.0) + (0.02 if player.state == Player.State.DASH else 0.0)
	_zoom_pulse = move_toward(_zoom_pulse, 0.0, delta * 0.25)
	camera.zoom = Vector2.ONE * (lerpf(camera.zoom.x - _zoom_pulse * 0.0, want_zoom, 1.0 - exp(-3.0 * delta)) + _zoom_pulse)
	_kick = _kick.lerp(Vector2.ZERO, 1.0 - exp(-18.0 * delta))
	var jitter := Vector2.ZERO
	if _shake > 0.05:
		jitter = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
		_shake = move_toward(_shake, 0.0, 45.0 * delta)
	camera.offset = jitter + _kick
	_rain.global_position = camera.global_position + Vector2(60, -230)
	_splash.global_position = Vector2(camera.global_position.x, 0.0)
