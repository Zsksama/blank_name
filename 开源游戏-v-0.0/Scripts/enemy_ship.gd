## 敌船：沿固定水道向左推进（lane_index 不变、y 不变），打到舰体归零就沉；
## 推到左岸（堡前沿）算"被冲破"，由战斗管理器扣堡耐久。
## 部位损伤与玩家船同一套规则（23-M4），只是不自动维修。
extends Area2D

const PartKind := preload("res://Scripts/data/part_kind.gd")

signal sunk(ship: Area2D)
signal breached(ship: Area2D)

@export var speed: float = 70.0
## 越过这条 X 线就算冲破防线（默认 = 海面左边界）
@export var breach_x: float = 268.0
## 倭船 E-01 占位：舰体 40 / 帆 30 / 炮台 20 / 舵 15 / 撞角 15
@export var part_hp_max: Array[int] = [40, 30, 20, 15, 15]

@export_group("视角（俯视感：越靠下的航道画在越前面、也越大）")
@export var base_z_index: int = 20
@export var z_step_per_lane: int = 10
@export var perspective_scale_per_lane: float = 0.04
## 船底对齐航道中线（关掉=船体中心对齐中线）
@export var align_bottom_to_lane_center: bool = true
## 半个船身高（px，未缩放）。_ready 里会按碰撞箱自动校正
@export var body_half_height: float = 100.0

@export_group("受击表现")
## 受击闪白/闪红的时长
@export var flash_time: float = 0.14
@export var flash_color: Color = Color(1.0, 0.42, 0.36, 1.0)
## 是否显示飘字伤害
@export var show_damage_text: bool = true

@export_group("部位外观（23-M4 7.1）")
@export var sail_torn_texture: Texture2D
@export var sail_ruined_texture: Texture2D
@export var hull_burn_texture: Texture2D

var lane_index: int = 0
## 由 battle_manager 指定的航道中线 y；-1 表示还没指定
var lane_center_y: float = -1.0
var part_hp: Array[int] = []
var is_sunk: bool = false

var _config: Node = null
var _alive: bool = true
var _sail_overlay: Sprite2D = null
var _hull_overlay: Sprite2D = null
var _body_sprite: Sprite2D = null


func _ready() -> void:
	add_to_group("damageable_ships")
	add_to_group("enemy_ships")
	part_hp.resize(PartKind.COUNT)
	for i in range(PartKind.COUNT):
		var src: int = part_hp_max[i] if i < part_hp_max.size() else 20
		part_hp[i] = src
	z_index = base_z_index + lane_index * z_step_per_lane
	var s: float = 1.0 + perspective_scale_per_lane * float(lane_index)
	scale = Vector2(s, s)
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		body_half_height = (cs.shape as RectangleShape2D).size.y * 0.5
	# 若 spawn 时先调了 place_on_lane（那时 scale 还是 1），这里按真实缩放重算一次
	if lane_center_y >= 0.0:
		place_on_lane(lane_center_y)
	_body_sprite = get_node_or_null("Sprite2D") as Sprite2D
	_sail_overlay = get_node_or_null("SailOverlay") as Sprite2D
	_hull_overlay = get_node_or_null("HullOverlay") as Sprite2D
	_refresh_damage_visuals()


## 部位受损外观（23-M4 7.1）：帆破损→裂口；帆破坏→只剩骨架；舰体受损→焦痕；炮台破坏→整船发暗
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
	if _body_sprite != null:
		var gun_ok: bool = part_state(PartKind.CANNON) != PartKind.STATE_DESTROYED
		_body_sprite.modulate = Color(1, 1, 1, 1) if gun_ok else Color(0.62, 0.58, 0.55, 1.0)


## 船底抬升量（贴图中心锚点，所以抬半个身高的缩放量）
func bottom_shift() -> float:
	if not align_bottom_to_lane_center:
		return 0.0
	return body_half_height * scale.y


## 把船放到指定航道的中线上（船底贴这条线）
func place_on_lane(center_y: float) -> void:
	lane_center_y = center_y
	position.y = center_y - bottom_shift()


func set_config(cfg: Node) -> void:
	_config = cfg


func config() -> Node:
	if _config != null:
		return _config
	return get_node_or_null("/root/CombatConfig")


# ---------- 部位 ----------

