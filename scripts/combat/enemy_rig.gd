class_name EnemyRig
extends Node2D
## 联合体安保机器人的程序化动画骨架（地面型：枪手 / 三连发 / 冲锋机）。原点在脚底，按面朝右画。
##   腿：两节 IK（膝盖朝前），步态按走过的距离推进，步幅随速度；冲锋时大步疾跑、身体前压
##   枪臂：两节 IK，手跟着瞄准方向抬起，开枪向后一顿（后坐），冷却时慢慢放下
##   受击：躯干被打得后仰（弹簧），头被甩一下；被打上天会翻滚，落地后站直
##   蓄力：压低身体、头往前探；切换动作时脚做惯性化过渡，不会一帧跳过去

const HIP_H := 15.0
const THIGH := 8.0
const SHIN := 8.0
const TORSO := 13.0
const UPPER_ARM := 6.0
const FOREARM := 6.0

var kind := "gunner"
var controlled := false
var flash := false
var muzzle_world := Vector2.ZERO

var _phase := 0.0
var _lean := 0.0
var _lean_v := 0.0
var _pelvis_y := -HIP_H
var _pelvis_v := 0.0
var _spin := 0.0
var _spin_v := 0.0
var _hit := 0.0
var _hit_v := 0.0
var _recoil := 0.0
var _gun_raise := 0.0
var _aim := Vector2.RIGHT
var _last_mode := ""
var _feet := [Vector2(4, 0), Vector2(-4, 0)]
var _feet_off := [Vector2.ZERO, Vector2.ZERO]
var _inert := 1.0
var _shapes: Array = []
var _facing := 1


## 被打：躯干向后弹，翻滚冲量（power 越大越猛）
func hit(dir_x: float, power: int, launched: bool) -> void:
	_hit_v += -signf(dir_x) * _facing * (9.0 + 5.0 * power)
	if launched:
		_spin_v = -signf(dir_x) * _facing * (9.0 + 3.0 * power)


## 开枪：手和枪往后一顿
func fire() -> void:
	_recoil = 1.0


