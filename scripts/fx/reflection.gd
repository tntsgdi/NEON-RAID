class_name Reflection
extends Node2D
## 湿地面倒影：把机体这一帧的图形上下翻转、压扁、调暗，画在脚下的地面上。
## 离地越高越淡；不在地面上方 90 像素以内就不画。

var rig: StriderRig
var body: Node2D
var _floor_y := 0.0
var _alpha := 0.0


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(body):
		return
	var from := body.global_position + Vector2(0, -2)
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 90), 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_alpha = 0.0
	else:
		_floor_y = hit.position.y
		_alpha = 0.33 * (1.0 - clampf((_floor_y - body.global_position.y) / 90.0, 0.0, 1.0))
	modulate = Color(0.6, 0.9, 1.0, _alpha)
	queue_redraw()


func _draw() -> void:
	if _alpha <= 0.01 or rig == null or not rig.visible:
		return
	var rs := rig.scale
	# 水面微微晃动：横向轻轻摆、略微倾斜
	var t := Time.get_ticks_msec() * 0.001
	var wob := sin(t * 7.0) * 0.8
	draw_set_transform(Vector2(body.global_position.x + wob, _floor_y + (_floor_y - body.global_position.y) * 0.55), sin(t * 5.0) * 0.02, Vector2(rs.x, -rs.y * 0.55))
	StriderRig.draw_shapes(self, rig.shapes())
	draw_set_transform(Vector2.ZERO)
