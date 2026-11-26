class_name EnemyShip
extends Area2D

signal sunk(ship: EnemyShip)
signal retreated(ship: EnemyShip)
signal fired(origin: Vector2, velocity: Vector2, lane: int, damage: float)

enum Action { SINK, FLEE, ATTACK_PLAYER, ATTACK_FORTRESS, ADVANCE, HOLD, ENTER_GATE }
enum Target { NONE, PLAYER, FORTRESS }

@export var config: EnemyShipConfig

var lanes: Lanes
var speed_cap := INF
var lane_index := 0:
	set(value):
		lane_index = value
		if combat != null:
			combat.lane_index = value
			if lanes != null:
				_align_to_lane()
var action := Action.HOLD
var morale := INF
var retreat_threshold := -INF
var lane_change_fail_reason := ""

var _reload := 0.0
var _target_delay := 0.0
var _target := Target.NONE
var _cruise_speed := 0.0
var _maneuver_left := 0.0
var _maneuver_x := 0.0
var _at_fort_stop := false

@onready var combat: ShipCombat = $Combat


func _ready() -> void:
	_cruise_speed = minf(speed_cap, config.speed + randf_range(0.0, config.speed_variance))
	combat.sprite_faces_left = config.sprite_faces_left
	combat.muzzle_offset = config.muzzle_offset
	combat.configure(config.damage_profile, config.size, -1.0, config.sprite, config.tint)
	combat.team = ShipCombat.Team.ENEMY
	combat.configure_damage_art(config.sail_torn_texture, config.sail_ruined_texture,
		config.hull_burn_texture, config.sail_cutout)
	combat.position.y = 1.0 - config.size.y * config.art_keel_ratio
	combat.lane_index = lane_index
	combat.min_gap = config.min_gap
	combat.sunk.connect(_on_sunk)
	combat.blast_pushed.connect(_on_blast_pushed)
	if lanes != null:
		_align_to_lane()
		lanes.register_ship(combat)


func set_morale(value: float, threshold: float) -> void:
	morale = value
	retreat_threshold = threshold


func step(delta: float, player: ShipCombat, fortress_front: float, fortress_alive: bool, gravity_acceleration: float) -> void:
	if not combat.targetable:
		return
	if action == Action.FLEE or morale <= retreat_threshold:
		_flee(delta)
		return

	_reload = combat.parts.advance_reload(_reload, delta)
	_target_delay = maxf(0.0, _target_delay - delta)
	var x := global_position.x
	var stop_x := fortress_front + config.stop_distance
	var player_in_range := absf(player.global_position.x - x) <= config.attack_range

	if player.targetable and player.lane_index == lane_index and player_in_range:
		action = Action.ATTACK_PLAYER
		_select_target(Target.PLAYER)
		_maneuver(delta, maxf(fortress_front + config.size.x * 0.5, player.global_position.x - config.attack_range),
			minf(lanes.sea_right + config.size.x * 0.5, player.global_position.x + config.attack_range))
		_aim_and_fire(player.aim_point(), gravity_acceleration)
	elif fortress_alive and absf(x - fortress_front) <= config.attack_range:
		action = Action.ATTACK_FORTRESS
		_select_target(Target.FORTRESS)
		if _at_fort_stop:
			_maneuver(delta, stop_x, minf(stop_x + config.attack_maneuver_distance, fortress_front + config.attack_range))
		else:
			_advance(delta, stop_x)
			_at_fort_stop = global_position.x <= stop_x
		_aim_and_fire(Vector2(fortress_front, lanes.lane_center_y(lane_index)), gravity_acceleration)
	else:
		_select_target(Target.NONE)
		combat.face(-1.0)
		action = Action.ADVANCE if _advance(delta, stop_x) else Action.HOLD


## 本轮 E-01 的行为树不主动换道。后续船型可在自己的行为条件成立时调用。
## 换道是否已彻底结束（y 已贴到目标道）。接舷战要求它为 true。
var lane_switch_done := true
## 换道完成那一刻的时间戳（毫秒）。
var lane_switch_finished_ms := 0


