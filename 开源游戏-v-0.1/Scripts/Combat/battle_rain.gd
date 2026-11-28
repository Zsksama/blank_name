extends CanvasLayer

const DROP_COUNT := 140
const FALL := Vector2(-0.31, 1.0)
const COLOR := Color(0.77, 0.87, 0.99, 0.43)

@onready var _streaks: Node2D = $Streaks

var _lanes: Lanes
var _rng := RandomNumberGenerator.new()
var _drops := PackedVector2Array()
var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _clock := 0.0
var _water_tick := 0.0
var _draw_count := 0


func _ready() -> void:
	_rng.randomize()
	_points.resize(DROP_COUNT * 2)
	_colors.resize(DROP_COUNT)
	for index in range(DROP_COUNT):
		_drops.append(Vector2(_rng.randf(), _rng.randf()))
		var alpha := _rng.randf_range(0.35, 1.0)
		_colors[index] = Color(COLOR, alpha * COLOR.a)
	_streaks.draw.connect(_draw_rain)
	set_process(false)


func configure(lanes: Lanes, active: bool) -> void:
	_lanes = lanes
	visible = active
	set_process(active)


func _process(delta: float) -> void:
	_clock += delta
	var viewport_size := get_viewport().get_visible_rect().size
	var density := 0.71 + sin(_clock * 1.6) * 0.16 + sin(_clock * 0.47) * 0.12
	_draw_count = clampi(roundi(DROP_COUNT * density * viewport_size.x / 1280.0), 1, DROP_COUNT)
	for index in range(_draw_count):
		var rate := lerpf(0.65, 1.1, float(index % 7) / 6.0)
		var position := Vector2(
			fposmod(_drops[index].x * (viewport_size.x + 44.0) + _clock * FALL.x * 620.0 * rate, viewport_size.x + 44.0),
			fposmod(_drops[index].y * (viewport_size.y + 64.0) + _clock * 620.0 * rate, viewport_size.y + 64.0)
		) - Vector2(12.0, 35.0)
		_points[index * 2] = position
		_points[index * 2 + 1] = position + FALL * lerpf(14.0, 33.0, rate)
	_streaks.queue_redraw()

	_water_tick -= delta
	if _water_tick <= 0.0:
		_water_tick = lerpf(0.08, 0.035, density)
		var lane := _rng.randi_range(0, _lanes.lane_count - 1)
		var x := _rng.randf_range(_lanes.sea_left + 6.0, _lanes.sea_right - 6.0)
		_lanes.sea.rain_impact(lane, x)


func _draw_rain() -> void:
	if _draw_count > 0:
		_streaks.draw_multiline_colors(_points.slice(0, _draw_count * 2),
			_colors.slice(0, _draw_count), 1.0)
