class_name EnemyShip
extends Area2D

signal sunk(ship: EnemyShip)
signal retreated(ship: EnemyShip)
signal fired(origin: Vector2, velocity: Vector2, lane: int, damage: float)

enum Action { SINK, FLEE, ATTACK_PLAYER, ATTACK_FORTRESS, ADVANCE, HOLD, ENTER_GATE }
enum Target { NONE, PLAYER, FORTRESS }

const RETREAT_SPEED_MULTIPLIER := 3.0


class WeaponDeck extends Node2D:
	var size: Vector2
	var parts: ShipParts

	func _draw() -> void:
		var box := Rect2(-size * 0.5, size)
		var can_fire := parts.can_fire()
		draw_rect(box, Color(0.52, 0.29, 0.13) if can_fire else Color(0.27, 0.23, 0.22))
		draw_rect(box, Color(0.81, 0.58, 0.29), false)
		var bar := Rect2(box.position - Vector2(0.0, 6.0), Vector2(size.x, 3.0))
		draw_rect(bar.grow(1.0), Color(0.13, 0.10, 0.09))
		bar.size.x *= parts.hp(ShipParts.Part.CANNON) / maxf(1.0, parts.max_hp(ShipParts.Part.CANNON))
		draw_rect(bar, Color(0.98, 0.77, 0.42))


class CentipedeFlag extends Node2D:
	func _draw() -> void:
		draw_line(Vector2(0, 9), Vector2(0, -14), Color(0.25, 0.16, 0.11), 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(0, -14), Vector2(32, -11),
			Vector2(27, -6), Vector2(0, -6)]), Color(0.74, 0.20, 0.12))
		for x in range(4, 29, 5):
			draw_line(Vector2(x, -7), Vector2(x + 3, -1), Color(0.84, 0.32, 0.16), 2.0)


@export var config: EnemyShipConfig

var lanes: Lanes
var speed_cap := INF
var formation_leader := false
var formation_predecessor: EnemyShip
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
var boarding_power := 0.0
var boarding_locked := false
var horizontal_speed := 0.0
var weave_strength := 0.0

var _reload := 0.0
var _target_delay := 0.0
var _target := Target.NONE
var _cruise_speed := 0.0
var _sway_phase := 0.0
var _firing_anchor_x := NAN
var _deck: WeaponDeck
var _flag: CentipedeFlag

@onready var combat: ShipCombat = $Combat


func _ready() -> void:
	_cruise_speed = clampf(config.speed + randf_range(0.0, config.speed_variance), 0.0,
		maxf(0.0, minf(speed_cap, EnemyShipConfig.MAX_SPEED)))
	_sway_phase = randf_range(0.0, TAU)
	combat.sprite_faces_left = config.sprite_faces_left
	combat.muzzle_offset = config.muzzle_offset
	combat.configure(config.build_damage_profile(), config.size, -1.0, config.sprite, config.tint)
	combat.team = ShipCombat.Team.ENEMY
	combat.configure_damage_art(config.sail_torn_texture, config.sail_ruined_texture,
		config.hull_burn_texture, config.sail_cutout)
	combat.position.y = 1.0 - config.size.y * config.art_keel_ratio
	combat.lane_index = lane_index
	combat.min_gap = config.min_gap
	combat.sunk.connect(_on_sunk)
	combat.blast_pushed.connect(_on_blast_pushed)
	var weapon_box := combat.get_node("Hitboxes/hit_cannon") as CollisionShape2D
	_deck = WeaponDeck.new()
	_deck.name = "WeaponDeck"
	_deck.size = (weapon_box.shape as RectangleShape2D).size
	_deck.parts = combat.parts
	combat.set_part_art(ShipParts.Part.CANNON, _deck)
	combat.parts.part_changed.connect(_on_part_changed)
	if formation_leader:
		_flag = CentipedeFlag.new()
		_flag.name = "CentipedeFlag"
		_flag.position = Vector2(-8.0, -config.size.y * 0.44)
		combat.get_node("Visual").add_child(_flag)
	if lanes != null:
		horizontal_speed = -_speed()
		_align_to_lane()
		lanes.register_ship(combat)


