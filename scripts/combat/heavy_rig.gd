class_name HeavyRig
extends Node2D
## 重装机的程序化骨架（原点在脚底，按面朝右画）：
##   宽厚的箱形躯干 + 正面撞角护板 + 背后的液压重锤臂 + 两条粗短的腿（两节 IK，膝朝前）
##   走路：步子大、慢，每一步身体下沉、左右（前后）晃，脚落地时踩得很实
##   冲撞：整个身体前压，护板顶在最前面；砸地：重锤举过头顶 → 狠狠砸到身前地面
##   瘫痪：身体塌下去、头垂着、目镜闪白（白色 = 可以夺）；停放：跪坐、目镜暗着
## 所有关节都是弹簧，换动作时带惯性和一点过冲。

## 约 64 像素高（体积约主角 2 倍），和 tools/pixel/build_enemies.py 的重装机部件对齐
const HIP_H := 26.0
const THIGH := 15.0
const SHIN := 14.0
const TORSO_H := 30.0
const TORSO_W := 38.0
const DIR := "res://assets/sprites/heavy/"

## "hostile" 红 / "controlled" 青 / "stunned" 白闪 / "parked" 暗白
var look := "hostile"
var flash := false
var wake := 0.0
var parts_local := {}
var turn := 1.0
var _turn_lin := 1.0

var _phase := 0.0
var _lean := 0.0
var _lean_v := 0.0
var _pelvis_y := -HIP_H
var _pelvis_v := 0.0
var _hammer := 150.0
var _hammer_v := 0.0
var _hit := 0.0
var _hit_v := 0.0
var _time := 0.0
var _feet := [Vector2(6, 0), Vector2(-6, 0)]
var _feet_off := [Vector2.ZERO, Vector2.ZERO]
var _inert := 1.0
var _last_mode := ""
var _shapes: Array = []
## 刚踩下一步（HeavyBot 用来扬尘、震屏）
var footfall := false


func hit(dir_x: float, power: float) -> void:
	_hit_v += -signf(dir_x) * (4.0 + 2.0 * power)


