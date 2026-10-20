class_name TestRange
extends Node2D
## M1 灰盒测试场。地面顶面 y = 0，向上为负。
## 从左到右：长直道 → 台阶 → 低矮通道 → 深沟 → 双墙竖井 → 靶桩 → 终点。

const SOLIDS := [
	Rect2(-200, 0, 1800, 80),       # 地面 A（-200..1600）
	Rect2(1810, 0, 1690, 80),       # 地面 B（1810..3500），中间是 210 宽的深沟
	Rect2(-200, -700, 180, 700),    # 左边界
	Rect2(760, -32, 100, 32),       # 台阶 1
	Rect2(860, -64, 100, 64),       # 台阶 2
	Rect2(960, -96, 100, 96),       # 台阶 3
	Rect2(1200, -420, 220, 398),    # 低矮通道顶（下沿 y=-22，站立 36 过不去，滑铲 16 能过）
	Rect2(1950, -330, 20, 280),     # 竖井左墙（下沿 y=-50，可以从下面走进去）
	Rect2(2070, -260, 20, 260),     # 竖井右墙
	Rect2(2070, -260, 560, 16),     # 竖井顶上的平台（靶桩所在）
	Rect2(3300, -700, 200, 700),    # 右边界
]

## [起点 x, 文本键]
const SECTIONS := [
	[-1000.0, "SEC_1"],
	[700.0, "SEC_2"],
	[1140.0, "SEC_3"],
	[1540.0, "SEC_4"],
	[1880.0, "SEC_5"],
	[2200.0, "SEC_6"],
	[2900.0, "SEC_7"],
]

const CHECKPOINTS := [Vector2(60, 0), Vector2(720, 0), Vector2(1150, 0), Vector2(1545, 0), Vector2(1880, 0), Vector2(2150, -260)]
## 起点旁边就有两台训练机（之前都在竖井上面，上不去就打不到）
const DUMMIES := [Vector2(380, 0), Vector2(450, 0), Vector2(2250, -260), Vector2(2400, -260), Vector2(2760, 0)]
const START := Vector2(60, 0)
const FINISH_X := 2950.0
const PIT_Y := 220.0

const MARK := Color(0.25, 0.85, 0.95, 0.22)

var dummies: Array[TargetDummy] = []


func _ready() -> void:
	Blocks.build(self, SOLIDS)
	for p in DUMMIES:
		var d := TargetDummy.new()
		d.position = p
		d.fx_parent = self
		add_child(d)
		dummies.append(d)


func start_pos() -> Vector2:
	return START


func limits() -> Rect2:
	return Rect2(-200, -700, 3700, 820)


func pit_y() -> float:
	return PIT_Y


func label(x: float) -> String:
	return tr(section_key(x))


func timer_started(p: Node2D) -> bool:
	return p.global_position.x > START.x + 30.0


func is_finished(p: Node2D) -> bool:
	return p.global_position.x >= FINISH_X


func reset() -> void:
	pass


func on_player_died() -> void:
	pass


func section_key(x: float) -> String:
	var key: String = SECTIONS[0][1]
	for s in SECTIONS:
		if x >= s[0]:
			key = s[1]
	return key


func checkpoint_for(x: float) -> Vector2:
	var best: Vector2 = CHECKPOINTS[0]
	for c in CHECKPOINTS:
		if c.x <= x + 1.0:
			best = c
	return best


func _draw() -> void:
	for s in SECTIONS.slice(1):
		var x: float = s[0]
		var y := -320.0
		while y < 0.0:
			draw_line(Vector2(x, y), Vector2(x, y + 6), MARK, 1.0)
			y += 12.0
	Blocks.draw(self, SOLIDS)
	# 终点线：青色斜纹
	for i in 12:
		var c := Color(0.25, 0.9, 1.0, 0.8) if i % 2 == 0 else Color(0.05, 0.25, 0.3, 0.8)
		draw_rect(Rect2(FINISH_X - 2, -120 + i * 10, 4, 10), c)
