class_name FxRing
extends Node2D
## 冲击环（见 Fx.ring）。

var radius := 18.0
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.2:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := _t / 0.2
	draw_arc(Vector2.ZERO, radius * (0.3 + 0.7 * k), 0.0, TAU, 24, Color(0.6, 1.0, 1.0, 1.0 - k), 2.0 * (1.0 - k) + 0.5, true)
