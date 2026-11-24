extends Node2D

## 战斗管理器（T-301—T-306 已落地）
## - 堡：一条血、四档外观、按道布炮、无盲道概念
## - 敌人：到 stop_distance 停船持续开火；堡破后最近的一艘驶入水门
## - 判负：堡血归零 → 演出 → 本场失败 → 扣兜底 → 归零进结局（接口）
## 所有数值都是 @export，策划可直接在检查器里调。

const PROJECTILE_SCENE := preload("res://Scenes/projectile.tscn")
const ENEMY_SCENE := preload("res://Scenes/enemy_ship.tscn")
const TURRET_SCENE := preload("res://Scenes/turret.tscn")
const PartKind := preload("res://Scripts/data/part_kind.gd")

signal on_fort_damaged_tier(tier: int)
signal on_battle_finished(won: bool, by_fort_breach: bool)

@export_group("全局配置")
@export var config_path: NodePath

@export_group("胜利条件")
@export var kills_to_win: int = 12

@export_group("敌船")
@export var spawn_interval: float = 4.0
@export var first_spawn_delay: float = 1.5
@export var enemy_speed: float = 35.0
## 敌船停下开火的位置（x 坐标）；陆地缩到 60px 后从 320 改成 120
@export var enemy_stop_distance: float = 120.0
@export var spawn_x: float = 1330.0

@export_group("堡 · 炮位（T-302）")
## 水门所在道（5 条道时是中间那条 = 2）
@export var water_gate_lane: int = 2
## 每道初始炮数，长度应等于航道数；水门道默认 0 门
@export var turret_lane_counts: Array[int] = [1, 1, 0, 1, 1]
## 每道炮位上限
@export var turret_lane_cap_normal: int = 2
@export var turret_lane_cap_water: int = 1
## 总炮位上限（首版 6）
@export var turret_total_cap: int = 6
@export var turret_x: float = 34.0
@export var turret_scale: float = 1.35
## 同一道多门炮时的纵向错位
@export var turret_lane_spread: float = 20.0

@export_group("堡 · 数值（T-301/T-303）")
@export var fort_max_hp: float = 400.0
@export var turret_damage: float = 6.0
@export var turret_cooldown: float = 3.0
## 射程：从炮口往右算的 X 距离（T-302：400）
@export var turret_range: float = 400.0
@export var turret_shell_speed: float = 1400.0
## 四档阈值（T-301：0.6 / 0.25，不用船那套 0.75/0.10）
@export var fort_tier_damaged: float = 0.6
@export var fort_tier_broken: float = 0.25

@export_group("堡 · 四档贴图（T-301）")
@export var fort_texture_intact: Texture2D
@export var fort_texture_damaged: Texture2D
@export var fort_texture_broken: Texture2D
@export var fort_texture_gone: Texture2D

@export_group("兜底与结局（T-305）")
## 0 = 简单（3 次）/ 1 = 普通（2 次）/ 2 = 困难（1 次）
@export var difficulty: int = 1
## 失败兜底次数；-1 表示按难度自动取
@export var fail_times: int = -1
## 破堡演出：敌船驶入水门的终点 X
@export var gate_target_x: float = -60.0
## 破堡演出的起跑位置 X（不够远就拉到这里，保证演出来得及）
@export var gate_start_x: float = 640.0
## 破堡演出兜底超时（秒）
@export var gate_enter_timeout: float = 8.0

@export_group("灯火（T-304）")
@export var lamp_value: int = 100
@export var lamp_penalty: Array[int] = [-8, -12, -25]

@export_group("警报文案（T-306）")
## 同一句提醒的冷却
@export var alert_cooldown: float = 8.0

@export_group("结算")
@export var end_delay: float = 3.0
@export var management_scene: String = "res://Scenes/Management/management.tscn"
## 没有会话时（直接 F5 跑战斗）要不要也进经营
@export var auto_begin_session: bool = true

const FAIL_TIMES_BY_DIFFICULTY := [3, 2, 1]
const ManagementRules := preload("res://Scripts/Management/management_rules.gd")

## 兜底次数要跨「重整」保留（reload 场景后 static 不丢）
static var persisted_fail_times: int = -1
## 本场战斗的开场快照（BattleStart，来自经营会话）
var _battle_start: Dictionary = {}

