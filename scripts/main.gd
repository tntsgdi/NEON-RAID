extends Node
## M1 灰盒手感测试场。
## 世界画在 640×360 的像素视口里（整数倍放大），界面在上层按高分辨率清晰绘制。

var viewport: SubViewport
var world: Node2D
var range_: TestRange
var player: Player
var camera: Camera2D
var hud: Hud
var tuning_panel: TuningPanel

var run_time := 0.0
var running := false
var finished := false
var best := -1.0
var _look := 0.0


func _ready() -> void:
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = _make_theme()
	add_child(ui)

	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ui.add_child(box)
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.snap_2d_transforms_to_pixel = true
	viewport.snap_2d_vertices_to_pixel = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.handle_input_locally = true
	box.add_child(viewport)

	world = Node2D.new()
	world.name = "World"
	viewport.add_child(world)
	world.add_child(CityBackdrop.make())
	range_ = TestRange.new()
	world.add_child(range_)
	player = Player.new()
	player.fx_parent = world
	world.add_child(player)
	camera = Camera2D.new()
	camera.limit_left = -200
	camera.limit_right = 3500
	camera.limit_top = -700
	camera.limit_bottom = 120
	world.add_child(camera)

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


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		restart()
	if Input.is_action_just_pressed("tuning"):
		tuning_panel.visible = not tuning_panel.visible
	if Input.is_action_just_pressed("language"):
		I18n.toggle()

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

	var T: Dictionary = Tuning.v
	_look = lerpf(_look, clampf(player.velocity.x * T.camera_look_ahead, -110.0, 110.0), 1.0 - exp(-3.0 * delta))
	var target := player.global_position + Vector2(_look, -40.0)
	camera.position.x = lerpf(camera.position.x, target.x, 1.0 - exp(-12.0 * delta))
	camera.position.y = lerpf(camera.position.y, target.y, 1.0 - exp(-7.0 * delta))

	hud.refresh(range_.section_key(x), run_time, best, player.velocity.length(), finished)
