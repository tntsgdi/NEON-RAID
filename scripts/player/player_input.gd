class_name PlayerInput
extends RefCounted
## 玩家意图的抽象层：机体逻辑只读这些字段。
## 键鼠、手柄、测试脚本都是它的子类；夺壳时同一个输入对象交给新机体。

var move := Vector2.ZERO
## 世界坐标下的瞄准方向（单位向量）；aim_keys 为 true 时表示没有鼠标/右摇杆在瞄，由机体按锁定目标或面朝方向决定
var aim := Vector2.RIGHT
var aim_keys := false
var jump_pressed := false
var jump_held := false
var dash_pressed := false
var slide_pressed := false
var slide_held := false
var slash_pressed := false
var shoot_pressed := false
## 按住跑步键（不按是走路）
var run_held := true
var possess_pressed := false


func poll(_body: Node2D) -> void:
	pass
