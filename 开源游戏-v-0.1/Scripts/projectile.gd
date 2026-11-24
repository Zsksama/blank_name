class_name Projectile
extends Area2D

signal fortress_hit(damage: float)

const Ballistics := preload("res://Scripts/ballistics.gd")

## 同时接触时先处理帆，再处理炮台和舰体。
const HIT_ORDER := [0, 2, 1]
const BLAST_PARTS := [ShipParts.Part.SAIL, ShipParts.Part.CANNON, ShipParts.Part.HULL]


class Impact:
	var entry: float
	var ship: ShipCombat
	var part: ShipParts.Part

	func _init(hit_entry: float, hit_ship: ShipCombat, hit_part: ShipParts.Part) -> void:
		entry = hit_entry
		ship = hit_ship
		part = hit_part


@export var arc_gravity: float = 900.0
@export var damage: float = 1.0
@export var despawn_min_x: float = -80.0
@export var despawn_max_x: float = 1360.0
@export var despawn_min_y: float = -220.0
@export var despawn_max_y: float = 820.0

@export_group("拖尾")
@export var puff_interval: float = 0.045
@export var puff_lifetime: float = 0.4
@export var puff_scale: float = 0.32
@export var puff_color: Color = Color(0.9, 0.92, 0.97, 0.6)
@export var puff_texture: Texture2D

var velocity := Vector2(900.0, 0.0)
var lane_index := 0
var team := ShipCombat.Team.ALLY
var ammo := ShipParts.Ammo.SOLID
var lanes: Lanes
var fortress_bounds: Rect2
var drag_k := 0.0
var pierce_left := 0
var pierce_damage_falloff := 0.6
var explode_radius := 0.0
var explosion_owner: ShipCombat

var _puff_timer := 0.0
var _spent := false
var _hit_parts: Dictionary[int, int] = {}

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _radius: float = ($CollisionShape2D.shape as CircleShape2D).radius


func _ready() -> void:
	if lanes != null:
		z_index = lanes.content_z(lane_index)
	if team == ShipCombat.Team.ENEMY:
		_sprite.modulate = Color(1.0, 0.66, 0.49)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	var start := global_position
	var next_velocity := Ballistics.step_velocity(velocity, arc_gravity, drag_k, delta)
	var end := Ballistics.step_position(start, velocity, next_velocity, delta)
	velocity = next_velocity

	var water_y := INF if lanes == null else lanes.to_global(Vector2(0.0, lanes.lane_bottom_y(lane_index))).y
	var water_fraction := Ballistics.water_fraction(start, end, water_y)
	var submerged := start.y > water_y
	if water_fraction <= 1.0:
		end = Vector2(lerpf(start.x, end.x, water_fraction), water_y)
	if not submerged and _resolve_hits(start, end):
		return
	if water_fraction <= 1.0:
		_stop(end)
		if not submerged:
			_explode(end)
			lanes.splash_at(lane_index, lanes.to_local(end).x)
		return
	global_position = end

	_puff_timer -= delta
	if _puff_timer <= 0.0:
		_puff_timer = puff_interval
		_spawn_puff()

	if end.x < despawn_min_x or end.x > despawn_max_x or end.y < despawn_min_y or end.y > despawn_max_y:
		queue_free()


static func velocity_for_time(from: Vector2, to: Vector2, flight_time: float, gravity_acceleration: float) -> Vector2:
	var time := maxf(flight_time, 0.05)
	return (to - from) / time - Vector2(0.0, 0.5 * gravity_acceleration * time)


## 用固定初速解较低的弹道，瞄准开火这一刻的位置。
static func velocity_for_speed(from: Vector2, to: Vector2, speed: float, gravity_acceleration: float) -> Vector2:
	var offset := to - from
	if speed <= 0.0 or offset.is_zero_approx():
		return Vector2.ZERO
	if is_zero_approx(gravity_acceleration):
		return offset.normalized() * speed

	var distance_squared := offset.length_squared()
	var term := speed * speed + gravity_acceleration * offset.y
	var discriminant := term * term - gravity_acceleration * gravity_acceleration * distance_squared
	if term <= 0.0 or discriminant < 0.0:
		return Vector2.ZERO
	var time := sqrt(2.0 * distance_squared / (term + sqrt(discriminant)))
	return offset / time - Vector2(0.0, 0.5 * gravity_acceleration * time)


