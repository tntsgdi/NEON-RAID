class_name StriderRig
extends Node2D
## R-0 基础机体：反关节（鸟腿）双足机。全部程序化：
##   楔形机身——天生前倾，疾跑时压到约 40°，倾角由弹簧驱动（加速前冲、急停后坐、落地回弹）
##   反曲腿——两节 IK 求落脚点；跑步有腾空期，触地时脚与地面同速不打滑
##   刀臂——右臂就是长刀，平时拖在身后；挥刀 = 短蓄力 → 全身扭转劈下 → 挥过头再收回
##   背炮——机身背上的小炮塔 360° 跟鼠标
##   线缆——背后两条发光线缆按弹簧物理被风往后拉
## 原点在脚底，按面朝右画；面朝左时 scale.x = -1。

const CYAN := Color(0.3, 1.0, 1.0)
const EDGE := Color(0.25, 0.8, 0.9)
const EDGE_BACK := Color(0.13, 0.42, 0.5)
const FILL := Color(0.15, 0.18, 0.24)
const FILL_BACK := Color(0.09, 0.11, 0.15)
const BLADE := Color(0.85, 1.0, 1.0)

const HIP_H := 20.0
const THIGH := 11.0
const SHIN := 11.0
const BLADE_LEN := 26.0
const ARM_LEN := 6.0
## 一个跑步周期走过的像素；触地占 40%，其余是摆腿（两条腿交替，中间有腾空）
const STRIDE := 64.0
const STANCE := 0.4

## 挥刀三段：刀相对出刀方向的起止角（度）和挥过头的角度
const SLASH := [
	{"from": -115.0, "to": 70.0, "over": 28.0},
	{"from": 85.0, "to": -100.0, "over": 28.0},
	{"from": -165.0, "to": 195.0, "over": 20.0},
]

## 机身外形（以髋部为原点、面朝右）
const HULL := [Vector2(-13, -11), Vector2(6, -14), Vector2(17, -8), Vector2(10, -1), Vector2(-9, -2), Vector2(-15, -7)]
const VISOR := [Vector2(9, -11), Vector2(15, -8.5), Vector2(14, -7), Vector2(8, -9)]
const SHOULDER := Vector2(7, -3)
const TURRET := Vector2(-4, -13)
const CABLE_ANCHORS := [Vector2(-14, -9), Vector2(-12, -5)]
const CABLE_POINTS := 7
const CABLE_SEG := 4.0

var hull_angle := 12.0
var _hull_vel := 0.0
var _pelvis_y := -HIP_H
var _pelvis_vel := 0.0
var _blade_angle := 150.0
var _turret_angle := 0.0
var _recoil := 0.0
var _facing := 1
var _cables: Array = []      # 每条线缆：[当前点数组, 上一帧点数组]（局部坐标，面朝右）
var _shapes: Array = []      # 本帧要画的图形，残影直接复制它
var _blade_pts := [Vector2.ZERO, Vector2.ZERO]
var _muzzle := Vector2.ZERO


func _ready() -> void:
	for a in CABLE_ANCHORS:
		var pts := []
		for i in CABLE_POINTS:
			pts.append(Vector2(0, -HIP_H) + a + Vector2(-CABLE_SEG * i, 0))
		_cables.append([pts, pts.duplicate()])


