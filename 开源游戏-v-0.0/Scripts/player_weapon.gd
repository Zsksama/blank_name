## 唬船的炮台与弹药模块（P-01 的 turret / ammo / reload 数据与逻辑都在这里）。
## 移动和部位在 player_ship.gd，两边互不写对方的字段。
extends Node2D

const PartKind := preload("res://Scripts/data/part_kind.gd")
const Ballistics := preload("res://Scripts/ballistics.gd")
const PROJECTILE_SCENE := preload("res://Scenes/projectile.tscn")

signal fired(shots: int)
signal state_changed

@export_group("炮台")
@export var turret_count: int = 2
@export var angle_min: float = 0.0
## 上限 90° = 正上方。不再给到 180°（正后方），避免炮弹往船后面飞。
@export var angle_max: float = 90.0
## 炮口追随鼠标的角速度（度/秒）
@export var angle_speed: float = 120.0
@export var muzzle_len: float = 36.0
## 每门炮的转轴（相对船体）
@export var turret_pivots: Array = [Vector2(20, -13), Vector2(-14, -13)]
## 装填时间（秒/门）
@export var reload_time: Array[float] = [1.0, 1.0]
## 齐射散布（±度）
@export var spread_deg: float = 5.0

@export_group("弹药：0 实心 / 1 破帆 / 2 爆炸")
## 三种各自独立、无上限
@export var ammo: Array[int] = [30, 20, 10]
@export var ammo_selected: int = 0
## 0 单发 / 1 齐射
@export var fire_mode: int = 0
@export var switch_ammo_delay: float = 1.5

@export_group("节点")
@export var preview_path: NodePath = ^"Preview"
@export var turret_paths: Array = [^"Turret0", ^"Turret1"]
## 预览线最多画多少个点（60 点 ≈ 1 秒飞行）。调小 = 只提示方向
@export var preview_max_points: int = 34

@export_group("装填倒计时")
## 在每门炮上方显示「还剩几秒 / 就绪」
@export var show_reload_labels: bool = true
@export var reload_label_font_size: int = 24
@export var reload_label_offset: Vector2 = Vector2(0, -20)

var turret_angle: float = 90.0
var reload_left: Array[float] = [0.0, 0.0]
var switch_lock: float = 0.0

var _line: Line2D
var _turret_sprites: Array[Node2D] = []
var _reload_labels: Array[Label] = []

func _ready() -> void:
	add_to_group("player_weapon")
	_line = get_node_or_null(preview_path) as Line2D
	if _line:
		_line.top_level = true
	for p in turret_paths:
		var sprite := get_node_or_null(p) as Node2D
		if sprite:
			_turret_sprites.append(sprite)
	reload_left.resize(maxi(turret_count, 1))
	for i in range(reload_left.size()):
		reload_left[i] = 0.0
	_update_turret_sprites()
	_build_reload_labels()

func _process(delta: float) -> void:
	_update_aim(delta)
	_update_reload(delta)
	_update_preview()
	_update_reload_labels()
	if Input.is_action_just_pressed("fire"):
		try_fire()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				select_ammo(0)
			KEY_2:
				select_ammo(1)
			KEY_3:
				select_ammo(2)
			KEY_Q:
				toggle_fire_mode()
				get_viewport().set_input_as_handled()

# ---------- 瞄准 ----------

func _update_aim(delta: float) -> void:
	var ship := ship_node()
	if ship == null or turret_pivots.is_empty():
		return
	var pivot: Vector2 = (ship.get_node("Body") if ship.has_node("Body") else ship).to_global(turret_pivots[0])
	var target_angle := Ballistics.angle_to_point(pivot, get_global_mouse_position())
	target_angle = clampf(target_angle, angle_min, angle_max)
	var step := angle_speed * delta
	turret_angle += clampf(target_angle - turret_angle, -step, step)
	_update_turret_sprites()

func _update_turret_sprites() -> void:
	for i in range(_turret_sprites.size()):
		var sprite := _turret_sprites[i]
		sprite.rotation_degrees = -turret_angle
		if i < turret_pivots.size():
			sprite.position = turret_pivots[i]

## 第 i 门炮的炮口世界坐标
func muzzle_global(index: int = 0) -> Vector2:
	var ship := ship_node()
	if ship == null or turret_pivots.is_empty():
		return global_position
	var body := ship.get_node_or_null("Body") as Node2D
	var base_node: Node2D = body if body != null else ship
	var i: int = clampi(index, 0, turret_pivots.size() - 1)
	var pivot: Vector2 = base_node.to_global(turret_pivots[i])
	var a := deg_to_rad(turret_angle)
	return pivot + Vector2(cos(a), -sin(a)) * muzzle_len

# ---------- 装填与开火 ----------

func _update_reload(delta: float) -> void:
	for i in range(reload_left.size()):
		reload_left[i] = maxf(0.0, reload_left[i] - delta)
	switch_lock = maxf(0.0, switch_lock - delta)

func ready_turrets() -> Array[int]:
	var out: Array[int] = []
	for i in range(mini(turret_count, reload_left.size())):
		if reload_left[i] <= 0.0:
			out.append(i)
	return out

