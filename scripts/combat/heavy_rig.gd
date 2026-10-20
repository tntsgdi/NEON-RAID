class_name HeavyRig
extends Node2D
## 重装机的程序化骨架（原点在脚底，按面朝右画）：
##   宽厚的箱形躯干 + 正面撞角护板 + 背后的液压重锤臂 + 两条粗短的腿（两节 IK，膝朝前）
##   走路：步子大、慢，每一步身体下沉、左右（前后）晃，脚落地时踩得很实
##   冲撞：整个身体前压，护板顶在最前面；砸地：重锤举过头顶 → 狠狠砸到身前地面
##   瘫痪：身体塌下去、头垂着、目镜闪白（白色 = 可以夺）；停放：跪坐、目镜暗着
## 所有关节都是弹簧，换动作时带惯性和一点过冲。

const HIP_H := 18.0
const THIGH := 10.0
const SHIN := 10.0
const TORSO_H := 22.0
const TORSO_W := 26.0

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
	var stride := 26.0 + speed * 0.06
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
		var t := Vector2(6.0 if i == 0 else -6.0, 0)
		match state:
			"walk", "ram":
				if speed > 5.0:
					var half := stride * stance * 0.5
					if p < stance:
						t = Vector2(lerpf(half, -half, p / stance) + 2.0, 0)
					else:
						var s := (p - stance) / (1.0 - stance)
						t = Vector2(lerpf(-half, half, s * s * (3.0 - 2.0 * s)) + 2.0, -sin(s * PI) * 6.0)
			"windup_ram":
				t = Vector2(10.0 if i == 0 else -12.0, 0)
			"windup_slam", "slam":
				t = Vector2(11.0 if i == 0 else -9.0, 0)
			"air", "dive":
				t = Vector2(5.0 if i == 0 else -6.0, _pelvis_y + 15.0)
			"stunned", "parked":
				t = Vector2(10.0 if i == 0 else -4.0, 0)
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

	# ---- 组装
	var pelvis := Vector2(0, _pelvis_y)
	var rot := deg_to_rad(_lean + _hit)
	var up := Vector2.UP.rotated(rot)
	var side := Vector2.RIGHT.rotated(rot)
	var top := pelvis + up * TORSO_H
	var main_col: Color
	var dark: Color
	match look:
		"controlled":
			main_col = Color(0.3, 1.1, 1.25)
			dark = Color(0.04, 0.12, 0.16)
		"stunned":
			var blink := 0.5 + 0.5 * sin(_time * 14.0)
			main_col = Color(1.25, 0.3, 0.35).lerp(Color(1.8, 1.9, 2.0), blink)
			dark = Color(0.16, 0.12, 0.14)
		"parked":
			main_col = Color(0.75, 0.8, 0.85)
			dark = Color(0.1, 0.11, 0.13)
		_:
			main_col = Color(1.25, 0.26, 0.32)
			dark = Color(0.2, 0.05, 0.08)
	var fill := Color.WHITE if flash else dark
	var metal := Color(0.42, 0.38, 0.44)
	var eye: Color = {"controlled": Neon.CYAN_HOT, "stunned": Color(2.4, 2.5, 2.6), "parked": Color(0.25, 0.3, 0.32)}.get(look, Neon.RED_HOT)
	wake = maxf(wake - delta, 0.0)
	if wake > 0.0:
		eye = Color(0.1, 0.25, 0.3).lerp(eye, pow(1.0 - wake / 0.4, 2.0))
	_shapes.clear()

	# 后腿
	_leg(pelvis + side * -5.0, _feet[1], main_col.darkened(0.45), 5.0)
	# 重锤臂（在身后，先画）
	var shoulder := top - up * 4.0 - side * 6.0
	var hdir := Vector2.from_angle(deg_to_rad(_hammer))
	var elbow := shoulder + hdir.rotated(-0.4) * 8.0
	var grip := shoulder + hdir * 15.0
	_shapes.append(["line", shoulder, elbow, 4.0, main_col.darkened(0.2)])
	_shapes.append(["line", elbow, grip, 3.5, main_col.darkened(0.2)])
	var hn := Vector2(-hdir.y, hdir.x)
	var head_c := grip + hdir * 5.0
	var hammer_poly := PackedVector2Array([head_c - hn * 7.0 - hdir * 4.0, head_c + hn * 7.0 - hdir * 4.0, head_c + hn * 7.0 + hdir * 4.0, head_c - hn * 7.0 + hdir * 4.0])
	_shapes.append(["poly", hammer_poly, metal, main_col])
	# 躯干：宽箱子，下窄上宽
	var torso := PackedVector2Array([pelvis - side * 9.0, pelvis + side * 9.0, top + side * (TORSO_W * 0.5) - up * 3.0, top + side * (TORSO_W * 0.5 - 4.0), top - side * (TORSO_W * 0.5 - 2.0), top - side * (TORSO_W * 0.5) - up * 4.0])
	_shapes.append(["poly", torso, fill, main_col])
	# 液压管：躯干两侧的两条竖线
	_shapes.append(["line", pelvis + side * 5.0 + up * 3.0, top + side * 8.0 - up * 4.0, 1.5, metal])
	_shapes.append(["line", pelvis - side * 5.0 + up * 3.0, top - side * 7.0 - up * 4.0, 1.5, metal])
	# 头：小小的传感器缝，嵌在躯干顶部前方，比躯干稳
	var hrot := deg_to_rad(_lean * 0.4 + (18.0 if look == "stunned" or look == "parked" else 0.0))
	var hc := top + side * 5.0 + up * 3.5
	var head := PackedVector2Array()
	for c in [Vector2(-6, -3), Vector2(6, -3), Vector2(7, 2), Vector2(-6, 2)]:
		head.append(hc + c.rotated(hrot))
	_shapes.append(["poly", head, fill, main_col])
	_shapes.append(["line", hc + Vector2(1, -0.5).rotated(hrot), hc + Vector2(6, -0.5).rotated(hrot), 2.0, Neon.WHITE_HOT if flash else eye])
	# 撞角护板：正面一块厚板
	var plate_c := pelvis + up * 13.0 + side * 15.0
	var plate := PackedVector2Array([plate_c - up * 11.0 - side * 1.0, plate_c - up * 9.0 + side * 4.0, plate_c + up * 9.0 + side * 4.0, plate_c + up * 11.0 - side * 1.0])
	_shapes.append(["poly", plate, metal.darkened(0.2) if not flash else Color.WHITE, main_col])
	# 前腿
	_leg(pelvis + side * 5.0, _feet[0], main_col, 5.5)

	var body_r := Rect2(torso[0], Vector2.ZERO)
	for p in torso:
		body_r = body_r.expand(p)
	var fx0 := minf(_feet[0].x, _feet[1].x) - 3.0
	var fx1 := maxf(_feet[0].x, _feet[1].x) + 4.0
	parts_local = {
		"head": Rect2(hc - Vector2(7, 5), Vector2(14, 9)),
		"body": body_r,
		"legs": Rect2(Vector2(fx0, minf(pelvis.y, -3.0)), Vector2(fx1 - fx0, maxf(-pelvis.y, 3.0))),
	}
	queue_redraw()


