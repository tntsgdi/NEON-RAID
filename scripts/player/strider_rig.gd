class_name StriderRig
extends Node2D
## R-0 基础机体：反关节（鸟腿）双足机。全部程序化：
##   楔形机身——天生前倾，疾跑时压到约 40°，倾角由弹簧驱动（加速前冲、急停后坐、落地回弹）
##   鸟腿——大腿/小腿/跖骨三节（膝朝前、踝朝后），IK 求落脚点；跑步有腾空期，触地时脚与地面同速不打滑
##   刀臂——右臂就是长刀，平时拖在身后；挥刀 = 短蓄力 → 全身扭转劈下 → 挥过头再收回
##   背炮——机身背上的小炮塔 360° 跟鼠标
##   线缆——背后两条发光线缆按弹簧物理被风往后拉
## 原点在脚底，按面朝右画；面朝左时 scale.x = -1。

const CYAN := Neon.CYAN_HOT
## 外壳描边带一点点霓虹发光
const EDGE := Color(0.3, 1.1, 1.25)
const EDGE_BACK := Color(0.13, 0.42, 0.5)
const FILL := Color(0.15, 0.18, 0.24)
const FILL_BACK := Color(0.09, 0.11, 0.15)
## 出刀 / 冲刺时刀刃发强光；平时只是亮青色，不盖住机身和腿
const BLADE := Color(1.05, 1.9, 2.1)
const BLADE_REST := Color(0.55, 1.15, 1.3)

