class_name RigPart
extends Node2D
## 机体的一个部件。肢体沿 +y 方向画（从关节向下），躯干沿 -y 画。

@export var kind := "limb"   # limb / torso / head / foot / blade / gun
@export var length := 10.0
@export var width := 4.0
@export var fill := Color.BLACK
@export var edge := Color.CYAN
@export var glow := 0.0


func _draw() -> void:
	match kind:
		"limb":
			var r := Rect2(-width * 0.5, -1.0, width, length + 2.0)
			draw_rect(r, fill)
			draw_rect(r, edge, false, 1.0)
		"torso":
			var r := Rect2(-width * 0.5, -length, width, length + 1.0)
			draw_rect(r, fill)
			draw_rect(r, edge, false, 1.0)
			# 青色核心：玩家标识，冲刺时更亮
			var core := Color(0.3, 1.0, 1.0).lerp(Color(0.9, 1.0, 1.0), glow)
			draw_rect(Rect2(0.0, -length * 0.62, 3.0, 3.0), core)
		"head":
			var r := Rect2(-width * 0.5, -length, width, length)
			draw_rect(r, fill)
			draw_rect(r, edge, false, 1.0)
			draw_rect(Rect2(0.0, -length * 0.66, width * 0.5 + 0.5, 2.0), Color(0.3, 1.0, 1.0))
		"foot":
			var r := Rect2(-2.0, -1.0, length, width)
			draw_rect(r, fill)
			draw_rect(r, edge, false, 1.0)
		"blade":
			draw_rect(Rect2(-1.5, -1.0, 3.0, 3.0), edge.darkened(0.5))
			draw_line(Vector2(0, 2), Vector2(0, length), edge, width)
		"gun":
			draw_rect(Rect2(-width * 0.5, -1.0, width, length), fill)
			draw_rect(Rect2(-width * 0.5, -1.0, width, length), edge, false, 1.0)
