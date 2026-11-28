class_name SeaSurface
extends Node2D

const SPRAY := preload("res://Scripts/sea_spray.gd")
const REFLECTION := preload("res://Scripts/sea_reflection.gdshader")
const WATER_DETAIL := preload("res://Scripts/sea_detail.gdshader")
const POINT_SPACING := 20.0
const MAX_TILT := 0.085
const RIPPLE_COUNT := 16
const RIPPLE_LIFE := 1.05
const RIPPLE_SPEED := 82.0

static var _default_surface: Texture2D

@export var waves_enabled := true
@export var reflections_enabled := true
@export var fade_wave_in_boarding := false
@export var surface_texture: Texture2D
@export_range(0.0, 1.0, 0.01) var reflection_opacity := 0.32


class Waterline:
	var points := PackedVector2Array()
	var band_points := PackedVector2Array()
	var pressure := PackedFloat32Array()
	var band: Polygon2D
	var spray: SPRAY
	var sample_height: Callable
	var base_y: float
	var amplitude: float
	var speed: float


class Ripple:
	var row: int
	var x: float
	var age := RIPPLE_LIFE


class ReflectionSource:
	var art: Sprite2D
	var mirror: Sprite2D
	var lane: int
	var ship: ShipCombat
	var hidden_sail_uv := Vector4.ZERO
	var profile_transition := Vector2(0.0, 1.0)


var _lanes: Lanes
var _water: Node2D
var _rows: Array[Waterline] = []
var _ripples: Array[Ripple] = []
var _ripple_cursor := 0
var _sources: Dictionary[int, ReflectionSource] = {}
var _ships: Array[ShipCombat] = []
var _profile_image: Image
var _profile_texture: ImageTexture
var _surface_material: ShaderMaterial
var _reflection_materials: Array[ShaderMaterial] = []
var _segments: int
var _step_x: float
var _clock := 0.0
var _amplitude_scale := 1.0
var _speed_scale := 1.0
var _detail_tint := Color.WHITE
var _detail_opacity := 1.0
var _boarding := false
var _animated := true
var _mirrors_visible := false


func _ready() -> void:
	process_priority = 5
	for index in range(RIPPLE_COUNT):
		_ripples.append(Ripple.new())


func rebuild(lanes: Lanes) -> void:
	_lanes = lanes
	if _water != null:
		remove_child(_water)
		_water.queue_free()
	_rows.clear()
	_reflection_materials.clear()
	_water = Node2D.new()
	_water.name = "WaterLayers"
	add_child(_water)
	var width := maxf(1.0, lanes.sea_right - lanes.sea_left)
	_segments = maxi(1, roundi(width / POINT_SPACING))
	_step_x = width / _segments
	if surface_texture == null and _default_surface == null:
		_default_surface = _make_water_texture()
	var fill := surface_texture if surface_texture != null else _default_surface
	for row in range(lanes.lane_count + 1):
		_add_waterline(row, fill)
	for ripple in _ripples:
		ripple.age = RIPPLE_LIFE
	_make_water_materials()
	_animated = true
	_process(0.0)


func set_weather(amplitude: float, speed: float, detail_tint: Color = Color.WHITE) -> void:
	_amplitude_scale = maxf(0.0, amplitude)
	_speed_scale = maxf(0.0, speed)
	_detail_tint = detail_tint


func set_boarding(active: bool) -> void:
	_boarding = active


func set_water_alpha(value: float) -> void:
	for index in range(_rows.size()):
		_set_band_tint(_rows[index], index, value)


## Rendered height in lane coordinates. Ballistics uses Lanes.lane_bottom_y instead.
func surface_y(lane: int, x: float) -> float:
	return _sample_row(x, lane + 1)


func register_ship(ship: ShipCombat) -> void:
	_ships.append(ship)
	ship.tree_exiting.connect(func(): _ships.erase(ship), CONNECT_ONE_SHOT)
	_register_reflection(ship.visual_sprite(), ship.lane_index, ship)


func register_projectile(sprite: Sprite2D, lane: int) -> void:
	_register_reflection(sprite, lane)