## m: state（idle / walk / windup_ram / ram / windup_slam / slam / air / dive / stunned / parked / recover），
##    facing, vel, k（当前动作的进度 0..1）
func update(m: Dictionary, delta: float) -> void:
	_time += delta
	_turn_lin = move_toward(_turn_lin, float(m.facing), delta / 0.22 * 2.0)
	var ts := (_turn_lin + 1.0) * 0.5
	turn = ts * ts * (3.0 - 2.0 * ts) * 2.0 - 1.0
	var turning := 1.0 - absf(turn)
	var state: String = m.state
	var vel: Vector2 = m.vel
	var speed := absf(vel.x)
	var k: float = m.get("k", 0.0)

	# ---- 躯干倾角、髋高、重锤角度（全部弹簧）
	var lean := 4.0
	var hip := -HIP_H
	var hammer := 150.0   # 平时：重锤垂在身后
	match state:
		"idle":
			hip += sin(_time * 1.6) * 0.8
			lean += sin(_time * 1.6 + 0.5) * 1.0
		"walk":
			hip += 1.5 - absf(sin(_phase * TAU)) * 3.0
			lean += 5.0 + sin(_phase * TAU * 2.0) * 2.0
			hammer = 150.0 + sin(_phase * TAU) * 10.0
		"windup_ram":
			lean = 22.0 + 4.0 * k
			hip += 5.0
			hammer = 175.0
		"ram":
			lean = 28.0
			hip += 2.0 - absf(sin(_phase * TAU)) * 2.0
			hammer = 185.0
		"windup_slam":
			# 举锤：身体后仰、髋下沉蓄力
			lean = lerpf(4.0, -10.0, k)
			hip += 4.0 * k
			hammer = lerpf(150.0, -95.0, k * k * (3.0 - 2.0 * k))
		"slam":
			lean = 16.0
			hip += 6.0
			hammer = 55.0
		"air":
			lean = 6.0
			hip -= 1.0
			hammer = 200.0
		"dive":
			lean = 10.0
			hammer = -100.0
		"stunned":
			lean = 22.0 + sin(_time * 7.0) * 2.0
			hip = -10.0
			hammer = 100.0
		"parked":
			lean = 18.0
			hip = -9.0
			hammer = 110.0
		"recover":
			lean = 10.0
			hip += 2.0
			hammer = 120.0
	hip += turning * 2.0
	_lean_v += ((lean - _lean) * 220.0 - _lean_v * 20.0) * delta
	_lean += _lean_v * delta
	_pelvis_v += ((hip - _pelvis_y) * 380.0 - _pelvis_v * 26.0) * delta
	_pelvis_y += _pelvis_v * delta
	var hk := 900.0 if state == "slam" else 200.0
	_hammer_v += ((angle_difference(deg_to_rad(_hammer), deg_to_rad(hammer)) * 57.3) * hk - _hammer_v * (40.0 if state == "slam" else 18.0)) * delta
	_hammer += _hammer_v * delta
	_hit_v += (-_hit * 200.0 - _hit_v * 14.0) * delta
	_hit += _hit_v * delta

	# ---- 步态：大步、慢
	var stride := 36.0 + speed * 0.08
	footfall = false
	if (state == "walk" or state == "ram") and speed > 5.0:
		var before := _phase
		_phase = fmod(_phase + speed * delta / stride, 1.0)
		if (before < 0.5 and _phase >= 0.5) or _phase < before:
			footfall = true
	var stance := 0.55
	var targets := []
	for i in 2:
		var p := fmod(_phase + 0.5 * i, 1.0)
		var t := Vector2(9.0 if i == 0 else -9.0, 0)
		match state:
			"walk", "ram":
				if speed > 5.0:
					var half := stride * stance * 0.5
					if p < stance:
						t = Vector2(lerpf(half, -half, p / stance) + 2.0, 0)
					else:
						var s := (p - stance) / (1.0 - stance)
						t = Vector2(lerpf(-half, half, s * s * (3.0 - 2.0 * s)) + 2.0, -sin(s * PI) * 8.0)
			"windup_ram":
				t = Vector2(14.0 if i == 0 else -16.0, 0)
			"windup_slam", "slam":
				t = Vector2(15.0 if i == 0 else -12.0, 0)
			"air", "dive":
				t = Vector2(7.0 if i == 0 else -8.0, _pelvis_y + 22.0)
			"stunned", "parked":
				t = Vector2(14.0 if i == 0 else -6.0, 0)
		targets.append(t)
	if state != _last_mode:
		for i in 2:
			_feet_off[i] = _feet[i] - targets[i]
		_inert = 0.0
		_last_mode = state
	_inert += delta
	var fade := exp(-_inert / 0.08)
	for i in 2:
		_feet[i] = targets[i] + _feet_off[i] * fade

	# ---- 组装（像素部件）
	var pelvis := Vector2(0, _pelvis_y)
	var rot := deg_to_rad(_lean + _hit)
	var up := Vector2.UP.rotated(rot)
	var side := Vector2.RIGHT.rotated(rot)
	var top := pelvis + up * TORSO_H
	var sfx := "_p" if look == "controlled" else ""
	var mod := Color(3.0, 3.0, 3.0) if flash else Color.WHITE
	match look:
		"stunned":
			# 瘫痪：整体闪白（白 = 可以夺）
			var blink := 0.5 + 0.5 * sin(_time * 14.0)
			mod = Color.WHITE.lerp(Color(2.2, 2.3, 2.4), blink)
		"parked":
			mod = Color(0.75, 0.8, 0.85)
	wake = maxf(wake - delta, 0.0)
	if wake > 0.0:
		mod = Color(0.5, 0.55, 0.6).lerp(Color.WHITE, pow(1.0 - wake / 0.4, 2.0))
	_shapes.clear()
	# 后腿
	_leg(pelvis - side * 7.0, _feet[1], "_b" + sfx, mod)
	# 重锤臂（在身后）
	var shoulder := top - up * 7.0 - side * 9.0
	var hdir := Vector2.from_angle(deg_to_rad(_hammer))
	_part("arm_b" + sfx, shoulder, hdir.angle(), mod)
	_part("hammer" + sfx, shoulder + hdir * 10.0, hdir.angle(), mod)
	# 躯干、头、撞角护板
	_part("torso" + sfx, pelvis, rot, mod)
	var hrot := deg_to_rad(_lean * 0.4 + (18.0 if look == "stunned" or look == "parked" else 0.0))
	var hc := top + side * 8.0 + up * 3.0
	_part("head" + sfx, hc, hrot, mod)
	var plate_c := pelvis + up * 17.0 + side * 20.0
	_part("plate" + sfx, plate_c, rot, mod)
	# 前腿
	_leg(pelvis + side * 7.0, _feet[0], sfx, mod)

	var body_r := Rect2(pelvis - side * 10.0, Vector2.ZERO).expand(pelvis + side * 10.0).expand(top + side * 19.0).expand(top - side * 19.0)
	var fx0 := minf(_feet[0].x, _feet[1].x) - 6.0
	var fx1 := maxf(_feet[0].x, _feet[1].x) + 6.0
	parts_local = {
		"head": Rect2(hc - Vector2(8, 6), Vector2(16, 8)),
		"body": body_r,
		"legs": Rect2(Vector2(fx0, minf(pelvis.y, -3.0)), Vector2(fx1 - fx0, maxf(-pelvis.y, 3.0))),
	}
	queue_redraw()


## 重锤头的位置（骨架本地坐标；砸地冲击波从这里出）
func hammer_point() -> Vector2:
	var pelvis := Vector2(0, _pelvis_y)
	var rot := deg_to_rad(_lean + _hit)
	var top := pelvis + Vector2.UP.rotated(rot) * TORSO_H
	var shoulder := top - Vector2.UP.rotated(rot) * 7.0 - Vector2.RIGHT.rotated(rot) * 9.0
	return shoulder + Vector2.from_angle(deg_to_rad(_hammer)) * 28.0


func _leg(hip: Vector2, foot: Vector2, sfx: String, mod: Color) -> void:
	var d := hip.distance_to(foot)
	var reach := THIGH + SHIN - 0.5
	if d > reach:
		foot = hip + (foot - hip).normalized() * reach
		d = reach
	d = maxf(d, 1.0)
	var dir := (foot - hip) / d
	var along := (THIGH * THIGH - SHIN * SHIN + d * d) / (2.0 * d)
	var h := sqrt(maxf(THIGH * THIGH - along * along, 0.0))
	var knee := hip + dir * along - Vector2(-dir.y, dir.x) * h
	_part("thigh" + sfx, hip, (knee - hip).angle(), mod)
	_part("shin" + sfx, knee, (foot - knee).angle(), mod)
	_part("foot" + sfx, foot, 0.0, mod)
	_part("knee" + sfx, knee, 0.0, mod)


func _part(name: String, pos: Vector2, angle: float, mod: Color) -> void:
	_shapes.append(["part", DIR + name, pos, angle, mod])


func _draw() -> void:
	StriderRig.draw_shapes(self, _shapes)
