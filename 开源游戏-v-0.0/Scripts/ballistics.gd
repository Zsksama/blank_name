## 弹道工具：预览线和真实炮弹共用这一套积分，保证"线上哪儿、弹就落在哪儿"。
## 角度约定：0° = 正前（+X），90° = 正上（-Y），180° = 正后（-X）。
extends RefCounted

const MAX_PREDICT_STEPS := 180

## 角度（度）+ 初速 → 速度向量（屏幕坐标，Y 向下为正）
static func velocity_from_angle(angle_deg: float, speed: float) -> Vector2:
	var a := deg_to_rad(angle_deg)
	return Vector2(cos(a), -sin(a)) * speed

## 反推角度：给起点和鼠标位置，返回 0—180 之间的角度
static func angle_to_point(from: Vector2, to: Vector2) -> float:
	return rad_to_deg(atan2(-(to.y - from.y), to.x - from.x))

## 逐帧积分，返回轨迹点。dt 必须和 projectile.gd 里用的完全一致。
static func simulate(
	from: Vector2,
	velocity: Vector2,
	gravity: float,
	drag_k: float,
	dt: float,
	max_steps: int = MAX_PREDICT_STEPS
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var p := from
	var v := velocity
	points.append(p)
	for _i in range(max_steps):
		v = step_velocity(v, gravity, drag_k, dt)
		p += v * dt
		points.append(p)
	return points

## 单帧速度更新（炮弹和预览必须调用同一个函数）
static func step_velocity(v: Vector2, gravity: float, drag_k: float, dt: float) -> Vector2:
	if drag_k > 0.0:
		var speed := v.length()
		return v + (-drag_k * speed * v + Vector2(0.0, gravity)) * dt
	return v + Vector2(0.0, gravity) * dt
