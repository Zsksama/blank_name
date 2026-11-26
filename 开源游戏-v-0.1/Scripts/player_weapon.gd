## 双炮、装填、弹药和瞄准。所有挂点使用 Body 中炮台箱的像素坐标。
class_name PlayerWeapon
extends Node2D

const Ballistics := preload("res://Scripts/ballistics.gd")
## 原炮管贴图中的炮轴和炮口。贴图大小变动时仍按比例换算。
const TEXTURE_PIVOT := Vector2(0.10, 0.54)
const TEXTURE_MUZZLE := Vector2(0.92, 0.54)

signal shot_requested(origin: Vector2, launch_velocity: Vector2, lane: int, ammo_type: ShipParts.Ammo)
signal fired(shots: int)
signal state_changed

@export_group("炮台")
@export var turret_count: int = 2
@export var angle_min: float = 0.0
@export var angle_max: float = 180.0
@export var angle_speed: float = 120.0
@export var reload_time: Array[float] = [1.0, 1.0]
@export var spread_deg: float = 5.0

@export_group("弹药：0 实心 / 1 破帆 / 2 爆炸")
@export var ammo: Array[int] = [30, 20, 10]
@export var ammo_selected: int = 0
@export var fire_mode: int = 0
@export var switch_ammo_delay: float = 1.5

@export_group("节点")
@export var preview_path: NodePath = ^"Preview"
@export var turret_paths: Array[NodePath] = [^"Turret0", ^"Turret1"]
@export_range(2, 180, 1) var preview_max_points: int = 34

@export_group("装填倒计时")
@export var show_reload_labels: bool = true
@export var reload_label_font_size: int = 24
@export var reload_label_offset: Vector2 = Vector2(0, -20)

var turret_angle: float = 90.0
var reload_left: Array[float] = []
var switch_lock: float = 0.0
var config: CombatConfig

var _ship: Node2D
var _line: Line2D
var _preview_inputs: Array = []
var _turret_sprites: Array[Sprite2D] = []
var _muzzle_points: Array[Vector2] = []
var _pending_spread: Array[float] = []
var _reload_labels: Array[Label] = []


func _ready() -> void:
	add_to_group("player_weapon")
	process_physics_priority = 5
	_ship = get_parent().get_parent() as Node2D
	_line = get_node_or_null(preview_path) as Line2D
	if _line != null:
		_line.top_level = true
		_line.z_as_relative = false



func configure_turrets(box: CollisionShape2D) -> void:
	var size := (box.shape as RectangleShape2D).size
	var count := mini(turret_count, turret_paths.size())
	for i in range(count):
		var sprite := get_node(turret_paths[i]) as Sprite2D
		var fraction := (float(i) + 0.5) / float(count) - 0.5
		var local_anchor := Vector2(size.x * fraction, size.y * 0.14)
		sprite.position = to_local(box.to_global(local_anchor))
		var texture_size := sprite.texture.get_size()
		var pivot := texture_size * TEXTURE_PIVOT
		var muzzle := texture_size * TEXTURE_MUZZLE - pivot
		sprite.centered = false
		sprite.offset = -pivot
		sprite.scale = Vector2.ONE * (size.x * 0.72 / muzzle.x)
		_turret_sprites.append(sprite)
		_muzzle_points.append(muzzle)
		_pending_spread.append(_roll_spread())
		reload_left.append(0.0)
	_update_turret_sprites()
	if show_reload_labels:
		_build_reload_labels()


func _process(delta: float) -> void:
	_update_aim(delta)
	_update_preview()
	_update_reload_labels()


func _physics_process(delta: float) -> void:
	_update_reload(delta)
	if Input.is_action_just_pressed("fire"):
		try_fire()


func _unhandled_input(event: InputEvent) -> void:
	if _ship.controls_locked:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: select_ammo(0)
			KEY_2: select_ammo(1)
			KEY_3: select_ammo(2)
			KEY_Q:
				toggle_fire_mode()
				get_viewport().set_input_as_handled()


func _update_aim(delta: float) -> void:
	if _turret_sprites.is_empty():
		return
	var pivot := _turret_sprites[0].position
	var aim := get_local_mouse_position()
	aim.y = minf(aim.y, pivot.y)
	var target_angle := Ballistics.angle_to_point(pivot, aim)
	turret_angle = move_toward(turret_angle, clampf(target_angle, angle_min, angle_max), angle_speed * delta)
	_update_turret_sprites()


func _update_turret_sprites() -> void:
	for sprite in _turret_sprites:
		sprite.rotation_degrees = -turret_angle
		sprite.modulate = Color.WHITE if _ship.combat.parts.can_fire() else Color(0.38, 0.34, 0.30)


