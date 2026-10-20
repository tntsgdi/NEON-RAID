class_name FxFlash
extends Node2D
## 闪光（见 Fx.flash）：一颗 HDR 光点加四角星芒，0.08 秒内缩小消失。

var color := Color.WHITE
var radius := 10.0
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.05:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	# 像素十字星：头 2 帧最大，之后收缩
	var k := 1.0 - _t / 0.05
	PixelFx.star(self, Vector2.ZERO, int(round(radius * 0.35 * (0.5 + 0.5 * k))), Color(color, 1.0))
