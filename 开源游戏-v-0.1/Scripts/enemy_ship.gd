extends Area2D

## 敌船：沿固定水道向左推进（Y 不变），被打光血量就沉，
## 推到左岸（碉堡前沿）算"被冲破"，由战斗管理器扣碉堡耐久。

signal sunk(ship: Area2D)
signal breached(ship: Area2D)

@export var speed: float = 70.0
@export var max_hp: int = 1
## 越过这条 X 线就算冲破防线（默认 = 海面左边界）
@export var breach_x: float = 268.0

var hp: int = 1
var lane_index: int = 0
var _alive: bool = true

func _ready() -> void:
	hp = max_hp

func _process(delta: float) -> void:
	if not _alive:
		return
	global_position.x -= speed * delta
	if global_position.x <= breach_x:
		_alive = false
		breached.emit(self)
		queue_free()

## 被炮弹命中时由 projectile.gd 调用
func take_hit(damage: int) -> void:
	if not _alive:
		return
	hp -= damage
	if hp <= 0:
		_alive = false
		sunk.emit(self)
		queue_free()
