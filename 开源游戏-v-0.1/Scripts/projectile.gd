extends Area2D

## 抛物线炮弹：只受重力影响，不再走直线。
## 发射时的初速度由 battle_manager.arc_velocity() 反解出来（给定起点、落点、飞行时间）。

## 注意：属性名不能叫 gravity —— Area2D 自带一个 gravity（物理区域的重力覆盖），重名会直接解析报错
@export var arc_gravity: float = 1500.0
@export var damage: int = 1
@export var despawn_min_x: float = -80.0
@export var despawn_max_x: float = 1360.0
@export var despawn_min_y: float = -220.0
@export var despawn_max_y: float = 820.0

@export_group("拖尾")
## 每隔多少秒留一团硝烟
@export var puff_interval: float = 0.045
@export var puff_lifetime: float = 0.4
@export var puff_scale: float = 1.3
@export var puff_color: Color = Color(0.9, 0.92, 0.97, 0.6)
## 硝烟要盖在海面之上（海面 z=0，敌船 z=5，炮弹 z=6）
@export var puff_z_index: int = 4
## 硝烟贴图（一张柔边白色圆点），不填则退回炮弹贴图
@export var puff_texture: Texture2D

## 初速度（像素/秒）。由发射方设置。
var velocity: Vector2 = Vector2(900.0, 0.0)

var _puff_timer: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _process(delta: float) -> void:
	velocity.y += arc_gravity * delta
	global_position += velocity * delta

	_puff_timer -= delta
	if _puff_timer <= 0.0:
		_puff_timer = puff_interval
		_spawn_puff()

	if global_position.x < despawn_min_x or global_position.x > despawn_max_x:
		queue_free()
		return
	if global_position.y < despawn_min_y or global_position.y > despawn_max_y:
		queue_free()


## 留一团会淡出、变小的硝烟，用来把抛物线轨迹画出来。
func _spawn_puff() -> void:
	var parent := get_parent()
	if parent == null or _sprite == null:
		return
	var puff := Sprite2D.new()
	puff.texture = puff_texture if puff_texture != null else _sprite.texture
	puff.global_position = global_position
	puff.scale = Vector2(puff_scale, puff_scale) * (1.0 if puff_texture != null else _sprite.scale)
	puff.modulate = puff_color
	puff.z_index = puff_z_index
	parent.add_child(puff)
	var tween := puff.create_tween()
	tween.set_parallel(true)
	tween.tween_property(puff, "modulate:a", 0.0, puff_lifetime)
	tween.tween_property(puff, "scale", puff.scale * 0.4, puff_lifetime)
	tween.chain().tween_callback(puff.queue_free)


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("take_hit"):
		area.take_hit(damage)
	queue_free()