## 重锤头的位置（骨架本地坐标；砸地冲击波从这里出）
func hammer_point() -> Vector2:
	var pelvis := Vector2(0, _pelvis_y)
	var rot := deg_to_rad(_lean + _hit)
	var top := pelvis + Vector2.UP.rotated(rot) * TORSO_H
	var shoulder := top - Vector2.UP.rotated(rot) * 4.0 - Vector2.RIGHT.rotated(rot) * 6.0
	return shoulder + Vector2.from_angle(deg_to_rad(_hammer)) * 20.0


func _leg(hip: Vector2, foot: Vector2, col: Color, width: float) -> void:
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
	_shapes.append(["polyline", PackedVector2Array([hip, knee, foot]), col, width])
	_shapes.append(["dot", knee, width * 0.55, col])
	# 大脚掌
	_shapes.append(["line", foot + Vector2(-4, 0), foot + Vector2(6, 0), 3.0, col])


func _draw() -> void:
	for s in _shapes:
		match s[0]:
			"poly":
				draw_colored_polygon(s[1], s[2])
				var o: PackedVector2Array = s[1].duplicate()
				o.append(s[1][0])
				draw_polyline(o, s[3], 1.4, true)
			"line":
				draw_line(s[1], s[2], s[4], s[3], true)
			"polyline":
				draw_polyline(s[1], s[2], s[3], true)
			"dot":
				draw_circle(s[1], s[2], s[3])
