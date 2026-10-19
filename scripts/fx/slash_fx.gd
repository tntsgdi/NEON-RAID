class_name SlashFx
extends Node2D
## 刀光：一段迅速变细、变淡的月牙。

var a0 := 0.0
var a1 := 0.0
var reach := 24.0
var heavy := false
var life := 0.13
var _t := 0.0


## from_deg / to_deg 是面朝右时的局部角度，这里按朝向换成世界角度
static func spawn(parent: Node, pos: Vector2, from_deg: float, to_deg: float, facing: int, reach_px: float, is_heavy: bool) -> void:
	if parent == null:
		return
	var fx := SlashFx.new()
	fx.position = pos
	fx.a0 = _world(from_deg, facing)
	fx.a1 = _world(to_deg, facing)
	fx.reach = reach_px
	fx.heavy = is_heavy
	fx.life = 0.17 if is_heavy else 0.13
	fx.z_index = 5
	parent.add_child(fx)


static func _world(deg: float, facing: int) -> float:
	var a := deg_to_rad(deg)
	return a if facing == 1 else PI - a


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := 1.0 - _t / life
	var n := 16
	var inner := reach * lerpf(0.55, 0.92, 1.0 - k)
	var pts := PackedVector2Array()
	for i in n + 1:
		pts.append(Vector2.from_angle(lerpf(a0, a1, float(i) / n)) * reach)
	var outer := pts.duplicate()
	for i in range(n, -1, -1):
		pts.append(Vector2.from_angle(lerpf(a0, a1, float(i) / n)) * inner)
	var col := Color(0.55, 1.0, 1.0, 0.75 * k) if not heavy else Color(0.85, 1.0, 1.0, 0.85 * k)
	draw_colored_polygon(pts, col)
	draw_polyline(outer, Color(1, 1, 1, k), 1.0)
