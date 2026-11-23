## 唬船 P-01：只负责「移动 + 部位血量 + 自修 + 后坐力位移」。
## 炮台、瞄准、弹药、装填在 player_weapon.gd；开火命令由它自己处理，不塞进这里。
extends CharacterBody2D

signal parts_changed
signal sunk

const PartKind := preload("res://Scripts/data/part_kind.gd")

@export_group("移动")
@export var move_speed: float = 250.0
@export var lanes_path: NodePath = ^"../Lanes"
## 换道耗时（秒），期间禁止开火
@export var lane_switch_time: float = 0.6

@export_group("部位（顺序：舰体/帆/炮台/舵/撞角）")
@export var part_hp_max: Array[int] = [100, 60, 60, 40, 40]
@export var threshold_broken: float = 0.75
@export var threshold_destroyed: float = 0.10

@export_group("自动维修")
## 子文件夹里 27-数据字典：破损档基础速率 0.5 %/s
@export var repair_base_rate: float = 0.5
@export var repair_discount_broken: float = 1.0
@export var repair_discount_destroyed: float = 0.2
@export var max_repair_ratio: float = 0.6

@export_group("视角（俯视感：越靠下的航道画在越前面、也越大）")
@export var base_z_index: int = 21
@export var z_step_per_lane: int = 10
@export var perspective_scale_per_lane: float = 0.04
## 船底对齐航道中线（关掉=船体中心对齐中线）
@export var align_bottom_to_lane_center: bool = true
## 半个船身高（px，未缩放）。_ready 里会按碰撞箱自动校正
@export var body_half_height: float = 108.0

@export_group("部位外观（23-M4 7.1）")
@export var sail_torn_texture: Texture2D
@export var sail_ruined_texture: Texture2D
@export var hull_burn_texture: Texture2D

@export_group("后坐力")
@export var recoil_impulse: float = 6.0
@export var recoil_sink: float = 3.0
@export var recoil_pitch: float = 4.0
@export var recoil_recover_time: float = 0.18

@export_group("击沉")
@export var captain_name: String = ""

var part_hp: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
## 逻辑航道号：只有换道才变，后坐力/浪只改 lane_offset_y
var lane_index: int = 0
var is_switching: bool = false
var lane_offset_y: float = 0.0
var wave_offset: float = 0.0
var is_sunk: bool = false
var respawn_timer: float = 0.0
## 由战斗管理器注入的全局配置（找不到时回落到 combat_config 组）
var config_source: Node = null

var _lanes: Node
var _body: Node2D
var _switch_left: float = 0.0
var _switch_span: float = 1.0
var _switch_from: float = 0.0
var _recoil: float = 0.0
var _repair_emit_timer: float = 0.0
var _sail_overlay: Sprite2D = null
var _hull_overlay: Sprite2D = null
var _turret_visuals: Array[Sprite2D] = []

func _ready() -> void:
	add_to_group("damageable_ships")
	add_to_group("player_ship")
	_lanes = get_node_or_null(lanes_path)
	_body = get_node_or_null("Body")
	part_hp.resize(PartKind.COUNT)
	for i in range(PartKind.COUNT):
		part_hp[i] = float(part_hp_max[i])
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		body_half_height = (cs.shape as RectangleShape2D).size.y * 0.5
	if _lanes:
		# 船底对齐时，位置 y 是船底而不是中心，按"船底 → 航道"反推
		lane_index = int(_lanes.lane_index_at_bottom_y(global_position.y))
	_sail_overlay = get_node_or_null("Body/SailOverlay") as Sprite2D
	_hull_overlay = get_node_or_null("Body/HullOverlay") as Sprite2D
	for p in ["Body/Weapon/Turret0", "Body/Weapon/Turret1"]:
		var t := get_node_or_null(p) as Sprite2D
		if t != null:
			_turret_visuals.append(t)
	_refresh_damage_visuals()