@onready var _lanes: Node = $Lanes
@onready var _turret_root: Node2D = $Fortress
@onready var _fort_sprite: Sprite2D = get_node_or_null("Fortress/FortVisual")
@onready var _player = $PlayerShip
@onready var _enemies: Node2D = $Enemies
@onready var _projectiles: Node2D = $Projectiles
@onready var _crosshair: Node2D = get_node_or_null("Crosshair")
@onready var _status: Label = $HUD/Status
@onready var _banner: Label = $HUD/Banner
@onready var _hint: Label = get_node_or_null("HUD/Hint")
@onready var _alert_label: Label = get_node_or_null("HUD/Alert")

var kills: int = 0
var fortress_hp: float = 0.0
var is_over: bool = false
## 本场是否已进入破堡演出
var gate_sequence: bool = false
var fail_times_left: int = 2

var _config: Node = null
var _turrets: Array[Node2D] = []
var _turret_lanes: Array[int] = []
var _turret_timers: Array[float] = []
var _spawn_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _clock: float = 0.0
var _alert_until: Dictionary = {}
var _lamp_tier_done: Array[bool] = [false, false, false]
var _fort_tier: int = 0
var _gate_entered: bool = false
var _damage_since_alert: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_config = _resolve_config()
	fortress_hp = fort_max_hp
	if persisted_fail_times < 0:
		persisted_fail_times = _resolve_fail_times()
	fail_times_left = persisted_fail_times
	_spawn_timer = first_spawn_delay
	_banner.text = ""
	if _alert_label:
		_alert_label.text = ""
		_alert_label.modulate.a = 0.0
	_enemies.add_to_group("enemies_root")
	_projectiles.add_to_group("projectiles")
	_inject_config()
	_apply_fort_texture(0)
	build_turrets()
	_refresh_status()
	if _hint:
		_hint.text = "鼠标瞄准 · 左键开火 · 1/2/3 换弹 · Q 切换齐射 · A/D 航行 · W/S 换道"
	_apply_battle_start()


func _resolve_fail_times() -> int:
	if fail_times >= 0:
		return fail_times
	return int(FAIL_TIMES_BY_DIFFICULTY[clampi(difficulty, 0, 2)])


## 让所有需要全局配置的节点拿到同一份 Config
func _inject_config() -> void:
	if _config == null:
		return
	_player.config_source = _config
	for child in _enemies.get_children():
		if child.has_method("set_config"):
			child.set_config(_config)


func _resolve_config() -> Node:
	if config_path != NodePath():
		var node := get_node_or_null(config_path)
		if node != null:
			return node
	var local := get_node_or_null("CombatConfig")
	if local != null:
		return local
	return get_node_or_null("/root/CombatConfig")


# ---------- 敌船 ----------

func spawn_enemy(lane: int = -1) -> Node2D:
	var count: int = maxi(_lanes.lane_count, 1)
	var index: int = lane if lane >= 0 else _rng.randi_range(0, count - 1)
	var ship: Node2D = ENEMY_SCENE.instantiate()
	ship.lane_index = index
	ship.speed = enemy_speed
	ship.stop_distance = enemy_stop_distance
	ship.breach_x = enemy_stop_distance - 20.0
	ship.position.x = spawn_x
	ship.place_on_lane(_lanes.lane_bottom_y(index))
	ship.sunk.connect(_on_enemy_sunk)
	ship.breached.connect(_on_enemy_breached)
	ship.attacked_fort.connect(_on_enemy_attacked_fort)
	_enemies.add_child(ship)
	if _config != null and ship.has_method("set_config"):
		ship.set_config(_config)
	return ship


func _on_enemy_sunk(_ship: Area2D) -> void:
	kills += 1
	_refresh_status()
	# 击沉 = 敌方士气下降（战斗胜利条件的一个表达，本期仍用击沉数）
	if kills >= kills_to_win and not is_over:
		_finish_won()


## 敌船冲过防线（已停船开火的敌人不会走到这一步；留作兜底）
func _on_enemy_breached(_ship: Area2D) -> void:
	if is_over:
		return
	_damage_fort(fort_max_hp * 0.1, "breach")


func _on_enemy_attacked_fort(damage: float) -> void:
	if is_over:
		return
	_damage_fort(damage, "attack")


