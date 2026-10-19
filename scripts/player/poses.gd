class_name Poses
## 机体姿势数据表。角度单位：度，Godot 旋转（正值顺时针），以面朝右为准：
##   躯干/头：正值前倾    大腿/上臂：负值向前摆
##   小腿：正值屈膝        前臂：负值屈肘
##   hip_y：髋部下沉的像素
## 同一套骨架给所有机体用，换部件不换姿势表。

const JOINTS := ["hip_y", "torso", "head", "thigh_f", "shin_f", "thigh_b", "shin_b", "uarm_f", "farm_f", "uarm_b", "farm_b"]

const IDLE := {"hip_y": 1.0, "torso": 4.0, "head": -2.0, "thigh_f": -8.0, "shin_f": 10.0, "thigh_b": 6.0, "shin_b": 8.0, "uarm_f": -10.0, "farm_f": -35.0, "uarm_b": 12.0, "farm_b": -25.0}
const JUMP := {"hip_y": 0.0, "torso": 8.0, "head": -6.0, "thigh_f": -55.0, "shin_f": 75.0, "thigh_b": 20.0, "shin_b": 40.0, "uarm_f": -40.0, "farm_f": -40.0, "uarm_b": 40.0, "farm_b": -30.0}
const FALL := {"hip_y": 0.0, "torso": 2.0, "head": -4.0, "thigh_f": -25.0, "shin_f": 35.0, "thigh_b": 15.0, "shin_b": 55.0, "uarm_f": -70.0, "farm_f": -20.0, "uarm_b": 70.0, "farm_b": -15.0}
const DASH := {"hip_y": 4.0, "torso": 45.0, "head": -30.0, "thigh_f": -30.0, "shin_f": 60.0, "thigh_b": 50.0, "shin_b": 35.0, "uarm_f": 60.0, "farm_f": -10.0, "uarm_b": 75.0, "farm_b": -10.0}
const SLIDE := {"hip_y": 11.0, "torso": -25.0, "head": 12.0, "thigh_f": -80.0, "shin_f": 0.0, "thigh_b": -30.0, "shin_b": 100.0, "uarm_f": 40.0, "farm_f": -30.0, "uarm_b": 50.0, "farm_b": -20.0}
## 急转刹车：身体后仰顶住惯性，前腿撑地
const SKID := {"hip_y": 4.0, "torso": -16.0, "head": 8.0, "thigh_f": -50.0, "shin_f": 8.0, "thigh_b": 25.0, "shin_b": 60.0, "uarm_f": -30.0, "farm_f": -30.0, "uarm_b": -40.0, "farm_b": -20.0}
const WALL := {"hip_y": 2.0, "torso": -4.0, "head": 4.0, "thigh_f": -45.0, "shin_f": 75.0, "thigh_b": 10.0, "shin_b": 60.0, "uarm_f": -20.0, "farm_f": -30.0, "uarm_b": 95.0, "farm_b": -20.0}

## 跑步：单腿 8 个相位样本 [大腿, 小腿]；后腿错开半个周期。
const RUN_LEG := [[-40.0, 10.0], [-20.0, 30.0], [5.0, 20.0], [30.0, 25.0], [40.0, 70.0], [10.0, 100.0], [-30.0, 80.0], [-50.0, 40.0]]
const RUN_BOB := [1.0, 2.0, 1.0, 0.0, 1.0, 2.0, 1.0, 0.0]
const RUN_LEAN := 16.0
const RUN_HEAD := -12.0
const RUN_FOREARM := -75.0
const RUN_ARM_SWING := 0.8
## 一个跑步周期走过的像素
const STRIDE := 56.0

## 挥刀三段：刀臂相对瞄准方向的起止角（第三段是大回旋）
const SLASH := [
	{"from": -120.0, "to": 70.0},
	{"from": 70.0, "to": -120.0},
	{"from": -170.0, "to": 160.0},
]


static func blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for j in JOINTS:
		out[j] = lerpf(a.get(j, 0.0), b.get(j, 0.0), t)
	return out


static func idle(time: float) -> Dictionary:
	var p := IDLE.duplicate()
	p.hip_y += sin(time * 2.4) * 0.6
	p.torso += sin(time * 2.4) * 1.0
	return p


## phase：0..1；amount：速度占全速的比例，决定步幅
static func run(phase: float, amount: float) -> Dictionary:
	var p := IDLE.duplicate()
	var lf := _leg(phase)
	var lb := _leg(fmod(phase + 0.5, 1.0))
	p.thigh_f = lf.x * amount
	p.shin_f = lf.y * (0.4 + 0.6 * amount)
	p.thigh_b = lb.x * amount
	p.shin_b = lb.y * (0.4 + 0.6 * amount)
	p.hip_y = _bob(phase) * amount
	p.torso = RUN_LEAN * amount
	p.head = RUN_HEAD * amount
	p.uarm_f = -p.thigh_f * RUN_ARM_SWING
	p.uarm_b = -p.thigh_b * RUN_ARM_SWING
	p.farm_f = RUN_FOREARM
	p.farm_b = RUN_FOREARM
	return p


static func _leg(phase: float) -> Vector2:
	var n := RUN_LEG.size()
	var f := phase * n
	var i := int(f) % n
	var j := (i + 1) % n
	var t := f - floorf(f)
	var a: Array = RUN_LEG[i]
	var b: Array = RUN_LEG[j]
	return Vector2(lerpf(a[0], b[0], t), lerpf(a[1], b[1], t))


static func _bob(phase: float) -> float:
	var n := RUN_BOB.size()
	var f := phase * n
	var i := int(f) % n
	return lerpf(RUN_BOB[i], RUN_BOB[(i + 1) % n], f - floorf(f))
