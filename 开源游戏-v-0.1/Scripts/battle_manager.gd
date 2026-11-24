extends Node2D

signal enemy_sunk(ship: EnemyShip)
signal enemy_retreated(ship: EnemyShip)
signal boarding_nearby(enemy_name: String)

const PROJECTILE_SCENE := preload("res://Scenes/projectile.tscn")
const ENEMY_SCENE := preload("res://Scenes/enemy_ship.tscn")
const TURRET_SCENE := preload("res://Scenes/turret.tscn")

@export_group("胜利条件")
@export var kills_to_win: int = 12

@export_group("敌船")
@export var enemy_config: EnemyShipConfig = preload("res://Data/Combat/enemy_e01.tres")
@export var spawn_interval: float = 2.2
@export var first_spawn_delay: float = 1.5
@export var spawn_x: float = 1330.0

@export_group("碉堡")
@export var turret_lanes: Array[int] = [0, 1, 3, 4]
@export var water_gate_lane: int = 2
@export var turret_x: float = 37.5
@export var turret_scale: float = 0.5
@export var max_fortress_hp: int = 400
@export var turret_fire_interval: float = 3.0
@export var turret_fire_range: float = 400.0
@export var turret_shell_speed: float = 1400.0
@export var turret_damage: float = 6.0

@export_group("接舷提示")
@export var boarding_distance: float = 60.0
@export var boarding_cooldown: float = 1.0

@export_group("结算")
@export var end_delay: float = 3.0
@export var management_scene: String = "res://Scenes/Management/management_demo.tscn"

@onready var _lanes: Lanes = $Lanes
@onready var _config: CombatConfig = $CombatConfig
@onready var _turret_root: Node2D = $Fortress
@onready var _player: PlayerShip = $PlayerShip
@onready var _weapon: PlayerWeapon = $PlayerShip/Combat/Weapon
@onready var _crosshair: Node2D = $Crosshair
@onready var _enemies: Node2D = $Enemies
@onready var _projectiles: Node2D = $Projectiles
@onready var _status: Label = $HUD/Status
@onready var _banner: Label = $HUD/Banner

var kills: int = 0
var fortress_hp: float = 0.0
var is_over: bool = false
var _victory_pending := false

var _turrets: Array[Node2D] = []
var _turret_timers: Array[float] = []
var _spawn_timer := 0.0
var _pending_spawn_lane := -1
var _boarding_left := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# 玩家先更新换道和移动，敌船再选目标，最后推进炮弹。
	process_physics_priority = 10
	_rng.randomize()
	_weapon.config = _config
	_weapon.shot_requested.connect(_on_player_shot)
	_weapon.state_changed.connect(_refresh_status)
	_player.combat.parts.part_changed.connect(_on_player_part_changed)
	fortress_hp = float(max_fortress_hp)
	_spawn_timer = first_spawn_delay
	_banner.text = ""
	build_turrets()


func build_turrets() -> void:
	for turret in _turrets:
		_turret_root.remove_child(turret)
		turret.queue_free()
	_turrets.clear()
	_turret_timers.clear()

	var counts := PackedInt32Array()
	counts.resize(_lanes.lane_count)
	for lane in turret_lanes:
		if _turrets.size() >= 6:
			break
		if lane < 0 or lane >= counts.size() or counts[lane] >= (1 if lane == water_gate_lane else 2):
			continue
		var turret: Node2D = TURRET_SCENE.instantiate()
		turret.lane_index = lane
		turret.position = Vector2(turret_x, _lanes.lane_bottom_y(lane) - 25.0 - counts[lane] * 34.0)
		turret.scale = Vector2.ONE * turret_scale
		_turret_root.add_child(turret)
		_turrets.append(turret)
		_turret_timers.append(turret_fire_interval * _rng.randf_range(0.2, 1.0))
		counts[lane] += 1
	_refresh_status()


func _process(_delta: float) -> void:
	_crosshair.global_position = get_global_mouse_position()


func _physics_process(delta: float) -> void:
	if is_over:
		return
	_update_spawn(delta)

	for child in _enemies.get_children():
		var ship := child as EnemyShip
		if ship != null:
			ship.step(delta, _player.combat, _lanes.sea_left, fortress_hp > 0.0, _config.gravity)

	_update_turrets(delta)
	_check_boarding(delta)


