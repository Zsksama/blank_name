class_name Watchtower
extends Node2D

## M11 望楼指引（T-505）
## 规则来源：`10-战斗/39-M11望楼.md` + `程序任务派发/待派-望楼.md`
## 望楼是堡的“眼睛”：不替你打，只告诉你先打谁、打哪儿，并让被锁的那艘整船吃更多伤害。

@export_group("锁定")
## 被锁目标受到的伤害倍率（+50% = 1.5，占位，后续挂 M5 升级）。
@export var damage_multiplier := 1.5
## 目标跑到这个 x 以外就算“退场”，视同沉没，立刻重锁。
@export var retreat_x := 1360.0

@export_group("准星")
## 准星半径（像素）。
@export var radius := 16.0
## 旋转速度（度/秒）。
@export var spin_speed := 90.0
## 放大缩小循环的频率与幅度。
@export var pulse_speed := 3.0
@export var pulse_amount := 0.16
## 黄 → 红 的渐变往返频率。
@export var color_speed := 1.6
@export var color_yellow := Color(1.0, 0.86, 0.25)
@export var color_red := Color(0.95, 0.22, 0.18)
@export var color_black := Color(0.12, 0.12, 0.14)

# 准星图形：四段圆弧 + 中心十字，程序化画，不依赖贴图。
@export_group("调试")
@export var log_lock := true

var target: EnemyShip = null

var _manager: Node = null
var _player: PlayerShip = null
var _enemies: Node = null
var _boarding: Node = null

var _locked_part: int = ShipParts.Part.CANNON
var _phase := 0.0
var _color_phase := 0.0
var _spin := 0.0


func setup(manager: Node, player: PlayerShip, enemies: Node, boarding: Node) -> void:
	_manager = manager
	_player = player
	_enemies = enemies
	_boarding = boarding
	z_index = 60
	z_as_relative = false


func _process(delta: float) -> void:
	# 接舷期间锁定冻结：不换目标、不重锁，准星也不动（T-505 边界）。
	var frozen := _boarding != null and bool(_boarding.get("active"))

	if not frozen:
		_refresh_target()
		var unlocked := target != null and _target_alive(target)
		if unlocked:
			_phase += delta * pulse_speed
			_spin += delta * spin_speed
			_color_phase += delta * color_speed

	if target != null and _target_alive(target):
		visible = true
		global_position = _anchor_point(target)
		queue_redraw()
	else:
		visible = false


## 选“横向速度最快”的那艘；目标消失立刻重锁。
func _refresh_target() -> void:
	if target != null and _target_alive(target):
		return
	_release_target()
	var best: EnemyShip = null
	var best_speed := -INF
	if _enemies == null:
		return
	for child in _enemies.get_children():
		var ship := child as EnemyShip
		if ship == null or not _target_alive(ship):
			continue
		var moving_speed: float = absf(ship.current_speed())
		if moving_speed > best_speed:
			best_speed = moving_speed
			best = ship
	if best == null:
		return
	target = best
	_locked_part = _part_for(best)
	target.combat.damage_taken_multiplier = damage_multiplier
	_phase = 0.0
	_spin = 0.0
	_color_phase = 0.0
	if log_lock:
		print("[望楼] 锁定 %s（速度 %.1f） 准星部位=%s 加伤 x%.2f" % [
			best.config.display_name, best_speed, _part_name(_locked_part), damage_multiplier])


func _release_target() -> void:
	if target != null and is_instance_valid(target):
		target.combat.damage_taken_multiplier = 1.0
	target = null


func _target_alive(ship: EnemyShip) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	if not ship.combat.targetable or ship.combat.parts.is_sunk():
		return false
	if ship.global_position.x > retreat_x:
		return false
	return true


## 快船锁帆（打帆让它慢下来），普通船 / 重船锁火器与弓手（先打掉火力）。
func _part_for(ship: EnemyShip) -> int:
	return ShipParts.Part.SAIL if ship.config.ship_class == EnemyShipConfig.ShipClass.FAST else ShipParts.Part.CANNON


func _anchor_point(ship: EnemyShip) -> Vector2:
	var box: Rect2 = ship.combat.hitbox(_locked_part)
	return box.get_center()


func _part_name(part: int) -> String:
	match part:
		ShipParts.Part.SAIL:
			return "帆"
		ShipParts.Part.CANNON:
			return "火器与弓手"
		ShipParts.Part.HULL:
			return "舰体"
		_:
			return "部位%d" % part


func _draw() -> void:
	var locked_broken := false
	if target != null and is_instance_valid(target):
		locked_broken = target.combat.parts.condition(_locked_part) == ShipParts.Condition.DESTROYED

	var color := color_black if locked_broken else color_yellow.lerp(color_red, 0.5 + 0.5 * sin(_color_phase))
	var scale_factor := 1.0 + pulse_amount * sin(_phase)
	var r := radius * scale_factor

	# 四段圆弧（留出缺口，像准星）
	var gap := deg_to_rad(26.0)
	for i in range(4):
		var start := _deg_to_rad(_spin) + i * TAU / 4.0 + gap * 0.5
		draw_arc(Vector2.ZERO, r, start, start + TAU / 4.0 - gap, 12, color, 2.5, true)
	# 中心十字
	draw_line(Vector2(-r * 0.35, 0.0), Vector2(-r * 0.12, 0.0), color, 2.0, true)
	draw_line(Vector2(r * 0.12, 0.0), Vector2(r * 0.35, 0.0), color, 2.0, true)
	draw_line(Vector2(0.0, -r * 0.35), Vector2(0.0, -r * 0.12), color, 2.0, true)
	draw_line(Vector2(0.0, r * 0.12), Vector2(0.0, r * 0.35), color, 2.0, true)


func _deg_to_rad(value: float) -> float:
	return value * PI / 180.0


## 供验收脚本读取。
func locked_part() -> int:
	return _locked_part


func locked_part_is_broken() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return target.combat.parts.condition(_locked_part) == ShipParts.Condition.DESTROYED