## m：state（walk / idle / aim / cool / stagger / air / windup / charge / hop），facing，vel，aim（世界方向），aim_k（瞄准进度 0..1），on_floor
func update(m: Dictionary, delta: float) -> void:
	_facing = m.facing
	var state: String = m.state
	var vel: Vector2 = m.vel
	var speed := absf(vel.x)
	var ratio := clampf(speed / 200.0, 0.0, 1.5)

	# ---- 躯干前倾、髋高（弹簧：有过冲）
	var lean := clampf(vel.x * _facing / 200.0, -0.5, 1.0) * 10.0
	var hip := -HIP_H
	match state:
		"walk":
			hip += 1.0 - absf(sin(_phase * TAU * 2.0)) * 1.5
		"aim":
			lean = -6.0
			hip += 1.0
		"windup":
			lean = 28.0
			hip += 5.0
		"charge":
			lean = 32.0
			hip += 2.0 - absf(sin(_phase * TAU * 2.0)) * 2.0
		"stagger":
			lean = -14.0
			hip += 2.0
		"air":
			lean = 6.0
		"hop":
			lean = 18.0
	_lean_v += ((lean - _lean) * 320.0 - _lean_v * 26.0) * delta
	_lean += _lean_v * delta
	_pelvis_v += ((hip - _pelvis_y) * 500.0 - _pelvis_v * 32.0) * delta
	_pelvis_y += _pelvis_v * delta
	_hit_v += (-_hit * 260.0 - _hit_v * 16.0) * delta
	_hit += _hit_v * delta
	# 翻滚：在空中转，落地后转回直立
	if state == "air":
		_spin += _spin_v * delta
		_spin_v = move_toward(_spin_v, 0.0, 6.0 * delta)
	else:
		_spin = lerp_angle(_spin, 0.0, 1.0 - exp(-14.0 * delta))
		_spin_v = 0.0
	rotation = _spin * _facing

	# ---- 步态
	var stride := 18.0 + speed * 0.07
	if state in ["walk", "charge"] and speed > 5.0:
		_phase = fmod(_phase + speed * delta / stride, 1.0)
	var stance := 0.42 if state == "charge" else 0.55
	var targets := []
	for i in 2:
		var p := fmod(_phase + 0.5 * i, 1.0)
		var t := Vector2(3.0 if i == 0 else -3.0, 0)
		match state:
			"walk", "charge":
				if speed > 5.0:
					var half := stride * stance * 0.5
					if p < stance:
						t = Vector2(lerpf(half, -half, p / stance) + 2.0, 0)
					else:
						var s := (p - stance) / (1.0 - stance)
						t = Vector2(lerpf(-half, half, s * s * (3.0 - 2.0 * s)) + 2.0, -sin(s * PI) * (3.0 + 4.0 * ratio))
			"aim":
				t = Vector2(5.0 if i == 0 else -6.0, 0)  # 站稳开枪：两脚分开
			"windup":
				t = Vector2(7.0 if i == 0 else -9.0, 0)  # 蓄力：前弓后蹬
			"air":
				t = Vector2(3.0 if i == 0 else -4.0, _pelvis_y + 12.0 + (2.0 if i == 0 else 0.0))
			"hop":
				t = Vector2(-2.0 if i == 0 else -8.0, _pelvis_y + 12.0)
			"stagger":
				t = Vector2(6.0 if i == 0 else -2.0, 0)
		targets.append(t)
	if state != _last_mode:
		for i in 2:
			_feet_off[i] = _feet[i] - targets[i]
		_inert = 0.0
		_last_mode = state
	_inert += delta
	var fade := exp(-_inert / 0.06)
	for i in 2:
		_feet[i] = targets[i] + _feet_off[i] * fade

	# ---- 枪臂：瞄准时抬起，冷却慢慢放下；开枪后坐
	var aiming: bool = state == "aim" or (controlled and m.get("weapon_hot", false))
	_gun_raise = move_toward(_gun_raise, 1.0 if aiming else 0.0, delta * (8.0 if aiming else 2.5))
	_recoil = move_toward(_recoil, 0.0, delta * 7.0)
	var aim_local: Vector2 = Vector2(m.aim.x * _facing, m.aim.y)
	if aim_local.length() < 0.1:
		aim_local = Vector2.RIGHT
	_aim = _aim.slerp(aim_local.normalized(), 1.0 - exp(-18.0 * delta))

	# ---- 组装图形（局部坐标，面朝右）
	var pelvis := Vector2(0, _pelvis_y)
	var rot := deg_to_rad(_lean + _hit)
	var up := Vector2.UP.rotated(rot)
	var neck := pelvis + up * TORSO
	var shoulder := pelvis + up * (TORSO - 2.0)
	var head_c := neck + up * 4.5 + Vector2(1.5, 0).rotated(rot)
	var red := Color(0.3, 1.1, 1.25) if controlled else Color(1.25, 0.26, 0.32)
	var dark := Color(0.05, 0.14, 0.18) if controlled else Color(0.2, 0.05, 0.08)
	var eye := Neon.CYAN_HOT if controlled else Neon.RED_HOT
	var fill := Color.WHITE if flash else dark
	var metal := Color(0.42, 0.38, 0.44)
	_shapes.clear()

	# 后腿、后臂
	_leg(pelvis + Vector2(-1.5, 0), _feet[1], red.darkened(0.45), 2.5)
	var back_hand := shoulder + Vector2(-3, 7).rotated(rot * 0.5) + Vector2(sin(_phase * TAU) * 3.0 * ratio, 0)
	if state == "charge":
		back_hand = shoulder + Vector2(-8, 3).rotated(rot)
	_arm(shoulder + Vector2(-1, 0), back_hand, red.darkened(0.45), 2.0)
	# 躯干（梯形）
	var w0 := 6.5
	var w1 := 7.5
	var side := Vector2(1, 0).rotated(rot)
	var torso := PackedVector2Array([pelvis - side * w0, pelvis + side * w0, neck + side * w1, neck - side * w1])
	_shapes.append(["poly", torso, fill, red])
	_shapes.append(["line", neck - side * (w1 + 1.0), neck - side * (w1 - 3.0), 3.0, metal])  # 肩甲
	# 头 + 目镜（目镜朝瞄准方向偏一点）
	var head := PackedVector2Array()
	for c in [Vector2(-4.5, -4), Vector2(4.5, -4), Vector2(4.5, 4), Vector2(-4.5, 4)]:
		head.append(head_c + c.rotated(rot * 0.6))
	_shapes.append(["poly", head, fill, red])
	var look := clampf(_aim.y * 2.0, -1.5, 1.5)
	_shapes.append(["line", head_c + Vector2(0.5, -1.0 + look).rotated(rot * 0.6), head_c + Vector2(4.5, -1.0 + look).rotated(rot * 0.6), 2.0, Neon.WHITE_HOT if flash else eye])
	# 前腿
	_leg(pelvis + Vector2(1.5, 0), _feet[0], red, 2.8)
	# 武器臂
	if kind == "rusher":
		# 冲锋机：两臂前伸护住撞角
		var hand := shoulder + Vector2(9, 3).rotated(rot) if state in ["windup", "charge"] else shoulder + Vector2(3, 8).rotated(rot * 0.5)
		_arm(shoulder + Vector2(1, 0), hand, red, 2.4)
		var horn := PackedVector2Array([head_c + Vector2(3, -3).rotated(rot), head_c + Vector2(11, 1).rotated(rot), head_c + Vector2(3, 3).rotated(rot)])
		_shapes.append(["poly", horn, metal, red])
		muzzle_world = to_global(hand)
	else:
		var rest_dir := Vector2(0.8, 0.6).normalized()
		var dir := rest_dir.slerp(_aim, _gun_raise).normalized()
		var hand := shoulder + dir * (UPPER_ARM + FOREARM - 2.0) - dir * _recoil * 3.0
		_arm(shoulder + Vector2(1, 0), hand, red, 2.4)
		var gun_end := hand + dir * 10.0
		_shapes.append(["line", hand - dir * 2.0, gun_end, 3.2, metal])
		if kind == "burst":
			var n := Vector2(-dir.y, dir.x) * 2.5
			_shapes.append(["line", hand + n, gun_end + n * 0.8, 2.0, metal])
		muzzle_world = to_global(gun_end)
		if state == "aim":
			var k: float = m.aim_k
			_shapes.append(["dot", gun_end, 1.0 + 2.5 * k, Color(2.5 + k, 0.4 + 1.6 * k, 0.4 + 1.6 * k, 0.4 + 0.6 * k)])
	queue_redraw()