## T-304：堡受击的唯一入口
func _damage_fort(amount: float, _source: String) -> void:
	if is_over:
		return
	var before: float = fortress_hp
	fortress_hp = maxf(0.0, fortress_hp - amount)
	_damage_since_alert += before - fortress_hp
	_check_fort_tier()
	_refresh_status()
	if fortress_hp <= 0.0:
		_start_gate_sequence()


# ---------- 堡：四档外观（T-301） ----------

## 0 = 完整 / 1 = 破损 / 2 = 破坏 / 3 = 门没了
func fort_tier() -> int:
	if fortress_hp <= 0.0:
		return 3
	var r: float = 1.0 if fort_max_hp <= 0.0 else fortress_hp / fort_max_hp
	if r <= fort_tier_broken:
		return 2
	if r <= fort_tier_damaged:
		return 1
	return 0


## 换档时只切图，不做补间（T-301 要求「门没了在归零瞬间就切」）
func _check_fort_tier() -> void:
	var tier: int = fort_tier()
	if tier <= _fort_tier:
		return
	_fort_tier = tier
	_apply_fort_texture(tier)
	match tier:
		1:
			_alert("贼攻城", "attack", 12.0)
		2:
			_alert("台已半圮", "half", 30.0)
		3:
			pass


func _apply_fort_texture(tier: int) -> void:
	_fort_tier = tier
	if _fort_sprite == null:
		return
	var tex: Texture2D = null
	match tier:
		0:
			tex = fort_texture_intact
		1:
			tex = fort_texture_damaged
		2:
			tex = fort_texture_broken
		_:
			tex = fort_texture_gone
	if tex != null:
		_fort_sprite.texture = tex


# ---------- 炮台（T-302 / T-303） ----------

## 按道布炮：有炮的道才开火，没有「盲道」这个概念。
func build_turrets() -> void:
	for child in _turret_root.get_children():
		if child.name == "FortVisual":
			continue
		child.queue_free()
	_turrets.clear()
	_turret_lanes.clear()
	_turret_timers.clear()

	var lane_count: int = maxi(_lanes.lane_count, 1)
	var total: int = 0
	for lane in range(lane_count):
		var want: int = _lane_turret_count(lane)
		var cap: int = turret_lane_cap_water if lane == water_gate_lane else turret_lane_cap_normal
		want = clampi(want, 0, cap)
		for k in range(want):
			if total >= turret_total_cap:
				break
			var turret: Node2D = TURRET_SCENE.instantiate()
			turret.lane_index = lane
			var dy: float = 0.0
			if want > 1:
				dy = (float(k) - float(want - 1) * 0.5) * turret_lane_spread
			turret.position = Vector2(turret_x, _lanes.lane_center_y(lane) + dy)
			turret.scale = Vector2(turret_scale, turret_scale)
			_turret_root.add_child(turret)
			_turrets.append(turret)
			_turret_lanes.append(lane)
			_turret_timers.append(turret_cooldown * _rng.randf_range(0.2, 1.0))
			total += 1
	_refresh_status()


func _lane_turret_count(lane: int) -> int:
	if lane >= 0 and lane < turret_lane_counts.size():
		return turret_lane_counts[lane]
	return 0


## 某条道当前有几门炮
func turret_count_in_lane(lane: int) -> int:
	var n: int = 0
	for l in _turret_lanes:
		if l == lane:
			n += 1
	return n


func _process(delta: float) -> void:
	_clock += delta
	_update_crosshair()
	if is_over:
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = spawn_interval
		spawn_enemy()
	_update_turrets(delta)
	_update_status_live()


func _update_crosshair() -> void:
	if _crosshair == null:
		return
	_crosshair.global_position = get_global_mouse_position()


func _update_turrets(delta: float) -> void:
	for i in range(_turrets.size()):
		_turret_timers[i] = maxf(0.0, _turret_timers[i] - delta)
		if _turret_timers[i] > 0.0:
			continue
		var turret: Node2D = _turrets[i]
		var lane: int = _turret_lanes[i]
		var muzzle: Vector2 = turret.muzzle_position()
		var target := _frontmost_enemy_in_lane(lane, muzzle.x + turret_range)
		if target == null:
			continue
		_launch_straight(muzzle, target)
		_turret_timers[i] = turret_cooldown


