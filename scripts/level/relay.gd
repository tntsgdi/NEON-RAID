class_name Relay
extends Node2D
## 意识中继（霓虹电网的一种）：机体站在中继旁边（REACH 内），夺壳距离从 220 放大到 RANGE，
## 可以夺深沟对面、远处的机体。站进去时中继亮起，画出放大的夺壳范围圈。

const REACH := 56.0
const RANGE := 620.0

var _t := 0.0
var _on := 0.0


func _ready() -> void:
	add_to_group("relay")
	z_index = -1


## 这具机体是不是站在中继旁边
func covers(n: Node2D) -> bool:
	return is_instance_valid(n) and n.global_position.distance_to(global_position) <= REACH


func _process(delta: float) -> void:
	_t += delta
	var body := get_tree().get_first_node_in_group("controlled") as Node2D
	_on = move_toward(_on, 1.0 if covers(body) else 0.0, delta * 5.0)
	queue_redraw()


func _draw() -> void:
	# 塔身：细长的发光支架 + 顶上的环
	var top := Vector2(0, -46)
	draw_line(Vector2(-6, 0), top + Vector2(-2, 6), Color(0.3, 0.6, 0.75), 2.0)
	draw_line(Vector2(6, 0), top + Vector2(2, 6), Color(0.3, 0.6, 0.75), 2.0)
	for i in 4:
		var y := -8.0 - i * 9.0
		draw_line(Vector2(-5 + i, y), Vector2(5 - i, y - 6), Color(0.3, 0.6, 0.75, 0.7), 1.0)
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	var core := Color(0.5, 1.6, 1.9).lerp(Color(2.2, 2.6, 2.8), _on)
	draw_circle(top, 4.0 + _on * 1.5, core)
	draw_arc(top, 9.0 + pulse * 3.0, 0.0, TAU, 24, Color(0.4, 1.5, 1.8, 0.35 + 0.3 * _on), 1.2, true)
	# 地面上的接收区
	draw_arc(Vector2.ZERO, REACH, PI, TAU, 32, Color(0.4, 1.4, 1.7, 0.25 + 0.35 * _on), 1.0, true)
	# 站进去：放大的夺壳范围（虚线圈）
	if _on > 0.01:
		var seg := 72
		for i in seg:
			if i % 2 == 0:
				var a0 := TAU * i / seg + _t * 0.2
				draw_arc(top, RANGE * (0.85 + 0.15 * _on), a0, a0 + TAU / seg, 3, Color(0.5, 1.6, 1.9, 0.35 * _on), 1.0, true)
