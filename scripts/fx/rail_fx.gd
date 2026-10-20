class_name RailFx
extends Node2D
## 电磁长矛的贯穿光束：3 像素宽的青色光柱 + 白芯，0.18 秒内从两头往中间收窄消失；沿途溅火花。

var a := Vector2.ZERO
var b := Vector2.ZERO
var power := 2
var _t := 0.0


static func spawn(parent: Node, from: Vector2, to: Vector2, p: int) -> void:
	var f := RailFx.new()
	f.a = from
	f.b = to
	f.power = p
	f.z_index = 8
	parent.add_child(f)
	var n := int(from.distance_to(to) / 40.0)
	for i in n:
		Fx.sparks(parent, from.lerp(to, (i + 0.5) / maxf(n, 1)), (to - from).normalized().rotated(randf_range(-0.6, 0.6)), 2, Color(1.0, 2.2, 2.4))


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.18:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := 1.0 - _t / 0.18
	var w := 1 + int(round((power - 1) * k))
	PixelFx.line(self, a, b, Color(PixelFx.CYAN[2], 0.6 * k), w + 2)
	PixelFx.line(self, a, b, Color(PixelFx.CYAN[3], k), w)
	PixelFx.line(self, a, b, Color(PixelFx.WHITE, k), 1)
	PixelFx.star(self, a, 3, PixelFx.CYAN[3])
	PixelFx.star(self, b, 4, PixelFx.WHITE)
