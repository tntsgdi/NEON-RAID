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
## 每波：[位置, 型号, 是否带盾, 巡逻半径]
const WAVES := [
	[[Vector2(180, 0), "gunner", false, 60.0], [Vector2(320, 0), "gunner", false, 50.0]],
	[[Vector2(-205, -80), "gunner", false, 35.0], [Vector2(250, 0), "rusher", false, 40.0], [Vector2(330, 0), "gunner", true, 30.0]],
	[[Vector2(0, -160), "burst", false, 30.0], [Vector2(-250, 0), "rusher", false, 40.0], [Vector2(250, 0), "gunner", true, 30.0], [Vector2(205, -80), "burst", false, 30.0]],
]

## 生存模式的刷怪点
const SPAWNS := [Vector2(180, 0), Vector2(320, 0), Vector2(-250, 0), Vector2(250, 0), Vector2(-205, -80), Vector2(205, -80), Vector2(0, -160)]

signal training_clear
signal survival_over(wave: int)

var player: Node2D
var auto_waves := true
var wave := 0
var cleared := false
## 三波训练打完后进入生存模式：随机配敌，逐波变多
var survival := false
var best_survival := 0
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
	if survival:
		return tr("SURV_WAVE") % wave
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
	survival = false
	_pending = 0.8


func on_player_died() -> void:
	_clear_enemies()
	if survival:
		# 生存模式：死了这一局就结束，从训练第 1 波重新开始
		best_survival = maxi(best_survival, wave)
		survival_over.emit(wave)
		reset()
		return
	wave = maxi(wave - 1, 0)
	_pending = 0.8


func spawn(pos: Vector2, shielded: bool, patrol: float, kind := "gunner") -> EnemyBot:
	var e := EnemyBot.new()
	e.kind = kind
	e.position = pos
	e.shielded = shielded
	e.patrol_range = patrol
	e.player = player
	e.fx_parent = self
	add_child(e)
	enemies.append(e)
	Fx.sparks(self, pos + Vector2(0, -18), Vector2.UP, 10, Color(1, 0.4, 0.45))
	return e


## 训练完成后由主场景调用：几秒后开始生存模式
func start_survival() -> void:
	survival = true
	_pending = 3.0


func _spawn_survival_wave() -> void:
	wave += 1
	var count := mini(2 + (wave - 3) / 2, 7)
	# 离玩家太近的刷怪点不用，免得冲锋机直接刷在脸上
	var spots := SPAWNS.filter(func(p): return not is_instance_valid(player) or p.distance_to(player.global_position) > 160.0)
	if spots.is_empty():
		spots = SPAWNS.duplicate()
	spots.shuffle()
	for i in count:
		var kinds := ["gunner", "gunner", "burst", "rusher"]
		var kind: String = kinds.pick_random()
		var e := spawn(spots[i % spots.size()], randf() < 0.1 + 0.02 * wave, 30.0, kind)
		if wave % 5 == 0 and i == 0:
			e.make_elite()
	Audio.play("charge", -8.0)
	Music.sting("wave")


func _clear_enemies() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()


func _physics_process(delta: float) -> void:
	if not auto_waves or (cleared and not survival):
		return
	enemies = enemies.filter(func(e): return is_instance_valid(e) and e.alive())
	# 最后一波打完才算清场；之前的波次只要场上只剩 1 个就开始倒数刷下一波
	var ready := enemies.is_empty() if (wave >= WAVES.size() and not survival) else enemies.size() <= 1
	if not ready:
		return
	if _pending > 0.0:
		_pending -= delta
		if _pending <= 0.0:
			if survival:
				_spawn_survival_wave()
				return
			if wave >= WAVES.size():
				cleared = true
				Music.sting("clear")
				training_clear.emit()
				return
			for s in WAVES[wave]:
				spawn(s[0], s[2], s[3], s[1])
			Audio.play("charge", -8.0)
			Music.sting("wave")
			wave += 1
	else:
		_pending = 1.2


func _draw() -> void:
	Blocks.draw(self, SOLIDS)