## 本道最靠左（最接近堡）的敌船，必须在射程内
func _frontmost_enemy_in_lane(lane: int, max_x: float) -> Node2D:
	var best: Node2D = null
	for child in _enemies.get_children():
		var ship := child as Node2D
		if ship == null or not ("lane_index" in ship):
			continue
		if int(ship.lane_index) != lane:
			continue
		if ship.global_position.x > max_x:
			continue
		if ship.get("is_entering_gate") == true:
			continue
		if best == null or ship.global_position.x < best.global_position.x:
			best = ship
	return best


## 堡炮：直射（33-M15 4.1），不走抛物线，不误伤玩家船（mask 只打敌船层）
func _launch_straight(from: Vector2, target: Node2D) -> Area2D:
	var ball: Area2D = PROJECTILE_SCENE.instantiate()
	ball.position = from
	ball.ammo_type = 0
	ball.from_player = false
	ball.target_mask = 8
	ball.lane_index = int(target.lane_index)
	ball.arc_gravity = 0.0
	ball.damage_override = turret_damage
	var dir: Vector2 = (target.global_position - from).normalized()
	ball.velocity = dir * turret_shell_speed
	_projectiles.add_child(ball)
	return ball


# ---------- 破堡演出与判负（T-305） ----------

func _start_gate_sequence() -> void:
	if gate_sequence:
		return
	gate_sequence = true
	is_over = true
	_apply_fort_texture(3)
	_alert("城陷矣", "fall", 60.0)
	_freeze_player(true)
	# 所有炮停火
	for i in range(_turret_timers.size()):
		_turret_timers[i] = 99999.0
	# 其余敌船停手
	for child in _enemies.get_children():
		if child.has_method("set_attack_enabled"):
			child.set_attack_enabled(false)
	var ship := _nearest_enemy_to_gate()
	if ship == null or not ship.has_method("enter_gate"):
		_end_battle(false, true)
		return
	# 演出：把它挪到水门道，从画面右侧驶向水门（避免原地等它开半小时）
	ship.lane_index = water_gate_lane
	if ship.has_method("place_on_lane"):
		ship.place_on_lane(_lanes.lane_bottom_y(water_gate_lane))
	ship.global_position.x = maxf(ship.global_position.x, gate_start_x)
	ship.entered_gate.connect(_on_enemy_entered_gate)
	ship.enter_gate(gate_target_x)
	# 演出兜底：卡住也要收场
	await get_tree().create_timer(gate_enter_timeout).timeout
	if not _gate_entered:
		_end_battle(false, true)


func _nearest_enemy_to_gate() -> Node2D:
	var best: Node2D = null
	var best_x: float = INF
	for child in _enemies.get_children():
		var ship := child as Node2D
		if ship == null or not is_instance_valid(ship):
			continue
		if ship.get("is_sunk") == true:
			continue
		if ship.global_position.x < best_x:
			best_x = ship.global_position.x
			best = ship
	return best


func _on_enemy_entered_gate(_ship: Node2D) -> void:
	if _gate_entered:
		return
	_gate_entered = true
	_end_battle(false, true)


func _freeze_player(frozen: bool) -> void:
	if _player == null:
		return
	if _player.has_method("set_frozen"):
		_player.set_frozen(frozen)
	_player.set_physics_process(not frozen)
	var weapon := _player.get_node_or_null("Body/Weapon")
	if weapon != null:
		weapon.set_process(not frozen)


func _finish_won() -> void:
	if is_over:
		return
	is_over = true
	_banner.text = "守住了！"
	_banner.add_theme_color_override("font_color", Color(0.85, 0.78, 0.45))
	on_battle_finished.emit(true, false)
	await get_tree().create_timer(end_delay).timeout
	if is_inside_tree():
		_go_to_management(true)


