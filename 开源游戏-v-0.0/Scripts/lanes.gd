class_name Lanes
extends Node2D

## 海道条数
@export_range(1, 12, 1) var lane_count: int = 5
@export var divider_texture: Texture2D
@export var sea_left: float = 260.0
@export var sea_right: float = 1280.0
@export var sea_top: float = 0.0
@export var sea_bottom: float = 720.0

const DIVIDER_Z_INDEX := 10

func _ready() -> void:
	rebuild()

func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var n: int = maxi(lane_count, 1)
	var lane_height: float = (sea_bottom - sea_top) / float(n)
	var center_x: float = (sea_left + sea_right) * 0.5
	for i in range(n + 1):
		var boundary_y: float = sea_top + lane_height * float(i)
		var line := Sprite2D.new()
		line.texture = divider_texture
		line.position = Vector2(center_x, boundary_y)
		line.z_index = DIVIDER_Z_INDEX
		add_child(line)

## 单条道的高度。
func lane_height() -> float:
	return (sea_bottom - sea_top) / float(maxi(lane_count, 1))


## 第 index 条道的中心 Y（0 = 最上面一条）。
func lane_center_y(index: int) -> float:
	return sea_top + lane_height() * (float(index) + 0.5)


## 某个 Y 坐标落在第几条道里。
func lane_index_at_y(y: float) -> int:
	return clamp_lane_index(int(floor((y - sea_top) / lane_height())))


## 把道序号夹在合法范围内，防止按 W/S 按出界。
func clamp_lane_index(index: int) -> int:
	return clampi(index, 0, maxi(lane_count, 1) - 1)