func set_morale(value: float, threshold: float) -> void:
	morale = value
	retreat_threshold = threshold


func step(delta: float, player: ShipCombat, fortress_front: float, fortress_alive: bool, battle_morale: float = INF) -> void:
	horizontal_speed = 0.0
	weave_strength = 0.0
	if not combat.targetable or boarding_locked:
		return
	if action == Action.FLEE or battle_morale < 0.10 or morale <= retreat_threshold:
		_flee(delta)
		return

	_reload = combat.parts.advance_reload(_reload, delta)
	_target_delay = maxf(0.0, _target_delay - delta)
	var x := global_position.x
	# 旧停位线超出新武器射程时，继续推进到射程边缘再停。
	var stop_x := fortress_front + minf(config.stop_distance, config.attack_range)
	var fortress_distance := absf(x - fortress_front)
	var allow_sway := fortress_distance <= config.sway_fortress_range
	var player_in_range := absf(player.global_position.x - x) <= config.attack_range

	if player.targetable and player.lane_index == lane_index and player_in_range:
		action = Action.ATTACK_PLAYER
		_select_target(Target.PLAYER)
		var player_stop_x := x
		var closing_for_boarding := config.approaches_for_boarding and player.previous_lane < 0 \
			and player.global_position.x < x
		if closing_for_boarding:
			var bow_offset := x - combat.hitbox(ShipParts.Part.HULL).position.x
			player_stop_x = player.hitbox(ShipParts.Part.HULL).end.x + bow_offset
		elif config.player_stop_distance > 0.0:
			player_stop_x = maxf(fortress_front + config.size.x * 0.5,
				player.global_position.x + config.player_stop_distance)
		var near_boarding_contact := closing_for_boarding and x - player.global_position.x <= config.size.x
		_navigate(delta, player_stop_x, allow_sway and not near_boarding_contact, player.global_position.x - config.attack_range)
		_aim_and_fire(player.aim_point())
	elif fortress_alive and fortress_distance <= config.attack_range:
		action = Action.ATTACK_FORTRESS
		_select_target(Target.FORTRESS)
		_navigate(delta, stop_x, allow_sway)
		_aim_and_fire(Vector2(fortress_front, lanes.lane_center_y(lane_index)))
	else:
		_select_target(Target.NONE)
		combat.face(-1.0)
		action = Action.ADVANCE if _navigate(delta, stop_x, allow_sway) else Action.HOLD


func finish_boarding(stun_seconds: float) -> void:
	if combat.targetable and stun_seconds > 0.0:
		await get_tree().create_timer(stun_seconds, false, false, true).timeout
	boarding_locked = false


## 本轮 E-01 的行为树不主动换道。后续船型可在自己的行为条件成立时调用。
func try_change_lane(index: int) -> bool:
	lane_change_fail_reason = ""
	if not config.can_change_lane or not combat.targetable or boarding_locked or lanes == null:
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
	return true


## 后续船型可接入躲弹行为。
func _align_to_lane() -> void:
	global_position.y = lanes.lane_bottom_y(lane_index)
	z_index = lanes.content_z(lane_index)


func consider_dodge(_projectile: Projectile) -> void:
	pass


