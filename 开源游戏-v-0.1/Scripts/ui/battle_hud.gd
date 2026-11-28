class_name BattleHUD
extends CanvasLayer

const ReloadDial := preload("res://Scripts/ui/reload_ring.gd")
const GRAYSCALE := preload("res://Scripts/ui/pause_grayscale.gdshader")
const EMPTY_CLICK := preload("res://Assets/Audio/SFX/empty_ammo.wav")
const AMMO_NAMES := ["实心", "破帆", "爆炸"]
const LEFT_PARTS := [
	ShipParts.Part.RAM, ShipParts.Part.CANNON, ShipParts.Part.HULL,
	ShipParts.Part.SAIL, ShipParts.Part.RUDDER,
]
const PART_GLYPHS := ["撞", "炮", "舰", "帆", "舵"]
const PART_COLORS := [Color("#7be1a7"), Color("#ffd070"), Color("#ff7675")]
const LEVEL_MARKS := ["Ⅰ", "Ⅱ", "Ⅲ"]
const PANEL := Color("#172631ed")
const EDGE := Color("#6c8d9b")
const INK := Color("#f1f5e8")
const GOLD := Color("#ffe7ac")
const MUTED := Color("#a5b4bc")


class RingMeter extends Control:
	var ratio := 1.0
	var tint := Color.WHITE
	var title := ""
	var value_text := ""
	var stroke := 3.0

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - stroke
		draw_circle(center, radius, PANEL, true, -1.0, true)
		draw_arc(center, radius, -PI / 2.0, TAU - PI / 2.0, 64, tint.darkened(0.66), stroke, true)
		if ratio > 0.0:
			draw_arc(center, radius, -PI / 2.0, TAU * ratio - PI / 2.0, 64, tint, stroke, true)
		var font := ThemeDB.fallback_font
		if value_text.is_empty():
			draw_string(font, Vector2(0, center.y + 5), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, tint.lightened(0.42))
		else:
			draw_string(font, Vector2(0, center.y - 5), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, GOLD)
			draw_string(font, Vector2(0, center.y + 19), value_text,
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, INK)


var _player: PlayerShip
var _weapon: PlayerWeapon
var _capsules: Array[Button] = []
var _part_meters: Array[RingMeter] = []
var _modes: Array[Button] = []
var _ammo_group: Control
var _ammo_message: Label
var _lamp: RingMeter
var _kills: Label
var _level: Label
var _enemy_count: Label
var _fort: Control
var _fort_bar: ProgressBar
var _fort_level: Label
var _morale_bar: ProgressBar
var _morale_percent: Label
var _ring = ReloadDial.new()
var _mode_group: Control
var _mode_glow: Panel
var _hint: Label
var _pause: Button
var _pause_bars: Control
var _screen: ColorRect
var _empty_click: AudioStreamPlayer
var _boarding := false
var _ended := false
var _owns_pause := false
var _last_kills := -1
var _displayed_mode := -1
var _boarding_shift := 0.0
var _boarding_tween: Tween
var _mode_tween: Tween
var _kills_tween: Tween
var _empty_tween: Tween


func _ready() -> void:
	_build_ammo_and_parts()
	_build_battle_readouts()
	_build_weapons()
	_build_pause()
	_empty_click = AudioStreamPlayer.new()
	_empty_click.name = "EmptyClick"
	_empty_click.stream = EMPTY_CLICK
	_empty_click.volume_db = -10.0
	add_child(_empty_click)


func _exit_tree() -> void:
	if _owns_pause:
		get_tree().paused = false


func bind(player: PlayerShip, weapon: PlayerWeapon) -> void:
	_player = player
	_weapon = weapon
	_ring.weapon = weapon
	_weapon.state_changed.connect(_refresh_weapon)
	player.combat.parts.part_changed.connect(_on_part_changed)
	_refresh_weapon()
	for part: ShipParts.Part in LEFT_PARTS:
		_on_part_changed(part, player.combat.parts.hp(part), player.combat.parts.condition(part))


func set_battle_status(
	level_name: String, resolved: int, roster: int, kills: int, light: int,
	fort_level: int, fort_ratio: float
) -> void:
	_level.text = level_name
	_enemy_count.text = "敌人 %d / %d" % [resolved, roster]
	_lamp.ratio = clampf(light / 100.0, 0.0, 1.0)
	_lamp.value_text = str(light)
	_lamp.queue_redraw()
	_fort_bar.value = fort_ratio
	_fort_level.text = LEVEL_MARKS[clampi(fort_level, 1, LEVEL_MARKS.size()) - 1]
	_fort.tooltip_text = "堡耐久  %d%%" % roundi(_fort_bar.value * 100.0)
	if _last_kills == kills:
		return
	_kills.text = "沉敌数：%d" % kills
	if _last_kills >= 0:
		if _kills_tween != null:
			_kills_tween.kill()
		_kills.modulate = Color(1.4, 1.24, 0.7)
		_kills_tween = create_tween()
		_kills_tween.tween_property(_kills, "modulate", Color.WHITE, 0.36)
	_last_kills = kills


