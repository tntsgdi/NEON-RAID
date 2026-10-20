class_name Breakable
extends StaticBody2D
## 可破坏的墙 / 薄地板：只有重装机撞得开（墙：冲撞；地板：砸地）。
## 外观：带黄黑警示斜纹和裂缝的板子，一眼看出"这块能破"。

signal smashed(b: Breakable)

## "wall" = 冲撞撞碎；"floor" = 砸地砸穿
var kind := "wall"
var rect := Rect2()
var _shake := 0.0


static func make(parent: Node, r: Rect2, k: String) -> Breakable:
	var b := Breakable.new()
	b.kind = k
	b.rect = r
	b.position = r.position
	parent.add_child(b)
	return b


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = rect.size * 0.5
	add_child(cs)
	add_to_group("breakable")


func global_rect() -> Rect2:
	return Rect2(global_position, rect.size)


## 被撞 / 被砸但没破（不是重装机）：晃一下
func bump() -> void:
	_shake = 0.2


func smash(dir: Vector2) -> void:
	var fxp := get_parent()
	var c := global_rect().get_center()
	var n := int(clampf(rect.size.length() / 10.0, 4.0, 14.0))
	for i in n:
		var p := global_position + Vector2(randf() * rect.size.x, randf() * rect.size.y)
		var v := (dir * 220.0 + Vector2(randf_range(-120, 120), randf_range(-220, -40)))
		FxPart.spawn(fxp, p, "rect", Vector2(randf_range(4, 9), randf_range(3, 7)), v, Color(0.16, 0.15, 0.12), Color(1.6, 1.3, 0.3))
	Fx.debris(fxp, c, dir, 14, Color(1.6, 1.3, 0.3))
	Fx.sparks(fxp, c, dir, 16, Color(2.4, 1.9, 0.8))
	Audio.play("break", 0.0, 0.8)
	fxp.get_tree().call_group("game", "shockwave", c)
	smashed.emit(self)
	queue_free()


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(_shake - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	var off := Vector2(sin(_shake * 120.0) * 2.0 * (_shake / 0.2), 0)
	var r := Rect2(off, rect.size)
	draw_rect(r, Color(0.09, 0.085, 0.07))
	# 黄黑警示斜纹
	var step := 10.0
	var x := -r.size.y
	while x < r.size.x:
		var a := Vector2(maxf(x, 0.0), 0.0 if x >= 0.0 else -x)
		var b := Vector2(minf(x + r.size.y, r.size.x), r.size.y if x + r.size.y <= r.size.x else r.size.x - x)
		draw_line(off + a, off + b, Color(1.3, 1.05, 0.2, 0.35), 3.0)
		x += step
	# 裂缝
	var c := r.get_center()
	draw_polyline(PackedVector2Array([c + Vector2(-6, -r.size.y * 0.4), c + Vector2(-1, -4), c + Vector2(-4, 3), c + Vector2(3, r.size.y * 0.4)]), Color(1.6, 1.3, 0.3, 0.8), 1.0)
	draw_rect(r, Color(1.5, 1.2, 0.25, 0.9), false, 1.0)
