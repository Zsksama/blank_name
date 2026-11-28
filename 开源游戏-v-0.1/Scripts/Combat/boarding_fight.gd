class_name BoardingFight
extends Node

## M8 接舷。海战使用减速时间，交手、按键和镜头使用真实时间。
enum Result { WIN, FLEE, LOSE }

signal finished(result: int)
signal morale_changed(points: float)
signal active_changed(active: bool)

const ManagementRules := preload("res://Scripts/Management/management_rules.gd")
const EFFECTS := preload("res://Scripts/Combat/boarding_effects.gd")
const MORALE_FACTORS := [1.2, 0.9, 0.75, 1.3]
const DAMAGE_SPLASH := 0.3
const POWER_TO_HP := 0.2
const IMPACT_SPEED_SCALE := 4.0 # 现版船速为 10–25 px/s，换算到原案的撞击调参单位。
const LIGHT_IMPACT_SPEED := 80.0
const RAM_GUARD := 0.7
const RAM_WEAR := 0.2

@export var enabled := true
@export_range(0.0, 10.0, 0.1) var cooldown := 3.0
@export_range(0.01, 1.0, 0.01) var boarding_time_scale := 0.03
@export var ram_k := 0.05
@export var lane_overlap_damage := 5.0
@export var player_tonnage := 1.0
@export var player_power := 100.0
@export var player_power_per_level := 10.0
@export_range(0.0, 1.0, 0.01) var damage_scale := 0.3
@export_range(0.1, 5.0, 0.1) var flee_hold := 1.0
@export var flee_distance := 200.0
@export_range(0.0, 1.0, 0.01) var flee_part_loss := 0.15
@export var stun_time := 0.5
@export_range(1.0, 4.0, 0.1) var camera_zoom := 2.6
@export var log_boarding := false

var active := false
var qte_multiplier := 1.0
var entry_snapshot: Dictionary = {}

var _enemy: EnemyShip
var _cooldowns: Dictionary[int, int] = {}
var _space_down := false
var _saved_time_scale := 1.0
var _get_lamp: Callable
var _get_morale: Callable
var _ship_level := 1
var _exchange_timer: Timer
var _decay_timer: Timer
var _flee_timer: Timer
var _effects: EFFECTS

var _camera: Camera2D
var _camera_tween: Tween
var _previous_camera: Camera2D
var _focus := Vector2.ZERO
var _camera_weight := 0.0
var _map_bounds: Rect2
var _overlay: Control
var _prompt: Label
var _impact: Label
var _impact_tween: Tween
var _player_hull: ProgressBar
var _enemy_hull: ProgressBar
var _hud_hidden: Array[CanvasItem] = []
var _morale_tween: Tween

@onready var _player: PlayerShip = $"../PlayerShip"
@onready var _lanes: Lanes = $"../Lanes"
@onready var _hud: Array[CanvasItem] = [$"../HUD/Status", $"../HUD/Hint", $"../HUD/ReloadRing", $"../Crosshair"]
@onready var _morale_indicator: Control = $"../HUD/Morale"


func _ready() -> void:
	var background: Sprite2D = $"../Background"
	_map_bounds = background.global_transform * background.get_rect()
	_camera = Camera2D.new()
	_camera.name = "BoardingCamera"
	_camera.enabled = false
	add_child(_camera)
	_effects = EFFECTS.new()
	_effects.name = "CombatFeedback"
	add_child(_effects)
	get_viewport().size_changed.connect(func():
		if _camera.enabled:
			_position_camera(_camera_weight)
	)
	_build_ui()
	_exchange_timer = _real_timer(1.0, false, _exchange)
	_decay_timer = _real_timer(0.3, false, _decay_qte)
	_flee_timer = _real_timer(flee_hold, true, _try_flee)
	set_process(false)
	set_process_input(false)


func configure(read_lamp: Callable, read_morale: Callable, ship_level: int) -> void:
	_get_lamp = read_lamp
	_get_morale = read_morale
	_ship_level = ship_level


