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
var _deny := 0.0
## 夺壳范围圈的圆心（当前机体），失败时显示
var origin_node: Node2D
## 夺壳冷却剩余比例（1 = 刚夺完，0 = 可以再夺）
var cooldown_k := 0.0


## 按 E 但没有能夺的目标：准星抖一下，画出 220 像素的夺壳范围
func deny() -> void:
	_deny = 0.5


func _process(delta: float) -> void:
	_t += delta
	_deny = maxf(_deny - delta, 0.0)
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
	if _deny > 0.0 and is_instance_valid(origin_node):
		var c := origin_node.global_position + Vector2(0, -18)
		var a := _deny / 0.5
		var seg := 48
		for i in seg:
			if i % 2 == 0:
				var a0 := TAU * i / seg
				draw_arc(c, Consciousness.POSSESS_RANGE, a0, a0 + TAU / seg, 3, Color(1.6, 1.7, 1.8, 0.5 * a), 1.0, false)
	if _shown <= 0.0:
		return
	var ready := cooldown_k <= 0.0
	var col := Color(1.15, 1.2, 1.25, _shown) if in_range and ready else Color(0.6, 0.65, 0.7, 0.6 * _shown)
	var pulse := 1.0 + (0.08 * sin(_t * 10.0) if in_range and ready else 0.0)
	var h := _size * 0.5 * pulse
	var p := _pos
	if _deny > 0.0:
		p += Vector2(sin(_t * 90.0) * 3.0 * (_deny / 0.5), 0)  # 夺不了：准星抖一下
	var arm := 5.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := p + Vector2(h.x * sx, h.y * sy)
			draw_line(c, c - Vector2(arm * sx, 0), col, 1.5, false)
			draw_line(c, c - Vector2(0, arm * sy), col, 1.5, false)
	# 冷却进度：外圈一道弧从空转到满，满了 E 才亮
	if not ready:
		var r := maxf(h.x, h.y) + 5.0
		draw_arc(p, r, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - cooldown_k), 32, Color(0.5, 1.6, 1.9, 0.9 * _shown), 2.0, false)
		draw_arc(p, r, -PI * 0.5 + TAU * (1.0 - cooldown_k), PI * 1.5, 32, Color(0.3, 0.35, 0.4, 0.4 * _shown), 1.0, false)
	if in_range:
		# 键帽："E"
		var font := ThemeDB.fallback_font
		var kp := p + Vector2(h.x + 4, -h.y - 2)
		draw_rect(Rect2(kp, Vector2(12, 13)), Color(0.02, 0.03, 0.05, 0.8 * _shown))
		draw_rect(Rect2(kp, Vector2(12, 13)), col, false, 1.0)
		draw_string(font, kp + Vector2(2.5, 11), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
