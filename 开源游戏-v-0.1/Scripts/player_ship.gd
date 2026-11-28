class_name PlayerShip
extends CharacterBody2D

signal sunk(ship: PlayerShip)
signal lane_change_finished

@export_group("航行")
@export var move_speed: float = 25.0
@export var lanes_path: NodePath = ^"../Lanes"
@export var lane_switch_time: float = 0.6

@export_group("船体")
@export_range(0.1, 1.0, 0.01) var ship_scale: float = 0.25
@export var art_keel_y: float = 90.0
@export var waterline_submerge: float = 1.0
@export var damage_profile: ShipDamageProfile
@export var sail_cutout := Rect2(96, 37, 151, 48)
@export var sail_torn_texture: Texture2D
@export var sail_ruined_texture: Texture2D
@export var hull_burn_texture: Texture2D

@export_group("自动维修")
@export var repair_base_rate: float = 0.5
@export var repair_discount_broken: float = 1.0
@export var repair_discount_destroyed: float = 0.2
@export var max_repair_ratio: float = 0.6

@export_group("后坐力")
@export var recoil_impulse: float = 10.0
@export var recoil_sink: float = 5.0
@export var recoil_pitch: float = 4.0
@export var recoil_recover_time: float = 1.0
@export_range(1.0, 4.0, 0.1) var recoil_recover_power: float = 2.0
@export var recoil_max: float = 2.0

var lane_index: int:
	get:
		return combat.lane_index
var lane_change_fail_reason := ""
var lane_offset_y := 0.0
var controls_locked := false
var _lanes: Lanes
var _switch_remaining := 0.0
var _switch_duration := 0.0
var _switch_from := 0.0
var _recoil := 0.0
var _recoil_start := 0.0
var _recoil_elapsed := 0.0
var _gate_tween: Tween
var _sink_tween: Tween
var _boarding_release_frame := -2

@onready var combat: ShipCombat = $Combat
@onready var _weapon: PlayerWeapon = $Combat/Weapon


func _ready() -> void:
	var sprite := combat.visual_sprite()
	var ship_size := sprite.texture.get_size() * ship_scale
	combat.configure(damage_profile, ship_size, 1.0)
	combat.configure_damage_art(sail_torn_texture, sail_ruined_texture, hull_burn_texture, sail_cutout)
	combat.sunk.connect(_on_sunk)

	combat.position.y = waterline_submerge - art_keel_y * ship_scale
	var collider := $CollisionShape2D as CollisionShape2D
	var shape := RectangleShape2D.new()
	shape.size = ship_size
	collider.shape = shape
	collider.position.y = combat.position.y
	_weapon.configure_turrets(combat.get_node("Hitboxes/hit_cannon") as CollisionShape2D)
	_lanes = get_node_or_null(lanes_path) as Lanes
	if _lanes != null:
		combat.lane_index = maxi(_lanes.lane_index_at_bottom_y(global_position.y), 0)
		_lanes.register_ship(combat)
		_apply_lane_pose()


func _physics_process(delta: float) -> void:
	if controls_locked:
		return
	_update_recoil(delta)
	_update_repair(delta)
	var speed := move_speed * combat.parts.speed_multiplier()
	if _lanes == null:
		velocity = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_up", "move_down")) * speed
		move_and_slide()
		return

	if not is_switching():
		if action_just_pressed(&"move_up"):
			try_change_lane(lane_index - 1)
		elif action_just_pressed(&"move_down"):
			try_change_lane(lane_index + 1)

	velocity = Vector2.ZERO
	var finished_switch := false
	if is_switching():
		_switch_remaining = maxf(0.0, _switch_remaining - delta)
		if is_zero_approx(_switch_remaining):
			combat.previous_lane = -1
			finished_switch = true
	if not is_switching():
		velocity.x = Input.get_axis("move_left", "move_right") * speed
		move_and_slide()
	_apply_lane_pose()
	if finished_switch:
		lane_change_finished.emit()


func try_change_lane(index: int) -> bool:
	lane_change_fail_reason = ""
	if _lanes == null or controls_locked or not combat.targetable or is_switching():
		return false
	if index != _lanes.clamp_lane_index(index) or index == lane_index:
		return false
	var multiplier := combat.parts.lane_switch_multiplier()
	if is_inf(multiplier):
		lane_change_fail_reason = "舵已破坏"
		return false
	_switch_from = _lanes.lane_bottom_y(lane_index) - _lanes.lane_bottom_y(index)
	_switch_duration = maxf(lane_switch_time * multiplier, 0.01)
	_switch_remaining = _switch_duration
	combat.previous_lane = lane_index
	combat.lane_index = index
	_apply_lane_pose()
	return true


