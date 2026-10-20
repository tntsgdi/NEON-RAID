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
	draw_line(Vector2.ZERO, Vector2(-length * k, 0), Color(0.7, 1.5, 1.8, 0.4 * k), 1.0, true)
