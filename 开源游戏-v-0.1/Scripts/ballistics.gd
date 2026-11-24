## 实弹和预瞄共用固定物理帧的积分与入水交点。
extends RefCounted

const MAX_PREDICT_STEPS := 180


static func velocity_from_angle(angle_deg: float, speed: float) -> Vector2:
	var angle := deg_to_rad(angle_deg)
	return Vector2(cos(angle), -sin(angle)) * speed


static func angle_to_point(from: Vector2, to: Vector2) -> float:
	return rad_to_deg(atan2(-(to.y - from.y), to.x - from.x))


static func simulate(
	from: Vector2,
	velocity: Vector2,
	gravity: float,
	drag_k: float,
	dt: float,
	water_y: float = INF
) -> PackedVector2Array:
	var points := PackedVector2Array([from])
	var point := from
	for i in range(MAX_PREDICT_STEPS):
		var next_velocity := step_velocity(velocity, gravity, drag_k, dt)
		var next := step_position(point, velocity, next_velocity, dt)
		velocity = next_velocity
		var fraction := water_fraction(point, next, water_y)
		if fraction <= 1.0:
			points.append(Vector2(lerpf(point.x, next.x, fraction), water_y))
			break
		points.append(next)
		point = next
	return points


static func step_velocity(velocity: Vector2, gravity: float, drag_k: float, dt: float) -> Vector2:
	var acceleration := Vector2(0.0, gravity)
	if drag_k > 0.0:
		acceleration -= drag_k * velocity.length() * velocity
	return velocity + acceleration * dt


static func step_position(from: Vector2, velocity: Vector2, next_velocity: Vector2, dt: float) -> Vector2:
	return from + (velocity + next_velocity) * (0.5 * dt)


## 返回本物理帧的入水比例。INF 表示没有向下越过水面。
static func water_fraction(from: Vector2, to: Vector2, water_y: float) -> float:
	if from.y > water_y:
		return 0.0
	if to.y < water_y or to.y <= from.y:
		return INF
	return clampf((water_y - from.y) / (to.y - from.y), 0.0, 1.0)
