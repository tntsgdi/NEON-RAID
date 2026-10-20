class_name FxStreak
extends Node2D
## 速度线（见 Fx.streak）：从机体身后往后拖、迅速变短变淡。

var length := 40.0
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.16:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := 1.0 - _t / 0.16
	draw_rect(Rect2(Vector2(minf(0.0, -length * k), 0), Vector2(absf(length * k), 1)), Color(0.62, 0.96, 1.0, 0.35 * k))