func _register_reflection(sprite: Sprite2D, lane: int, ship: ShipCombat = null) -> void:
	var source := ReflectionSource.new()
	source.art = sprite
	source.lane = lane
	source.ship = ship
	var id := sprite.get_instance_id()
	_sources[id] = source
	sprite.tree_exiting.connect(_remove_reflection.bind(id), CONNECT_ONE_SHOT)


func _remove_reflection(id: int) -> void:
	var source := _sources[id]
	if is_instance_valid(source.mirror):
		source.mirror.hide()
		source.mirror.queue_free()
	_sources.erase(id)


func impact(lane: int, x: float, boarding_impact: bool) -> void:
	if not waves_enabled or x < _lanes.sea_left or x > _lanes.sea_right or lane < 0 or lane >= _lanes.lane_count:
		return
	var row := lane + 1
	var ripple := _ripples[_ripple_cursor]
	_ripple_cursor = (_ripple_cursor + 1) % RIPPLE_COUNT
	ripple.row = row
	ripple.x = x
	ripple.age = 0.0
	_rows[row].spray.splash(Vector2(x, surface_y(lane, x)), 13 if boarding_impact else 8, 1.3 if boarding_impact else 1.0, boarding_impact)


func ship_hit(lane: int, world_point: Vector2, part: ShipParts.Part) -> void:
	if waves_enabled:
		_rows[lane + 1].spray.debris(to_local(world_point), part)


func _add_waterline(index: int, fill: Texture2D) -> void:
	var row := Waterline.new()
	var depth := float(index - 1) / maxf(1.0, _lanes.lane_count - 1.0)
	row.base_y = _lanes.sea_top if index == 0 else _lanes.lane_bottom_y(index - 1)
	row.amplitude = 0.38 if index == 0 else lerpf(1.65, 6.8, depth)
	row.speed = 0.18 if index == 0 else lerpf(0.58, 1.44, depth)
	row.points.resize(_segments + 1)
	row.pressure.resize(_segments + 1)
	row.band_points.resize(2 * (_segments + 1))
	row.band = Polygon2D.new()
	row.band.name = "WaterBand%d" % index
	row.band.z_index = _lanes.content_z(0) - 2 if index == 0 else _lanes.content_z(index - 1) + 1
	row.band.texture = fill
	row.band.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	row.band.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_set_band_tint(row, index, _lanes.water_alpha)
	_water.add_child(row.band)
	if index > 0:
		row.spray = SPRAY.new()
		row.spray.name = "Spray%d" % (index - 1)
		row.spray.z_index = row.band.z_index + 2
		row.sample_height = _sample_row.bind(index)
		_water.add_child(row.spray)
	_rows.append(row)


func _set_band_tint(row: Waterline, index: int, alpha: float) -> void:
	if surface_texture != null:
		row.band.color = Color(Color.WHITE, alpha)
		return
	var tint := _lanes.water_color
	var depth := float(index) / _lanes.lane_count
	var next := minf(1.0, float(index + 1) / _lanes.lane_count)
	var far := tint.lightened(0.12)
	var near := tint.darkened(0.08)
	var colors := PackedColorArray()
	colors.resize(2 * (_segments + 1))
	var top := Color(far.lerp(near, depth), alpha)
	var bottom := Color(far.lerp(near, next), alpha)
	for point in range(_segments + 1):
		colors[point] = top
		colors[point + _segments + 1] = bottom
	row.band.vertex_colors = colors