func set_enemy_morale(ratio: float) -> void:
	_morale_bar.value = ratio
	var percent := roundi(ratio * 100.0)
	# 四舍五入不能把已经触发撤退的气焰显示成 10%。
	if ratio < EnemyShip.RETREAT_MORALE_THRESHOLD:
		percent = mini(percent, roundi(EnemyShip.RETREAT_MORALE_THRESHOLD * 100.0) - 1)
	_morale_percent.text = "%d%%" % percent


func fit_fort_clearance(edge: float) -> void:
	var left := edge + 12.0
	_pause.position.x = left - 45.0
	_ammo_group.position.x = left
	_ring.position.x = left
	_mode_group.position.x = left + 123.0


func set_boarding(active: bool) -> void:
	_boarding = active
	_hint.visible = not active
	if _boarding_tween != null:
		_boarding_tween.kill()
	_boarding_tween = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_boarding_tween.tween_method(_shift_boarding_controls, _boarding_shift, float(active), 0.19)


func finish() -> void:
	_ended = true
	_ammo_message.hide()
	_ring.hide()
	_mode_group.hide()
	_pause.disabled = true


func pointer_on_hud() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and is_ancestor_of(hovered)


func _build_ammo_and_parts() -> void:
	_ammo_group = Control.new()
	_place(_ammo_group, self, "AmmoAndParts", Vector2.ZERO, Rect2(62, 17, 316, 108))
	var ammunition := HBoxContainer.new()
	ammunition.add_theme_constant_override(&"separation", 7)
	_place(ammunition, _ammo_group, "Ammo", Vector2.ZERO, Rect2(0, 0, 314, 32))
	for index in range(AMMO_NAMES.size()):
		var capsule := _button("Ammo%d" % (index + 1))
		capsule.toggle_mode = true
		capsule.custom_minimum_size = Vector2(100, 32)
		capsule.tooltip_text = "%s弹 · %d" % [AMMO_NAMES[index], index + 1]
		ammunition.add_child(capsule)
		capsule.pressed.connect(_select_ammo.bind(index))
		_capsules.append(capsule)

	var parts := HBoxContainer.new()
	parts.add_theme_constant_override(&"separation", 9)
	_place(parts, _ammo_group, "Parts", Vector2.ZERO, Rect2(0, 38, 230, 36))
	for title in PART_GLYPHS:
		var meter := RingMeter.new()
		meter.custom_minimum_size = Vector2(36, 36)
		meter.title = title
		parts.add_child(meter)
		_track_pointer(meter)
		_part_meters.append(meter)
	_ammo_message = _label(_ammo_group, "EmptyMessage", Vector2.ZERO, Rect2(0, 77, 270, 24), 14, GOLD)
	_ammo_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ammo_message.text = "弹药用尽！"
	_ammo_message.hide()


func _build_battle_readouts() -> void:
	_lamp = RingMeter.new()
	_lamp.stroke = 5.0
	_lamp.tint = Color("#ffc663")
	_lamp.title = "灯火"
	_place(_lamp, self, "Lamp", Vector2(0.5, 0), Rect2(-40, 12, 80, 80))
	_kills = _label(self, "Kills", Vector2(0.5, 0), Rect2(-90, 94, 180, 24), 16, GOLD)
	_level = _label(self, "Level", Vector2(1, 0), Rect2(-246, 22, 222, 34), 25)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_count = _label(self, "EnemyCount", Vector2(1, 0), Rect2(-246, 62, 222, 26), 17)
	_enemy_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_fort = Control.new()
	_place(_fort, self, "FortHealth", Vector2(0, 0.5), Rect2(4, -105, 29, 210))
	_track_pointer(_fort)
	_fort_level = _label(_fort, "Level", Vector2.ZERO, Rect2(0, 0, 29, 28), 18, GOLD)
	_fort_bar = _bar(_fort, "Bar", Rect2(12, 30, 5, 180), Color("#88dfa9"))

	var morale := get_node("Morale") as Control
	_label(morale, "Title", Vector2.ZERO, Rect2(0, 0, 58, 23), 15, GOLD).text = "气焰"
	_morale_percent = _label(morale, "Percent", Vector2.ZERO, Rect2(0, 25, 58, 23), 16)
	_morale_bar = _bar(morale, "Bar", Rect2(24, 54, 10, 166), Color("#f2a667"))


