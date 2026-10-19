class_name RobotRig
extends Node2D
## 模块化机体：部件是独立的 RigPart，姿势按 Poses 数据表插值。
## 原点在脚底；面朝方向用 scale.x = ±1 翻转。
## 上半身是独立的一层：枪臂跟鼠标、刀臂跟挥刀，不打断下半身的动作。

const HIP_Y := -19.0
const FILL := Color(0.17, 0.2, 0.26)
const FILL_BACK := Color(0.1, 0.12, 0.16)
const EDGE := Color(0.22, 0.78, 0.88)
const EDGE_BACK := Color(0.12, 0.42, 0.5)
const BLADE := Color(0.82, 1.0, 1.0)

var parts := {}
var pose := {}


func _ready() -> void:
	# 冲刺残影是 duplicate() 出来的，已经带着部件
	if get_child_count() > 0:
		return
	var hip := Node2D.new()
	hip.name = "hip"
	hip.position = Vector2(0, HIP_Y)
	add_child(hip)
	parts.hip = hip
	_leg(hip, "b", -3, FILL_BACK, EDGE_BACK)
	var torso := _part(hip, "torso", "torso", Vector2.ZERO, 13, 8, FILL, EDGE, 0)
	_part(torso, "head", "head", Vector2(0, -13), 9, 8, FILL, EDGE, 0)
	var ub := _part(torso, "uarm_b", "limb", Vector2(0, -11), 8, 4, FILL_BACK, EDGE_BACK, -2)
	var fb := _part(ub, "farm_b", "limb", Vector2(0, 8), 7, 3, FILL_BACK, EDGE_BACK, 0)
	_part(fb, "blade", "blade", Vector2(0, 7), 21, 2, FILL, BLADE, 0)
	_leg(hip, "f", 1, FILL, EDGE)
	var uf := _part(torso, "uarm_f", "limb", Vector2(0, -11), 8, 4, FILL, EDGE, 3)
	var ff := _part(uf, "farm_f", "limb", Vector2(0, 8), 7, 3, FILL, EDGE, 0)
	_part(ff, "gun", "gun", Vector2(0, 7), 7, 4, Color(0.3, 0.34, 0.4), EDGE, 0)
	for j in Poses.JOINTS:
		pose[j] = Poses.IDLE[j]


func _leg(hip: Node2D, side: String, z: int, fill: Color, edge: Color) -> void:
	var th := _part(hip, "thigh_" + side, "limb", Vector2.ZERO, 10, 5, fill, edge, z)
	var sh := _part(th, "shin_" + side, "limb", Vector2(0, 10), 10, 4, fill, edge, 0)
	_part(sh, "foot_" + side, "foot", Vector2(0, 10), 6, 3, fill, edge, 0)


func _part(parent: Node2D, part_name: String, kind: String, pos: Vector2, length: float, width: float, fill: Color, edge: Color, z: int) -> RigPart:
	var p := RigPart.new()
	p.name = part_name
	p.kind = kind
	p.position = pos
	p.length = length
	p.width = width
	p.fill = fill
	p.edge = edge
	p.z_index = z
	parent.add_child(p)
	parts[part_name] = p
	return p


## 把当前姿势向目标姿势插值，rate 越大跟得越紧
func apply(target: Dictionary, delta: float, rate: float) -> void:
	var k := 1.0 - exp(-rate * delta)
	for j in Poses.JOINTS:
		var t: float = target.get(j, 0.0)
		pose[j] = lerpf(pose.get(j, t), t, k)
	parts.hip.position.y = HIP_Y + pose.hip_y
	_rot("torso", pose.torso)
	_rot("head", pose.head)
	for side in ["f", "b"]:
		var th: float = pose["thigh_" + side]
		var sh: float = pose["shin_" + side]
		_rot("thigh_" + side, th)
		_rot("shin_" + side, sh)
		_rot("foot_" + side, -(th + sh))  # 脚掌保持水平
	_rot("uarm_f", pose.uarm_f)
	_rot("farm_f", pose.farm_f)
	_rot("uarm_b", pose.uarm_b)
	_rot("farm_b", pose.farm_b)


## 持枪待命：上臂大部分跟随动作姿势，前臂和枪指向瞄准方向（local_aim 已按朝向翻转），头跟着看。
## M2 开枪时把 aim_weight 提到 1 就是完全举枪。
func aim_gun(local_aim: Vector2, aim_weight := 0.3) -> void:
	var ang := rad_to_deg(local_aim.angle())
	var upper := lerpf(pose.uarm_f, ang - 90.0 - pose.torso, aim_weight)
	_rot("uarm_f", upper)
	_rot("farm_f", wrapf(ang - 90.0 - pose.torso - upper, -180.0, 180.0))
	if local_aim.x > -0.2:
		_rot("head", clampf(ang * 0.5, -30.0, 25.0) - pose.torso * 0.6)


## 刀臂指向 local_deg（面朝右的局部角度），挥刀时画在身体前面
func swing_blade(local_deg: float) -> void:
	_rot("uarm_b", local_deg - 90.0 - pose.torso)
	_rot("farm_b", -10.0)
	parts.uarm_b.z_index = 4


func release_blade() -> void:
	parts.uarm_b.z_index = -2


## 刀身根部与刀尖的全局坐标（刀光拖尾用）
func blade_points() -> Array:
	var b: RigPart = parts.blade
	var y := b.global_transform.y.normalized()
	return [b.global_position + y * 5.0, b.global_position + y * (b.length + 1.0)]


func set_glow(value: float) -> void:
	var torso: RigPart = parts.torso
	if not is_equal_approx(torso.glow, value):
		torso.glow = value
		torso.queue_redraw()


func _rot(part_name: String, deg: float) -> void:
	parts[part_name].rotation_degrees = deg