func _physics_process(delta: float) -> void:
	var speed := move_speed * sail_speed_multiplier()
	velocity.x = Input.get_axis("move_left", "move_right") * speed
	velocity.y = 0.0

	if not is_switching:
		if Input.is_action_just_pressed("move_up"):
			begin_lane_switch(-1)
		elif Input.is_action_just_pressed("move_down"):
			begin_lane_switch(1)

	move_and_slide()
	_update_switch(delta)
	_update_recoil(delta)
	_update_repair(delta)
	_apply_position_y()

# ---------- 移动 ----------

## W/S 换道：一次只走一道，0.6s 内吞掉新输入
func begin_lane_switch(direction: int) -> void:
	if _lanes == null or is_sunk:
		return
	# 换道途中吞掉新输入（用户拍板：不排队）
	if is_switching:
		return
	if part_state(PartKind.RUDDER) == 2:
		return
	var target: int = int(_lanes.clamp_lane_index(lane_index + direction))
	if target == lane_index:
		return
	var span: float = lane_switch_time
	if part_state(PartKind.RUDDER) == 1:
		span *= 1.4
	_switch_from = float(_lanes.lane_center_y(lane_index)) - float(_lanes.lane_center_y(target))
	lane_index = target
	_switch_span = maxf(span, 0.01)
	_switch_left = _switch_span
	is_switching = true

func _update_switch(delta: float) -> void:
	if not is_switching:
		lane_offset_y = 0.0
		return
	_switch_left = maxf(0.0, _switch_left - delta)
	var t: float = 1.0 - (_switch_left / _switch_span)
	var k: float = t * t * (3.0 - 2.0 * t)
	lane_offset_y = _switch_from * (1.0 - k)
	if _switch_left <= 0.0:
		is_switching = false
		lane_offset_y = 0.0

func _apply_position_y() -> void:
	if _lanes == null:
		return
	# 俯视感：下面的航道画在前面，并稍微放大
	z_index = base_z_index + lane_index * z_step_per_lane
	var s: float = 1.0 + perspective_scale_per_lane * float(lane_index)
	scale = Vector2(s, s)
	# 船底贴该海道下方的分道线（方案 B）：整条船从这条线往上"立"起来
	global_position.y = float(_lanes.lane_bottom_y(lane_index)) + lane_offset_y + wave_offset - _bottom_shift()
	if _body:
		_body.position = Vector2(-recoil_impulse * _recoil, recoil_sink * _recoil)
		_body.rotation_degrees = -recoil_pitch * _recoil

## 船底要往上抬多少（贴图是中心锚点，所以抬半个身高的缩放量）
func _bottom_shift() -> float:
	if not align_bottom_to_lane_center:
		return 0.0
	return body_half_height * scale.y

## 当前逻辑航道号（炮弹跨道判定用）
func current_lane() -> int:
	return lane_index

# ---------- 部位 ----------

func config() -> Node:
	if config_source != null:
		return config_source
	return get_tree().get_first_node_in_group("combat_config")

## 0 正常 / 1 破损 / 2 被破坏（由 hp/hp_max 实时算，不单独存）
func part_state(part: int) -> int:
	var mx := float(part_hp_max[part])
	if mx <= 0.0:
		return 2
	var ratio: float = part_hp[part] / mx
	if ratio <= threshold_destroyed:
		return 2
	if ratio <= threshold_broken:
		return 1
	return 0

func part_ratio(part: int) -> float:
	var mx := float(part_hp_max[part])
	if mx <= 0.0:
		return 0.0
	return part_hp[part] / mx

func sail_speed_multiplier() -> float:
	match part_state(PartKind.SAIL):
		1:
			return 0.7
		2:
			return 0.4
	return 1.0

func reload_multiplier() -> float:
	return 1.3 if part_state(PartKind.CANNON) == 1 else 1.0

func cannon_operable() -> bool:
	return part_state(PartKind.CANNON) < 2

