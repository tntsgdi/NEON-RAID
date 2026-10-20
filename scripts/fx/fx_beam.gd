class_name FxBeam
extends Node2D
## 夺壳光束：意识从旧机体射向新机体的一道光，0.18 秒内从起点往终点收拢消失。

var a := Vector2.ZERO
var b := Vector2.ZERO
var _t := 0.0


static func spawn(parent: Node, from: Vector2, to: Vector2) -> void:
	if parent == null:
		return
	var f := FxBeam.new()
	f.a = from
	f.b = to
	f.z_index = 8
	parent.add_child(f)


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.18:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := _t / 0.18
	var start := a.lerp(b, k * k)
	draw_line(start, b, Color(0.4, 1.4, 1.7, 0.35 * (1.0 - k)), 6.0, true)
	draw_line(start, b, Color(1.6, 2.6, 2.8, 1.0 - k), 2.0, true)
	draw_circle(b, 4.0 * (1.0 - k), Neon.WHITE_HOT)