func _navigate(delta: float, stop_x: float, allow_sway: bool, fire_left_limit: float = -INF) -> bool:
	var speed := _speed()
	var distance := speed * delta
	var follow_limit := -INF
	if config.approaches_for_boarding:
		follow_limit = lanes.friendly_follow_limit(combat)
	if is_instance_valid(formation_predecessor) and formation_predecessor.combat.targetable \
		and formation_predecessor.lane_index == lane_index and formation_predecessor.action != Action.FLEE:
		follow_limit = maxf(follow_limit, formation_predecessor.global_position.x + config.min_gap)
	var x := global_position.x
	var remaining := maxf(0.0, x - maxf(stop_x, follow_limit))
	var motion := -minf(distance, remaining)
	if remaining > 0.0:
		_firing_anchor_x = NAN
		if allow_sway and config.sway_advance > 0.0 and config.sway_advance_hz > 0.0:
			var reverse_speed := _advance_sway(config.sway_advance, config.sway_advance_hz, delta)
			# 短暂回摆后重新推进，整个过程沿着水线走。
			var turn := pow(0.5 + 0.5 * sin(_sway_phase), 4.0)
			motion = maxf(-remaining, lerpf(-speed, reverse_speed, turn) * delta)
	elif allow_sway and _target != Target.NONE and config.sway_idle > 0.0 and config.sway_idle_hz > 0.0:
		if is_nan(_firing_anchor_x):
			_firing_anchor_x = x
		var left_edge := maxf(follow_limit, maxf(fire_left_limit, lanes.sea_left + config.size.x * 0.5))
		var left := maxf(left_edge, _firing_anchor_x - 2.0 * config.sway_idle)
		if left < _firing_anchor_x:
			_advance_sway((_firing_anchor_x - left) * 0.5, config.sway_idle_hz, delta)
			var aim_x := lerpf(left, _firing_anchor_x, 0.5 + 0.5 * sin(_sway_phase))
			motion = move_toward(x, aim_x, distance) - x
	# 船底沿航道水线航行，推进和转向共用横向限速。
	global_position.x += motion
	horizontal_speed = motion / maxf(delta, 0.000001)
	return remaining > 0.0 and not is_zero_approx(motion)


func _advance_sway(amplitude: float, hz: float, delta: float) -> float:
	var rate := TAU * hz * combat.parts.speed_multiplier()
	_sway_phase = fposmod(_sway_phase + rate * delta, TAU)
	var speed := minf(_speed(), amplitude * rate)
	weave_strength = speed / maxf(_cruise_speed, 0.001)
	return speed


func _flee(delta: float) -> void:
	action = Action.FLEE
	combat.face(1.0)
	horizontal_speed = _speed() * RETREAT_SPEED_MULTIPLIER
	global_position.x += horizontal_speed * delta
	var screen_right := maxf(lanes.sea_right, get_viewport_rect().end.x)
	if global_position.x >= screen_right + config.size.x * 0.5:
		combat.targetable = false
		retreated.emit(self)
		queue_free()


func _speed() -> float:
	return _cruise_speed * combat.parts.speed_multiplier()


func _select_target(next: Target) -> void:
	if next != _target:
		_target = next
		_firing_anchor_x = NAN
		_target_delay = config.target_switch_delay


func _on_blast_pushed(distance: float) -> void:
	if boarding_locked:
		return
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


func _aim_and_fire(point: Vector2) -> void:
	var heading := -1.0 if point.x < global_position.x else 1.0
	combat.face(heading)
	if _target_delay > 0.0 or _reload > 0.0 or not combat.parts.can_fire():
		return
	var origin := combat.muzzle_position(heading)
	var launch_velocity := Projectile.velocity_for_speed(origin, point, config.projectile_speed, config.projectile_gravity)
	if launch_velocity.is_zero_approx():
		return
	_reload = config.attack_interval
	if config.attack_style != Projectile.Visual.ARROW:
		combat.recoil(heading, origin)
	fired.emit(origin, launch_velocity, lane_index, config.attack_damage)


func _on_part_changed(part: ShipParts.Part, hp: float, _condition: ShipParts.Condition) -> void:
	if part == ShipParts.Part.HULL and hp <= 0.0:
		combat.finish_if_sunk()
	elif part == ShipParts.Part.CANNON:
		_deck.queue_redraw()


func _on_sunk() -> void:
	action = Action.SINK
	_deck.hide()
	if _flag != null:
		_flag.hide()
	combat.play_sinking().chain().tween_callback(queue_free)
	sunk.emit(self)
