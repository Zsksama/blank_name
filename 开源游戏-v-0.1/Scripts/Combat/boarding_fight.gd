class_name BoardingFight
extends Node

## 接舷战 T-401—T-406（依据 `10-战斗/35-M8接舷战.md`、`程序任务派发/待派-接舷战.md`）。
##
## 设计口径：接舷是**被动作战**，系统不给任何加成，划不划算由玩家按公式自己算。
## 本节点由 battle_manager 在 _ready() 里创建并调用 tick()，自带相机与 UI，不改战斗场景结构。

enum Result { WIN, FLEE, LOSE }

signal finished(result: int)
signal morale_changed(delta: float)

@export_group("开关")
@export var enabled := true

@export_group("T-401 触发与判定")
## 碰撞箱相交之外的第二重判定：两船中心距 ≤ 这个值也算接触（占位）。
@export var contact_center_distance := 40.0
## 同一对船的接舷冷却（秒）。
@export_range(0.0, 10.0, 0.1) var cooldown := 3.0

@export_group("T-402 撞击伤害")
## 公式里的 k。占位：按 100 px/s 撞角完好约 3.5 伤。
@export var ram_k := 0.05
## 撞角减伤系数：撞角剩余耐久比例 × 该值。
@export var ram_hp_factor := 0.7
@export_range(0.0, 1.0, 0.01) var ram_loss_ratio := 0.2
@export_range(0.0, 1.0, 0.01) var ram_loss_cap := 0.3
## 相对速度低于此值算“轻碰”，伤害按 0 处理（仍进接舷）。
@export var light_hit_speed := 80.0
## 换道重叠不走公式，走这个固定伤害（占位，等舰体血量定稿再校）。
@export var lane_overlap_damage := 5.0
@export var tonnage_player := 1.0
@export var tonnage_enemy := 1.0

@export_group("T-403 接舷过程")
@export_range(0.01, 1.0, 0.01) var boarding_time_scale := 0.03
@export var power_player := 6.0
@export var power_enemy := 5.0
## 其它部位每秒掉「舰体伤害 × 该比例」。
@export_range(0.0, 1.0, 0.01) var splash_ratio := 0.3

@export_group("T-404 QTE 与逃跑")
@export var qte_min := 1.0
@export var qte_max := 1.5
@export var qte_press_gain := 0.01
## 按住空格时的自动重复间隔（秒）。
@export var qte_decay := 0.01
@export var qte_decay_interval := 0.3
@export var flee_hold := 1.0

@export_group("T-405 结局与气焰")
@export var flee_back_distance := 200.0
@export_range(0.0, 1.0, 0.01) var flee_part_loss := 0.15
## 逃跑气焰 +10；胜利气焰 −25。
@export var morale_flee_gain := 10.0
@export var morale_win_loss := 25.0
## 气焰四档系数：1.2 / 0.9 / 0.75 / 1.3（M14 定档后由外部 set_morale_tier 驱动）。
@export var morale_factors: Array[float] = [1.2, 0.9, 0.75, 1.3]
@export var morale_tier := 1
@export var stun_time := 0.5

@export_group("T-406 演出")
@export var camera_zoom := 2.6
@export var camera_lerp := 0.35
@export var big_text_time := 0.8
@export var log_boarding := true

var active := false

var _manager: Node
var _player: PlayerShip
var _enemy: EnemyShip
var _cam: Camera2D
var _layer: CanvasLayer
var _prompt: Label
var _big: Label
var _qte := 1.0
var _decay_left := 0.0
var _space_was_down := false
var _snap_player_hull := 0.0
var _snap_player_ram := 0.0
var _snap_enemy_hull := 0.0
var _snap_enemy_ram := 0.0
var _snap_lane_overlap := false
var _hp: Label
var _flee_left := 0.0
var _second_accum := 0.0
var _cooldowns := {}
var _last_msec := 0
var _saved_time_scale := 1.0
var _enemy_speed_cap := INF
var _stun_left := 0.0
var _mouse_was_visible := true


func setup(manager: Node, player: PlayerShip) -> void:
	_manager = manager
	_player = player
	_cam = Camera2D.new()
	_cam.name = "BoardingCamera"
	_cam.enabled = false
	add_child(_cam)
	_build_ui()


