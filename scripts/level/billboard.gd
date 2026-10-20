class_name Billboard
extends Node2D
## 环境文字的载体：墙上一块小小的像素终端屏（暗底、滚动的字形、一个闪烁的光标）。
## 机体走近时，屏幕亮起，文字以"截获"的形式清晰地打印在界面左下角（HUD.terminal），每块屏只触发一次。

const SHOW_DIST := 110.0

var key := ""
var _on := 0.0
var _t := 0.0
var _fired := false


func _ready() -> void:
	z_index = -2


func _process(delta: float) -> void:
	_t += delta
	var body := get_tree().get_first_node_in_group("controlled") as Node2D
	var near := body != null and body.global_position.distance_to(global_position) < SHOW_DIST
	_on = move_toward(_on, 1.0 if near else 0.0, delta * 3.0)
	if near and not _fired:
		_fired = true
		get_tree().call_group("game", "env_text", tr(key))
	queue_redraw()


func _draw() -> void:
	# 16×10 的终端屏 + 支架
	var r := Rect2(-8, -24, 16, 10)
	draw_rect(Rect2(r.position - Vector2(1, 1), r.size + Vector2(2, 2)), Color(0.02, 0.025, 0.035))
	draw_rect(r, Color(0.05, 0.03, 0.06))
	var lit := 0.35 + 0.65 * _on
	var col := Color(0.72, 0.2, 0.56) * lit
	# 滚动的字形（每行几段短横）
	var off := int(_t * 4.0)
	for row in 3:
		var y := r.position.y + 2 + row * 3
		var x := r.position.x + 2
		var k := (row * 7 + off) % 5
		while x < r.end.x - 2:
			var w := 1 + (k % 3)
			draw_rect(Rect2(x, y, w, 1), col)
			x += w + 1 + (k % 2)
			k += 3
	if fmod(_t, 0.8) < 0.4:
		draw_rect(Rect2(r.end.x - 3, r.end.y - 3, 1, 2), Color(1.6, 0.6, 1.3) * lit)
	draw_rect(Rect2(-1, -14, 2, 14), Color(0.12, 0.14, 0.18))
