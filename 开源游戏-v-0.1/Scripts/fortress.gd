class_name Fortress
extends Node2D

@export var damage_textures: Array[AtlasTexture]

var damage_tier := 0
var hit_sections: Array[Rect2] = []
var _lane_fronts := PackedFloat32Array()
var _lanes: Lanes

@onready var watchtower: Watchtower = $Watchtower
@onready var _visual: FortWall = $FortVisual


func fit_to_lanes(lanes: Lanes) -> void:
	_lanes = lanes
	_visual.fit_height(lanes.sea_bottom)


func art_bounds() -> Rect2:
	return _visual.global_transform * _visual.art_rect()


func gate_entrance() -> Vector2:
	return _visual.to_global(_visual.art_point(FortWall.GATE_SILL))


func target_x(lane: int) -> float:
	return _lane_fronts[lane]


func cannon_mount(lane: int, slot: int) -> Vector2:
	var points := FortWall.CANNON_POINTS
	var index := floori((lane + 0.5) * points.size() / _lanes.lane_count)
	var muzzle: Vector2 = points[index] + Vector2(-2.0, -7.0) * slot
	return _visual.transform * _visual.art_point(muzzle)


func show_damage(tier: int) -> void:
	if damage_tier == tier and not hit_sections.is_empty():
		return
	damage_tier = tier
	_visual.texture = damage_textures[tier]
	hit_sections.assign(_visual.hit_sections())
	_lane_fronts.resize(_lanes.lane_count)
	var outer_edge := art_bounds().end.x
	for lane in range(_lanes.lane_count):
		var y := _lanes.to_global(Vector2(0.0, _lanes.lane_center_y(lane))).y
		_lane_fronts[lane] = outer_edge
		for section in hit_sections:
			if section.position.y <= y and y < section.end.y:
				_lane_fronts[lane] = section.end.x
				break
