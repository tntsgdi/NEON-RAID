class_name AimLock
## 敌人开枪前的锁定框（学《碳酸危机》）：四个红色角括号从大到小、从斜到正收紧到目标身上，
## 收紧越多越亮，最后 15% 变白——这时还没打断它就要开火了。

## k = 锁定进度 0..1；r = 目标的受击矩形（画布本地坐标）
static func draw(ci: CanvasItem, r: Rect2, k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 2.0)
	var c := r.get_center()
	var h := r.size * 0.5 + Vector2(6, 6)
	h *= lerpf(2.4, 1.0, e)
	var rot := lerpf(PI * 0.25, 0.0, e)
	var white := k > 0.85
	var col := Color(2.2, 2.2, 2.2, 0.95) if white else Color(2.0, 0.3, 0.35, 0.35 + 0.55 * k)
	var arm := 4.0 + 3.0 * k
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := Vector2(h.x * sx, h.y * sy)
			var p0 := c + corner.rotated(rot)
			ci.draw_line(p0, p0 + Vector2(-arm * sx, 0).rotated(rot), col, 1.5, false)
			ci.draw_line(p0, p0 + Vector2(0, -arm * sy).rotated(rot), col, 1.5, false)
	if white:
		ci.draw_circle(c, 1.5, col)
