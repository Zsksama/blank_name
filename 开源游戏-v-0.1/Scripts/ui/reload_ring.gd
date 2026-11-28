extends Control

signal ammo_pressed(index: int)

const SELECT_RADIUS := 34.0
const RELOAD_RADIUS := 47.0
const FIRST_SECTOR := -PI * 7.0 / 6.0
const SECTOR_SIZE := TAU / 3.0
const AMMO_NAMES := ["实心弹", "破帆弹", "爆炸弹"]
const GOLD := Color("#ffe7ac")
const READY := Color("#91dfb1")
const LOADING := Color("#ffba72")

var weapon: PlayerWeapon
var _last_reload := PackedFloat32Array([0.0, 0.0])
var _reload_duration := PackedFloat32Array([1.0, 1.0])
var _last_switch_lock := 0.0
var _flash_index := -1
var _flash_left := 0.0
var _seconds_background := StyleBoxFlat.new()


func _ready() -> void:
	_seconds_background.bg_color = Color("#142430")
	_seconds_background.set_corner_radius_all(4)


func _process(delta: float) -> void:
	if weapon == null:
		return
	var needs_redraw := _flash_left > 0.0 or _last_switch_lock != weapon.switch_lock
	_last_switch_lock = weapon.switch_lock
	_flash_left = maxf(0.0, _flash_left - delta / maxf(Engine.time_scale, 0.001))
	for index in range(mini(2, weapon.reload_left.size())):
		var remaining := weapon.reload_left[index]
		if remaining > _last_reload[index]:
			# The fired duration already includes the condition at the time of the shot.
			_reload_duration[index] = remaining
		needs_redraw = needs_redraw or not is_equal_approx(remaining, _last_reload[index])
		_last_reload[index] = remaining
	if needs_redraw:
		queue_redraw()


func flash_empty(index: int) -> void:
	_flash_index = index
	_flash_left = 0.36
	queue_redraw()


func _has_point(point: Vector2) -> bool:
	return point.distance_squared_to(size / 2.0) <= 55.0 * 55.0


func _get_tooltip(at_position: Vector2) -> String:
	var index := _ammo_at(at_position)
	if weapon == null or index == -1:
		return "双炮装填"
	return "%d  %s  ·  余 %d" % [index + 1, AMMO_NAMES[index], weapon.ammo[index]]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and weapon != null:
		var index := _ammo_at(event.position)
		if index >= 0:
			ammo_pressed.emit(index)
		accept_event()


func _ammo_at(point: Vector2) -> int:
	var relative := point - size * 0.5
	if relative.length_squared() > SELECT_RADIUS * SELECT_RADIUS:
		return -1
	return mini(2, floori(fposmod(relative.angle() - FIRST_SECTOR, TAU) / SECTOR_SIZE))


func _draw() -> void:
	if weapon == null:
		return
	var center := size * 0.5
	draw_circle(center, 54.0, Color("#142430e8"), true, -1.0, true)
	for index in range(2):
		var start := PI * (0.5 - float(index)) + 0.11
		var span := PI - 0.22
		var remaining := weapon.reload_left[index] if index < weapon.reload_left.size() else 0.0
		var fill := clampf(1.0 - remaining / maxf(_reload_duration[index], 0.001), 0.0, 1.0)
		var tint := READY if remaining <= 0.0 else LOADING
		draw_arc(center, RELOAD_RADIUS, start, start + span, 44, Color("#394c59"), 7.0, true)
		if fill > 0.0:
			draw_arc(center, RELOAD_RADIUS, start, start + span * fill, 44, tint, 7.0, true)

		var label_at := center + Vector2(float(index * 2 - 1) * RELOAD_RADIUS, -5.0)
		draw_style_box(_seconds_background, Rect2(label_at - Vector2(14, 7), Vector2(28, 14)))
		_center_text("%.1fs" % remaining, label_at, 10, tint)

	for index in range(AMMO_NAMES.size()):
		var start := FIRST_SECTOR + index * SECTOR_SIZE
		var points := PackedVector2Array([center])
		for step in range(21):
			var angle := start + lerpf(0.05, SECTOR_SIZE - 0.05, float(step) / 20.0)
			points.append(center + Vector2.from_angle(angle) * SELECT_RADIUS)
		var selected := index == weapon.ammo_selected
		var empty := weapon.ammo[index] <= 0
		var fill := Color("#725732") if selected else Color("#2d4555")
		if empty:
			fill = Color("#444b51")
		if index == _flash_index and _flash_left > 0.0 and fposmod(_flash_left, 0.18) > 0.09:
			fill = Color("#a74b41")
		draw_colored_polygon(points, fill)
		if selected:
			draw_arc(center, SELECT_RADIUS, start + 0.05, start + SECTOR_SIZE - 0.05, 24, GOLD, 2.0, true)
		var tint := Color("#9ba7ad") if empty else (GOLD if selected else Color("#e5edf0"))
		var switching := selected and weapon.switch_lock > 0.0
		var slot_text := "%.1fs" % weapon.switch_lock if switching else str(index + 1)
		_center_text(slot_text, center + Vector2.from_angle(start + SECTOR_SIZE * 0.5) * 20.0,
			10 if switching else 15, tint)


func _center_text(message: String, point: Vector2, font_size: int, tint: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, point + Vector2(-14.0, 0.35 * font_size), message,
		HORIZONTAL_ALIGNMENT_CENTER, 28.0, font_size, tint)
