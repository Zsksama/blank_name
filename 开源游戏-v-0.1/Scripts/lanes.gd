class_name Lanes
extends Node2D

@export_range(1, 12, 1) var lane_count: int = 5
@export var sea_left: float = 60.0
@export var sea_right: float = 1280.0
@export var sea_top: float = 144.0
@export var sea_bottom: float = 720.0
@export var divider_texture: Texture2D
@export var water_color := Color(0.18, 0.41, 0.58)
@export_range(0.0, 1.0, 0.01) var water_alpha: float = 0.85:
	set(value):
		water_alpha = clampf(value, 0.0, 1.0)
		for band in _water_bands:
			band.color = Color(water_color, water_alpha)

const FIRST_LANE_Z := 10
const LANE_Z_STEP := 4

class WaterSplash extends Node2D:
	var boarding_impact := false

	func _draw() -> void:
		var strokes := PackedVector2Array([
			Vector2(-2, 1), Vector2(-8, -6), Vector2(-0.5, 1), Vector2(-2, -12),
			Vector2(0.75, 1), Vector2(3, -8), Vector2(2, 1), Vector2(8, -4),
		])
		draw_multiline(strokes, Color(0.91, 0.97, 1.0, 0.95), 2.0)
		if boarding_impact:
			var chips := PackedVector2Array([Vector2(-11, -5), Vector2(-15, -8),
				Vector2(5, -10), Vector2(7, -13), Vector2(11, -4), Vector2(15, -5)])
			draw_multiline(chips, Color(0.83, 0.52, 0.24), 2.0)


class Blast extends Node2D:
	var radius: float

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, Color(0.98, 0.48, 0.18, 0.25))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(1.0, 0.79, 0.4, 0.85), 3.0, true)


var _water_bands: Array[ColorRect] = []
var _ships: Array[ShipCombat] = []


func _ready() -> void:
	add_to_group("battle_lanes")
	rebuild()


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_water_bands.clear()

	# 地平线下第一条带没有前景物体。在其后的每道，水体盖在本道船只和炮弹之上。
	_add_water_band(sea_top, lane_bottom_y(0), FIRST_LANE_Z - 1)
	_add_waterline(0, sea_top, FIRST_LANE_Z, 1.0)
	for lane in range(lane_count):
		var y := lane_bottom_y(lane)
		_add_waterline(lane + 1, y, content_z(lane) - 1, -1.0)
		if lane + 1 < lane_count:
			_add_water_band(y, lane_bottom_y(lane + 1), content_z(lane) + 1)


func _add_waterline(index: int, y: float, depth: int, offset_y: float) -> void:
	var line := Line2D.new()
	line.name = "Waterline%d" % index
	line.position.y = y
	line.z_index = depth
	line.width = 2.0
	line.default_color = Color(0.70, 0.86, 0.93, 0.8)
	line.add_point(Vector2(sea_left, offset_y))
	line.add_point(Vector2(sea_right, offset_y))
	if divider_texture != null:
		line.texture = divider_texture
		line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	add_child(line)


func _add_water_band(top: float, bottom: float, depth: int) -> void:
	var band := ColorRect.new()
	band.name = "FarWater" if depth < FIRST_LANE_Z else "WaterBand%d" % _water_bands.size()
	band.position = Vector2(sea_left, top)
	band.size = Vector2(sea_right - sea_left, bottom - top)
	band.z_index = depth
	band.color = Color(water_color, water_alpha)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	_water_bands.append(band)


func splash_at(lane: int, x: float, boarding_impact: bool = false) -> void:
	if x < sea_left or x > sea_right or lane < 0 or lane >= lane_count:
		return
	var splash := WaterSplash.new()
	splash.name = "WaterSplash"
	splash.boarding_impact = boarding_impact
	splash.position = Vector2(x, lane_bottom_y(lane))
	splash.z_index = content_z(lane)
	add_child(splash)
	splash.add_to_group("water_splash")
	var tween := splash.create_tween().set_parallel().set_ignore_time_scale(boarding_impact)
	tween.tween_property(splash, "scale", Vector2(1.5, 0.65), 0.4)
	tween.tween_property(splash, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(splash.queue_free)


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
