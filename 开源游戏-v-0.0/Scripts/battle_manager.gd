extends Node2D

## 战斗管理器：波次生成、每道炮台自动开火（抛物线弹道）、胜负判定、切经营场景。
## 玩家的炮台/装填/弹药已交给 PlayerShip/Body/Weapon（player_weapon.gd），这里只读不写。
## 所有数值都用 @export 暴露，方便策划侧调参而不用改代码。

const PROJECTILE_SCENE := preload("res://Scenes/projectile.tscn")
const ENEMY_SCENE := preload("res://Scenes/enemy_ship.tscn")
const TURRET_SCENE := preload("res://Scenes/turret.tscn")
const PartKind := preload("res://Scripts/data/part_kind.gd")

@export_group("全局配置")
## 不填就从场景里的 CombatConfig 节点或 /root/CombatConfig 自动找
@export var config_path: NodePath

@export_group("胜利条件")
## 击沉多少艘算士气胜利（01 第六节 B16：不必全歼）
@export var kills_to_win: int = 12

@export_group("敌船")
@export var spawn_interval: float = 4.0
@export var first_spawn_delay: float = 1.5
@export var enemy_speed: float = 70.0
@export var spawn_x: float = 1330.0

@export_group("堡（33-M15）")
## 炮门数：初始 2，满级 4；上限被 lane_count - 1 锁死（盲道永远没炮）
@export var turret_slots: int = 2
@export var turret_x: float = 205.0
## 堡炮台整体放大倍数（船变大后炮台显得太小）
@export var turret_scale: float = 1.35
## 盲道 = 最靠近堡的那条道（默认 0 号），炮打不到，玩家必须自己去
@export var blind_lane: int = 0
## 堡总血量：单一血条，没有部位、没有传导（33-M15 3.4）
@export var fort_max_hp: float = 400.0
## 单发伤害
@export var turret_damage: float = 6.0
## 每门炮独立冷却
@export var turret_cooldown: float = 3.0
## 射程：从炮口往右算的 X 距离（33-M15 4.2：X ≤ 360）
@export var turret_range: float = 360.0
## 直射弹速（堡在高处俯射，不做抛物线）
@export var turret_shell_speed: float = 1400.0
## 敌船被冲破防线时对堡的伤害（敌人开火落地前先用这个兜底）
@export var breach_damage: float = 40.0
## 盲道提示（33-M15 7.2 方案 A）：给盲道压一层暗色
@export var show_blind_lane_hint: bool = true

@export_group("结算")
@export var end_delay: float = 3.0
@export var management_scene: String = "res://Scenes/Management/management_demo.tscn"

@onready var _lanes: Node = $Lanes
@onready var _turret_root: Node2D = $Fortress
@onready var _player = $PlayerShip
@onready var _enemies: Node2D = $Enemies
@onready var _projectiles: Node2D = $Projectiles
@onready var _crosshair: Node2D = get_node_or_null("Crosshair")
@onready var _status: Label = $HUD/Status
@onready var _banner: Label = $HUD/Banner
@onready var _hint: Label = get_node_or_null("HUD/Hint")

var kills: int = 0
var fortress_hp: float = 0.0
var is_over: bool = false
var _config: Node = null

var _turrets: Array[Node2D] = []
var _turret_timers: Array[float] = []
## 每门炮负责的航道列表（扇区）
var _turret_lanes: Array = []
var _spawn_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_config = _resolve_config()
	fortress_hp = fort_max_hp
	_spawn_timer = first_spawn_delay
	_banner.text = ""
	_enemies.add_to_group("enemies_root")
	_projectiles.add_to_group("projectiles")
	_inject_config()
	build_turrets()
	_refresh_status()
	if _hint:
		_hint.text = "鼠标瞄准 · 左键开火 · 1/2/3 换弹 · Q 切换齐射 · A/D 航行 · W/S 换道"


## 让所有需要全局配置的节点拿到同一份 Config
func _inject_config() -> void:
	if _config == null:
		return
	_player.config_source = _config
	for child in _enemies.get_children():
		if child.has_method("set_config"):
			child.set_config(_config)


## 找全局配置：@export > 场景里的 CombatConfig > /root/CombatConfig
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

## 生成一艘敌船。lane 为 -1 时随机选一条道。
func spawn_enemy(lane: int = -1) -> Node2D:
	var count: int = maxi(_lanes.lane_count, 1)
	var index: int = lane if lane >= 0 else _rng.randi_range(0, count - 1)
	var ship: Node2D = ENEMY_SCENE.instantiate()
	ship.lane_index = index
	ship.speed = enemy_speed
	ship.position.x = spawn_x
	ship.place_on_lane(_lanes.lane_bottom_y(index))
	ship.sunk.connect(_on_enemy_sunk)
	ship.breached.connect(_on_enemy_breached)
	_enemies.add_child(ship)
	if _config != null and ship.has_method("set_config"):
		ship.set_config(_config)
	return ship


func _on_enemy_sunk(_ship: Area2D) -> void:
	kills += 1
	_refresh_status()
	if kills >= kills_to_win:
		_finish(true)


func _on_enemy_breached(_ship: Area2D) -> void:
	# 被冲破：扣堡血，堡血归零即失败（33-M15 5.3：船沉不算失败，堡破才算）
	fortress_hp = maxf(0.0, fortress_hp - breach_damage)
	_refresh_status()
	if fortress_hp <= 0.0:
		_finish(false)


# ---------- 炮台 ----------