func muzzle_global(index: int = 0) -> Vector2:
	return _turret_sprites[index].to_global(_muzzle_points[index])


func _shot_velocity(index: int, speed: float) -> Vector2:
	var angle := clampf(turret_angle + _pending_spread[index], angle_min, angle_max)
	return Ballistics.velocity_from_angle(angle, speed).rotated(global_rotation)


func _roll_spread() -> float:
	return randf_range(-spread_deg, spread_deg) * 0.5


func _update_reload(delta: float) -> void:
	for i in range(reload_left.size()):
		reload_left[i] = maxf(0.0, reload_left[i] - delta)
	switch_lock = maxf(0.0, switch_lock - delta)


func ready_turrets() -> Array[int]:
	var ready: Array[int] = []
	for i in range(reload_left.size()):
		if reload_left[i] <= 0.0:
			ready.append(i)
	return ready


func can_fire() -> bool:
	if _ship == null or _ship.controls_locked or not _ship.combat.targetable or _ship.is_switching():
		return false
	if not _ship.combat.parts.can_fire() or switch_lock > 0.0 or ammo[ammo_selected] <= 0:
		return false
	var ready := ready_turrets()
	return not ready.is_empty() and (fire_mode == 0 or ammo[ammo_selected] >= ready.size())


func try_fire() -> void:
	if config == null or not can_fire():
		return
	var ready := ready_turrets()
	if fire_mode == 0:
		ready.resize(1)
	var speed: float = config.shell_speed[ammo_selected]
	var heading_x := _shot_velocity(ready[0], speed).normalized().x
	for index in ready:
		shot_requested.emit(muzzle_global(index), _shot_velocity(index, speed), _ship.lane_index, ammo_selected as ShipParts.Ammo)
		_pending_spread[index] = _roll_spread()
		reload_left[index] = reload_time[index] * _ship.combat.parts.reload_multiplier()
	ammo[ammo_selected] -= ready.size()
	_ship.add_recoil(heading_x)
	state_changed.emit()
	fired.emit(ready.size())


func select_ammo(index: int) -> void:
	if index < 0 or index >= ammo.size() or index == ammo_selected:
		return
	ammo_selected = index
	switch_lock = switch_ammo_delay
	state_changed.emit()


func toggle_fire_mode() -> void:
	fire_mode = 1 - fire_mode
	state_changed.emit()


func _build_reload_labels() -> void:
	for i in range(reload_left.size()):
		var label := Label.new()
		label.top_level = true
		label.z_index = 100
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", reload_label_font_size)
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
		add_child(label)
		_reload_labels.append(label)


func _update_reload_labels() -> void:
	for i in range(_reload_labels.size()):
		var label := _reload_labels[i]
		var remaining := reload_left[i]
		label.text = "%.1f" % remaining if remaining > 0.0 else "就绪"
		label.add_theme_color_override("font_color",
			Color(1.0, 0.72, 0.32) if remaining > 0.0 else Color(0.62, 1.0, 0.66))
		var row_offset := Vector2.UP * i * (reload_label_font_size + 5.0)
		label.position = _turret_sprites[0].global_position + reload_label_offset + row_offset - label.size * 0.5


func _update_preview() -> void:
	if _line == null:
		return
	var lanes := get_tree().get_first_node_in_group("battle_lanes") as Lanes
	_line.visible = (config != null and not _ship.controls_locked and _ship.combat.targetable and not _ship.is_switching()
		and _ship.combat.parts.can_fire() and switch_lock <= 0.0 and not _turret_sprites.is_empty())
	if not _line.visible:
		return
	var ready := ready_turrets()
	var index := 0 if ready.is_empty() else ready[0]
	var start := muzzle_global(index)
	var speed: float = config.shell_speed[ammo_selected]
	var water_y := INF if lanes == null else lanes.to_global(Vector2(0.0, lanes.lane_bottom_y(_ship.lane_index))).y
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var launch_velocity := _shot_velocity(index, speed)
	var inputs := [start, launch_velocity, config.gravity, config.drag_k, dt, water_y, preview_max_points]
	_line.z_index = _ship.z_index
	if inputs == _preview_inputs:
		return
	_preview_inputs = inputs
	var points := Ballistics.simulate(start, launch_velocity, config.gravity, config.drag_k, dt, water_y)
	var samples := mini(points.size(), preview_max_points)
	var preview := PackedVector2Array()
	for i in range(samples):
		var point := roundi(float(i) * (points.size() - 1) / (samples - 1))
		preview.append(_line.to_local(points[point]))
	_line.points = preview