## 每个物理帧由 Player 调用。m 是机体的运动状态（见 Player._motion）。
func update(m: Dictionary, delta: float) -> void:
	if m.facing != _facing:
		_mirror_cables()
		_facing = m.facing
	var state: String = m.state
	var ratio: float = m.speed_ratio

	# ---- 机身倾角与髋部高度（弹簧：有过冲和回弹）
	var target_angle := 12.0
	var target_y := -HIP_H
	match state:
		"run":
			target_angle = 14.0 + 26.0 * clampf(ratio, 0.0, 1.3)
			target_y = -HIP_H + 1.5 - absf(sin(m.run_phase * TAU * 2.0)) * 2.5 * ratio
		"idle":
			target_angle = 10.0 + sin(m.time * 2.2) * 1.5
			target_y = -HIP_H + 1.0 + sin(m.time * 2.2) * 0.6
		"skid":
			target_angle = -12.0
			target_y = -HIP_H + 4.0
		"air":
			target_angle = 18.0 + clampf(m.vel.y / 30.0, -10.0, 14.0)
			target_y = -HIP_H - 2.0
		"dash":
			target_angle = 52.0
			target_y = -HIP_H + 3.0
		"slide":
			target_angle = -6.0
			target_y = -10.0
		"wall":
			target_angle = -28.0
			target_y = -HIP_H
	target_angle += clampf(m.accel_x * m.facing * 0.012, -14.0, 16.0)
	target_y += m.land_squash * 7.0
	if m.slash_step >= 0:
		target_angle += _slash_twist(m.slash_t)
	var k_angle := 260.0 if state != "dash" else 600.0
	_hull_vel += ((target_angle - hull_angle) * k_angle - _hull_vel * 24.0) * delta
	hull_angle += _hull_vel * delta
	_pelvis_vel += ((target_y - _pelvis_y) * 500.0 - _pelvis_vel * 30.0) * delta
	_pelvis_y += _pelvis_vel * delta
	var pelvis := Vector2(0, _pelvis_y)
	var rot := deg_to_rad(hull_angle)

	# ---- 腿：落脚点 → 两节 IK（膝盖朝后）
	var feet := _foot_targets(m, pelvis)
	var legs := []
	for i in 2:
		legs.append(_leg(pelvis, feet[i]))

	# ---- 刀臂
	var shoulder := pelvis + SHOULDER.rotated(rot)
	var rest := 150.0 + hull_angle * 0.5
	if state == "wall":
		rest = 60.0
	elif state == "dash":
		rest = 175.0
	var want := rest
	if m.slash_step >= 0:
		want = m.slash_dir + _slash_arc(m.slash_step, m.slash_t)
		_blade_angle = want
	else:
		_blade_angle = lerp_angle_deg(_blade_angle, want, 1.0 - exp(-14.0 * delta))
	var bdir := Vector2.from_angle(deg_to_rad(_blade_angle))
	var hand := shoulder + bdir * ARM_LEN
	var tip := hand + bdir * BLADE_LEN
	_blade_pts = [to_global(hand + bdir * 4.0), to_global(tip)]

	# ---- 背炮
	var mount := pelvis + TURRET.rotated(rot)
	var aim: Vector2 = m.aim_local
	_turret_angle = lerp_angle_deg(_turret_angle, rad_to_deg(aim.angle()), 1.0 - exp(-30.0 * delta))
	_recoil = move_toward(_recoil, 0.0, 30.0 * delta)
	var tdir := Vector2.from_angle(deg_to_rad(_turret_angle - _recoil * 3.0))
	var barrel_end := mount + tdir * (9.0 - _recoil)
	_muzzle = barrel_end

	# ---- 线缆
	var world_vel: Vector2 = m.vel
	var local_vel := Vector2(world_vel.x * m.facing, world_vel.y)
	var anchors := []
	for a in CABLE_ANCHORS:
		anchors.append(pelvis + a.rotated(rot))
	_step_cables(anchors, local_vel, delta)

	# ---- 收集要画的图形
	_shapes.clear()
	_add_leg(legs[1], FILL_BACK, EDGE_BACK)
	for c in _cables:
		_shapes.append(["cable", c[0].duplicate()])
	var hull := PackedVector2Array()
	for p in HULL:
		hull.append(pelvis + p.rotated(rot))
	_shapes.append(["poly", hull, FILL, EDGE])
	var visor := PackedVector2Array()
	for p in VISOR:
		visor.append(pelvis + p.rotated(rot))
	_shapes.append(["poly", visor, CYAN.lerp(Color.WHITE, m.glow), CYAN])
	_shapes.append(["dot", pelvis + Vector2(-3, -7).rotated(rot), 1.8 + m.glow, CYAN.lerp(Color.WHITE, m.glow)])
	_shapes.append(["line", mount, barrel_end, 3.5, Color(0.35, 0.4, 0.48)])
	_shapes.append(["line", mount, barrel_end, 1.0, EDGE])
	_shapes.append(["dot", mount, 2.5, FILL])
	_add_leg(legs[0], FILL, EDGE)
	_shapes.append(["line", shoulder, hand, 3.0, EDGE])
	_shapes.append(["line", hand, tip, 4.5, Color(0.3, 0.9, 1.0, 0.3)])
	_shapes.append(["line", hand, tip, 2.0, BLADE])
	_shapes.append(["dot", shoulder, 2.0, EDGE])
	queue_redraw()


func _foot_targets(m: Dictionary, pelvis: Vector2) -> Array:
	var ground := -3.0
	match m.state:
		"run":
			var out := []
			for i in 2:
				var p := fmod(m.run_phase + 0.5 * i, 1.0)
				var half := STRIDE * STANCE * 0.5
				var x: float
				var y := ground
				if p < STANCE:
					x = lerpf(half, -half, p / STANCE)
				else:
					var s := (p - STANCE) / (1.0 - STANCE)
					x = lerpf(-half, half, s * s * (3.0 - 2.0 * s))
					y = ground - sin(s * PI) * (5.0 + 7.0 * clampf(m.speed_ratio, 0.0, 1.0))
				out.append(Vector2(x + 4.0, y))
			return out
		"skid":
			return [Vector2(13, ground), Vector2(-3, ground)]
		"air":
			var tuck := clampf(-m.vel.y / 450.0, 0.0, 1.0)
			return [pelvis + Vector2(5, lerpf(16.0, 9.0, tuck)), pelvis + Vector2(-7, lerpf(15.0, 11.0, tuck))]
		"dash":
			return [pelvis + Vector2(-8, 13), pelvis + Vector2(-15, 9)]
		"slide":
			return [Vector2(17, ground), Vector2(-6, ground)]
		"wall":
			return [pelvis + Vector2(-6, 8), pelvis + Vector2(-6, 16)]
	return [Vector2(5, ground), Vector2(-5, ground)]


