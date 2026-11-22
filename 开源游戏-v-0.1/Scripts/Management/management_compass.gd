extends Control

signal choice_requested(id: String)

const INK := Color("#242d2a")
const TEAL := Color("#618480")
const SEAL := Color("#a63127")
const PARKED_NEEDLE := Color("#849492")
const BASE_ANGLE := -PI / 2.0

var _options: Array[Dictionary] = []
var _selected := -1
var _needle_angle := BASE_ANGLE
var _dragging := false
var _recommended := ""
var _pulse := 0.0


func show_choices(options: Array[Dictionary], selection: String, recommendation: String) -> void:
	_options = options
	_recommended = recommendation
	set_selection(selection)
	if _selected >= 0:
		_needle_angle = _angle_at(_selected)


func set_selection(selection: String) -> void:
	_selected = -1
	for index in _options.size():
		if _options[index].id == selection:
			_selected = index
			break
	if _selected < 0:
		_needle_angle = BASE_ANGLE
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _selected >= 0:
		_needle_angle = lerp_angle(_needle_angle, _angle_at(_selected), 1.0 - exp(-18.0 * delta))
	_pulse = fmod(_pulse + delta * 2.8, TAU)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _options.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_choose_point(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_dragging = (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		if _dragging:
			_choose_point(event.position)
			accept_event()


func _choose_point(point: Vector2) -> void:
	var direction := point - size * 0.5
	if direction.length_squared() < 225.0:
		return
	var angle := wrapf(direction.angle() - BASE_ANGLE, 0.0, TAU)
	var index := roundi(angle * _options.size() / TAU) % _options.size()
	if index != _selected:
		choice_requested.emit(_options[index].id)


func _angle_at(index: int) -> float:
	return BASE_ANGLE + TAU * index / _options.size()


func _draw() -> void:
	if _options.is_empty():
		return
	var center := size * 0.5
	var radius := minf(size.x * 0.33, (size.y - 48.0) * 0.5)
	draw_circle(center, radius + 4.0, INK, true, -1.0, true)
	draw_circle(center, radius + 1.0, Color("#b1a48c"), true, -1.0, true)
	draw_circle(center, radius - 2.0, Color("#f1e8ce"), true, -1.0, true)

	var font := get_theme_default_font()
	var label_size := 13
	for index in _options.size():
		var angle := _angle_at(index)
		var heading := Vector2.from_angle(angle)
		var is_recommended: bool = _options[index].id == _recommended
		if is_recommended:
			var area := PackedVector2Array([center])
			for segment in range(17):
				var edge_angle := angle + lerpf(-0.37, 0.37, segment / 16.0)
				area.append(center + Vector2.from_angle(edge_angle) * (radius - 5.0))
			draw_colored_polygon(area, Color(0.93, 0.68, 0.23, 0.27 + sin(_pulse) * 0.13))
		_draw_option_name(font, label_size, center + heading * (radius + 15.0), index, is_recommended)

	for tick in range(32):
		var heading := Vector2.from_angle(TAU * tick / 32.0)
		var long_tick := tick % 4 == 0
		var inner := radius - (15.0 if long_tick else 10.0)
		draw_line(center + heading * inner, center + heading * (radius - 5.0), TEAL, 2.0 if long_tick else 1.0, true)

	_draw_rose(center, radius)
	var front := Vector2.from_angle(_needle_angle)
	var side := front.orthogonal()
	draw_colored_polygon(PackedVector2Array([
		center + front * (radius - 14.0), center + side * 8.0,
		center - front * (radius * 0.62), center - side * 8.0,
	]), INK)
	draw_colored_polygon(PackedVector2Array([
		center + front * (radius - 19.0), center + side * 5.0, center - side * 5.0,
	]), SEAL if _selected >= 0 else PARKED_NEEDLE)
	draw_circle(center, 8.0, INK, true, -1.0, true)
	draw_circle(center, 5.0, Color("#edca79"), true, -1.0, true)


func _draw_option_name(font: Font, font_size: int, point: Vector2, index: int, is_recommended: bool) -> void:
	var title: String = _options[index].title
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var aligned_x := clampf(point.x - width * 0.5, 0.0, size.x - width)
	var color := SEAL if _selected == index or is_recommended else INK
	draw_string(font, Vector2(aligned_x, point.y + font.get_ascent(font_size) * 0.4), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_rose(center: Vector2, radius: float) -> void:
	for point in range(8):
		var heading := Vector2.from_angle(TAU * point / 8.0)
		var tip := center + heading * radius * (0.78 if point % 2 == 0 else 0.54)
		var edge := heading.orthogonal() * 7.0
		draw_colored_polygon(PackedVector2Array([tip, center + edge, center - edge]), Color("#9da99a"))
		draw_colored_polygon(PackedVector2Array([tip, center, center - edge]), TEAL)
