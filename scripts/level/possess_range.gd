class_name PossessRange
extends Node2D
## M3 夺壳训练场：起点和对岸之间是一道 560 像素宽的深渊——基础机体怎么跳都过不去，
## 要夺取悬在崖边的失控侦察机飞过去；对岸有高台上的盾兵枪手、三连发、冲锋机和一台敌对侦察机，
## 都可以夺来用。到达终点线计时结束。

const SOLIDS := [
	Rect2(-440, 0, 840, 80),        # 起点地面（-440..400）
	Rect2(-480, -520, 40, 600),     # 左墙
	Rect2(960, 0, 1040, 80),        # 对岸地面（960..2000）
	Rect2(1300, -170, 300, 14),     # 对岸高台
	Rect2(2000, -520, 40, 600),     # 右墙
]
const START := Vector2(-320, 0)
const FAR_CHECKPOINT := Vector2(1010, 0)
const FINISH_X := 1880.0
const PIT_Y := 300.0

var player: Node2D
var _actors: Array = []


func _ready() -> void:
	Blocks.build(self, SOLIDS)


func start_pos() -> Vector2:
	return START


func limits() -> Rect2:
	return Rect2(-480, -520, 2520, 640)


func pit_y() -> float:
	return PIT_Y


func label(x: float) -> String:
	return tr("POS_LABEL_FAR") if x > 960.0 else tr("POS_LABEL")


func checkpoint_for(x: float) -> Vector2:
	return FAR_CHECKPOINT if x > 960.0 else START


func timer_started(p: Node2D) -> bool:
	return p.global_position.x > START.x + 30.0


func is_finished(p: Node2D) -> bool:
	return p.global_position.x >= FINISH_X


func on_player_died() -> void:
	pass


## 重新摆好所有机体
func reset() -> void:
	for a in _actors:
		if is_instance_valid(a):
			a.queue_free()
	_actors.clear()
	# 崖边两台失控侦察机（夺来飞过深渊）
	_drone(Vector2(330, -80), true)
	_drone(Vector2(220, -150), true)
	# 对岸的敌人
	_drone(Vector2(1150, -150), false)
	_bot(Vector2(1420, -170), "gunner", true)
	_bot(Vector2(1220, 0), "burst", false)
	_bot(Vector2(1700, 0), "rusher", false)


func _drone(pos: Vector2, wild: bool) -> void:
	var d := DroneBot.new()
	d.position = pos
	d.wild = wild
	d.player = player
	d.fx_parent = self
	add_child(d)
	_actors.append(d)


func _bot(pos: Vector2, kind: String, shielded: bool) -> void:
	var e := EnemyBot.new()
	e.kind = kind
	e.shielded = shielded
	e.position = pos
	e.patrol_range = 30.0
	e.player = player
	e.fx_parent = self
	add_child(e)
	_actors.append(e)


func _draw() -> void:
	Blocks.draw(self, SOLIDS)
	# 崖边警示条（黄黑斜纹换成琥珀色，环境色）
	for x0 in [392.0, 960.0]:
		for i in 4:
			draw_rect(Rect2(x0 + (i % 2) * 2, -4 + i * 3, 6, 2), Color(1.6, 0.9, 0.25, 0.8))
	# 终点线
	for i in 12:
		var c := Color(0.25, 0.9, 1.0, 0.8) if i % 2 == 0 else Color(0.05, 0.25, 0.3, 0.8)
		draw_rect(Rect2(FINISH_X - 2, -120 + i * 10, 4, 10), c)