func _leg(hip: Vector2, foot: Vector2, col: Color, width: float) -> void:
	var d := hip.distance_to(foot)
	var reach := THIGH + SHIN - 0.3
	if d > reach:
		foot = hip + (foot - hip).normalized() * reach
		d = reach
	d = maxf(d, 1.0)
	var dir := (foot - hip) / d
	var along := (THIGH * THIGH - SHIN * SHIN + d * d) / (2.0 * d)
	var h := sqrt(maxf(THIGH * THIGH - along * along, 0.0))
	var knee := hip + dir * along - Vector2(-dir.y, dir.x) * h  # 膝盖朝前
	_shapes.append(["polyline", PackedVector2Array([hip, knee, foot]), col, width])
	_shapes.append(["line", foot + Vector2(-1.5, 0), foot + Vector2(3.0, 0), 2.0, col])


func _arm(shoulder: Vector2, hand: Vector2, col: Color, width: float) -> void:
	var d := shoulder.distance_to(hand)
	var reach := UPPER_ARM + FOREARM - 0.3
	if d > reach:
		hand = shoulder + (hand - shoulder).normalized() * reach
		d = reach
	d = maxf(d, 1.0)
	var dir := (hand - shoulder) / d
	var along := (UPPER_ARM * UPPER_ARM - FOREARM * FOREARM + d * d) / (2.0 * d)
	var h := sqrt(maxf(UPPER_ARM * UPPER_ARM - along * along, 0.0))
	var elbow := shoulder + dir * along + Vector2(-dir.y, dir.x) * h  # 肘朝下后
	_shapes.append(["polyline", PackedVector2Array([shoulder, elbow, hand]), col, width])


func _draw() -> void:
	for s in _shapes:
		match s[0]:
			"poly":
				draw_colored_polygon(s[1], s[2])
				var o: PackedVector2Array = s[1].duplicate()
				o.append(s[1][0])
				draw_polyline(o, s[3], 1.3, true)
			"line":
				draw_line(s[1], s[2], s[4], s[3], true)
			"polyline":
				draw_polyline(s[1], s[2], s[3], true)
			"dot":
				draw_circle(s[1], s[2], s[3])
