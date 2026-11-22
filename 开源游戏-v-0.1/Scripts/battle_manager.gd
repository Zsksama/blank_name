extends Node2D

## 战斗管理器：波次生成、玩家开火与弹药、每道炮台自动开火（抛物线弹道）、
## 胜负判定、切经营场景。所有数值都用 @export 暴露，方便策划侧调参而不用改代码。

const PROJECTILE_SCENE := preload("res://Scenes/projectile.tscn")
const ENEMY_SCENE := preload("res://Scenes/enemy_ship.tscn")
const TURRET_SCENE := preload("res://Scenes/turret.tscn")

@export_group("胜利条件")
## 击沉多少艘算士气胜利（01 第六节 B16：不必全歼）
@export var kills_to_win: int = 12

@export_group("敌船")
@export var spawn_interval: float = 2.2
@export var first_spawn_delay: float = 1.5
@export var enemy_speed: float = 70.0
@export var spawn_x: float = 1330.0

@export_group("玩家开火")
@export var player_ammo: int = 30
@export var player_fire_cooldown: float = 0.45
## 同一条道上没有敌人时，玩家这一炮默认打多远
@export var player_default_range: float = 620.0

@export_group("海道炮台")
## 炮台中心 X：贴左侧陆地靠水的一侧
@export var turret_x: float = 205.0
## 所有炮台共享的碉堡总耐久，被冲破一次 -1
@export var max_fortress_hp: int = 10
@export var turret_fire_interval: float = 1.3
@export var turret_fire_range: float = 800.0

@export_group("抛物线弹道")
## 重力加速度（像素/秒²），越大弧线越"陡"
@export var arc_gravity: float = 1500.0
## 这一炮从炮口飞到落点用多久（秒），越短越平快
@export var arc_flight_time: float = 0.62

@export_group("结算")
@export var end_delay: float = 3.0
@export var management_scene: String = "res://Scenes/Management/management_demo.tscn"

@onready var _lanes: Node = $Lanes
@onready var _turret_root: Node2D = $Fortress
@onready var _player = $PlayerShip
@onready var _enemies: Node2D = $Enemies
@onready var _projectiles: Node2D = $Projectiles
@onready var _status: Label = $HUD/Status
@onready var _banner: Label = $HUD/Banner

var ammo: int = 0
var kills: int = 0
var fortress_hp: int = 0
var is_over: bool = false

var _turrets: Array[Node2D] = []
var _turret_timers: Array[float] = []
var _spawn_timer: float = 0.0
var _player_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	ammo = player_ammo
	fortress_hp = max_fortress_hp
	_spawn_timer = first_spawn_delay
	_banner.text = ""
	build_turrets()
	_refresh_status()


## 每条海道生成一座炮台。海道条数改了之后也可以直接调这个重建。
func build_turrets() -> void:
	for child in _turret_root.get_children():
		child.queue_free()
	_turrets.clear()
	_turret_timers.clear()
	var count: int = maxi(_lanes.lane_count, 1)
	for i in range(count):
		var turret: Node2D = TURRET_SCENE.instantiate()
		turret.lane_index = i
		turret.position = Vector2(turret_x, _lanes.lane_center_y(i))
		_turret_root.add_child(turret)
		_turrets.append(turret)
		# 错开各道首次开火的时间，避免五门炮同时响
		_turret_timers.append(turret_fire_interval * _rng.randf_range(0.2, 1.0))


func _process(delta: float) -> void:
	if is_over:
		return
	_player_timer = maxf(0.0, _player_timer - delta)

	_try_player_fire()

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = spawn_interval
		spawn_enemy()

	_update_turrets(delta)


# ---------- 敌船 ----------

## 生成一艘敌船。lane 为 -1 时随机选一条道。
func spawn_enemy(lane: int = -1) -> Node2D:
	var count: int = maxi(_lanes.lane_count, 1)
	var index: int = lane if lane >= 0 else _rng.randi_range(0, count - 1)
	var ship: Node2D = ENEMY_SCENE.instantiate()
	ship.lane_index = index
	ship.speed = enemy_speed
	ship.position = Vector2(spawn_x, _lanes.lane_center_y(index))
	ship.sunk.connect(_on_enemy_sunk)
	ship.breached.connect(_on_enemy_breached)
	_enemies.add_child(ship)
	return ship