## 本场失败：扣兜底；还有次数就重整，归零就进结局
func _end_battle(_won: bool, by_fort_breach: bool) -> void:
	if by_fort_breach:
		fail_times_left = maxi(0, fail_times_left - 1)
		persisted_fail_times = fail_times_left
	on_battle_finished.emit(false, by_fort_breach)
	if fail_times_left > 0:
		_banner.text = "堡已破 · 乡兵击退了倭寇"
		_banner.add_theme_color_override("font_color", Color(0.86, 0.72, 0.42))
		push_warning("[battle] 本场失败，剩余兜底 %d 次" % fail_times_left)
		await get_tree().create_timer(end_delay).timeout
		if is_inside_tree():
			_go_to_management(false)
	else:
		_banner.text = "堡已破 · 乡兵尽没"
		_banner.add_theme_color_override("font_color", Color(0.72, 0.3, 0.28))
		# 结局本期不做：留接口 + 日志
		push_warning("[battle] 兜底次数归零 → 触发结局分支（本版未实现结局场景）")
		await get_tree().create_timer(end_delay).timeout
		if is_inside_tree():
			_go_to_management(false)


# ---------- 警报文案（T-306） ----------

## 同一句有冷却；多道同时开打合并成一条（后到的同类提醒直接吃掉）
func _alert(text: String, key: String, cd: float = -1.0) -> void:
	if _alert_label == null:
		return
	var wait: float = alert_cooldown if cd < 0.0 else cd
	var until: float = float(_alert_until.get(key, -1.0))
	if _clock < until:
		return
	_alert_until[key] = _clock + wait
	_alert_label.text = text
	_alert_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(_alert_label, "modulate:a", 0.0, 0.9)


# ---------- HUD ----------

func _refresh_status() -> void:
	_update_status_live()


## 堡等级：炮门数 4 → Ⅰ / 5 → Ⅱ / 6 → Ⅲ
func fort_level_index() -> int:
	var n: int = _turrets.size()
	if n >= 6:
		return 3
	if n >= 5:
		return 2
	return 1


func fort_level_name() -> String:
	match fort_level_index():
		1:
			return "Ⅰ"
		2:
			return "Ⅱ"
		3:
			return "Ⅲ"
	return "·"


## 炮位格：已解锁 ■，未解锁 □（首版总 6 格）
func turret_slot_markers() -> String:
	var parts: Array[String] = []
	for i in range(turret_total_cap):
		parts.append("■" if i < _turrets.size() else "□")
	return "".join(parts)


func _update_status_live() -> void:
	if _status == null:
		return
	var weapon: Node = null
	if _player.has_node("Body/Weapon"):
		weapon = _player.get_node("Body/Weapon")
	var ammo_text := ""
	if weapon != null:
		var sel: int = int(weapon.ammo_selected)
		var names := ["实心", "破帆", "爆炸"]
		var parts: Array[String] = []
		for i in range(weapon.ammo.size()):
			var mark: String = "▶" if i == sel else " "
			parts.append("%s%s%d" % [mark, names[i], int(weapon.ammo[i])])
		ammo_text = "  ".join(parts)
	var hp_parts: Array[String] = []
	for p in range(PartKind.COUNT):
		if _player.has_method("part_ratio"):
			hp_parts.append("%s%d%%" % [PartKind.NAMES[p], int(round(_player.part_ratio(p) * 100.0))])
	var ratio: float = 0.0 if fort_max_hp <= 0.0 else clampf(fortress_hp / fort_max_hp, 0.0, 1.0)
	_status.text = "%s        击沉 %d / %d        堡%s  %d%%   炮位 %s\n%s" % [
		ammo_text, kills, kills_to_win, fort_level_name(), int(round(ratio * 100.0)),
		turret_slot_markers(), "  ".join(hp_parts),
	]

# ---------- 战斗 ⇄ 经营 数据互通 ----------

## 开场：把经营给的 BattleStart 快照铺到本场战斗里
func _session() -> Node:
	return get_node_or_null("/root/GameSession")


