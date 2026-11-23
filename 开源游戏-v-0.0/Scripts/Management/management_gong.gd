extends Control

const INK := Color("#272c28")
const BRONZE := Color("#a47839")
const GOLD := Color("#dfb95d")


func _draw() -> void:
	var scale_factor := minf(size.x / 132.0, size.y / 76.0)
	draw_set_transform(Vector2(size.x * 0.5, size.y * 0.5), 0.0, Vector2.ONE * scale_factor)
	draw_polyline(PackedVector2Array([
		Vector2(-52, -22), Vector2(-40, -31), Vector2(-23, -34),
		Vector2(23, -34), Vector2(40, -31), Vector2(52, -22),
	]), INK, 6.0)
	draw_rect(Rect2(-47, -24, 6, 57), INK)
	draw_rect(Rect2(41, -24, 6, 57), INK)
	draw_rect(Rect2(-55, 30, 110, 5), INK)
	draw_line(Vector2(0, -31), Vector2(0, -22), INK, 3.0, true)
	draw_circle(Vector2.ZERO, 26.0, INK, true, -1.0, true)
	draw_circle(Vector2.ZERO, 23.5, BRONZE, true, -1.0, true)
	draw_circle(Vector2.ZERO, 20.5, GOLD, true, -1.0, true)
	draw_arc(Vector2.ZERO, 17.5, -PI, -0.16, 25, Color("#f9df94"), 1.5, true)
	draw_circle(Vector2.ZERO, 5.5, BRONZE, true, -1.0, true)
	draw_line(Vector2(48, 25), Vector2(30, 7), INK, 5.0, true)
	draw_line(Vector2(48, 25), Vector2(30, 7), Color("#a16d4a"), 2.0, true)
	draw_circle(Vector2(30, 7), 5.5, INK, true, -1.0, true)
	draw_circle(Vector2(30, 7), 4.0, Color("#a63127"), true, -1.0, true)
