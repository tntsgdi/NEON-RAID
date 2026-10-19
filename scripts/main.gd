extends Node
## M1 灰盒手感测试场。
## 镜头视野按 640×360 设计。默认高清平滑渲染（四肢转动、高速移动不闪锯齿）；
## F3 切到 640×360 像素渲染（整数倍放大）对比。界面始终在最上层清晰绘制。

var world: Node2D
var range_: TestRange
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
	range_ = TestRange.new()
	world.add_child(range_)
	player = Player.new()
	player.fx_parent = world
	player.impact.connect(_on_impact)
	world.add_child(player)
	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.limit_left = -200
	camera.limit_right = 3500
	camera.limit_top = -700
	camera.limit_bottom = 120
	world.add_child(camera)

	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = theme
	ui_layer.add_child(ui)
	hud = Hud.new()
	ui.add_child(hud)
	tuning_panel = TuningPanel.new()
	tuning_panel.visible = false
	ui.add_child(tuning_panel)
	restart()


func _make_theme() -> Theme:
	# 中文靠系统字体兜底；字体只在启动时建一次，之后不改
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "Source Han Sans SC"])
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 8
	return t


func set_pixel_mode(on: bool) -> void:
	pixel_mode = on
	_pixel_layer.visible = on
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	world.reparent(_viewport if on else self, false)
	camera.make_current()
	camera.reset_physics_interpolation()


func restart() -> void:
	place(TestRange.START)
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


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		restart()
	if Input.is_action_just_pressed("tuning"):
		tuning_panel.visible = not tuning_panel.visible
	if Input.is_action_just_pressed("language"):
		I18n.toggle()
	if Input.is_action_just_pressed("render_mode"):
		set_pixel_mode(not pixel_mode)

	var x := player.global_position.x
	if not running and not finished and x > TestRange.START.x + 30.0:
		running = true
	if running:
		run_time += delta
		if x >= TestRange.FINISH_X:
			running = false
			finished = true
			best = run_time if best < 0.0 else minf(best, run_time)
	if player.global_position.y > TestRange.PIT_Y:
		place(range_.checkpoint_for(player.last_floor_x))

	hud.refresh(range_.section_key(x), run_time, best, player.velocity.length(), finished,
		"HUD_MODE_PIXEL" if pixel_mode else "HUD_MODE_HD")


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