func part_hp_value(part: int) -> int:
	return part_hp[part] if part >= 0 and part < part_hp.size() else 0


func part_max(part: int) -> int:
	return part_hp_max[part] if part >= 0 and part < part_hp_max.size() else 1


func part_ratio(part: int) -> float:
	return clampf(float(part_hp_value(part)) / float(maxi(part_max(part), 1)), 0.0, 1.0)


func part_state(part: int) -> int:
	var ratio := part_ratio(part)
	if ratio <= PartKind.THRESHOLD_DESTROYED:
		return PartKind.STATE_DESTROYED
	if ratio <= PartKind.THRESHOLD_BROKEN:
		return PartKind.STATE_BROKEN
	return PartKind.STATE_NORMAL


## 帆被打坏就减速（×0.7 / ×0.4）
func current_speed() -> float:
	match part_state(PartKind.SAIL):
		PartKind.STATE_BROKEN:
			return speed * 0.7
		PartKind.STATE_DESTROYED:
			return speed * 0.4
	return speed


# ---------- 受击 ----------

## 由 ShipPartBox 转交：命中哪个部位、造成多少伤害
func apply_part_hit(part: int, projectile: Node) -> void:
	if not _alive or is_sunk:
		return
	var cfg: Node = config()
	var ammo_type: int = int(projectile.ammo_type) if "ammo_type" in projectile else 0
	var at: int = clampi(ammo_type, 0, 2)
	var base: float = float(projectile.damage) if "damage" in projectile else 5.0
	var ov: float = float(projectile.damage_override) if "damage_override" in projectile else 0.0
	if cfg != null:
		if ov > 0.0:
			# 堡炮：固定伤害 × 部位系数（仍受"打帆穿透、打舰体停"的规则）
			base = ov * float(cfg.damage_mult_vs_part[at][part])
		else:
			base = float(cfg.shell_damage[at]) * float(cfg.damage_mult_vs_part[at][part])
	elif ov > 0.0:
		base = ov
	var lost: float = minf(base, float(part_hp_value(part)))
	_damage_part(part, base)
	# 炮台命中额外伤舰体（23-M4：显式伴随伤害，别藏在碰撞箱重叠里）
	if part == PartKind.CANNON and cfg != null:
		var extra: float = base * float(cfg.cannon_extra_hull_ratio)
		lost += minf(extra, float(part_hp_value(PartKind.HULL)))
		_damage_part(PartKind.HULL, extra)
	_show_hit(lost)

## 受击表现：闪色 + 飘字（24-M3 的伤害系数一改，这里显示的数值会跟着变）
func _show_hit(lost: float) -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.modulate = flash_color
		var tw := create_tween()
		tw.tween_property(sprite, "modulate", Color.WHITE, flash_time)
	if not show_damage_text or lost < 0.5:
		return
	var label := Label.new()
	label.text = "-%d" % int(round(lost))
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.55, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.z_index = 200
	var parent := get_parent()
	if parent == null:
		return
	parent.add_child(label)
	label.global_position = global_position + Vector2(0.0, -46.0)
	var tw2 := label.create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(label, "position:y", label.position.y - 30.0, 0.7)
	tw2.tween_property(label, "modulate:a", 0.0, 0.7)
	tw2.chain().tween_callback(label.queue_free)


func _damage_part(part: int, amount: float) -> void:
	if part < 0 or part >= part_hp.size():
		return
	part_hp[part] = maxi(0, int(round(part_hp[part] - amount)))
	_refresh_damage_visuals()
	if part == PartKind.HULL and part_hp[PartKind.HULL] <= 0:
		_sink()


func _sink() -> void:
	if not _alive:
		return
	_alive = false
	is_sunk = true
	sunk.emit(self)
	# 沉没表现：淡出 + 下沉 + 轻微倾斜，播完再回收
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.45)
	tw.tween_property(self, "position:y", position.y + 30.0, 0.45)
	tw.tween_property(self, "rotation", deg_to_rad(10.0), 0.45)
	tw.chain().tween_callback(queue_free)


# ---------- 推进 ----------

func _process(delta: float) -> void:
	if not _alive or is_sunk:
		return
	global_position.x -= current_speed() * delta
	if global_position.x <= breach_x:
		_alive = false
		breached.emit(self)
		queue_free()
