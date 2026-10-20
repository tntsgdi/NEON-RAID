class_name CityBackdrop
extends Node2D
## 灰盒阶段的远景：两层视差的楼宇剪影，只为看清速度感，不是正式美术。

var tint := Color(0.06, 0.08, 0.12)
var height := 200.0
var seed_value := 1
var window_color := Color(0.25, 0.85, 0.95, 0.3)
var signs := false


static func make() -> Node2D:
	var root := Node2D.new()
	root.name = "Backdrop"
	# 背景压暗、低对比，免得被当成能站能蹬的墙
	root.add_child(_layer(Vector2(0.15, 0.3), Color(0.05, 0.06, 0.09), 260.0, 7))
	root.add_child(_layer(Vector2(0.4, 0.6), Color(0.075, 0.085, 0.12), 180.0, 3))
	return root


## 前景：比机体移动得更快的灯柱剪影（视差 1.5），高速跑过时一根根掠过
static func make_foreground() -> Node2D:
	var p := Parallax2D.new()
	p.name = "Foreground"
	p.scroll_scale = Vector2(1.5, 1.0)
	p.repeat_size = Vector2(420, 0)
	p.repeat_times = 4
	p.z_index = 20
	var poles := ForegroundPoles.new()
	p.add_child(poles)
	return p


static func _layer(scroll: Vector2, col: Color, h: float, s: int) -> Parallax2D:
	var p := Parallax2D.new()
	p.scroll_scale = scroll
	p.repeat_size = Vector2(800, 0)
	p.repeat_times = 4
	p.z_index = -10
	var b := CityBackdrop.new()
	b.tint = col
	b.height = h
	b.seed_value = s
	b.signs = scroll.x > 0.3
	p.add_child(b)
	return p


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var x := 0.0
	while x < 800.0:
		var w := rng.randf_range(30, 80)
		var h := rng.randf_range(height * 0.4, height)
		var r := Rect2(x, -h, w - 4, h + 200)
		draw_rect(r, tint)
		for i in rng.randi_range(3, 10):
			var wp := Vector2(x + rng.randf_range(4, w - 10), -h + rng.randf_range(8, h - 10))
			var lit := rng.randf() < 0.15
			draw_rect(Rect2(wp, Vector2(2, 1)), Color(0.6, 1.6, 1.8, 0.6) if lit else window_color)
		# 近景楼上挂竖排霓虹招牌（洋红 / 琥珀：只用于环境，不和青红敌我色混淆）
		if signs and rng.randf() < 0.45:
			var col: Color = Neon.MAGENTA if rng.randf() < 0.6 else Neon.AMBER
			var sp := Vector2(x + rng.randf_range(4, maxf(w - 14, 5)), -h + rng.randf_range(10, 40))
			var sh := rng.randf_range(24, 44)
			draw_rect(Rect2(sp, Vector2(8, sh)), Color(col.r * 0.05, col.g * 0.05, col.b * 0.05, 0.9))
			draw_rect(Rect2(sp, Vector2(8, sh)), Color(col, 0.9), false, 1.0)
			var gy := sp.y + 4
			while gy < sp.y + sh - 5:
				draw_rect(Rect2(sp.x + 2, gy, 4, 3), Color(col, 0.75))
				gy += 6
		x += w