func set_morale_tier(tier: int) -> void:
	morale_tier = clampi(tier, 0, morale_factors.size() - 1)


func tick(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _last_msec == 0:
		_last_msec = now
	var real := float(now - _last_msec) / 1000.0
	_last_msec = now
	_tick_cooldowns(real)
	_tick_stun(real)
	if active:
		_step_boarding(real)


# ---------------------------------------------------------------- T-401

func try_engage(enemy: EnemyShip, relative_speed: float, lane_overlap: bool) -> bool:
	if not enabled or active or enemy == null or _player == null:
		return false
	if not enemy.combat.targetable or not _player.combat.targetable:
		return false
	var key := enemy.get_instance_id()
	if _cooldowns.has(key) and float(_cooldowns[key]) > 0.0:
		return false
	_enter(enemy, relative_speed, lane_overlap)
	return true


func center_distance(enemy: EnemyShip) -> float:
	if enemy == null or _player == null:
		return INF
	return absf(enemy.global_position.x - _player.global_position.x)


# ---------------------------------------------------------------- T-402

func _impact_damage(attacker: ShipCombat, defender_is_player: bool, relative_speed: float, lane_overlap: bool) -> float:
	if lane_overlap:
		return lane_overlap_damage
	if relative_speed < light_hit_speed:
		return 0.0
	var ram_max := maxf(attacker.parts.max_hp(ShipParts.Part.RAM), 0.001)
	var ram_ratio := clampf(attacker.parts.hp(ShipParts.Part.RAM) / ram_max, 0.0, 1.0)
	# 撞角三档复用 M4：完好 x1.0 / 破损 x0.5 / 被破坏 x0（撞角碎了撞不出伤害）。
	var ram_state := attacker.parts.ram_damage_multiplier()
	var ram_factor := ram_ratio * ram_hp_factor * ram_state
	var tonnage_ratio := (tonnage_player / tonnage_enemy) if defender_is_player else (tonnage_enemy / tonnage_player)
	return relative_speed * tonnage_ratio * ram_factor * ram_k


func _apply_impact(enemy: EnemyShip, relative_speed: float, lane_overlap: bool) -> void:
	var to_enemy := _impact_damage(_player.combat, false, relative_speed, lane_overlap)
	var to_player := _impact_damage(enemy.combat, true, relative_speed, lane_overlap)
	if to_enemy > 0.0:
		enemy.combat.apply_raw_damage(ShipParts.Part.HULL, to_enemy)
	if to_player > 0.0:
		_player.combat.apply_raw_damage(ShipParts.Part.HULL, to_player)
	# 只有“实打实的正面撞击”才扣撞角耐久（20%）：
	# 换道蹭上来（lane_overlap）不磨，低于轻碰阈值（没造成撞击）也不磨。
	if not lane_overlap and relative_speed >= light_hit_speed:
		_wear_ram(_player.combat)
		_wear_ram(enemy.combat)
	if log_boarding:
		print("[接舷] 撞击 相对速度=%.1f 重叠=%s → 敌 %.1f / 我 %.1f" % [relative_speed, str(lane_overlap), to_enemy, to_player])


func _wear_ram(combat: ShipCombat) -> void:
	var ram_max := combat.parts.max_hp(ShipParts.Part.RAM)
	var loss := minf(ram_max * ram_loss_ratio, ram_max * ram_loss_cap)
	combat.parts.set_hp(ShipParts.Part.RAM, combat.parts.hp(ShipParts.Part.RAM) - loss)


# ---------------------------------------------------------------- 进入 / 退出

func _enter(enemy: EnemyShip, relative_speed: float, lane_overlap: bool) -> void:
	_enemy = enemy
	# T-401 规则 5：进入时记录快照（舰体血量 / 撞角耐久 / 战力），供日志与结算核对。
	_snap_player_hull = _player.combat.parts.hp(ShipParts.Part.HULL)
	_snap_player_ram = _player.combat.parts.hp(ShipParts.Part.RAM)
	_snap_enemy_hull = enemy.combat.parts.hp(ShipParts.Part.HULL)
	_snap_enemy_ram = enemy.combat.parts.hp(ShipParts.Part.RAM)
	_snap_lane_overlap = lane_overlap
	_enemy_speed_cap = enemy.speed_cap
	# 接舷期间敌船停死，避免它在慢放下继续往左挪；两船位置保持真实，不做任何吸附。
	enemy.speed_cap = 0.0
	_apply_impact(enemy, relative_speed, lane_overlap)

	# 撞沉了就不进接舷，直接走击沉流程。
	if _player.combat.parts.is_sunk() or enemy.combat.parts.is_sunk():
		_cooldowns[enemy.get_instance_id()] = cooldown
		_show_big("撞沉！")
		_finish_if_sunk()
		return

	active = true
	_qte = qte_min
	_decay_left = qte_decay_interval
	_space_was_down = false
	_flee_left = 0.0
	_second_accum = 0.0
	_saved_time_scale = Engine.time_scale
	Engine.time_scale = boarding_time_scale
	_player.lock_controls()
	_player.combat.damage_float_enabled = false
	enemy.combat.damage_float_enabled = false
	_show_ui(true)
	_update_hp()
	_show_big("撞击！")
	_focus_camera(true)
	if log_boarding:
		print("[接舷] 开始 敌=%s 我方舰体=%.1f 敌方舰体=%.1f" % [enemy.config.display_name, _player.combat.parts.hp(ShipParts.Part.HULL), enemy.combat.parts.hp(ShipParts.Part.HULL)])


func _exit(result: int) -> void:
	if not active:
		return
	active = false
	# T-406 退出顺序：恢复时间 → 清输入 → 恢复 UI → 上冷却。
	Engine.time_scale = _saved_time_scale
	_qte = qte_min
	_flee_left = 0.0
	_space_was_down = false
	_show_ui(false)
	_player.controls_locked = false
	_player.combat.damage_float_enabled = true
	if _enemy != null and is_instance_valid(_enemy):
		_enemy.combat.damage_float_enabled = true
	_focus_camera(false)
	if _enemy != null and is_instance_valid(_enemy):
		_cooldowns[_enemy.get_instance_id()] = cooldown
	_release_stun()

	match result:
		Result.WIN:
			if log_boarding:
				print("[接舷] 结局：胜利 → 击沉敌船、气焰 -%.0f" % morale_win_loss)
			morale_changed.emit(-morale_win_loss)
			if _enemy != null and is_instance_valid(_enemy):
				_enemy.combat.apply_raw_damage(ShipParts.Part.HULL, 99999.0)
		Result.FLEE:
			if log_boarding:
				print("[接舷] 结局：逃跑 → 后退 %.0f px、各部位 -%.0f%%、气焰 +%.0f" % [flee_back_distance, flee_part_loss * 100.0, morale_flee_gain])
			morale_changed.emit(morale_flee_gain)
			_retreat_player()
			_apply_stun()
		Result.LOSE:
			if log_boarding:
				print("[接舷] 结局：失败 → 走击沉流程")
			_player.combat.apply_raw_damage(ShipParts.Part.HULL, 99999.0)
			_apply_stun()
	finished.emit(result)
	_enemy = null


func _finish_if_sunk() -> void:
	if _enemy != null and is_instance_valid(_enemy) and _enemy.combat.parts.is_sunk():
		return
	if _player.combat.parts.is_sunk():
		return


# ---------------------------------------------------------------- T-403 / T-404

func _step_boarding(real: float) -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		_exit(Result.FLEE)
		return

	_update_qte(real)

	_second_accum += real
	while _second_accum >= 1.0 and active:
		_second_accum -= 1.0
		_tick_second()

	if not active:
		return
	if _player.combat.parts.is_sunk():
		_exit(Result.LOSE)
	elif _enemy.combat.parts.is_sunk():
		_exit(Result.WIN)


func _update_qte(real: float) -> void:
	# T-404：每“按一次”空格 +0.01（按下的那一帧才算），不看按住时长。
	var space_down := Input.is_physical_key_pressed(KEY_SPACE)
	if space_down and not _space_was_down:
		_qte = minf(qte_max, _qte + qte_press_gain)
	_space_was_down = space_down
	# 自然回落：每 0.3s −0.01，与按不按无关。
	_decay_left -= real
	if _decay_left <= 0.0:
		_decay_left = qte_decay_interval
		_qte = maxf(qte_min, _qte - qte_decay)
	_update_prompt()

	if Input.is_physical_key_pressed(KEY_T):
		_flee_left += real
		if _flee_left >= flee_hold:
			_exit(Result.FLEE)
	else:
		_flee_left = 0.0


func _tick_second() -> void:
	var player_out := power_player * _lamp_factor() * _qte
	var enemy_out := power_enemy * _morale_factor()
	_damage_player(enemy_out)
	_damage_enemy(player_out)
	_flash_damage(player_out, enemy_out)
	_update_hp()
	if log_boarding:
		print("[接舷] 每秒 我舰体=%.1f 敌舰体=%.1f qte=%.2f 灯火x%.2f 气焰x%.2f" % [
			_player.combat.parts.hp(ShipParts.Part.HULL),
			_enemy.combat.parts.hp(ShipParts.Part.HULL), _qte, _lamp_factor(), _morale_factor()])


func _damage_player(amount: float) -> void:
	_player.combat.apply_raw_damage(ShipParts.Part.HULL, amount)
	var splash := amount * splash_ratio
	for part in [ShipParts.Part.SAIL, ShipParts.Part.CANNON, ShipParts.Part.RUDDER, ShipParts.Part.RAM]:
		_player.combat.apply_raw_damage(part, splash)


func _damage_enemy(amount: float) -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	_enemy.combat.apply_raw_damage(ShipParts.Part.HULL, amount)
	var splash := amount * splash_ratio
	for part in [ShipParts.Part.SAIL, ShipParts.Part.CANNON, ShipParts.Part.RUDDER, ShipParts.Part.RAM]:
		_enemy.combat.apply_raw_damage(part, splash)


## 每秒只在两船各冒一条合并飘字（逐部位飘字在接舷期间已关）。
func _flash_damage(to_enemy: float, to_player: float) -> void:
	var host := _manager
	DamageFloat.spawn(host, _player.combat.aim_point(), to_player, Color(1.0, 0.42, 0.38))
	if _enemy != null and is_instance_valid(_enemy):
		DamageFloat.spawn(host, _enemy.combat.aim_point(), to_enemy, Color(1.0, 0.88, 0.5))


func _lamp_factor() -> float:
	var lamp := 100
	if _manager != null and _manager.get("lamp_value") != null:
		lamp = int(_manager.lamp_value)
	if lamp >= 70:
		return 1.2
	if lamp >= 40:
		return 1.0
	if lamp >= 20:
		return 0.8
	return 0.6


func _morale_factor() -> float:
	if morale_factors.is_empty():
		return 1.0
	return morale_factors[clampi(morale_tier, 0, morale_factors.size() - 1)]


# ---------------------------------------------------------------- T-405 收尾

func _retreat_player() -> void:
	var left := 0.0
	if _manager != null and _manager.get("_lanes") != null:
		left = float(_manager._lanes.sea_left) + 24.0
	var target_x := maxf(_player.global_position.x - flee_back_distance, left)
	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(_player, "global_position:x", target_x, 0.6)
	for part in ShipParts.Part.values():
		var hp := _player.combat.parts.hp(part)
		_player.combat.parts.set_hp(part, hp * (1.0 - flee_part_loss))


func _apply_stun() -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	_enemy.speed_cap = 0.0
	_stun_left = stun_time


func _release_stun() -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	_enemy.speed_cap = _enemy_speed_cap


func _tick_stun(real: float) -> void:
	if _stun_left <= 0.0:
		return
	_stun_left -= real
	if _stun_left <= 0.0:
		_release_stun()


func _tick_cooldowns(real: float) -> void:
	if _cooldowns.is_empty():
		return
	for key in _cooldowns.keys():
		var left := float(_cooldowns[key]) - real
		if left <= 0.0:
			_cooldowns.erase(key)
		else:
			_cooldowns[key] = left


# ---------------------------------------------------------------- T-406 UI 与相机

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "BoardingUI"
	_layer.layer = 20
	add_child(_layer)

	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	_prompt.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03, 0.9))
	_prompt.add_theme_constant_override("outline_size", 5)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-640, -96)
	_prompt.size = Vector2(1280, 40)
	_prompt.visible = false
	_layer.add_child(_prompt)

	_big = Label.new()
	_big.name = "Big"
	_big.add_theme_font_size_override("font_size", 56)
	_big.add_theme_color_override("font_color", Color(1.0, 0.72, 0.42))
	_big.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.03, 0.9))
	_big.add_theme_constant_override("outline_size", 8)
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.set_anchors_preset(Control.PRESET_CENTER)
	_big.position = Vector2(-200, -210)
	_big.size = Vector2(400, 80)
	_big.visible = false
	_layer.add_child(_big)

	_hp = Label.new()
	_hp.name = "HpLine"
	_hp.add_theme_font_size_override("font_size", 26)
	_hp.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	_hp.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03, 0.9))
	_hp.add_theme_constant_override("outline_size", 6)
	_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hp.position = Vector2(-640, 34)
	_hp.size = Vector2(1280, 36)
	_hp.visible = false
	_layer.add_child(_hp)