const HIP_H := 21.0
const THIGH := 13.0
const SHIN := 13.0
## 跖骨：踝关节在脚尖的后上方
const META := Vector2(-3.0, -7.5)
const BLADE_LEN := 26.0
const ARM_LEN := 6.0
## 触地占一个跑步周期的 40%，其余是摆腿（两条腿交替，中间有腾空）
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
## 转身：从 ±1 平滑过渡（中途压扁成一条，再翻过来），而不是瞬间翻面
var turn := 1.0
var _prev_blade := 150.0
## 惯性化过渡：切换动作时，旧姿势和新姿势的差在约 0.1 秒内衰减到零（输入立即生效，画面不跳）
const INERTIA_TAU := 0.07
var _last_mode := ""
var _last_toes := [Vector2.ZERO, Vector2.ZERO]
var _last_tilts := [0.0, 0.0]
var _toe_off := [Vector2.ZERO, Vector2.ZERO]
var _tilt_off := [0.0, 0.0]
var _inert_t := 1.0
## 刀臂也做惯性化：出刀、收刀那一刻不会一帧跳过去
## 台阶：机体整体被挪上/挪下时，脚先留在原来的世界位置，再平滑踩到新地面
var _toe_shift := 0.0
var _was_slashing := false
var _blade_off := 0.0
var _blade_t := 1.0


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
	if m.speed_ratio > 0.4 and m.state == "run":
		turn = float(m.facing)
	else:
		turn = move_toward(turn, float(m.facing), delta / 0.12 * 2.0)
	var state: String = m.state
	var ratio: float = m.speed_ratio

	# ---- 机身倾角与髋部高度（弹簧：有过冲和回弹）
	var target_angle := 12.0
	var target_y := -HIP_H
	match state:
		"run":
			# 每一步：落地时压低、蹬地时弹起，机身跟着点头；疾驰档再压低、再前倾
			var beat: float = sin(m.run_phase * TAU * 2.0)
			target_angle = 14.0 + 26.0 * clampf(ratio, 0.0, 1.0) + beat * 3.0 * ratio + (7.0 if m.sprint else 0.0)
			target_y = -HIP_H + 2.5 - absf(beat) * 4.5 * clampf(ratio, 0.0, 1.0) + (2.0 if m.sprint else 0.0)
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
		"kneel":
			target_angle = 30.0
			target_y = -11.0
	target_angle += clampf(m.accel_x * m.facing * 0.012, -14.0, 16.0)
	target_y += m.land_squash * 7.0
	if m.slash_step >= 0:
		target_angle += _slash_twist(m.slash_step, m.slash_t)
	var k_angle := 260.0 if state != "dash" else 600.0
	_hull_vel += ((target_angle - hull_angle) * k_angle - _hull_vel * 24.0) * delta
	hull_angle += _hull_vel * delta
	_pelvis_vel += ((target_y - _pelvis_y) * 500.0 - _pelvis_vel * 30.0) * delta
	_pelvis_y += _pelvis_vel * delta
	# 贴墙时机身挪离墙面，不插进墙里（墙在身后）
	var pelvis := Vector2(8.0 if state == "wall" else 0.0, _pelvis_y)
	var rot := deg_to_rad(hull_angle)

	# ---- 腿：脚尖落点 → 三节 IK（膝朝前、踝朝后）
	var feet := _foot_targets(m, pelvis)
	if state != _last_mode:
		# 动作切换：记下旧脚位与新目标的差，接下来让它平滑衰减
		for i in 2:
			_toe_off[i] = _last_toes[i] - feet[i][0]
			_tilt_off[i] = _last_tilts[i] - feet[i][1]
		_inert_t = 0.0
		_last_mode = state
	_inert_t += delta
	var fade := exp(-_inert_t / INERTIA_TAU)
	_toe_shift *= exp(-delta / 0.05)
	var legs := []
	for i in 2:
		var toe: Vector2 = feet[i][0] + _toe_off[i] * fade + Vector2(0, _toe_shift)
		var tilt: float = feet[i][1] + _tilt_off[i] * fade
		_last_toes[i] = toe
		_last_tilts[i] = tilt
		legs.append(_leg(pelvis, toe, tilt))

	# ---- 刀臂
	var shoulder := pelvis + SHOULDER.rotated(rot)
	var rest := 150.0 + hull_angle * 0.5
	if state == "kneel":
		rest = 100.0
	elif state == "wall":
		rest = 60.0
	elif state == "dash":
		rest = 175.0
	var want := rest
	var slashing: bool = m.slash_step >= 0
	if slashing:
		want = m.slash_dir + _slash_arc(m.slash_step, m.slash_t)
	if slashing != _was_slashing:
		_blade_off = rad_to_deg(angle_difference(deg_to_rad(want), deg_to_rad(_blade_angle)))
		_blade_t = 0.0
		_was_slashing = slashing
	if slashing:
		# 出刀：前约 0.06 秒从原来的位置接过去，之后严格按挥刀曲线走（命中判定不受影响）
		_blade_angle = want + _blade_off * exp(-_blade_t / 0.03)
	else:
		_blade_angle = lerp_angle_deg(_blade_angle, want, 1.0 - exp(-14.0 * delta))
	_blade_t += delta
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
	# glow < 0：没有意识的空机体，目镜和核心变暗
	var g: float = maxf(m.glow, 0.0)
	var eye: Color = CYAN.lerp(Color.WHITE, g) if m.glow >= 0.0 else Color(0.1, 0.3, 0.35)
	_shapes.append(["poly", visor, eye, CYAN if m.glow >= 0.0 else EDGE_BACK])
	_shapes.append(["dot", pelvis + Vector2(-3, -7).rotated(rot), 1.8 + g, eye])
	if state == "kneel":
		_shapes.append(["ring", pelvis + Vector2(0, -4), 20.0 + 3.0 * sin(m.time * 3.0), Color(0.4, 1.4, 1.7, 0.35 + 0.2 * sin(m.time * 3.0))])
	_shapes.append(["line", mount, barrel_end, 3.5, Color(0.35, 0.4, 0.48)])
	_shapes.append(["line", mount, barrel_end, 1.0, EDGE])
	_shapes.append(["dot", mount, 2.5, FILL])
	_add_leg(legs[0], FILL, EDGE)
	_shapes.append(["line", shoulder, hand, 3.0, EDGE])
	# 刀残影：挥得越快，前一帧到这一帧之间留下的半透明刀身越多
	var swing := angle_difference(deg_to_rad(_prev_blade), deg_to_rad(_blade_angle))
	if absf(swing) > deg_to_rad(6.0):
		for i in 4:
			var a := deg_to_rad(_prev_blade) + swing * (float(i) + 0.5) / 4.0
			var d := Vector2.from_angle(a)
			var h := shoulder + d * ARM_LEN
			_shapes.append(["line", h, h + d * BLADE_LEN, 3.0, Color(0.4, 1.5, 1.8, 0.07 + 0.05 * i)])
	_prev_blade = _blade_angle
	var hot: bool = m.slash_step >= 0 or state == "dash"
	if hot:
		_shapes.append(["line", hand, tip, 4.0, Color(0.25, 0.9, 1.0, 0.25)])
	_shapes.append(["line", hand, tip, 2.0, BLADE if hot else BLADE_REST])
	_shapes.append(["dot", shoulder, 2.0, EDGE])
	queue_redraw()


