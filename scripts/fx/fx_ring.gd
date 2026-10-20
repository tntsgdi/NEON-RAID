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
	PixelFx.ring(self, Vector2.ZERO, radius * (0.3 + 0.7 * k), Color(0.62, 0.96, 1.0, 1.0 - k))
	if k < 0.4:
		PixelFx.ring(self, Vector2.ZERO, radius * (0.3 + 0.7 * k) - 1.0, Color(0.17, 0.77, 0.84, 0.8))