func _show_ui(show_it: bool) -> void:
	_layer.visible = show_it
	_set_hud_visible(not show_it)
	if show_it:
		_update_prompt()
		_update_hp()
	else:
		_prompt.visible = false
		if _hp != null:
			_hp.visible = false


func _set_hud_visible(show_it: bool) -> void:
	if _manager == null:
		return
	for path in ["HUD/Status", "HUD/ReloadRing", "HUD/Hint"]:
		var node := _manager.get_node_or_null(path)
		if node is CanvasItem:
			(node as CanvasItem).visible = show_it
	var cross := _manager.get_node_or_null("Crosshair")
	if cross is CanvasItem:
		(cross as CanvasItem).visible = show_it


func _update_prompt() -> void:
	if not active:
		return
	_prompt.visible = true
	var hold := "" if _flee_left <= 0.0 else "（撤退 %.1f/%.1f 秒）" % [_flee_left, flee_hold]
	_prompt.text = "接舷战！连按空格提升倍率 ×%.2f    长按 T 撤退%s" % [_qte, hold]


## 接舷中显示双方舰体血量（策划 11-26 反馈）。
func _update_hp() -> void:
	if _hp == null or _player == null:
		return
	if not active and _enemy == null:
		return
	var player_hull: float = _player.combat.parts.hp(ShipParts.Part.HULL)
	var player_max: float = maxf(_player.combat.parts.max_hp(ShipParts.Part.HULL), 0.001)
	var line := "我舰 舰体 %.0f / %.0f" % [maxf(player_hull, 0.0), player_max]
	if _enemy != null and is_instance_valid(_enemy):
		var enemy_hull: float = _enemy.combat.parts.hp(ShipParts.Part.HULL)
		var enemy_max: float = maxf(_enemy.combat.parts.max_hp(ShipParts.Part.HULL), 0.001)
		line += "        敌舰 舰体 %.0f / %.0f" % [maxf(enemy_hull, 0.0), enemy_max]
	_hp.text = line
	_hp.visible = true


func _show_big(text: String) -> void:
	_big.text = text
	_big.visible = true
	_big.modulate.a = 1.0
	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_interval(big_text_time)
	tween.tween_property(_big, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func() -> void: _big.visible = false)


func _focus_camera(on_boarding: bool) -> void:
	if _cam == null:
		return
	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	if on_boarding:
		var mid := (_player.global_position + _enemy.global_position) * 0.5
		_cam.global_position = mid
		_cam.zoom = Vector2.ONE
		_cam.enabled = true
		tween.tween_property(_cam, "zoom", Vector2.ONE * camera_zoom, camera_lerp)
		tween.parallel().tween_property(_cam, "global_position", mid, camera_lerp)
	else:
		tween.tween_property(_cam, "zoom", Vector2.ONE, camera_lerp)
		tween.tween_callback(func() -> void: _cam.enabled = false)


func _exit_tree() -> void:
	if _saved_time_scale > 0.0:
		Engine.time_scale = 1.0