func _on_enemy_sunk(_ship: Area2D) -> void:
	kills += 1
	_refresh_status()
	if kills >= kills_to_win:
		_finish(true)


func _on_enemy_breached(_ship: Area2D) -> void:
	# 被冲破：扣碉堡总耐久，耐久归零即失败
	fortress_hp = maxi(0, fortress_hp - 1)
	_refresh_status()
	if fortress_hp <= 0:
		_finish(false)


# ---------- 炮台 ----------

func _update_turrets(delta: float) -> void:
	for i in range(_turrets.size()):
		_turret_timers[i] = maxf(0.0, _turret_timers[i] - delta)
		if _turret_timers[i] > 0.0:
			continue
		var turret: Node2D = _turrets[i]
		var target := _frontmost_enemy_in_lane(i, turret.global_position.x + turret_fire_range)
		if target == null:
			continue
		_launch_arc(turret.muzzle_position(), target.global_position)
		_turret_timers[i] = turret_fire_interval * _rng.randf_range(0.85, 1.15)


## 找某条道上最靠前（最靠左）的敌船，且不能超出 max_x。
func _frontmost_enemy_in_lane(lane: int, max_x: float) -> Node2D:
	var best: Node2D = null
	for child in _enemies.get_children():
		var ship := child as Node2D
		if ship == null or ship.lane_index != lane:
			continue
		if ship.global_position.x > max_x:
			continue
		if best == null or ship.global_position.x < best.global_position.x:
			best = ship
	return best


# ---------- 开火 ----------

func _try_player_fire() -> void:
	if _player_timer > 0.0 or ammo <= 0:
		return
	if not Input.is_action_pressed("fire"):
		return
	ammo -= 1
	_player_timer = player_fire_cooldown
	var from: Vector2 = _player.muzzle_position()
	var target := _frontmost_enemy_in_lane(_player_lane(), 1340.0)
	var to: Vector2 = target.global_position if target != null else Vector2(from.x + player_default_range, from.y)
	_launch_arc(from, to)
	_refresh_status()


func _player_lane() -> int:
	if _player.has_method("current_lane"):
		return _player.current_lane()
	if _player.has_method("lane_index_at_y"):
		return _player.lane_index_at_y(_player.global_position.y)
	return _lanes.lane_index_at_y(_player.global_position.y)


## 打出一发抛物线炮弹：给定起点与落点，按固定飞行时间反解初速度。
func _launch_arc(from: Vector2, to: Vector2) -> Area2D:
	var ball: Area2D = PROJECTILE_SCENE.instantiate()
	ball.position = from
	ball.arc_gravity = arc_gravity
	ball.velocity = arc_velocity(from, to, arc_flight_time, arc_gravity)
	_projectiles.add_child(ball)
	return ball


## 抛体反解：x 方向匀速，y 方向 vy = (dy)/t - 0.5*g*t
static func arc_velocity(from: Vector2, to: Vector2, flight_time: float, gravity: float) -> Vector2:
	var t: float = maxf(flight_time, 0.05)
	return Vector2((to.x - from.x) / t, (to.y - from.y) / t - 0.5 * gravity * t)


# ---------- 结算 ----------

func _finish(won: bool) -> void:
	if is_over:
		return
	is_over = true
	_banner.text = "守住了！" if won else "碉堡失守……"
	_banner.add_theme_color_override("font_color", Color(0.85, 0.78, 0.45) if won else Color(0.72, 0.3, 0.28))
	refresh_after_end(won)


## 结算后要执行的收尾动作。单独一个函数，方便测试时替换/覆盖。
func refresh_after_end(_won: bool) -> void:
	await get_tree().create_timer(end_delay).timeout
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file(management_scene)


func _refresh_status() -> void:
	if _status == null:
		return
	_status.text = "弹药  %d        击沉  %d / %d        碉堡  %d / %d" % [
		ammo, kills, kills_to_win, fortress_hp, max_fortress_hp,
	]