## 跑步步幅随速度拉长（48–100 像素）：跑得越快步子越大，高速时步频不会快到发抖
static func stride_px(speed: float) -> float:
	return clampf(40.0 + speed * 0.13, 48.0, 100.0)


## 每条腿返回 [脚尖位置, 跖骨方向偏转（度，正值脚尖下垂）]
func _foot_targets(m: Dictionary, pelvis: Vector2) -> Array:
	match m.state:
		"run":
			var out := []
			var length := stride_px(absf(m.vel.x))
			for i in 2:
				var p := fmod(m.run_phase + 0.5 * i, 1.0)
				var half := length * STANCE * 0.5
				if p < STANCE:
					out.append([Vector2(lerpf(half, -half, p / STANCE) + 4.0, 0.0), 0.0])
				else:
					var s := (p - STANCE) / (1.0 - STANCE)
					var x := lerpf(-half, half, s * s * (3.0 - 2.0 * s))
					var lift := sin(s * PI) * (6.0 + 8.0 * clampf(m.speed_ratio, 0.0, 1.0) + (3.0 if m.sprint else 0.0))
					out.append([Vector2(x + 4.0, -lift), 35.0 * sin(s * PI)])
			return out
		"skid":
			return [[Vector2(15, 0), -10.0], [Vector2(-3, 0), 0.0]]
		"air":
			var tuck := clampf(-m.vel.y / 450.0, 0.0, 1.0)
			return [[pelvis + Vector2(7, lerpf(21.0, 13.0, tuck)), 30.0 * tuck], [pelvis + Vector2(-6, lerpf(20.0, 15.0, tuck)), 40.0]]
		"dash":
			return [[pelvis + Vector2(-10, 17), 50.0], [pelvis + Vector2(-19, 12), 60.0]]
		"slide":
			return [[Vector2(20, 0), -20.0], [Vector2(-6, 0), 0.0]]
		"kneel":
			# 待机：一条腿跪下，一条腿撑着
			return [[Vector2(7, 0), -10.0], [Vector2(-9, 0), 70.0]]
		"wall":
			# 一只脚抵住身后的墙，另一条腿收起
			return [[Vector2(-6, -9), -80.0], [pelvis + Vector2(2, 13), 50.0]]
	return [[Vector2(6, 0), 0.0], [Vector2(-5, 0), 0.0]]