## 两节 IK：膝盖朝后（反关节）。返回 [髋, 膝, 踝, 脚尖]
func _leg(hip: Vector2, ankle: Vector2) -> Array:
	var d := hip.distance_to(ankle)
	var reach := THIGH + SHIN - 0.5
	if d > reach:
		ankle = hip + (ankle - hip).normalized() * reach
		d = reach
	d = maxf(d, 2.0)
	var dir := (ankle - hip) / d
	var along := (THIGH * THIGH - SHIN * SHIN + d * d) / (2.0 * d)
	var h := sqrt(maxf(THIGH * THIGH - along * along, 0.0))
	var knee := hip + dir * along + Vector2(-dir.y, dir.x) * h
	var toe := ankle + Vector2(5, 3)
	return [hip, knee, ankle, toe]


func _add_leg(l: Array, fill: Color, edge: Color) -> void:
	_shapes.append(["line", l[0], l[1], 3.5, fill])
	_shapes.append(["line", l[1], l[2], 3.0, fill])
	_shapes.append(["line", l[2], l[3], 2.5, fill])
	_shapes.append(["polyline", PackedVector2Array([l[0], l[1], l[2], l[3]]), edge])
	_shapes.append(["dot", l[1], 2.0, edge])


## 挥刀：0–15% 回拉蓄力，15–55% 劈过去并挥过头，之后收回到终点
func _slash_arc(step: int, t: float) -> float:
	var s: Dictionary = SLASH[step]
	var sgn := signf(s.to - s.from)
	if t < 0.15:
		return s.from - sgn * 18.0 * (t / 0.15)
	if t < 0.55:
		var u := (t - 0.15) / 0.4
		var e := 1.0 - pow(1.0 - u, 3.0)
		return lerpf(s.from - sgn * 18.0, s.to + sgn * s.over, e)
	var v := (t - 0.55) / 0.45
	return lerpf(s.to + sgn * s.over, s.to, v * v)


## 挥刀时全身扭转：蓄力往后仰，劈下时往前压
func _slash_twist(t: float) -> float:
	if t < 0.15:
		return -10.0 * (t / 0.15)
	if t < 0.55:
		return lerpf(-10.0, 16.0, (t - 0.15) / 0.4)
	return lerpf(16.0, 0.0, (t - 0.55) / 0.45)


func _step_cables(anchors: Array, local_vel: Vector2, delta: float) -> void:
	# 风：和速度反向；重力往下。用 Verlet 积分 + 长度约束
	var acc := Vector2(0, 260.0) - local_vel * 2.2
	for ci in _cables.size():
		var cur: Array = _cables[ci][0]
		var prev: Array = _cables[ci][1]
		for i in range(1, cur.size()):
			var p: Vector2 = cur[i]
			var nxt: Vector2 = p + (p - prev[i]) * 0.86 + acc * delta * delta
			prev[i] = p
			cur[i] = nxt
		cur[0] = anchors[ci]
		prev[0] = anchors[ci]
		for it in 3:
			for i in range(1, cur.size()):
				var a: Vector2 = cur[i - 1]
				var b: Vector2 = cur[i]
				var dv := b - a
				var dl := dv.length()
				if dl > 0.001:
					cur[i] = a + dv / dl * CABLE_SEG


func _mirror_cables() -> void:
	for c in _cables:
		for arr in c:
			for i in arr.size():
				arr[i].x = -arr[i].x


func kick() -> void:
	_recoil = 3.0


func muzzle() -> Vector2:
	return to_global(_muzzle)


## 刀身根部与刀尖的全局坐标（刀光拖尾用）
func blade_points() -> Array:
	return _blade_pts


## 冲刺残影：把当前这一帧的图形复制一份，慢慢淡出
func spawn_ghost(parent: Node, alpha: float) -> void:
	var g := RigGhost.new()
	g.shapes = _shapes.duplicate(true)
	parent.add_child(g)
	g.global_transform = global_transform
	g.modulate = Color(0.3, 0.95, 1.0, alpha)
	g.z_index = -1
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.22)
	tw.tween_callback(g.queue_free)


func _draw() -> void:
	draw_shapes(self, _shapes)


static func draw_shapes(ci: CanvasItem, shapes: Array) -> void:
	for s in shapes:
		match s[0]:
			"poly":
				ci.draw_colored_polygon(s[1], s[2])
				var outline: PackedVector2Array = s[1].duplicate()
				outline.append(s[1][0])
				ci.draw_polyline(outline, s[3], 1.0, true)
			"line":
				ci.draw_line(s[1], s[2], s[4], s[3], true)
			"polyline":
				ci.draw_polyline(s[1], s[2], 1.0, true)
			"dot":
				ci.draw_circle(s[1], s[2], s[3])
			"cable":
				var pts: Array = s[1]
				for i in range(1, pts.size()):
					var k := 1.0 - float(i) / pts.size()
					ci.draw_line(pts[i - 1], pts[i], Color(0.3, 1.0, 1.0, 0.25 + 0.6 * k), 0.6 + 1.6 * k, true)


static func lerp_angle_deg(a: float, b: float, t: float) -> float:
	return rad_to_deg(lerp_angle(deg_to_rad(a), deg_to_rad(b), t))