func is_switching() -> bool:
	return combat.previous_lane >= 0


func current_lane() -> int:
	return lane_index


func muzzle_position(_heading: float = 1.0) -> Vector2:
	return _weapon.muzzle_global()


func add_recoil(heading_x: float, amount: float = 1.0) -> void:
	var next := minf(recoil_max, _recoil + amount)
	move_and_collide(Vector2(-heading_x * recoil_impulse * (next - _recoil), 0.0))
	_recoil_start = next
	_recoil = next
	_recoil_elapsed = 0.0
	_apply_lane_pose()


func _update_recoil(delta: float) -> void:
	if _recoil <= 0.0:
		return
	_recoil_elapsed += delta
	var remaining := 1.0 - clampf(_recoil_elapsed / maxf(recoil_recover_time, 0.001), 0.0, 1.0)
	_recoil = _recoil_start * pow(remaining, recoil_recover_power)


func _apply_lane_pose() -> void:
	if _lanes == null:
		return
	var draw_lane := lane_index
	if is_switching():
		var progress := 1.0 - _switch_remaining / _switch_duration
		lane_offset_y = _switch_from * (1.0 - smoothstep(0.0, 1.0, progress))
		draw_lane = maxi(combat.previous_lane, lane_index)
		combat.rotation_degrees = 0.0
	else:
		lane_offset_y = recoil_sink * _recoil
		combat.rotation_degrees = -recoil_pitch * _recoil
	z_index = _lanes.content_z(draw_lane)
	global_position.y = _lanes.lane_bottom_y(lane_index) + lane_offset_y


func _update_repair(delta: float) -> void:
	for part in ShipParts.Part.values():
		var full := combat.parts.max_hp(part)
		var condition := combat.parts.condition(part)
		if condition == ShipParts.Condition.NORMAL:
			continue
		var discount := repair_discount_destroyed if condition == ShipParts.Condition.DESTROYED else repair_discount_broken
		combat.parts.repair_toward(part, full * repair_base_rate * discount * delta / 100.0, full * max_repair_ratio)


func _on_sunk() -> void:
	lock_controls()
	$CollisionShape2D.set_deferred("disabled", true)
	_weapon.hide()
	_sink_tween = combat.play_sinking()
	sunk.emit(self)


func lock_controls() -> void:
	controls_locked = true
	velocity = Vector2.ZERO
	if _gate_tween != null:
		_gate_tween.kill()
	_weapon.get_node("Preview").hide()


func unlock_after_boarding() -> void:
	controls_locked = false
	_boarding_release_frame = Engine.get_physics_frames()


func action_just_pressed(action: StringName) -> bool:
	# release 清掉按住状态，输入边沿还可能留在当前或下一物理帧。
	return Input.is_action_just_pressed(action) and (Engine.get_physics_frames() > _boarding_release_frame + 1
		or Input.is_action_pressed(action))


func sail_from_gate(lane: int, inside_x: float, exit_x: float, duration: float) -> void:
	lock_controls()
	combat.targetable = false
	$CollisionShape2D.set_deferred("disabled", true)
	if _sink_tween != null:
		_sink_tween.kill()
	if combat.parts.is_sunk():
		for part in ShipParts.Part.values():
			combat.parts.set_hp(part, combat.parts.max_hp(part))
		combat.reset_sinking_pose()
	_weapon.show()
	_set_gate_lane(lane)
	global_position.x = inside_x
	if duration > 0.0:
		_gate_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		_gate_tween.tween_property(self, "global_position:x", exit_x, duration)
		await _gate_tween.finished
	else:
		global_position.x = exit_x
	combat.targetable = true
	controls_locked = false
	$CollisionShape2D.set_deferred("disabled", false)


func sail_back_to_gate(lane: int, inside_x: float, duration: float) -> void:
	combat.targetable = false
	if duration <= 0.0:
		return
	_gate_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_gate_tween.tween_property(self, "global_position:y", _lanes.lane_bottom_y(lane), duration * 0.35)
	_gate_tween.tween_callback(_set_gate_lane.bind(lane))
	_gate_tween.tween_property(self, "global_position:x", inside_x, duration * 0.65)


func _set_gate_lane(lane: int) -> void:
	combat.previous_lane = -1
	combat.lane_index = lane
	_switch_remaining = 0.0
	_recoil = 0.0
	_apply_lane_pose()
