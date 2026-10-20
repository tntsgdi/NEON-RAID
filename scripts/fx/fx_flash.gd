class_name FxFlash
extends Node2D
## 闪光（见 Fx.flash）：一颗 HDR 光点加四角星芒，0.08 秒内缩小消失。

var color := Color.WHITE
var radius := 10.0
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.08:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := 1.0 - _t / 0.08
	var r := radius * (0.4 + 0.6 * k)
	draw_circle(Vector2.ZERO, r * 0.25, Color(color.r * 0.7, color.g * 0.7, color.b * 0.7))
	draw_circle(Vector2.ZERO, r * 0.7, Color(color, 0.25 * k))
	for a in [0.0, PI * 0.5]:
		var d := Vector2.from_angle(a + 0.4) * r * 1.4
		draw_line(-d, d, Color(color, k), 1.5, true)
