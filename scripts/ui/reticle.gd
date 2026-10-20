class_name Reticle
extends Node2D
## 软锁定准星：套在锁定目标外面的四个角括号。
## 白色 + "E" = 在夺壳距离内（白色是"可夺壳"的颜色）；灰色 = 只是射击 / 挥刀的锁定目标。

var target: Node2D
var in_range := false
var _t := 0.0
var _pos := Vector2.ZERO
var _size := Vector2(20, 30)
var _shown := 0.0


func _process(delta: float) -> void:
	_t += delta
	if is_instance_valid(target):
		var r: Rect2 = target.hurt_rect()
		# 准星从上一个目标滑过去，而不是瞬间跳过去
		_pos = _pos.lerp(r.get_center(), 1.0 - exp(-25.0 * delta)) if _shown > 0.0 else r.get_center()
		_size = _size.lerp(r.size + Vector2(10, 10), 1.0 - exp(-25.0 * delta))
		_shown = minf(_shown + delta * 8.0, 1.0)
	else:
		_shown = maxf(_shown - delta * 8.0, 0.0)
	queue_redraw()


func _draw() -> void:
	if _shown <= 0.0:
		return
	var col := Color(2.0, 2.1, 2.2, _shown) if in_range else Color(0.6, 0.65, 0.7, 0.6 * _shown)
	var pulse := 1.0 + (0.08 * sin(_t * 10.0) if in_range else 0.0)
	var h := _size * 0.5 * pulse
	var arm := 5.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := _pos + Vector2(h.x * sx, h.y * sy)
			draw_line(c, c - Vector2(arm * sx, 0), col, 1.5, true)
			draw_line(c, c - Vector2(0, arm * sy), col, 1.5, true)
	if in_range:
		var font := ThemeDB.fallback_font
		draw_string(font, _pos + Vector2(h.x + 3, -h.y + 4), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)
