@tool
class_name FortWall
extends Node2D

const REFERENCE_SIZE := Vector2(112, 360)
const GATE_SILL := Vector2(77, 222)
# 原图上的海侧石壁坐标，中央航道的升级炮使用第二座敌台的下侧。
const CANNON_POINTS := [
	Vector2(101, 86),
	Vector2(103, 138),
	Vector2(100, 147),
	Vector2(104, 270),
	Vector2(103, 330),
]

@export var texture: AtlasTexture:
	set(value):
		texture = value
		queue_redraw()

var _art_scale := 2.0


func fit_height(height: float) -> void:
	_art_scale = height / REFERENCE_SIZE.y
	queue_redraw()


func art_rect() -> Rect2:
	return Rect2(Vector2.ZERO, REFERENCE_SIZE * _art_scale)


func art_point(point: Vector2) -> Vector2:
	return point * _art_scale


func _draw() -> void:
	if texture != null and texture.atlas != null:
		draw_texture_rect_region(texture.atlas, art_rect(), texture.region)


## 城墙从画面左缘连续铺到海侧。合并轮廓宽度相同的行，保留水门的内凹。
func hit_sections() -> Array[Rect2]:
	var sections: Array[Rect2] = []
	if texture == null or texture.atlas == null:
		return sections
	var image := texture.atlas.get_image()
	var source := Rect2i(texture.region)
	var source_per_pixel := Vector2(source.size) / REFERENCE_SIZE
	for row in range(int(REFERENCE_SIZE.y)):
		var source_y := source.position.y + floori((row + 0.5) * source_per_pixel.y)
		var edge := source.end.x
		while edge > source.position.x and image.get_pixel(edge - 1, source_y).a < 0.5:
			edge -= 1
		var width := (edge - source.position.x) * _art_scale / source_per_pixel.x
		if width <= 0.0:
			continue
		var top := row * _art_scale
		if not sections.is_empty() and is_equal_approx(sections[-1].size.x, width) and is_equal_approx(sections[-1].end.y, top):
			sections[-1].size.y += _art_scale
		else:
			sections.append(Rect2(0.0, top, width, _art_scale))
	for index in range(sections.size()):
		sections[index] = global_transform * sections[index]
	return sections
