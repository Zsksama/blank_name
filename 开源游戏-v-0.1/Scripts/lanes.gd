class_name Lanes
extends Node2D

signal water_impact(lane: int, point: Vector2)

@export_range(1, 12, 1) var lane_count: int = 5
@export var sea_left: float = 60.0
@export var sea_right: float = 1280.0
@export var sea_top: float = 144.0
@export var sea_bottom: float = 720.0
@export var water_color := Color(0.10, 0.54, 0.73)
@export_range(0.0, 1.0, 0.01) var water_alpha: float = 0.85:
	set(value):
		water_alpha = clampf(value, 0.0, 1.0)
		if sea != null:
			sea.set_water_alpha(water_alpha)

const FIRST_LANE_Z := 10
const LANE_Z_STEP := 4

class Blast extends Node2D:
	var radius: float

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, Color(0.98, 0.48, 0.18, 0.25))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(1.0, 0.79, 0.4, 0.85), 3.0, true)


var _ships: Array[ShipCombat] = []
@onready var sea: SeaSurface = get_node_or_null("SeaSurface")


func _ready() -> void:
	add_to_group("battle_lanes")
	rebuild()


func rebuild() -> void:
	if sea == null:
		sea = SeaSurface.new()
		sea.name = "SeaSurface"
		add_child(sea)
	sea.rebuild(self)


func splash_at(lane: int, x: float, boarding_impact: bool = false) -> void:
	if x < sea_left or x > sea_right or lane < 0 or lane >= lane_count:
		return
	if not boarding_impact:
		water_impact.emit(lane, to_global(Vector2(x, lane_bottom_y(lane))))
	sea.impact(lane, x, boarding_impact)


func blast_at(lane: int, point: Vector2, radius: float) -> void:
	var blast := Blast.new()
	blast.radius = radius
	blast.position = to_local(point)
	blast.z_index = content_z(lane)
	blast.scale = Vector2.ONE * 0.15
	add_child(blast)
	var tween := blast.create_tween().set_parallel()
	tween.tween_property(blast, "scale", Vector2.ONE, 0.28)
	tween.tween_property(blast, "modulate:a", 0.0, 0.28).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(blast.queue_free)


func content_z(index: int) -> int:
	return FIRST_LANE_Z + clamp_lane_index(index) * LANE_Z_STEP + 1


func lane_height() -> float:
	return (sea_bottom - sea_top) / float(maxi(lane_count, 1))


func lane_center_y(index: int) -> float:
	return sea_top + lane_height() * (float(index) + 0.5)


func lane_index_at_y(y: float) -> int:
	if y < sea_top or y > sea_bottom:
		return -1
	return clamp_lane_index(floori((y - sea_top) / lane_height()))


## 船底与本道下一条海平面相贴。
func lane_bottom_y(index: int) -> float:
	return sea_top + lane_height() * (float(clamp_lane_index(index)) + 1.0)


func lane_index_at_bottom_y(y: float) -> int:
	if y < sea_top or y > sea_bottom:
		return -1
	return clamp_lane_index(ceili((y - sea_top) / lane_height() - 0.00001) - 1)


func clamp_lane_index(index: int) -> int:
	return clampi(index, 0, maxi(lane_count, 1) - 1)



func register_ship(ship: ShipCombat) -> void:
	_ships.append(ship)
	ship.tree_exiting.connect(func(): _ships.erase(ship), CONNECT_ONE_SHOT)
	sea.register_ship(ship)
	ship.struck.connect(func(part: ShipParts.Part, point: Vector2, hp_loss: float):
		sea.ship_hit(ship.lane_index, point, part)
		if hp_loss >= 0.05:
			var text := "-%d" % roundi(hp_loss) if is_equal_approx(hp_loss, roundf(hp_loss)) else "-%.1f" % hp_loss
			var tint := Color("#ff948c") if ship.team == ShipCombat.Team.ALLY else Color("#ffe5aa")
			DamageFloat.caption(self, point + Vector2.UP * 20.0, text, tint, 16)
	)


func targets_in_lane(index: int, team: ShipCombat.Team) -> Array[ShipCombat]:
	var targets: Array[ShipCombat] = []
	for ship in _ships:
		if ship.targetable and ship.lane_index == index and ship.team != team:
			targets.append(ship)
	return targets


func has_space(
	index: int, x: float, width: float, min_gap: float,
	ignore: ShipCombat = null, margin: float = 0.0
) -> bool:
	if index != clamp_lane_index(index):
		return false
	for other in _ships:
		if other == ignore or not other.occupies_lane(index):
			continue
		var separation := _ship_spacing(width, min_gap, other)
		if absf(other.global_position.x - x) < maxf(separation, margin):
			return false
	return true


func _ship_spacing(width: float, min_gap: float, other: ShipCombat) -> float:
	return maxf((width + other.size.x) * 0.5, maxf(min_gap, other.min_gap))


func friendly_follow_limit(ship: ShipCombat) -> float:
	var left_limit := -INF
	for other in _ships:
		if other.team != ship.team or other.global_position.x >= ship.global_position.x \
			or not other.occupies_lane(ship.lane_index):
			continue
		left_limit = maxf(left_limit, other.global_position.x + _ship_spacing(ship.size.x, ship.min_gap, other))
	return left_limit
