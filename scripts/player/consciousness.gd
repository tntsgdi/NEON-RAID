class_name Consciousness
extends Node
## R-0 的意识：决定当前控制哪具机体，负责软锁定、夺壳和紧急投射。
##   软锁定：离瞄准方向最近、够得着（360 像素）的目标挂准星；纯键盘瞄准时锥角放宽
##   夺壳：E 夺准星目标（220 像素内、在 possessable 组里）；继承 70% 速度；旧机体——基础机体跪下待机，敌人机体断电报废
##   紧急投射：被夺来的机体被打坏 → 弹出光球，1.5 秒内可以投射到附近任意机体；超时 → lost（回检查点）

signal shell_changed(shell: Node2D)
signal lost

const POSSESS_RANGE := 220.0
const LOCK_RANGE := 360.0

var base: Player
var current: Node2D
var input: PlayerInput = DeviceInput.new()
var lock: Node2D
var lock_in_range := false
var world: Node2D
var reticle: Reticle


func setup(base_shell: Player, world_node: Node2D) -> void:
	base = base_shell
	world = world_node
	current = base
	base.input = input
	reticle = Reticle.new()
	reticle.z_index = 9
	world.add_child(reticle)
	process_physics_priority = -10  # 先算锁定，再让机体用


## 回到基础机体并放到 pos（重来、回检查点、测试都用它）
func return_to_base(pos: Vector2) -> void:
	if current != base and is_instance_valid(current):
		_detach(current)
		current.release_control()
	if base.parked:
		base.take_control(input, Vector2.ZERO)
	base.input = input
	base.reset_at(pos)
	current = base
	lock = null
	shell_changed.emit(base)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(current):
		return
	_update_lock()
	if "lock_target" in current:
		current.lock_target = lock
	reticle.target = lock
	reticle.in_range = lock_in_range
	if input.possess_pressed and lock_in_range:
		possess(lock)
		return
	# 光球碰到任意机体就直接投射进去
	if current is Wisp:
		for n in get_tree().get_nodes_in_group("possessable"):
			if n.alive() and n.center().distance_to(current.global_position) < 16.0:
				possess(n)
				return


func _aim_dir() -> Vector2:
	var f: float = float(current.facing) if "facing" in current else 1.0
	if input.aim_keys or input.aim.length() < 0.1:
		return Vector2(f, 0)
	return input.aim.normalized()


func _update_lock() -> void:
	var origin: Vector2 = current.global_position + Vector2(0, -18)
	var dir := _aim_dir()
	var cone := deg_to_rad(75.0 if input.aim_keys else 35.0)
	if current is Wisp:
		cone = PI  # 光球：附近哪个都行
	var best: Node2D = null
	var best_score := INF
	var prev_score := INF
	var seen := {}
	for group in ["hittable", "possessable"]:
		for n in get_tree().get_nodes_in_group(group):
			if n == current or seen.has(n) or not n.alive():
				continue
			seen[n] = true
			var to: Vector2 = n.center() - origin
			var d := to.length()
			if d > LOCK_RANGE:
				continue
			var ang := absf(dir.angle_to(to)) if d > 1.0 else 0.0
			if ang > cone and d > 40.0:
				continue
			var score := d * (1.0 + 1.5 * ang)
			if n == lock:
				prev_score = score
			if score < best_score:
				best_score = score
				best = n
	# 迟滞：原来的目标只要不比最好的差太多就不换，准星不会来回跳
	if is_instance_valid(lock) and prev_score < INF and prev_score < best_score * 1.3:
		best = lock
	lock = best
	lock_in_range = lock != null and lock.is_in_group("possessable") and lock.center().distance_to(origin) <= POSSESS_RANGE


func possess(target: Node2D) -> void:
	if not is_instance_valid(target) or target == current:
		return
	var old := current
	var from: Vector2 = old.global_position + Vector2(0, -16)
	var vel: Vector2 = old.velocity * 0.7 if "velocity" in old else Vector2.ZERO
	FxBeam.spawn(world, from, target.center())
	Fx.flash(world, target.center(), Neon.WHITE_HOT, 16.0)
	Fx.ring(world, target.center(), 22.0)
	Audio.play("possess", -2.0)
	TimeFx.hitstop(0.05)
	_detach(old)
	old.release_control()
	target.take_control(input, vel)
	# 新机体继承原来的朝向：夺过去之后还是面朝同一边，锁定和出手方向不会突然反过来
	if "facing" in old and "facing" in target:
		target.facing = old.facing
	if target != base and target.has_signal("died"):
		target.died.connect(_on_shell_died, CONNECT_ONE_SHOT)
	current = target
	lock = null
	shell_changed.emit(target)


## 意识主动离开一具机体时，先断开它的"被打坏"信号——它接下来的断电报废不算被打坏
func _detach(shell: Node) -> void:
	if shell.has_signal("died") and shell.died.is_connected(_on_shell_died):
		shell.died.disconnect(_on_shell_died)


## 夺来的机体被打坏：弹出意识光球
func _on_shell_died(shell: Node) -> void:
	if shell != current:
		return
	var w := Wisp.new()
	w.position = shell.global_position + Vector2(0, -10)
	world.add_child(w)
	w.take_control(input, Vector2(0, -160))
	w.expired.connect(func(): lost.emit())
	current = w
	lock = null
	Audio.play("overclock", -6.0, 1.4)
	shell_changed.emit(w)
