extends Node2D

const POOL_SIZE := 72
const WOOD := Color(0.78, 0.52, 0.25)
const CLOTH := Color(0.93, 0.87, 0.67)
const METAL := Color(0.89, 0.77, 0.56)
const FOAM := Color(0.82, 0.96, 1.0)

class Drop:
	var point: Vector2
	var velocity: Vector2
	var tint: Color
	var life := 0.0
	var duration: float
	var spray: bool
	var real_time: bool


var _drops: Array[Drop] = []
var _cursor := 0
var _rng := RandomNumberGenerator.new()
var _redraw := false
var _landings := PackedVector2Array()


func _ready() -> void:
	for index in range(POOL_SIZE):
		_drops.append(Drop.new())


func debris(point: Vector2, part: ShipParts.Part) -> void:
	var tint := WOOD
	match part:
		ShipParts.Part.SAIL: tint = CLOTH
		ShipParts.Part.CANNON: tint = METAL
	for index in range(5):
		_emit(point, Vector2(_rng.randf_range(-32.0, 32.0), _rng.randf_range(-49.0, -18.0)),
			tint, 1.6, false, false)


func splash(point: Vector2, amount: int, strength: float = 1.0, real_time: bool = false) -> void:
	for index in range(amount):
		_emit(point, Vector2(_rng.randf_range(-39.0, 39.0), _rng.randf_range(-66.0, -19.0)) * strength,
			FOAM, _rng.randf_range(0.23, 0.47), true, real_time)


func clear() -> void:
	for drop in _drops:
		drop.life = 0.0
	queue_redraw()


func _emit(point: Vector2, velocity: Vector2, tint: Color, life: float, spray: bool, real_time: bool) -> void:
	var drop := _drops[_cursor]
	_cursor = (_cursor + 1) % POOL_SIZE
	drop.point = point
	drop.velocity = velocity
	drop.tint = tint
	drop.duration = life
	drop.life = life
	drop.spray = spray
	drop.real_time = real_time


func advance(delta: float, surface_y: Callable) -> void:
	var moving := false
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	_landings.clear()
	for drop in _drops:
		if drop.life <= 0.0:
			continue
		var step := real_delta if drop.real_time else delta
		drop.life -= step
		drop.velocity.y += (150.0 if drop.spray else 220.0) * step
		drop.point += drop.velocity * step
		if drop.velocity.y > 0.0:
			var water := float(surface_y.call(drop.point.x))
			if drop.point.y >= water:
				drop.life = 0.0
				if not drop.spray:
					_landings.append(Vector2(drop.point.x, water))
		moving = true
	for point in _landings:
		splash(point, 4, 0.64)
	if moving or _redraw:
		queue_redraw()
	_redraw = moving


func _draw() -> void:
	for drop in _drops:
		if drop.life <= 0.0:
			continue
		var opacity := smoothstep(0.0, 0.45, drop.life / drop.duration)
		var color := Color(drop.tint, opacity * 0.88)
		if drop.spray:
			draw_line(drop.point, drop.point - drop.velocity * 0.045, color, 1.35, true)
		else:
			draw_line(drop.point, drop.point + Vector2(2.7, 1.3), color, 1.7, true)