func _build_weapons() -> void:
	_place(_ring, self, "ReloadRing", Vector2(0, 1), Rect2(124, -128, 112, 112))
	_track_pointer(_ring)
	_ring.ammo_pressed.connect(_select_ammo)

	_mode_group = Control.new()
	_place(_mode_group, self, "Mode", Vector2(0, 1), Rect2(247, -88, 124, 34))
	for index in range(2):
		var base := Panel.new()
		base.add_theme_stylebox_override(&"panel", _panel(PANEL, EDGE.darkened(0.25), 7))
		_place(base, _mode_group, "Frame%d" % (index + 1), Vector2.ZERO, Rect2(index * 62, 0, 58, 34))
	_mode_glow = Panel.new()
	_mode_glow.add_theme_stylebox_override(&"panel", _panel(Color("#63502f"), GOLD, 7, 2, 4))
	_place(_mode_glow, _mode_group, "Selection", Vector2.ZERO, Rect2(62, 0, 58, 34))
	for index in range(2):
		var mode := int(index == 0)
		var button := _button("Salvo" if mode == 1 else "Single")
		button.text = "齐射" if mode == 1 else "单射"
		button.tooltip_text = "%s · Q" % button.text
		for state in [&"normal", &"hover", &"pressed", &"focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.add_theme_color_override(&"font_hover_color", GOLD)
		button.add_theme_color_override(&"font_pressed_color", GOLD)
		button.pressed.connect(_set_fire_mode.bind(mode))
		_place(button, _mode_group, button.name, Vector2.ZERO, Rect2(index * 62, 0, 58, 34))
		_track_pointer(button)
		_modes.append(button)

	_hint = _label(self, "Hint", Vector2(0.5, 1.0), Rect2(-280, -36, 560, 26), 15)
	_hint.text = "鼠标瞄准 · 左键开火 · 1/2/3 换弹 · Q 切换齐射 · A/D 航行 · W/S 换道"
	_hint.modulate.a = 0.68
	_track_pointer(_hint)
	_hint.mouse_entered.connect(func(): _hint.modulate.a = 1.0)
	_hint.mouse_exited.connect(func(): _hint.modulate.a = 0.68)


func _build_pause() -> void:
	_pause = _button("Pause")
	_place(_pause, self, "Pause", Vector2.ZERO, Rect2(17, 17, 34, 32))
	_track_pointer(_pause)
	_pause.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause.tooltip_text = "暂停"
	_pause.pressed.connect(_toggle_pause)
	_pause_bars = Control.new()
	_place(_pause_bars, _pause, "Bars", Vector2(0.5, 0.5), Rect2(-5, -7, 10, 14))
	for x in [0.0, 6.0]:
		var bar := ColorRect.new()
		bar.color = INK
		_place(bar, _pause_bars, "Bar", Vector2.ZERO, Rect2(x, 0, 4, 14))
	_render_pause_icon(true)

	var overlay := CanvasLayer.new()
	overlay.name = "Grayscale"
	overlay.layer = 30
	add_child(overlay)
	_screen = ColorRect.new()
	_screen.name = "Screen"
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = GRAYSCALE
	_screen.material = material
	overlay.add_child(_screen)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.hide()


func _render_pause_icon(show_bars: bool) -> void:
	_pause_bars.visible = show_bars
	_pause.text = "" if show_bars else "▶"
	_pause.add_theme_font_size_override(&"font_size", 19)
	_pause.tooltip_text = "暂停" if show_bars else "继续"


func _toggle_pause() -> void:
	if _ended or (get_tree().paused and not _owns_pause):
		return
	_owns_pause = not _owns_pause
	_screen.visible = _owns_pause
	_render_pause_icon(not _owns_pause)
	get_tree().paused = _owns_pause


func _select_ammo(index: int) -> void:
	if _weapon.ammo[index] <= 0 and not _ended:
		_show_empty_ammo(index)
	elif not _ended and not _boarding and not _player.controls_locked:
		_weapon.select_ammo(index)
	_refresh_weapon()


func _set_fire_mode(mode: int) -> void:
	if not _ended and not _boarding and not _player.controls_locked and _weapon.fire_mode != mode:
		_weapon.toggle_fire_mode()


func _on_part_changed(part: ShipParts.Part, hp: float, condition: ShipParts.Condition) -> void:
	var meter := _part_meters[LEFT_PARTS.find(part)]
	meter.ratio = clampf(hp / maxf(_player.combat.parts.max_hp(part), 0.001), 0.0, 1.0)
	meter.tint = PART_COLORS[condition]
	meter.tooltip_text = "%s  %d%%" % [ShipParts.PART_NAMES[part], roundi(meter.ratio * 100.0)]
	meter.queue_redraw()


func _refresh_weapon() -> void:
	for index in range(_capsules.size()):
		var button := _capsules[index]
		var count := maxi(0, _weapon.ammo[index])
		var selected := index == _weapon.ammo_selected
		button.text = "%d  %s  %d" % [index + 1, AMMO_NAMES[index], count]
		button.set_pressed_no_signal(selected)
		var fill := Color("#233039") if count == 0 else PANEL
		var border := Color("#ffe4a6") if selected else EDGE.darkened(0.22)
		if count == 0:
			border = Color("#a6a197") if selected else Color("#66737d")
		var style := _panel(fill, border, 15, 2 if selected else 1, 5 if selected else 0)
		button.add_theme_stylebox_override(&"normal", style)
		button.add_theme_stylebox_override(&"pressed", style)
		button.add_theme_stylebox_override(&"hover", _panel(fill.lightened(0.12), border, 15, 2 if selected else 1))
		button.add_theme_stylebox_override(&"hover_pressed", style)
		for state in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color"]:
			button.add_theme_color_override(state, MUTED if count == 0 else (GOLD if selected else INK))
	_ring.queue_redraw()

	var new_mode := _weapon.fire_mode
	if new_mode == _displayed_mode:
		return
	if _mode_tween != null:
		_mode_tween.kill()
	for index in range(_modes.size()):
		_modes[index].add_theme_color_override(&"font_color", GOLD if index == 1 - new_mode else INK)
	var x := float(1 - new_mode) * 62.0
	if _displayed_mode == -1:
		_mode_glow.position.x = x
	else:
		_mode_tween = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_mode_tween.tween_property(_mode_glow, "position:x", x, 0.17)
	_displayed_mode = new_mode


func _show_empty_ammo(index: int) -> void:
	if _empty_tween != null:
		_empty_tween.kill()
		for capsule in _capsules:
			capsule.modulate = Color.WHITE
	_empty_click.play()
	_ammo_message.show()
	_ring.flash_empty(index)
	_empty_tween = create_tween().set_ignore_time_scale(true)
	for flash in range(2):
		_empty_tween.tween_property(_capsules[index], "modulate", Color(1.7, 0.64, 0.52), 0.08)
		_empty_tween.tween_property(_capsules[index], "modulate", Color.WHITE, 0.1)
	_empty_tween.tween_interval(0.85)
	_empty_tween.tween_callback(_ammo_message.hide)


func _shift_boarding_controls(amount: float) -> void:
	_boarding_shift = amount
	_offset_y(_ammo_group, 17.0 - 12.0 * amount)
	_offset_y(_ring, -128.0 - 105.0 * amount)
	_offset_y(_mode_group, -88.0 - 105.0 * amount)


func _offset_y(item: Control, top: float) -> void:
	var height := item.size.y
	item.offset_top = top
	item.offset_bottom = top + height


func _button(id: String) -> Button:
	var button := Button.new()
	button.name = id
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override(&"font_size", 15)
	button.add_theme_color_override(&"font_color", INK)
	button.add_theme_stylebox_override(&"normal", _panel(PANEL, EDGE, 7))
	button.add_theme_stylebox_override(&"hover", _panel(PANEL.lightened(0.12), GOLD, 7))
	button.add_theme_stylebox_override(&"pressed", _panel(PANEL, GOLD, 7, 2))
	return button


func _label(
	parent: Node, id: String, anchor: Vector2, bounds: Rect2,
	font_size: int, color := INK
) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color("#0c1b25"))
	label.add_theme_constant_override(&"outline_size", 4)
	_place(label, parent, id, anchor, bounds)
	return label


func _bar(parent: Node, id: String, bounds: Rect2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.step = 0.0
	bar.show_percentage = false
	bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	bar.add_theme_stylebox_override(&"background", _panel(Color("#142330ef"), Color("#334d5e"), 2))
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override(&"fill", fill)
	_place(bar, parent, id, Vector2.ZERO, bounds)
	return bar


func _panel(fill: Color, border: Color, radius: int, width := 1, glow := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(border, 0.48)
	style.shadow_size = glow
	return style


func _place(control: Control, parent: Node, id: String, anchor: Vector2, bounds: Rect2) -> void:
	control.name = id
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(control)
	control.anchor_left = anchor.x
	control.anchor_right = anchor.x
	control.anchor_top = anchor.y
	control.anchor_bottom = anchor.y
	control.offset_left = bounds.position.x
	control.offset_top = bounds.position.y
	control.offset_right = bounds.end.x
	control.offset_bottom = bounds.end.y


func _track_pointer(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_STOP