func try_change_lane(index: int) -> bool:
	lane_change_fail_reason = ""
	if not config.can_change_lane or not combat.targetable or lanes == null:
		lane_change_fail_reason = "未启用"
		return false
	if index != lanes.clamp_lane_index(index):
		lane_change_fail_reason = "无效航道"
		return false
	if index == lane_index:
		return true
	if not lanes.has_space(index, global_position.x, config.size.x, config.min_gap, combat, config.lane_change_margin):
		lane_change_fail_reason = "有人"
		return false
	if is_inf(combat.parts.lane_switch_multiplier()):
		lane_change_fail_reason = "舵已破坏"
		return false
	lane_index = index
	lane_switch_done = false
	return true


## 后续船型可接入躲弹行为。
func is_lane_switch_done() -> bool:
	return lane_switch_done


func _align_to_lane() -> void:
	global_position.y = lanes.lane_bottom_y(lane_index)
	z_index = lanes.content_z(lane_index)
	lane_switch_done = true
	lane_switch_finished_ms = Time.get_ticks_msec()


func consider_dodge(_projectile: Projectile) -> void:
	pass


func _advance(delta: float, stop_x: float) -> bool:
	var x := global_position.x
	global_position.x = move_toward(x, minf(x, stop_x), _speed() * delta)
	return global_position.x < x


func _flee(delta: float) -> void:
	action = Action.FLEE
	combat.face(1.0)
	global_position.x += _speed() * delta
	if global_position.x >= lanes.sea_right + config.size.x * 0.5:
		combat.targetable = false
		retreated.emit(self)
		queue_free()


func _speed() -> float:
	return _cruise_speed * combat.parts.speed_multiplier()


func _select_target(next: Target) -> void:
	if next != _target:
		_target = next
		_target_delay = config.target_switch_delay
		_at_fort_stop = false
		_maneuver_left = randf_range(0.8, 1.3)
		_maneuver_x = global_position.x


func _maneuver(delta: float, min_x: float, max_x: float) -> void:
	if config.attack_maneuver_distance <= 0.0 or min_x >= max_x:
		return
	_maneuver_left -= delta
	if _maneuver_left <= 0.0:
		_maneuver_left = randf_range(1.0, 2.2)
		_maneuver_x = global_position.x + randf_range(-1.0, 1.0) * config.attack_maneuver_distance
	global_position.x = move_toward(global_position.x, clampf(_maneuver_x, min_x, max_x), _speed() * 0.55 * delta)


func _on_blast_pushed(distance: float) -> void:
	global_position.x = clampf(global_position.x + distance, lanes.sea_left + config.size.x * 0.5,
		lanes.sea_right + config.size.x * 0.5)


func sail_into_gate(lane: int, entrance: Vector2, inside_x: float, duration: float) -> Tween:
	action = Action.ENTER_GATE
	combat.targetable = false
	combat.face(-1.0)
	z_index = lanes.content_z(maxi(lane_index, lane))
	var sail := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	sail.tween_property(self, "global_position", entrance, duration * 0.76)
	sail.tween_property(self, "lane_index", lane, 0.0)
	sail.tween_property(self, "global_position:x", inside_x, duration * 0.24)
	sail.tween_callback(hide)
	return sail


func _aim_and_fire(point: Vector2, gravity_acceleration: float) -> void:
	var heading := -1.0 if point.x < global_position.x else 1.0
	combat.face(heading)
	if _target_delay > 0.0 or _reload > 0.0 or not combat.parts.can_fire():
		return
	var origin := combat.muzzle_position(heading)
	var launch_velocity := Projectile.velocity_for_speed(origin, point, config.projectile_speed, gravity_acceleration)
	if launch_velocity.is_zero_approx():
		return
	_reload = config.attack_interval
	combat.recoil(heading, origin)
	fired.emit(origin, launch_velocity, lane_index, config.attack_damage)


func _on_sunk() -> void:
	action = Action.SINK
	combat.play_sinking().chain().tween_callback(queue_free)
	sunk.emit(self)