func _update_spawn(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	if _pending_spawn_lane < 0:
		_pending_spawn_lane = _rng.randi_range(0, maxi(_lanes.lane_count - 1, 0))
	if spawn_enemy(_pending_spawn_lane) != null:
		_spawn_timer = spawn_interval
		_pending_spawn_lane = -1


## 入口返回空时保留当前生成请求，等同道空出位置再试。
func spawn_enemy(lane: int = -1) -> EnemyShip:
	var index := _rng.randi_range(0, maxi(_lanes.lane_count - 1, 0)) if lane == -1 else lane
	if is_over or not _lanes.has_space(index, spawn_x, enemy_config.size.x, enemy_config.min_gap):
		return null

	var ship: EnemyShip = ENEMY_SCENE.instantiate()
	ship.config = enemy_config
	ship.lanes = _lanes
	ship.lane_index = index
	ship.position = _enemies.to_local(Vector2(spawn_x, _lanes.lane_bottom_y(index)))
	ship.sunk.connect(_on_enemy_sunk)
	ship.retreated.connect(enemy_retreated.emit)
	ship.fired.connect(_on_enemy_fired)
	_enemies.add_child(ship)
	return ship


func _on_enemy_sunk(ship: EnemyShip) -> void:
	if is_over:
		return
	kills += 1
	_refresh_status()
	enemy_sunk.emit(ship)
	if kills >= kills_to_win and not _victory_pending:
		# 同一物理帧可能有一发爆炸击沉多艘船，登记完再停战。
		_victory_pending = true
		_finish.call_deferred(true)


func _on_enemy_fired(origin: Vector2, velocity: Vector2, lane: int, damage: float) -> void:
	launch_projectile(origin, velocity, lane, ShipCombat.Team.ENEMY, damage)


func _on_fortress_hit(damage: float) -> void:
	if is_over or _victory_pending:
		return
	fortress_hp = maxf(0.0, fortress_hp - damage)
	_refresh_status()
	if fortress_hp <= 0.0:
		_finish(false)


func _update_turrets(delta: float) -> void:
	for index in range(_turrets.size()):
		_turret_timers[index] = maxf(0.0, _turret_timers[index] - delta)
		if _turret_timers[index] > 0.0:
			continue
		var turret: Node2D = _turrets[index]
		var origin: Vector2 = turret.muzzle_position()
		var lane: int = turret.lane_index
		var target := _frontmost_enemy_in_lane(lane, origin.x + turret_fire_range)
		if target == null:
			continue
		var aim := target.combat.aim_point()
		launch_projectile(origin, origin.direction_to(aim) * turret_shell_speed,
			lane, ShipCombat.Team.ALLY, turret_damage, ShipParts.Ammo.SOLID, 0.0)
		_turret_timers[index] = turret_fire_interval


func _frontmost_enemy_in_lane(lane: int, max_x: float) -> EnemyShip:
	var best: EnemyShip = null
	for child in _enemies.get_children():
		var ship := child as EnemyShip
		if ship == null or not ship.combat.targetable or ship.lane_index != lane:
			continue
		if ship.global_position.x > max_x:
			continue
		if best == null or ship.global_position.x < best.global_position.x:
			best = ship
	return best


func _check_boarding(delta: float) -> void:
	_boarding_left = maxf(0.0, _boarding_left - delta)
	if _boarding_left > 0.0 or not _player.combat.targetable or _player.is_switching():
		return
	var player_hull := _player.combat.hitbox(ShipParts.Part.HULL)
	for child in _enemies.get_children():
		var ship := child as EnemyShip
		if ship == null or not ship.combat.targetable or ship.lane_index != _player.lane_index:
			continue
		var enemy_hull := ship.combat.hitbox(ShipParts.Part.HULL)
		var gap := maxf(enemy_hull.position.x - player_hull.end.x, player_hull.position.x - enemy_hull.end.x)
		if gap >= boarding_distance:
			continue
		_boarding_left = boarding_cooldown
		print("[接舷] %s 逼近，接舷战未实现" % ship.config.display_name)
		boarding_nearby.emit(ship.config.display_name)
		break


func _on_player_shot(origin: Vector2, velocity: Vector2, lane: int, ammo_type: ShipParts.Ammo) -> void:
	launch_projectile(origin, velocity, lane, ShipCombat.Team.ALLY, _config.shell_damage[ammo_type], ammo_type)


func _on_player_part_changed(_part: ShipParts.Part, _hp: float, _condition: ShipParts.Condition) -> void:
	_refresh_status()


func launch_projectile(
	origin: Vector2, velocity: Vector2, lane: int, team: ShipCombat.Team,
	damage: float, ammo_type: ShipParts.Ammo = ShipParts.Ammo.SOLID, gravity: float = NAN
) -> Projectile:
	var ball: Projectile = PROJECTILE_SCENE.instantiate()
	ball.position = _projectiles.to_local(origin)
	ball.arc_gravity = _config.gravity if is_nan(gravity) else gravity
	ball.velocity = velocity
	ball.lane_index = lane
	ball.team = team
	ball.damage = damage
	ball.ammo = ammo_type
	ball.lanes = _lanes
	if team == ShipCombat.Team.ALLY and is_nan(gravity):
		ball.drag_k = _config.drag_k
		ball.pierce_left = _config.pierce_count[ammo_type]
		ball.pierce_damage_falloff = _config.pierce_damage_falloff
		if ammo_type == ShipParts.Ammo.EXPLOSIVE:
			ball.explode_radius = _config.explode_radius
			if _config.explode_self_damage:
				ball.explosion_owner = _player.combat
	if team == ShipCombat.Team.ENEMY:
		var height := _lanes.sea_bottom - _lanes.sea_top
		ball.fortress_bounds = Rect2(_lanes.sea_left - 16.0, _lanes.sea_top, 16.0, height)
		ball.fortress_hit.connect(_on_fortress_hit)
	_projectiles.add_child(ball)
	return ball


func _finish(won: bool) -> void:
	if is_over:
		return
	is_over = true
	_weapon.set_process(false)
	_weapon.set_physics_process(false)
	_weapon.set_process_unhandled_input(false)
	_weapon.get_node("Preview").hide()
	for child in _projectiles.get_children():
		child.set_physics_process(false)
	_banner.text = "守住了！" if won else "碉堡失守……"
	_banner.add_theme_color_override("font_color", Color(0.85, 0.78, 0.45) if won else Color(0.72, 0.3, 0.28))
	refresh_after_end(won)


func refresh_after_end(_won: bool) -> void:
	await get_tree().create_timer(end_delay).timeout
	if is_inside_tree():
		get_tree().change_scene_to_file(management_scene)


func _refresh_status() -> void:
	var ammo_names := ["实心", "破帆", "爆炸"]
	var ammo_labels := PackedStringArray()
	for index in range(_weapon.ammo.size()):
		var selected := "▶" if index == _weapon.ammo_selected else " "
		ammo_labels.append("%s%s%d" % [selected, ammo_names[index], _weapon.ammo[index]])

	var labels := ["舰体", "帆", "炮台", "舵", "撞角"]
	var parts := _player.combat.parts
	var order := [ShipParts.Part.HULL, ShipParts.Part.SAIL, ShipParts.Part.CANNON, ShipParts.Part.RUDDER, ShipParts.Part.RAM]
	var hp_labels := PackedStringArray()
	for index in range(order.size()):
		var part: ShipParts.Part = order[index]
		var ratio := parts.hp(part) / maxf(parts.max_hp(part), 0.001)
		hp_labels.append("%s%d%%" % [labels[index], roundi(ratio * 100.0)])
	var fort_percent := roundi(100.0 * fortress_hp / maxf(max_fortress_hp, 1.0))
	var level := "·"
	match _turrets.size():
		4: level = "Ⅰ"
		5: level = "Ⅱ"
		6: level = "Ⅲ"
	_status.text = "%s        击沉 %d / %d        堡%s %d / %d（%d%%）\n%s" % [
		"  ".join(ammo_labels), kills, kills_to_win, level, ceili(fortress_hp), max_fortress_hp, fort_percent, "  ".join(hp_labels)]
