extends Node
## 灰盒测试：F4 在「手感测试场」（M1）和「战斗训练场」（M2）之间切换。
## 镜头视野按 640×360 设计。默认高清平滑渲染（四肢转动、高速移动不闪锯齿）；
## F3 切到 640×360 像素渲染（整数倍放大）对比。界面始终在最上层清晰绘制。

var world: Node2D
var level: Node2D
## 当前是手感测试场时指向它（测试用），否则为 null
var range_: TestRange
var arena: CombatArena
var player: Player
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
var _pixel_layer: CanvasLayer
var _viewport: SubViewport
var _tint: ColorRect


func _ready() -> void:
	var theme := _make_theme()

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
	box.add_child(_viewport)

	world = Node2D.new()
	world.name = "World"
	add_child(world)
	world.add_child(CityBackdrop.make())
	player = Player.new()
	player.fx_parent = world
	player.impact.connect(_on_impact)
	player.died.connect(_on_player_died, CONNECT_DEFERRED)
	world.add_child(player)
	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	world.add_child(camera)

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
	load_level("range")


func _make_theme() -> Theme:
	# 中文靠系统字体兜底；字体只在启动时建一次，之后不改
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "Source Han Sans SC"])
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 8
	return t


## kind："range"（手感测试场）或 "arena"（战斗训练场）
func load_level(kind: String) -> void:
	if level != null:
		world.remove_child(level)
		level.queue_free()
	range_ = null
	arena = null
	if kind == "arena":
		arena = CombatArena.new()
		arena.player = player
		level = arena
	else:
		range_ = TestRange.new()
		level = range_
	world.add_child(level)
	world.move_child(level, 1)  # 在远景之上、机体之下
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


func restart() -> void:
	TimeFx.reset()
	for b in get_tree().get_nodes_in_group("enemy_bullets") + get_tree().get_nodes_in_group("player_bullets"):
		b.queue_free()
	level.reset()
	place(level.start_pos())
	run_time = 0.0
	running = false
	finished = false


## 把机体放到某处并让镜头立刻跟上（测试也用它）
func place(pos: Vector2, vel := Vector2.ZERO) -> void:
	player.reset_at(pos)
	player.velocity = vel
	_look = 0.0
	camera.position = pos + Vector2(0, -40)
	camera.reset_smoothing()
	camera.reset_physics_interpolation()


func _on_impact(strength: float) -> void:
	_shake = maxf(_shake, strength * Tuning.v.shake)


## 血打空：0.3 秒内回检查点（不黑屏不加载），当前这一段重来
func _on_player_died() -> void:
	TimeFx.reset()
	level.on_player_died()
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		b.queue_free()
	get_tree().create_timer(0.25, true, false, true).timeout.connect(func(): place(level.checkpoint_for(player.last_floor_x)))


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		restart()
	if Input.is_action_just_pressed("tuning"):
		tuning_panel.visible = not tuning_panel.visible
	if Input.is_action_just_pressed("language"):
		I18n.toggle()
	if Input.is_action_just_pressed("render_mode"):
		set_pixel_mode(not pixel_mode)
	if Input.is_action_just_pressed("switch_level"):
		load_level("range" if arena != null else "arena")

	var x := player.global_position.x
	if not running and not finished and level.timer_started(player):
		running = true
	if running:
		run_time += delta
		if level.is_finished(player):
			running = false
			finished = true
			best = run_time if best < 0.0 else minf(best, run_time)
	if player.global_position.y > level.pit_y():
		place(level.checkpoint_for(player.last_floor_x))

	var slow := TimeFx.slowmo_active()
	_tint.color.a = lerpf(_tint.color.a, 0.14 if slow else 0.0, 1.0 - exp(-20.0 * delta / maxf(Engine.time_scale, 0.05)))
	hud.refresh(level.label(x), run_time, best, player.velocity.length(), finished,
		"HUD_MODE_PIXEL" if pixel_mode else "HUD_MODE_HD")
	hud.refresh_combat(player.hp, Player.MAX_HP, player.energy, Tuning.v.gun_energy, player.overclock_charge > 0.0)


## 镜头在物理帧里移动，和机体一起被物理插值，任何刷新率下都平滑
func _physics_process(delta: float) -> void:
	var T: Dictionary = Tuning.v
	_look = lerpf(_look, clampf(player.velocity.x * T.camera_look_ahead, -110.0, 110.0), 1.0 - exp(-3.0 * delta))
	var target := player.global_position + Vector2(_look, -40.0)
	camera.position.x = lerpf(camera.position.x, target.x, 1.0 - exp(-12.0 * delta))
	camera.position.y = lerpf(camera.position.y, target.y, 1.0 - exp(-7.0 * delta))
	if _shake > 0.05:
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
		_shake = move_toward(_shake, 0.0, 45.0 * delta)
	else:
		camera.offset = Vector2.ZERO