func _apply_battle_start() -> void:
	var gs: Node = _session()
	if gs == null:
		return
	var snap: Dictionary = gs.battle_start
	if snap.is_empty() and auto_begin_session:
		gs.begin_run("normal", 1)
		snap = gs.battle_start
	if snap.is_empty():
		return
	_battle_start = snap
	var ship_level: int = int(snap.get("ship_level", 1))
	var fort_level: int = int(snap.get("fort_level", 1))
	lamp_value = clampi(int(snap.get("light", lamp_value)), 0, 100)
	var weapon := _player.get_node_or_null("Body/Weapon")
	if weapon != null and snap.has("ammo"):
		var a: Dictionary = snap["ammo"]
		var given: Array = [int(a.get("round", 0)), int(a.get("chain", 0)), int(a.get("grape", 0))]
		var ammo_arr: Array = weapon.ammo
		for i in range(mini(given.size(), ammo_arr.size())):
			weapon.ammo[i] = int(given[i])
	var fcap: float = float(ManagementRules.fort_cap(fort_level))
	if fcap > 0.0:
		fortress_hp = clampf(fort_max_hp * float(snap.get("fort_hp", fcap)) / fcap, 0.0, fort_max_hp)
	var caps: Dictionary = ManagementRules.ship_caps(ship_level)
	if _player != null and snap.has("ship_hp"):
		var hp: Dictionary = snap["ship_hp"]
		_set_part_ratio(PartKind.HULL, hp.get("hull", 0), caps.get("hull", 1))
		_set_part_ratio(PartKind.SAIL, hp.get("rigging", 0), caps.get("rigging", 1))
		_set_part_ratio(PartKind.CANNON, hp.get("guns", 0), caps.get("guns", 1))
	fail_times_left = maxi(0, int(snap.get("defeats_left", fail_times_left)))
	persisted_fail_times = fail_times_left
	_refresh_status()


func _set_part_ratio(part: int, value: Variant, cap: Variant) -> void:
	if _player == null:
		return
	var c: float = maxf(1.0, float(cap))
	var r: float = clampf(float(value) / c, 0.0, 1.0)
	_player.part_hp[part] = float(_player.part_hp_max[part]) * r


func _part_ratio(part: int) -> float:
	if _player == null:
		return 1.0
	var mx: float = maxf(1.0, float(_player.part_hp_max[part]))
	return clampf(float(_player.part_hp[part]) / mx, 0.0, 1.0)


## 按契约打包战果（键名不能改，经营侧会校验）
func _build_result(won: bool) -> Dictionary:
	var snap: Dictionary = _battle_start
	if snap.is_empty():
		var gs: Node = _session()
		if gs != null:
			snap = gs.battle_start
	var ship_level: int = int(snap.get("ship_level", 1))
	var fort_level: int = int(snap.get("fort_level", 1))
	var caps: Dictionary = ManagementRules.ship_caps(ship_level)
	var fcap: int = int(ManagementRules.fort_cap(fort_level))
	var ship_hp: Dictionary = {
		"hull": int(roundf(float(caps.get("hull", 100)) * _part_ratio(PartKind.HULL))),
		"rigging": int(roundf(float(caps.get("rigging", 60)) * _part_ratio(PartKind.SAIL))),
		"guns": int(roundf(float(caps.get("guns", 60)) * _part_ratio(PartKind.CANNON))),
	}
	var ammo: Dictionary = {"round": 0, "chain": 0, "grape": 0}
	var weapon := _player.get_node_or_null("Body/Weapon")
	if weapon != null:
		ammo["round"] = int(weapon.ammo[0])
		ammo["chain"] = int(weapon.ammo[1])
		ammo["grape"] = int(weapon.ammo[2])
	var fort_ratio: float = clampf(fortress_hp / maxf(1.0, fort_max_hp), 0.0, 1.0)
	var left: int = int(snap.get("defeats_left", 0))
	if not won:
		left -= 1
	return {
		"battle_id": int(snap.get("battle_id", 1)),
		"won": won,
		"light": clampi(int(roundf(lamp_value)), 0, 100),
		"ammo": ammo,
		"ship_hp": ship_hp,
		"fort_hp": clampi(int(roundf(float(fcap) * fort_ratio)), 0, fcap),
		"defeats_left": maxi(0, left),
	}


## 战斗结束：提交战果 → 切经营 → 把会话交给经营界面
func _go_to_management(won: bool) -> void:
	var gs: Node = _session()
	if gs != null and gs.has_session():
		if not gs.submit_result(_build_result(won)):
			push_warning("[battle] 战果被经营会话拒绝，按无数据进入经营")
	var err: int = get_tree().change_scene_to_file(management_scene)
	if err != OK:
		push_error("[battle] 切经营场景失败：%s (err %d)" % [management_scene, err])
		return
	# 本节点马上会被销毁，绑定交给不被销毁的 autoload
	if gs != null:
		gs.bind_pending_scene()