func can_fire() -> bool:
	var ship := ship_node()
	if ship == null or ship.is_sunk or ship.is_switching:
		return false
	if not ship.cannon_operable() or switch_lock > 0.0:
		return false
	if int(ammo[ammo_selected]) <= 0:
		return false
	var ready := ready_turrets()
	if ready.is_empty():
		return false
	if fire_mode == 1 and int(ammo[ammo_selected]) < ready.size():
		return false
	return true

## 鼠标左键触发：单发打一发，齐射把所有就绪炮同时打出去
func try_fire() -> void:
	if not can_fire():
		return
	var ship := ship_node()
	var cfg: Node = ship.config()
	if cfg == null:
		return
	var ready := ready_turrets()
	var shots: Array[int] = []
	if fire_mode == 0:
		shots.append(ready[0])
	else:
		shots = ready
	for i in shots:
		_spawn_projectile(i, cfg, ship)
		reload_left[i] = float(reload_time[i]) * ship.reload_multiplier()
	ammo[ammo_selected] = int(ammo[ammo_selected]) - shots.size()
	ship.add_recoil(1.0)
	state_changed.emit()
	fired.emit(shots.size())

func _spawn_projectile(index: int, cfg: Node, ship: Node) -> void:
	var proj := PROJECTILE_SCENE.instantiate()
	var a: float = turret_angle + randf_range(-spread_deg, spread_deg) * 0.5
	proj.ammo_type = ammo_selected
	proj.damage = float(cfg.shell_damage[ammo_selected])
	proj.arc_gravity = float(cfg.gravity)
	proj.drag_k = float(cfg.drag_k)
	proj.pierce_left = int(cfg.pierce_count[ammo_selected])
	proj.pierce_damage_falloff = float(cfg.pierce_damage_falloff)
	proj.explode_radius = float(cfg.explode_radius) if ammo_selected == 2 else 0.0
	proj.lane_index = int(ship.lane_index)
	proj.from_player = true
	proj.velocity = Ballistics.velocity_from_angle(a, float(cfg.shell_speed[ammo_selected]))
	proj.position = muzzle_global(index)
	var container := get_tree().get_first_node_in_group("projectiles")
	if container == null:
		container = get_tree().current_scene
	container.add_child(proj)

# ---------- 弹药切换 ----------

func select_ammo(index: int) -> void:
	if index < 0 or index >= ammo.size() or index == ammo_selected:
		return
	ammo_selected = index
	switch_lock = switch_ammo_delay
	state_changed.emit()

func toggle_fire_mode() -> void:
	fire_mode = 1 - fire_mode
	state_changed.emit()

# ---------- 装填倒计时 ----------

func _build_reload_labels() -> void:
	for l in _reload_labels:
		if is_instance_valid(l):
			l.queue_free()
	_reload_labels.clear()
	for i in range(reload_left.size()):
		var l := Label.new()
		l.top_level = true
		l.z_index = 100
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", reload_label_font_size)
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
		add_child(l)
		_reload_labels.append(l)

func _update_reload_labels() -> void:
	if _reload_labels.is_empty():
		return
	var ship := ship_node()
	var body: Node2D = null
	if ship != null:
		body = ship.get_node_or_null("Body") as Node2D
		if body == null:
			body = ship as Node2D
	for i in range(_reload_labels.size()):
		var l := _reload_labels[i]
		if not show_reload_labels or body == null or turret_pivots.is_empty():
			l.visible = false
			continue
		var idx: int = clampi(i, 0, turret_pivots.size() - 1)
		var anchor: Vector2 = body.to_global(turret_pivots[idx]) + reload_label_offset
		var left: float = reload_left[i] if i < reload_left.size() else 0.0
		if left > 0.0:
			l.text = "%.1f" % left
			l.add_theme_color_override("font_color", Color(1.0, 0.72, 0.32, 1.0))
		else:
			l.text = "就绪"
			l.add_theme_color_override("font_color", Color(0.62, 1.0, 0.66, 1.0))
		l.visible = true
		l.position = anchor - Vector2(l.size.x * 0.5, l.size.y * 0.5)

# ---------- 预览线 ----------

func _update_preview() -> void:
	if _line == null:
		return
	var ship := ship_node()
	if ship == null or ship.is_switching or not ship.cannon_operable() or switch_lock > 0.0:
		_line.visible = false
		return
	var cfg: Node = ship.config()
	if cfg == null:
		return
	var from := muzzle_global(0)
	var v := Ballistics.velocity_from_angle(turret_angle, float(cfg.shell_speed[ammo_selected]))
	var pts: PackedVector2Array = Ballistics.simulate(from, v, float(cfg.gravity), float(cfg.drag_k), 1.0 / 60.0)
	# 只画前一段（用户反馈：画完整条线手感很怪，先给一截方向提示）
	if preview_max_points > 1 and pts.size() > preview_max_points:
		pts = pts.slice(0, preview_max_points)
	_line.points = pts
	_line.visible = true

func ship_node() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("part_state") and n.has_method("config"):
			return n
		n = n.get_parent()
	return null
