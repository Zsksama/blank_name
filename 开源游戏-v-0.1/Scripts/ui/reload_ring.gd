extends Node2D
## 装填分段圆环（22-M2）：N 段 = N 门炮，每段按该炮装填进度独立填充，
## 中心显示「可开炮数 / 总数」。圆环本身不挂在船上，位置由场景里摆放。

@export var radius: float = 40.0
@export var thickness: float = 11.0
@export var gap_deg: float = 10.0
@export var color_ready: Color = Color(0.42, 0.86, 0.52, 1.0)
@export var color_loading: Color = Color(0.96, 0.62, 0.26, 1.0)
@export var color_bg: Color = Color(0.06, 0.09, 0.13, 0.60)
@export var center_color: Color = Color(0.94, 0.96, 0.99, 1.0)
@export var center_font_size: int = 20
## 装填进度满之前，段内显示的填充比例上限（1.0 = 画满整段才算就绪）
@export var show_partial: bool = true

var _weapon: Node = null

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	if _weapon == null or not is_instance_valid(_weapon):
		_weapon = get_tree().get_first_node_in_group("player_weapon")
	queue_redraw()

func _turret_total() -> int:
	if _weapon == null:
		return 1
	var n: int = 0
	for v in _weapon.get("reload_left"):
		n += 1
	return maxi(n, 1)

func _reload_left() -> Array:
	if _weapon == null:
		return []
	return _weapon.get("reload_left")

func _reload_time() -> Array:
	if _weapon == null:
		return []
	return _weapon.get("reload_time")

func _draw() -> void:
	var left: Array = _reload_left()
	var total: Array = _reload_time()
	var switch_left: float = _weapon.switch_lock if _weapon != null else 0.0
	var switching := switch_left > 0.0
	var n: int = maxi(left.size(), 1)
	var seg: float = TAU / float(n)
	var gap: float = deg_to_rad(gap_deg)
	var ready_count: int = 0

	for i in range(n):
		var start: float = -PI * 0.5 + seg * float(i)
		var end: float = start + seg
		# 底圈
		draw_arc(Vector2.ZERO, radius, start + gap, end - gap, 24, color_bg, thickness, true)
		var remain: float = float(left[i]) if i < left.size() else 0.0
		var full: float = float(total[i]) if i < total.size() else 1.0
		var progress: float = 1.0 if full <= 0.0 else clampf(1.0 - remain / full, 0.0, 1.0)
		if switching:
			progress = clampf(1.0 - switch_left / _weapon.switch_ammo_delay, 0.0, 1.0)
			if progress > 0.01:
				draw_arc(Vector2.ZERO, radius, start + gap, start + gap + (seg - 2.0 * gap) * progress, 24, color_loading, thickness, true)
		elif remain <= 0.0:
			ready_count += 1
			draw_arc(Vector2.ZERO, radius, start + gap, end - gap, 24, color_ready, thickness, true)
		elif show_partial and progress > 0.01:
			draw_arc(Vector2.ZERO, radius, start + gap, start + gap + (end - start - 2.0 * gap) * progress, 24, color_loading, thickness, true)

	# 中心「可开炮数 / 总数」
	var font: Font = ThemeDB.fallback_font
	var text: String = "切换弹药" if switching else "%d/%d" % [ready_count, n]
	var font_size := 12 if switching else center_font_size
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, Vector2(-size.x * 0.5, size.y * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, center_color)