func _resolve_hits(from: Vector2, to: Vector2) -> bool:
	if lanes == null:
		return false
	var motion := to - from
	var fortress_entry := -1.0
	if team == ShipCombat.Team.ENEMY and fortress_bounds.has_area():
		fortress_entry = _entry_fraction(from, motion, fortress_bounds.grow(_radius))

	var impacts: Array[Impact] = []
	for ship in lanes.targets_in_lane(lane_index, team):
		var envelope := ship.hitbox_bounds().grow(_radius)
		if _entry_fraction(from, motion, envelope) < 0.0:
			continue
		for index in range(3):
			var part := index as ShipParts.Part
			var entry := _entry_fraction(from, motion, ship.hitbox(part).grow(_radius))
			if entry >= 0.0:
				impacts.append(Impact.new(entry, ship, part))

	impacts.sort_custom(func(a: Impact, b: Impact) -> bool:
		if a.entry == b.entry:
			return HIT_ORDER[a.part] < HIT_ORDER[b.part]
		return a.entry < b.entry
	)

	for impact in impacts:
		if fortress_entry >= 0.0 and impact.entry > fortress_entry:
			break
		var ship := impact.ship
		if not ship.targetable:
			continue
		var id := ship.get_instance_id()
		var previous: int = _hit_parts.get(id, 0)
		var bit := 1 << impact.part
		if previous & bit:
			continue
		_hit_parts[id] = previous | bit
		var point := from + motion * impact.entry
		if explode_radius > 0.0:
			_stop(point)
			_explode(point)
			return true
		ship.receive_hit(impact.part, ammo, damage)
		if impact.part != ShipParts.Part.SAIL:
			_stop(point)
			return true
		if pierce_left > 0:
			pierce_left -= 1
			damage *= pierce_damage_falloff

	if fortress_entry >= 0.0:
		_stop(from + motion * fortress_entry)
		fortress_hit.emit(damage)
		return true
	return false


func _explode(point: Vector2) -> void:
	if explode_radius <= 0.0 or lanes == null:
		return
	var targets := lanes.targets_in_lane(lane_index, team)
	if is_instance_valid(explosion_owner) and explosion_owner.lane_index == lane_index and explosion_owner.targetable:
		targets.append(explosion_owner)
	for ship in targets:
		var bounds := ship.hitbox_bounds()
		if point.distance_squared_to(point.clamp(bounds.position, bounds.end)) > explode_radius * explode_radius:
			continue
		for part in BLAST_PARTS:
			var box := ship.hitbox(part)
			var distance := point.distance_to(point.clamp(box.position, box.end))
			if distance <= explode_radius:
				var falloff := lerpf(1.0, 0.5, distance / explode_radius)
				ship.receive_hit(part, ammo, damage * falloff)


## 有命中时返回进入矩形的步进比例，无交集时返回 -1。
static func _entry_fraction(from: Vector2, motion: Vector2, box: Rect2) -> float:
	var enter := 0.0
	var leave := 1.0
	for axis in range(2):
		if is_zero_approx(motion[axis]):
			if from[axis] < box.position[axis] or from[axis] > box.end[axis]:
				return -1.0
			continue
		var first := (box.position[axis] - from[axis]) / motion[axis]
		var last := (box.end[axis] - from[axis]) / motion[axis]
		enter = maxf(enter, minf(first, last))
		leave = minf(leave, maxf(first, last))
		if enter > leave:
			return -1.0
	return enter


func _stop(point: Vector2) -> void:
	_spent = true
	hide()
	global_position = point
	queue_free()


func _spawn_puff() -> void:
	var parent := get_parent() as Node2D
	if parent == null:
		return
	var puff := Sprite2D.new()
	puff.texture = puff_texture if puff_texture != null else _sprite.texture
	puff.position = parent.to_local(global_position)
	var base_scale := Vector2.ONE if puff_texture != null else _sprite.scale
	puff.scale = base_scale * puff_scale
	puff.modulate = puff_color
	puff.z_index = z_index
	parent.add_child(puff)
	var tween := puff.create_tween().set_parallel()
	tween.tween_property(puff, "modulate:a", 0.0, puff_lifetime)
	tween.tween_property(puff, "scale", puff.scale * 0.4, puff_lifetime)
	tween.chain().tween_callback(puff.queue_free)