## 被炮弹命中时由 ship_part_box.gd 调用
func apply_part_hit(part: int, proj: Area2D) -> void:
	if is_sunk:
		return
	var cfg := config()
	if cfg == null or part < 0 or part >= PartKind.COUNT:
		return
	var at: int = clampi(int(proj.get("ammo_type")), 0, 2)
	var base: float = float(cfg.shell_damage[at]) * float(cfg.damage_mult_vs_part[at][part])
	_damage_part(part, base)

	if part == PartKind.HULL:
		_try_conduction(PartKind.HULL, PartKind.RUDDER, base, cfg)
		_try_conduction(PartKind.HULL, PartKind.RAM, base, cfg)
	elif part == PartKind.CANNON:
		# 炮台命中时显式伴随伤害舰体（不靠碰撞箱重叠）
		_damage_part(PartKind.HULL, base * float(cfg.cannon_extra_hull_ratio))
		_try_conduction(PartKind.CANNON, PartKind.RUDDER, base, cfg)
		_try_conduction(PartKind.CANNON, PartKind.RAM, base, cfg)

func _damage_part(part: int, amount: float) -> void:
	if amount <= 0.0:
		return
	part_hp[part] = maxf(0.0, part_hp[part] - amount)
	parts_changed.emit()
	_refresh_damage_visuals()
	if part == PartKind.HULL and part_hp[part] <= 0.0:
		_sink()


## 部位受损外观（23-M4 7.1）：帆破损→裂口贴图；帆破坏→只剩骨架；舰体受损→焦痕；炮台破坏→炮管变暗
func _refresh_damage_visuals() -> void:
	if _sail_overlay != null:
		var st: int = part_state(PartKind.SAIL)
		if st == PartKind.STATE_DESTROYED and sail_ruined_texture != null:
			_sail_overlay.texture = sail_ruined_texture
			_sail_overlay.visible = true
		elif st == PartKind.STATE_BROKEN and sail_torn_texture != null:
			_sail_overlay.texture = sail_torn_texture
			_sail_overlay.visible = true
		else:
			_sail_overlay.visible = false
	if _hull_overlay != null and hull_burn_texture != null:
		var hs: int = part_state(PartKind.HULL)
		_hull_overlay.visible = hs != PartKind.STATE_NORMAL
		_hull_overlay.texture = hull_burn_texture
		_hull_overlay.modulate.a = 1.0 if hs == PartKind.STATE_DESTROYED else 0.55
	var gun_ok: bool = cannon_operable()
	for t in _turret_visuals:
		if t != null:
			t.modulate = Color(1, 1, 1, 1) if gun_ok else Color(0.38, 0.34, 0.30, 1.0)

func _try_conduction(source: int, target: int, base: float, cfg: Node) -> void:
	var row: int = 0 if source == PartKind.HULL else 1
	var col: int = 0 if target == PartKind.RUDDER else 1
	var state := part_state(source)
	var chance: float = 0.0
	if state == 1:
		chance = float(cfg.conduction_prob_broken[row][col])
	elif state == 2:
		chance = float(cfg.conduction_prob_destroyed)
	if chance <= 0.0:
		return
	if randf() < chance:
		_damage_part(target, base * float(cfg.conduction_ratio))

func _update_repair(delta: float) -> void:
	if is_sunk:
		return
	var changed := false
	for i in range(PartKind.COUNT):
		var mx := float(part_hp_max[i])
		if mx <= 0.0:
			continue
		var ratio: float = part_hp[i] / mx
		if ratio >= threshold_broken:
			continue
		var rate: float = repair_base_rate
		if ratio <= threshold_destroyed:
			rate *= repair_discount_destroyed
		else:
			rate *= repair_discount_broken
		var cap: float = max_repair_ratio * mx
		if part_hp[i] >= cap:
			continue
		part_hp[i] = minf(cap, part_hp[i] + rate / 100.0 * mx * delta)
		changed = true
	if changed:
		_repair_emit_timer -= delta
		if _repair_emit_timer <= 0.0:
			_repair_emit_timer = 0.25
			parts_changed.emit()

func _sink() -> void:
	if is_sunk:
		return
	is_sunk = true
	sunk.emit()

# ---------- 后坐力 ----------

func add_recoil(amount: float = 1.0) -> void:
	_recoil = minf(1.0, _recoil + amount)

func _update_recoil(delta: float) -> void:
	if _recoil > 0.0:
		_recoil = maxf(0.0, _recoil - delta / maxf(recoil_recover_time, 0.001))
