class_name PlayerInput
extends RefCounted
## 玩家意图的抽象层：机体逻辑只读这些字段。
## 键鼠、手柄、测试脚本，以及以后夺壳后的敌方 AI，都是它的子类。

var move := Vector2.ZERO
## 世界坐标下的瞄准方向（单位向量）
var aim := Vector2.RIGHT
var jump_pressed := false
var jump_held := false
var dash_pressed := false
var slide_pressed := false
var slide_held := false
var slash_pressed := false
var shoot_pressed := false


func poll(_body: Node2D) -> void:
	pass