func can_engage(enemy: EnemyShip) -> bool:
	return enabled and not active and enemy.combat.targetable and not enemy.boarding_locked \
		and _cooldowns.get(enemy.get_instance_id(), 0) <= Time.get_ticks_msec()


func try_engage(enemy: EnemyShip, closing_speed: float, lane_overlap: bool) -> bool:
	if not can_engage(enemy) or not _player.combat.targetable or _player.controls_locked:
		return false
	var player_combat := _player.combat
	var enemy_combat := enemy.combat
	var upgraded_power := player_power + player_power_per_level * (_ship_level - 1)
	# 预留给战后结算和修复。目前供联调复现。
	entry_snapshot = {
		"player": _snapshot(player_combat.parts, upgraded_power),
		"enemy": _snapshot(enemy_combat.parts, enemy.boarding_power),
		"lane_overlap": lane_overlap,
	}
	_apply_impact(enemy, closing_speed * IMPACT_SPEED_SCALE, lane_overlap)
	var contact := player_combat.aim_point().lerp(enemy_combat.aim_point(), 0.5)
	_lanes.splash_at(_player.lane_index, _lanes.to_local(contact).x, true)
	if player_combat.parts.is_sunk() or enemy_combat.parts.is_sunk():
		_start_cooldown(enemy)
		_show_impact("撞沉！")
		return true

	_enemy = enemy
	active = true
	_enemy.boarding_locked = true
	_player.lock_controls()
	_clear_input()
	_saved_time_scale = Engine.time_scale
	Engine.time_scale = boarding_time_scale
	_effects.begin(player_combat, enemy_combat)
	# 接舷期间关掉逐部位飘字：每秒五条数字会糊成一片，这里本来就用合并数字。
	player_combat.damage_float_enabled = false
	enemy_combat.damage_float_enabled = false
	_set_presentation(true)
	_show_impact("撞击！")
	_exchange_timer.start()
	_decay_timer.start()
	set_process(true)
	set_process_input(true)
	active_changed.emit(true)
	if log_boarding:
		print("[接舷] 开始 %s %s" % [enemy.config.display_name, entry_snapshot])
	return true


func _snapshot(parts: ShipParts, power: float) -> Dictionary:
	return {"hull": parts.hp(ShipParts.Part.HULL), "ram": parts.hp(ShipParts.Part.RAM), "power": power}


func _apply_impact(enemy: EnemyShip, speed: float, lane_overlap: bool) -> void:
	var player_combat := _player.combat
	var enemy_combat := enemy.combat
	if lane_overlap:
		player_combat.apply_raw_damage(ShipParts.Part.HULL, lane_overlap_damage)
		enemy_combat.apply_raw_damage(ShipParts.Part.HULL, lane_overlap_damage)
	elif speed >= LIGHT_IMPACT_SPEED:
		var tonnage_ratio := maxf(0.001, enemy.config.boarding_tonnage) / maxf(0.001, player_tonnage)
		var to_player := speed * ram_k * tonnage_ratio * _ram_exposure(player_combat.parts)
		var to_enemy := speed * ram_k / tonnage_ratio * _ram_exposure(enemy_combat.parts)
		for combat: ShipCombat in [player_combat, enemy_combat]:
			combat.apply_raw_damage(ShipParts.Part.RAM, combat.parts.max_hp(ShipParts.Part.RAM) * RAM_WEAR)
		player_combat.apply_raw_damage(ShipParts.Part.HULL, to_player)
		enemy_combat.apply_raw_damage(ShipParts.Part.HULL, to_enemy)


func _ram_exposure(parts: ShipParts) -> float:
	var ratio := parts.hp(ShipParts.Part.RAM) / maxf(parts.max_hp(ShipParts.Part.RAM), 0.001)
	return 1.0 - ratio * RAM_GUARD


