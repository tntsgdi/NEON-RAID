class_name CombatArena
extends Node2D
## M2 战斗训练场：一块封闭场地、几层平台，3 波安保机（后两波有盾兵）。
## 死了就重打当前这一波；清完 3 波算训练完成。

const SOLIDS := [
	Rect2(-460, 0, 920, 80),        # 地面
	Rect2(-500, -420, 80, 420),     # 左墙
	Rect2(420, -420, 80, 420),      # 右墙
	Rect2(-280, -80, 150, 12),      # 左平台
	Rect2(130, -80, 150, 12),       # 右平台
	Rect2(-70, -160, 140, 12),      # 顶平台
]
const START := Vector2(-370, 0)
## 每波：[位置, 是否盾兵, 巡逻半径]
const WAVES := [
	[[Vector2(180, 0), false, 60.0], [Vector2(320, 0), false, 50.0]],
	[[Vector2(-205, -80), false, 35.0], [Vector2(205, -80), false, 35.0], [Vector2(300, 0), true, 40.0]],
	[[Vector2(0, -160), false, 35.0], [Vector2(-250, 0), true, 30.0], [Vector2(250, 0), true, 30.0], [Vector2(205, -80), false, 35.0]],
]

var player: Node2D
var auto_waves := true
var wave := 0
var cleared := false
var enemies: Array = []
var _pending := 0.8


func _ready() -> void:
	Blocks.build(self, SOLIDS)


func start_pos() -> Vector2:
	return START


func limits() -> Rect2:
	return Rect2(-500, -420, 1000, 540)


func pit_y() -> float:
	return 400.0


func label(_x: float) -> String:
	if cleared:
		return tr("ARENA_CLEAR")
	return tr("ARENA_WAVE") % [maxi(wave, 1), WAVES.size()]


func checkpoint_for(_x: float) -> Vector2:
	return START


func timer_started(_p: Node2D) -> bool:
	return wave >= 1


func is_finished(_p: Node2D) -> bool:
	return cleared


func reset() -> void:
	_clear_enemies()
	wave = 0
	cleared = false
	_pending = 0.8


func on_player_died() -> void:
	_clear_enemies()
	wave = maxi(wave - 1, 0)
	_pending = 0.8


func spawn(pos: Vector2, shielded: bool, patrol: float) -> EnemyBot:
	var e := EnemyBot.new()
	e.position = pos
	e.shielded = shielded
	e.patrol_range = patrol
	e.player = player
	e.fx_parent = self
	add_child(e)
	enemies.append(e)
	Fx.sparks(self, pos + Vector2(0, -18), Vector2.UP, 10, Color(1, 0.4, 0.45))
	return e


func _clear_enemies() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()


func _physics_process(delta: float) -> void:
	if not auto_waves or cleared:
		return
	enemies = enemies.filter(func(e): return is_instance_valid(e) and e.alive())
	if not enemies.is_empty():
		return
	if _pending > 0.0:
		_pending -= delta
		if _pending <= 0.0:
			if wave >= WAVES.size():
				cleared = true
				return
			for s in WAVES[wave]:
				spawn(s[0], s[1], s[2])
			Audio.play("charge", -12.0)
			wave += 1
	else:
		_pending = 1.0


func _draw() -> void:
	Blocks.draw(self, SOLIDS)