func _process(delta: float) -> void:
	if _rows.is_empty():
		return
	if not waves_enabled:
		if _animated:
			_animated = false
			_write_waterlines(0.0)
			_update_geometry()
			_surface_material.set_shader_parameter(&"detail_amount", 0.0)
			_set_spray_visible(false)
			_hide_reflections()
			for ripple in _ripples:
				ripple.age = RIPPLE_LIFE
			for ship in _ships:
				ship.set_wave_pose(0.0, 0.0)
		return
	if not _animated:
		_animated = true
		_set_spray_visible(true)
	_clock += delta * _speed_scale
	var target_opacity := 0.0 if fade_wave_in_boarding and _boarding else 1.0
	_detail_opacity = move_toward(_detail_opacity, target_opacity, 6.0 * delta / maxf(Engine.time_scale, 0.001))
	_update_pressure()
	_write_waterlines(delta)
	_update_geometry()
	_update_wave_profile()
	_surface_material.set_shader_parameter(&"water_clock", _clock)
	_surface_material.set_shader_parameter(&"swell_scale", _amplitude_scale)
	_surface_material.set_shader_parameter(&"detail_amount", _detail_opacity)
	_surface_material.set_shader_parameter(&"detail_tint", _detail_tint)
	for ship in _ships:
		_apply_ship_pose(ship)
	for row in _rows:
		if row.spray != null:
			row.spray.advance(delta, row.sample_height)
	_update_reflections()


func _set_spray_visible(value: bool) -> void:
	for row in _rows:
		if row.spray != null:
			row.spray.visible = value
			if not value:
				row.spray.clear()


func _update_pressure() -> void:
	for row in _rows:
		row.pressure.fill(1.0)
	for ship in _ships:
		if not ship.targetable:
			continue
		var anchor := _ship_anchor(ship)
		var radius := ship.size.x * 0.76
		if ship.previous_lane < 0:
			_press_wave(ship.lane_index + 1, anchor.x, radius, 1.0)
			continue
		var blend := _lane_blend(ship, anchor.y)
		_press_wave(ship.previous_lane + 1, anchor.x, radius, 1.0 - blend)
		_press_wave(ship.lane_index + 1, anchor.x, radius, blend)


func _press_wave(row_index: int, x: float, radius: float, weight: float) -> void:
	var left := maxi(0, ceili((x - radius - _lanes.sea_left) / _step_x))
	var right := mini(_segments, floori((x + radius - _lanes.sea_left) / _step_x))
	var row := _rows[row_index]
	for index in range(left, right + 1):
		var distance := absf(_lanes.sea_left + index * _step_x - x)
		var factor := 1.0 - 0.68 * weight * (1.0 - smoothstep(0.0, radius, distance))
		row.pressure[index] = minf(row.pressure[index], factor)


func _write_waterlines(delta: float) -> void:
	for row_index in range(_rows.size()):
		var row := _rows[row_index]
		var phase := row_index * 2.37
		var motion := _clock * row.speed
		for index in range(_segments + 1):
			var x := _lanes.sea_left + index * _step_x
			var y := row.base_y
			if waves_enabled:
				var swell := sin(x * 0.031 - motion * 2.0 + phase) * 0.69
				var chop := sin(x * 0.075 + motion * 2.8 + phase * 1.61) * 0.31
				y -= (swell + chop) * row.amplitude * _amplitude_scale * row.pressure[index]
			row.points[index] = Vector2(x, y)
	if not waves_enabled:
		return
	for ripple in _ripples:
		if ripple.age < RIPPLE_LIFE:
			ripple.age += delta
			_apply_ripple(ripple)


func _apply_ripple(ripple: Ripple) -> void:
	var spread := ripple.age * RIPPLE_SPEED
	var strength := 4.8 * maxf(0.0, 1.0 - ripple.age / RIPPLE_LIFE)
	var left := maxi(0, floori((ripple.x - spread - 32.0 - _lanes.sea_left) / _step_x))
	var right := mini(_segments, ceili((ripple.x + spread + 32.0 - _lanes.sea_left) / _step_x))
	var row := _rows[ripple.row]
	var limit := row.amplitude * _amplitude_scale + 4.5
	for index in range(left, right + 1):
		var point := row.points[index]
		var front := absf(point.x - ripple.x) - spread
		var envelope := 1.0 - smoothstep(0.0, 33.0, absf(front))
		point.y = clampf(point.y + cos(front * 0.11) * envelope * strength, row.base_y - limit, row.base_y + limit)
		row.points[index] = point


func _band_bottom(row_index: int, index: int) -> Vector2:
	if row_index + 1 < _rows.size():
		return _rows[row_index + 1].points[index]
	return Vector2(_rows[row_index].points[index].x, _lanes.sea_bottom)