## 按扇区生成炮台：盲道不布炮，其余航道按 turret_slots 连续分组，一组一门炮。
## 33-M15 3.3：炮门上限 = lane_count - 1，所以 5 条道最多 4 门，永远有死角。
func build_turrets() -> void:
	for child in _turret_root.get_children():
		child.queue_free()
	var old_hint := get_node_or_null("BlindLaneHint")
	if old_hint != null:
		old_hint.queue_free()
	_turrets.clear()
	_turret_timers.clear()
	_turret_lanes.clear()
	var count: int = maxi(_lanes.lane_count, 1)
	var usable: Array[int] = []
	for i in range(count):
		if i != blind_lane:
			usable.append(i)
	if usable.is_empty():
		return
	var slots: int = clampi(turret_slots, 1, usable.size())
	for s in range(slots):
		var lo: int = int(floor(float(s) * float(usable.size()) / float(slots)))
		var hi: int = int(floor(float(s + 1) * float(usable.size()) / float(slots)))
		var lanes: Array[int] = []
		for k in range(lo, hi):
			lanes.append(usable[k])
		if lanes.is_empty():
			continue
		var mid_lane: int = lanes[lanes.size() / 2]
		var turret: Node2D = TURRET_SCENE.instantiate()
		turret.lane_index = mid_lane
		turret.position = Vector2(turret_x, _lanes.lane_center_y(mid_lane))
		turret.scale = Vector2(turret_scale, turret_scale)
		_turret_root.add_child(turret)
		_turrets.append(turret)
		_turret_lanes.append(lanes)
		_turret_timers.append(turret_cooldown * _rng.randf_range(0.2, 1.0))
	_build_blind_hint()


## 盲道提示（方案 A）：压一层暗色 + 一行小字，让玩家一眼看出这条道堡打不到
func _build_blind_hint() -> void:
	if not show_blind_lane_hint:
		return
	var lane_h: float = _lanes.lane_height()
	var rect := ColorRect.new()
	rect.name = "BlindLaneHint"
	rect.position = Vector2(_lanes.sea_left, _lanes.sea_top + lane_h * float(blind_lane))
	rect.size = Vector2(_lanes.sea_right - _lanes.sea_left, lane_h)
	rect.color = Color(0.06, 0.08, 0.14, 0.30)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = 9
	add_child(rect)
	var label := Label.new()
	label.name = "BlindLaneLabel"
	label.text = "盲道 · 堡打不到"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95, 0.55))
	label.position = Vector2(14.0, lane_h * 0.72)
	label.z_index = 12
	rect.add_child(label)


func _process(delta: float) -> void:
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
		var muzzle: Vector2 = turret.muzzle_position()
		var target := _frontmost_enemy_in_lanes(_turret_lanes[i], muzzle.x + turret_range)
		if target == null:
			continue
		_launch_straight(muzzle, target)
		_turret_timers[i] = turret_cooldown


## 扇区内最靠左（最接近堡）的敌船
func _frontmost_enemy_in_lanes(lanes: Array, max_x: float) -> Node2D:
	var best: Node2D = null
	for child in _enemies.get_children():
		var ship := child as Node2D
		if ship == null or not ("lane_index" in ship):
			continue
		if not lanes.has(ship.lane_index):
			continue
		if ship.global_position.x > max_x:
			continue
		if best == null or ship.global_position.x < best.global_position.x:
			best = ship
	return best


## 堡炮：直射（33-M15 4.1），不走抛物线
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


## 旧版「每条道一座炮台」的抛物线开火已删除（33-M15 红线：堡不能覆盖全场）。
## 需要抛物线弹道时用 Ballistics.gd + PlayerWeapon，不要在这里恢复。


# ---------- 结算 ----------

func _finish(won: bool) -> void:
	if is_over:
		return
	is_over = true
	_banner.text = "守住了！" if won else "碉堡失守……"
	_banner.add_theme_color_override("font_color", Color(0.85, 0.78, 0.45) if won else Color(0.72, 0.3, 0.28))
	refresh_after_end(won)


## 结算后要执行的收尾动作。单独一个函数，方便测试时替换/覆盖。
func refresh_after_end(_won: bool) -> void:
	await get_tree().create_timer(end_delay).timeout
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file(management_scene)


# ---------- HUD ----------

func _refresh_status() -> void:
	_update_status_live()


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
	var hp_text := ""
	var hp_parts: Array[String] = []
	for p in range(PartKind.COUNT):
		if _player.has_method("part_ratio"):
			hp_parts.append("%s%d%%" % [PartKind.NAMES[p], int(round(_player.part_ratio(p) * 100.0))])
	hp_text = "  ".join(hp_parts)
	var ratio: float = 0.0 if fort_max_hp <= 0.0 else clampf(fortress_hp / fort_max_hp, 0.0, 1.0)
	_status.text = "%s        击沉 %d / %d        堡%s %d / %d（%d%%）\n%s" % [
		ammo_text, kills, kills_to_win, fort_level_name(), int(round(fortress_hp)),
		int(round(fort_max_hp)), int(round(ratio * 100.0)), hp_text,
	]


## 堡的等级名：炮门数就是等级（2 = 堡Ⅰ / 3 = 堡Ⅱ / 4 = 堡Ⅲ，33-M15 6.2）
func fort_level_name() -> String:
	match _turrets.size():
		1:
			return "Ⅰ"
		2:
			return "Ⅰ"
		3:
			return "Ⅱ"
		4:
			return "Ⅲ"
	return "·"