func _process(delta: float) -> void:
	if not _resolve_finished():
		_effects.advance(minf(delta / maxf(Engine.time_scale, 0.001), 0.05))
		_position_camera(_camera_weight)
		_update_ui()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null:
		return
	var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
	match code:
		KEY_SPACE:
			if key.pressed and not key.echo and not _space_down:
				qte_multiplier = minf(1.5, qte_multiplier + 0.01)
				_effects.on_qte()
			_space_down = key.pressed
		KEY_T:
			if key.pressed and not key.echo and _flee_timer.is_stopped():
				_flee_timer.start(flee_hold)
			elif not key.pressed:
				_flee_timer.stop()
		_:
			return
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if active and (what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_PAUSED):
		_space_down = false
		_flee_timer.stop()


func _decay_qte() -> void:
	qte_multiplier = maxf(1.0, qte_multiplier - 0.01)


func _exchange() -> void:
	if not active or _resolve_finished():
		return
	var lamp_factor := _lamp_factor()
	var morale_factor := _morale_factor()
	var enemy := _enemy
	var player_damage := float(entry_snapshot.player.power) * lamp_factor * qte_multiplier * damage_scale * POWER_TO_HP
	var enemy_damage := enemy.boarding_power * morale_factor * damage_scale * POWER_TO_HP
	var to_player := _apply_exchange_damage(_player.combat, enemy_damage)
	if not active or not is_instance_valid(enemy):
		return
	var to_enemy := _apply_exchange_damage(enemy.combat, player_damage)
	if not active or not is_instance_valid(enemy):
		return
	_effects.on_exchange(to_player, to_enemy)
	if log_boarding:
		print("[接舷] 我舰 -%.2f / 敌舰 -%.2f · QTE %.2f · 灯火 ×%.2f · 气焰 ×%.2f" % [
			to_player, to_enemy, qte_multiplier, lamp_factor, morale_factor])
	_resolve_finished()


func _apply_exchange_damage(combat: ShipCombat, amount: float) -> float:
	var hull_damage := minf(combat.parts.hp(ShipParts.Part.HULL), amount)
	for part: ShipParts.Part in [ShipParts.Part.SAIL, ShipParts.Part.CANNON, ShipParts.Part.RUDDER, ShipParts.Part.RAM]:
		combat.apply_raw_damage(part, hull_damage * DAMAGE_SPLASH)
	combat.apply_raw_damage(ShipParts.Part.HULL, hull_damage)
	return hull_damage


func _lamp_factor() -> float:
	match ManagementRules.light_tier(_get_lamp.call()).id:
		"bright": return 1.1
		"faint": return 0.9
	return 1.0


func _morale_factor() -> float:
	var morale: float = _get_morale.call()
	if morale > 0.85:
		return MORALE_FACTORS[0]
	if morale >= 0.30:
		return MORALE_FACTORS[1]
	if morale >= 0.10:
		return MORALE_FACTORS[2]
	return MORALE_FACTORS[3]


func _resolve_finished() -> bool:
	if _player.combat.parts.is_sunk():
		_finish(Result.LOSE)
	elif not is_instance_valid(_enemy):
		cancel()
	elif _enemy.combat.parts.is_sunk():
		_finish(Result.WIN)
	else:
		return false
	return true


func _try_flee() -> void:
	if active and not _resolve_finished():
		_finish(Result.FLEE)


func _finish(result: Result) -> void:
	var morale_before: float = _get_morale.call()
	_end_fight(stun_time)
	match result:
		Result.WIN:
			morale_changed.emit(-25.0)
		Result.FLEE:
			_player.move_and_collide(Vector2.LEFT * flee_distance)
			for part: ShipParts.Part in [ShipParts.Part.SAIL, ShipParts.Part.CANNON, ShipParts.Part.RUDDER, ShipParts.Part.RAM, ShipParts.Part.HULL]:
				var combat := _player.combat
				combat.apply_raw_damage(part, combat.parts.hp(part) * flee_part_loss)
			morale_changed.emit(10.0)
	if log_boarding:
		print("[接舷] 结束 %s · 气焰 %.1f%% → %.1f%%" % [
			Result.keys()[result], morale_before * 100.0, _get_morale.call() * 100.0])
	finished.emit(result)