func _update_geometry() -> void:
	var texture_scale := Vector2.ONE
	if surface_texture != null:
		texture_scale = surface_texture.get_size() / Vector2(
			_lanes.sea_right - _lanes.sea_left, _lanes.sea_bottom - _lanes.sea_top)
	var texture_origin := Vector2(_lanes.sea_left, _lanes.sea_top)
	var point_count := _segments + 1
	for row_index in range(_rows.size()):
		var row := _rows[row_index]
		for index in range(point_count):
			var bottom := _band_bottom(row_index, index)
			var top := row.points[index]
			top.y = minf(top.y, bottom.y - 0.5)
			row.band_points[index] = top
			row.band_points[2 * point_count - 1 - index] = bottom
		row.band.polygon = row.band_points
		var uv := row.band_points.duplicate()
		for index in range(uv.size()):
			uv[index] = (uv[index] - texture_origin) * texture_scale
		row.band.uv = uv


func _ship_anchor(ship: ShipCombat) -> Vector2:
	return to_local((ship.get_parent() as Node2D).global_position)


func _lane_blend(ship: ShipCombat, y: float) -> float:
	var from := _lanes.lane_bottom_y(ship.previous_lane)
	var to := _lanes.lane_bottom_y(ship.lane_index)
	return clampf(inverse_lerp(from, to, y), 0.0, 1.0)


func _apply_ship_pose(ship: ShipCombat) -> void:
	var anchor := _ship_anchor(ship)
	var width := ship.size.x * 0.84
	var left := anchor.x - width * 0.5
	var right := anchor.x + width * 0.5
	var lane := ship.lane_index
	var base := _lanes.lane_bottom_y(lane)
	var left_offset := surface_y(lane, left) - base
	var right_offset := surface_y(lane, right) - base
	if ship.previous_lane >= 0:
		var previous := ship.previous_lane
		var blend := _lane_blend(ship, anchor.y)
		var old_base := _lanes.lane_bottom_y(previous)
		left_offset = lerpf(surface_y(previous, left) - old_base, left_offset, blend)
		right_offset = lerpf(surface_y(previous, right) - old_base, right_offset, blend)
	var tilt := clampf(atan2(right_offset - left_offset, width), -MAX_TILT, MAX_TILT)
	ship.set_wave_pose((left_offset + right_offset) * 0.5, tilt)


func _sample_row(x: float, row: int) -> float:
	var sample := clampf((x - _lanes.sea_left) / _step_x, 0.0, float(_segments))
	var index := mini(floori(sample), _segments - 1)
	var points := _rows[row].points
	return lerpf(points[index].y, points[index + 1].y, sample - index)


func _profile_uv(row_index: int) -> float:
	return (row_index + 0.5) / _rows.size()


func _make_water_materials() -> void:
	_profile_image = Image.create_empty(_segments + 1, _rows.size(), false, Image.FORMAT_RGF)
	_profile_texture = ImageTexture.create_from_image(_profile_image)
	var top_left := to_global(Vector2(_lanes.sea_left, _lanes.sea_top))
	var bottom_right := to_global(Vector2(_lanes.sea_right, _lanes.sea_bottom))
	_surface_material = ShaderMaterial.new()
	_surface_material.shader = WATER_DETAIL
	_surface_material.set_shader_parameter(&"wave_profile", _profile_texture)
	_surface_material.set_shader_parameter(&"water_origin", top_left)
	_surface_material.set_shader_parameter(&"water_size", bottom_right - top_left)
	_surface_material.set_shader_parameter(&"sample_count", float(_segments + 1))
	for index in range(_rows.size()):
		var row := _rows[index]
		row.band.material = _surface_material
		row.band.set_instance_shader_parameter(&"row_profile", Vector4(
			_profile_uv(index), to_global(Vector2(0.0, row.base_y)).y, row.amplitude, row.speed))
	var water_x := Vector2(top_left.x, bottom_right.x)
	for lane in range(_lanes.lane_count):
		var material := ShaderMaterial.new()
		material.shader = REFLECTION
		material.set_shader_parameter(&"wave_profile", _profile_texture)
		material.set_shader_parameter(&"water_x", water_x)
		material.set_shader_parameter(&"sample_count", float(_segments + 1))
		material.set_shader_parameter(&"profile_row", _profile_uv(lane + 1))
		material.set_shader_parameter(&"water_tint", _lanes.water_color)
		_reflection_materials.append(material)


