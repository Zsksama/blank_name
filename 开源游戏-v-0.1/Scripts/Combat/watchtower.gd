class_name Watchtower
extends Node2D

const MARK_YELLOW := Color(1.0, 0.84, 0.23)
const MARK_RED := Color(1.0, 0.27, 0.16)
const MARK_CONTRAST := Color(0.10, 0.07, 0.06, 0.9)

@export_range(1.0, 3.0, 0.05) var damage_multiplier := 1.5

var target: EnemyShip
var target_part := ShipParts.Part.CANNON
var marker_color := MARK_YELLOW

var _enemies: Node2D
var _frozen := false
var _phase := 0.0
var _brackets := PackedVector2Array()


func _ready() -> void:
	z_as_relative = false
	z_index = 54
	process_physics_priority = 16
	process_priority = 10
	for corner in range(4):
		var angle := corner * PI * 0.5
		_brackets.append(Vector2(8.0, -12.0).rotated(angle))
		_brackets.append(Vector2(14.0, -12.0).rotated(angle))
		_brackets.append(Vector2(14.0, -12.0).rotated(angle))
		_brackets.append(Vector2(14.0, -6.0).rotated(angle))
	hide()
	set_process(false)


func track(enemies: Node2D) -> void:
	_enemies = enemies


func set_frozen(value: bool) -> void:
	_frozen = value
	if not _frozen:
		refresh_target()
	set_process(not _frozen and visible)


func _physics_process(_delta: float) -> void:
	refresh_target()


func refresh_target() -> void:
	if _frozen or not is_instance_valid(_enemies):
		return
	if is_instance_valid(target) and _is_targetable(target):
		return
	var best: EnemyShip
	var fastest := -1.0
	for child in _enemies.get_children():
		var candidate := child as EnemyShip
		if not _is_targetable(candidate):
			continue
		var speed := absf(candidate.horizontal_speed)
		if speed > fastest:
			fastest = speed
			best = candidate
	if is_instance_valid(target):
		target.combat.hit_damage_multiplier = 1.0
	target = best
	visible = target != null
	set_process(visible)
	if target == null:
		return

	target_part = ShipParts.Part.SAIL if target.config.enemy_type == EnemyShipConfig.Type.FAST else ShipParts.Part.CANNON
	target.combat.hit_damage_multiplier = damage_multiplier
	_phase = 0.0
	_process(0.0)


func _is_targetable(ship: EnemyShip) -> bool:
	return is_instance_valid(ship) and not ship.is_queued_for_deletion() and ship.combat.targetable


func _process(delta: float) -> void:
	if not is_instance_valid(target) or not _is_targetable(target):
		refresh_target()
		return
	_phase = fposmod(_phase + delta * 3.5, TAU * 2.0)
	global_position = target.combat.visible_part_position(target_part)
	rotation = _phase * 0.5
	scale = Vector2.ONE * (1.0 + 0.17 * sin(_phase))
	var broken := target.combat.parts.condition(target_part) == ShipParts.Condition.DESTROYED
	marker_color = Color.BLACK if broken else MARK_YELLOW.lerp(MARK_RED, 0.5 - 0.5 * cos(_phase))
	queue_redraw()


func _draw() -> void:
	var outline := Color(1.0, 0.90, 0.65, 0.8) if marker_color == Color.BLACK else MARK_CONTRAST
	draw_multiline(_brackets, outline, 4.2, true)
	draw_arc(Vector2.ZERO, 7.2, 0.0, TAU, 25, marker_color, 1.6, true)
	draw_multiline(_brackets, marker_color, 1.8, true)


func _exit_tree() -> void:
	if is_instance_valid(target) and is_instance_valid(target.combat):
		target.combat.hit_damage_multiplier = 1.0