func cancel() -> void:
	if active:
		_end_fight(0.0, false)
	elif _camera_tween != null and _camera_tween.is_running():
		_camera_tween.kill()
		_restore_camera()


func _end_fight(stun_seconds: float, animate_camera: bool = true) -> void:
	active = false
	Engine.time_scale = _saved_time_scale
	_clear_input()
	_exchange_timer.stop()
	_decay_timer.stop()
	_flee_timer.stop()
	set_process(false)
	set_process_input(false)
	_effects.end()
	if _player.combat != null:
		_player.combat.damage_float_enabled = true
	if is_instance_valid(_enemy):
		_enemy.combat.damage_float_enabled = true
	if _player.combat.targetable:
		_player.unlock_after_boarding()
	if is_instance_valid(_enemy):
		_start_cooldown(_enemy)
		_enemy.finish_boarding(stun_seconds)
	_enemy = null
	_set_presentation(false, animate_camera)
	active_changed.emit(false)


func _start_cooldown(enemy: EnemyShip) -> void:
	var id := enemy.get_instance_id()
	if not _cooldowns.has(id):
		enemy.tree_exiting.connect(func(): _cooldowns.erase(id), CONNECT_ONE_SHOT)
	_cooldowns[id] = Time.get_ticks_msec() + int(cooldown * 1000.0)