## 三节 IK：脚尖 → 踝（跖骨固定长度），髋 → 踝用两节、膝盖朝前。返回 [髋, 膝, 踝, 脚尖]
func _leg(hip: Vector2, toe: Vector2, meta_tilt: float) -> Array:
	var ankle := toe + META.rotated(deg_to_rad(meta_tilt))
	var d := hip.distance_to(ankle)
	var reach := THIGH + SHIN - 0.5
	if d > reach:
		var pull := (ankle - hip).normalized() * (d - reach)
		ankle -= pull
		toe -= pull
		d = reach
	d = maxf(d, 2.0)
	var dir := (ankle - hip) / d
	var along := (THIGH * THIGH - SHIN * SHIN + d * d) / (2.0 * d)
	var h := sqrt(maxf(THIGH * THIGH - along * along, 0.0))
	var knee := hip + dir * along - Vector2(-dir.y, dir.x) * h
	return [hip, knee, ankle, toe]


func _add_leg(l: Array, fill: Color, edge: Color) -> void:
	_shapes.append(["line", l[0], l[1], 6.0, edge])
	_shapes.append(["line", l[0], l[1], 3.6, fill])
	_shapes.append(["line", l[1], l[2], 5.0, edge])
	_shapes.append(["line", l[1], l[2], 2.8, fill])
	_shapes.append(["line", l[2], l[3], 3.5, edge])
	_shapes.append(["dot", l[1], 2.6, edge])
	_shapes.append(["dot", l[2], 2.0, fill])
	_shapes.append(["line", l[3], l[3] + Vector2(3, 0), 2.0, edge])


## 挥刀：第一刀 0–15% 回拉蓄力，然后劈过去并挥过头，最后收回到终点。
## 连击的第二、三刀不再回拉：接着上一刀的收势直接劈出去，整串连起来不顿。
func _slash_arc(step: int, t: float) -> float:
	var s: Dictionary = SLASH[step]
	var sgn := signf(s.to - s.from)
	var wind := 0.15 if step == 0 else 0.0
	var pull := 18.0 if step == 0 else 0.0
	if t < wind:
		return s.from - sgn * pull * (t / wind)
	var strike_end := wind + 0.4
	if t < strike_end:
		var u := (t - wind) / 0.4
		var e := 1.0 - pow(1.0 - u, 3.0)
		return lerpf(s.from - sgn * pull, s.to + sgn * s.over, e)
	var v := (t - strike_end) / (1.0 - strike_end)
	return lerpf(s.to + sgn * s.over, s.to, v * v)


## 挥刀时全身扭转：蓄力往后仰，劈下时往前压（连击的后两刀不再后仰）
func _slash_twist(step: int, t: float) -> float:
	var wind := 0.15 if step == 0 else 0.0
	var back := -10.0 if step == 0 else 4.0
	if t < wind:
		return back * (t / wind)
	if t < wind + 0.4:
		return lerpf(back, 16.0, (t - wind) / 0.4)
	return lerpf(16.0, 0.0, (t - wind - 0.4) / (1.0 - wind - 0.4))


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


## 机体被整体挪了 dy（世界坐标，正 = 往下）：髋、脚、线缆先留在原处，再平滑追上
func ground_shift(dy: float) -> void:
	_pelvis_y -= dy
	_toe_shift -= dy
	for c in _cables:
		for arr in c:
			for i in arr.size():
				arr[i].y -= dy


func kick() -> void:
	_recoil = 3.0


func muzzle() -> Vector2:
	return to_global(_muzzle)


## 刀身根部与刀尖的全局坐标（刀光拖尾用）
func blade_points() -> Array:
	return _blade_pts


## 当前这一帧要画的图形（倒影用）
func shapes() -> Array:
	return _shapes


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
			"ring":
				ci.draw_arc(s[1], s[2], 0.0, TAU, 32, s[3], 1.5, true)
			"cable":
				var pts: Array = s[1]
				for i in range(1, pts.size()):
					var k := 1.0 - float(i) / pts.size()
					ci.draw_line(pts[i - 1], pts[i], Color(0.4, 1.6, 1.9, 0.25 + 0.6 * k), 0.6 + 1.6 * k, true)


static func lerp_angle_deg(a: float, b: float, t: float) -> float:
	return rad_to_deg(lerp_angle(deg_to_rad(a), deg_to_rad(b), t))
