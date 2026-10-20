class_name RigGhost
extends Node2D
## 机体残影：画一份复制下来的图形。

var shapes: Array = []


func _draw() -> void:
	StriderRig.draw_shapes(self, shapes)
