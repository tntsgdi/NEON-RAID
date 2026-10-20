class_name ForegroundPoles
extends Node2D
## 前景灯柱剪影（见 CityBackdrop.make_foreground）：半透明，不挡视线。


func _draw() -> void:
	for x in [40.0, 250.0]:
		draw_rect(Rect2(x, -260, 7, 400), Color(0.02, 0.025, 0.04, 0.45))
		draw_rect(Rect2(x - 10, -200, 27, 3), Color(0.02, 0.025, 0.04, 0.45))
		draw_circle(Vector2(x + 14, -196), 2.0, Color(0.4, 1.0, 1.0, 0.8))
		draw_circle(Vector2(x + 14, -196), 6.0, Color(0.4, 1.0, 1.0, 0.12))