func _clear_input() -> void:
	qte_multiplier = 1.0
	_space_down = false
	for action in [&"move_left", &"move_right", &"move_up", &"move_down", &"fire"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func _real_timer(seconds: float, one_shot: bool, callback: Callable) -> Timer:
	var timer := Timer.new()
	timer.wait_time = seconds
	timer.one_shot = one_shot
	timer.ignore_time_scale = true
	timer.timeout.connect(callback)
	add_child(timer)
	return timer


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Interface"
	layer.layer = 20
	add_child(layer)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.hide()
	_player_hull = _add_hull_bar("PlayerHull", -264.0, Color(0.36, 0.74, 0.70))
	_enemy_hull = _add_hull_bar("EnemyHull", 24.0, Color(0.79, 0.36, 0.28))
	_prompt = _caption(_overlay, Vector2(0.5, 1.0), Rect2(-440, -66, 880, 40), 22)
	_impact = _caption(layer, Vector2(0.5, 0.0), Rect2(-160, 92, 320, 74), 52)
	_impact.hide()


func _add_hull_bar(id: String, x: float, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = id
	bar.show_percentage = false
	bar.step = 0.01
	var empty := StyleBoxFlat.new()
	empty.bg_color = Color(0.09, 0.10, 0.14, 0.94)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override(&"background", empty)
	bar.add_theme_stylebox_override(&"fill", fill)
	_place(bar, _overlay, Vector2(0.5, 0.0), Rect2(x, 54, 240, 12))
	_caption(bar, Vector2(0.0, 0.0), Rect2(0, -30, 240, 28), 20).name = "Readout"
	return bar


func _caption(parent: Node, anchor: Vector2, bounds: Rect2, font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", Color(1.0, 0.93, 0.77))
	label.add_theme_color_override(&"font_outline_color", Color(0.06, 0.04, 0.04))
	label.add_theme_constant_override(&"outline_size", 6)
	_place(label, parent, anchor, bounds)
	return label


func _place(control: Control, parent: Node, anchor: Vector2, bounds: Rect2) -> void:
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


func _update_ui() -> void:
	var retreat := "  %.1f / %.1f 秒" % [flee_hold - _flee_timer.time_left, flee_hold] if not _flee_timer.is_stopped() else ""
	_prompt.text = "连按空格提升战力  ×%.2f    ·    长按 T 撤退%s" % [qte_multiplier, retreat]
	_update_hull_bar(_player_hull, _player.combat.parts, "我舰")
	_update_hull_bar(_enemy_hull, _enemy.combat.parts, _enemy.config.display_name)


func _update_hull_bar(bar: ProgressBar, parts: ShipParts, title: String) -> void:
	bar.max_value = parts.max_hp(ShipParts.Part.HULL)
	bar.value = parts.hp(ShipParts.Part.HULL)
	bar.get_node("Readout").text = "%s舰体  %.0f / %.0f" % [title + " · " if title != "我舰" else "我方", bar.value, bar.max_value]


func _show_impact(message: String) -> void:
	if _impact_tween != null:
		_impact_tween.kill()
	_impact.text = message
	_impact.show()
	_impact.modulate.a = 1.0
	_impact_tween = create_tween().set_ignore_time_scale(true)
	_impact_tween.tween_interval(0.55)
	_impact_tween.tween_property(_impact, "modulate:a", 0.0, 0.25)
	_impact_tween.tween_callback(_impact.hide)


func _set_presentation(show_boarding: bool, animate_camera: bool = true) -> void:
	_overlay.visible = show_boarding
	if show_boarding:
		for item in _hud:
			if item.visible:
				_hud_hidden.append(item)
				item.hide()
		_update_ui()
		_morale_tween = create_tween().set_ignore_time_scale(true).set_loops()
		_morale_tween.tween_property(_morale_indicator, "rotation", -0.035, 0.12)
		_morale_tween.parallel().tween_property(_morale_indicator, "modulate", Color(1.35, 1.18, 0.85), 0.12)
		_morale_tween.tween_property(_morale_indicator, "rotation", 0.035, 0.12)
		_morale_tween.parallel().tween_property(_morale_indicator, "modulate", Color.WHITE, 0.12)
	else:
		for item in _hud_hidden:
			item.show()
		_hud_hidden.clear()
		_morale_tween.kill()
		_morale_indicator.rotation = 0.0
		_morale_indicator.modulate = Color.WHITE
		_impact_tween.kill()
		_impact.hide()
	_animate_camera(show_boarding, animate_camera)


func _animate_camera(focus_ships: bool, animate: bool) -> void:
	if _camera_tween != null:
		_camera_tween.kill()
	if focus_ships:
		if not _camera.enabled:
			_previous_camera = get_viewport().get_camera_2d()
			_camera.enabled = true
			_camera.make_current()
		_focus = _player.combat.aim_point().lerp(_enemy.combat.aim_point(), 0.5)
		_position_camera(_camera_weight)
	elif not animate:
		_restore_camera()
		return
	_camera_tween = create_tween().set_ignore_time_scale(true)
	_camera_tween.tween_method(_position_camera, _camera_weight, 1.0 if focus_ships else 0.0, 0.35)
	if not focus_ships:
		_camera_tween.tween_callback(_restore_camera)


func _position_camera(weight: float) -> void:
	_camera_weight = weight
	var screen := get_viewport().get_visible_rect().size
	var coverage := maxf(1.0, maxf(screen.x / _map_bounds.size.x, screen.y / _map_bounds.size.y))
	var zoom := lerpf(coverage, maxf(coverage, camera_zoom), weight)
	var half_visible := screen / (2.0 * zoom)
	_camera.zoom = Vector2.ONE * zoom
	var center := _map_bounds.get_center().lerp(_focus, weight) + _effects.camera_shake() * weight
	_camera.global_position = center.clamp(
		_map_bounds.position + half_visible, _map_bounds.end - half_visible)
	_camera.force_update_scroll()


func _restore_camera() -> void:
	_camera.enabled = false
	_camera_weight = 0.0
	if is_instance_valid(_previous_camera) and _previous_camera.enabled:
		_previous_camera.make_current()
	_previous_camera = null


func _exit_tree() -> void:
	if active:
		Engine.time_scale = _saved_time_scale
		_clear_input()