func _hide_reflections() -> void:
	if not _mirrors_visible:
		return
	_mirrors_visible = false
	for source: ReflectionSource in _sources.values():
		if source.mirror != null:
			source.mirror.hide()


func _update_reflections() -> void:
	if not reflections_enabled:
		_hide_reflections()
		return
	var has_mirror := false
	var world_to_surface := global_transform.affine_inverse()
	for source: ReflectionSource in _sources.values():
		var art := source.art
		var pose := world_to_surface * art.global_transform
		var ship := source.ship
		var lane := source.lane if ship == null else ship.lane_index
		var previous := -1 if ship == null else ship.previous_lane
		var plane := surface_y(lane, pose.origin.x)
		var transition := Vector2(0.0, 1.0)
		if previous >= 0:
			var blend := _lane_blend(ship, _ship_anchor(ship).y)
			plane = lerpf(surface_y(previous, pose.origin.x), plane, blend)
			transition = Vector2(_profile_uv(previous + 1), blend)
		var in_range := (art.is_visible_in_tree() and art.texture != null
			and pose.origin.x >= _lanes.sea_left - 80.0 and pose.origin.x <= _lanes.sea_right + 80.0
			and pose.origin.y >= plane - _lanes.lane_height() - 48.0)
		if not in_range:
			if source.mirror != null:
				source.mirror.hide()
			continue
		if source.mirror == null:
			source.mirror = Sprite2D.new()
			source.mirror.name = "WaterReflection"
			add_child(source.mirror)
		var mirror := source.mirror
		mirror.texture = art.texture
		mirror.flip_h = art.flip_h
		mirror.flip_v = art.flip_v
		mirror.modulate = Color(art.modulate, art.modulate.a * reflection_opacity)
		mirror.z_index = _lanes.content_z(maxi(lane, previous)) + 2
		mirror.material = _reflection_materials[lane]
		if source.profile_transition != transition:
			source.profile_transition = transition
			mirror.set_instance_shader_parameter(&"profile_transition", transition)
		if source.ship != null and source.hidden_sail_uv != source.ship.hidden_sail_uv:
			source.hidden_sail_uv = source.ship.hidden_sail_uv
			mirror.set_instance_shader_parameter(&"hidden_sail_uv", source.hidden_sail_uv)
		mirror.transform = Transform2D(Vector2.RIGHT, Vector2.UP, Vector2(0.0, 2.0 * plane)) * pose
		mirror.show()
		has_mirror = true
	_mirrors_visible = has_mirror


func _update_wave_profile() -> void:
	var y_origin := global_position.y
	for row in range(_rows.size()):
		var points := _rows[row].points
		for index in range(_segments + 1):
			_profile_image.set_pixel(index, row, Color(
				points[index].y + y_origin, _band_bottom(row, index).y + y_origin, 0.0))
	_profile_texture.update(_profile_image)


static func _make_water_texture() -> Texture2D:
	const SIZE := 512
	var fill := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	fill.fill(Color(0.85, 0.91, 0.97))
	var rng := RandomNumberGenerator.new()
	rng.seed = 603
	for index in range(480):
		var x := rng.randi_range(0, SIZE - 1)
		var y := rng.randi_range(0, SIZE - 1)
		var length := rng.randi_range(5, 36)
		var light := rng.randf_range(0.013, 0.058)
		for pixel in range(length):
			var tint := sin(PI * pixel / length) * light
			fill.set_pixel((x + pixel) % SIZE, y, Color(0.85 + tint, 0.91 + tint, 0.97 + tint * 0.3))
	return ImageTexture.create_from_image(fill)
