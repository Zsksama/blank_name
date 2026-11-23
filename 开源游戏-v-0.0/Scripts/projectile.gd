## 通用炮弹：一种积分器 + 弹种参数驱动（23-M4 / 24-M3 / 27-数据字典）。
## 不做「实心弹一个脚本、爆炸弹另一个脚本」。
extends Area2D

const PartKind := preload("res://Scripts/data/part_kind.gd")

## 0 实心 / 1 破帆 / 2 爆炸
@export var ammo_type: int = 0
## 跨道判定用：只有同道目标才结算（23-M4 / 26）
@export var lane_index: int = -1
@export var damage: float = 12.0
## >0 时覆盖弹种伤害表：堡炮用固定 6 伤（33-M15 4.2），不吃 24-M3 的弹种系数
@export var damage_override: float = 0.0
## 注意：不能叫 gravity —— Area2D 自带同名属性，重名会直接解析报错
@export var arc_gravity: float = 1500.0
@export var drag_k: float = 0.0
## 还能再穿透几次（破帆弹）
@export var pierce_left: int = 0
@export var pierce_damage_falloff: float = 0.6
@export var explode_radius: float = 0.0
@export var from_player: bool = true
## 打谁：8 = 敌船的部位碰撞箱，16 = 玩家船的部位碰撞箱。
## 炮台（堡）和玩家船打的是同一种目标，所以都是 8；以后敌人开炮才用 16。
@export var target_mask: int = 8

@export_group("出界回收")
@export var despawn_min_x: float = -120.0
@export var despawn_max_x: float = 1400.0
@export var despawn_min_y: float = -320.0
@export var despawn_max_y: float = 900.0

@export_group("拖尾")
@export var puff_interval: float = 0.045
@export var puff_lifetime: float = 0.4
@export var puff_scale: float = 1.3
@export var puff_color: Color = Color(0.9, 0.92, 0.97, 0.6)
@export var puff_z_index: int = 4
@export var puff_texture: Texture2D

var velocity: Vector2 = Vector2(900.0, 0.0)
## 同一发炮弹对同一部位只结算一次（23-M4）
var hit_parts: Dictionary = {}

var _puff_timer: float = 0.0
var _spent: bool = false

func _ready() -> void:
	# 不再按 from_player 猜层号：炮台炮弹也是打敌船的，猜到 16 会打空
	collision_mask = target_mask
	area_entered.connect(_on_area_entered)

func _process(delta: float) -> void:
	if _spent:
		return
	velocity = step_velocity(velocity, delta)
	position += velocity * delta
	_puff_timer -= delta
	if _puff_timer <= 0.0:
		_puff_timer = puff_interval
		_spawn_puff()
	if position.x < despawn_min_x or position.x > despawn_max_x:
		queue_free()
	elif position.y > despawn_max_y or position.y < despawn_min_y:
		queue_free()

## 与 Ballistics.step_velocity 完全一致的积分（改一处必须改两处）
func step_velocity(v: Vector2, delta: float) -> Vector2:
	if drag_k > 0.0:
		var speed := v.length()
		return v + (-drag_k * speed * v + Vector2(0.0, arc_gravity)) * delta
	return v + Vector2(0.0, arc_gravity) * delta

func _on_area_entered(area: Area2D) -> void:
	if _spent or not area.has_method("receive_hit"):
		return
	var ship: Node = null
	if area.has_method("owner_ship"):
		ship = area.owner_ship()
	else:
		ship = area.get_parent()
	if ship == null:
		return
	# 跨道：不同道的目标一律穿过（23-M4）
	if int(ship.get("lane_index")) != lane_index:
		return
	var blocked: bool = area.receive_hit(self)
	if ammo_type == 2:
		_explode()
		_consume()
		return
	if blocked:
		_consume()
		return
	# 穿透：伤害衰减，穿透次数用尽后继续衰减
	if pierce_left > 0:
		pierce_left -= 1
	damage *= pierce_damage_falloff

## 爆炸弹：只结算同一航道、半径内的船（26 号议题：AoE 不跨道）
func _explode() -> void:
	for s in get_tree().get_nodes_in_group("damageable_ships"):
		if s == null or not is_instance_valid(s):
			continue
		# 玩家的爆炸弹只伤敌船，不炸自己
		if from_player and not s.is_in_group("enemy_ships"):
			continue
		if int(s.get("lane_index")) != lane_index:
			continue
		if s.global_position.distance_to(global_position) > explode_radius:
			continue
		if not s.has_method("apply_part_hit"):
			continue
		for part in [PartKind.HULL, PartKind.SAIL, PartKind.CANNON]:
			s.apply_part_hit(part, self)

func _consume() -> void:
	_spent = true
	set_deferred("monitoring", false)
	queue_free()

func _spawn_puff() -> void:
	if puff_texture == null:
		return
	var parent := get_parent()
	if parent == null:
		return
	var puff := Sprite2D.new()
	puff.texture = puff_texture
	puff.global_position = global_position
	puff.scale = Vector2.ONE * puff_scale
	puff.modulate = puff_color
	puff.z_index = puff_z_index
	parent.add_child(puff)
	var tween := puff.create_tween()
	tween.tween_property(puff, "modulate:a", 0.0, puff_lifetime)
	tween.parallel().tween_property(puff, "scale", Vector2.ONE * puff_scale * 1.8, puff_lifetime)
	tween.tween_callback(puff.queue_free)
