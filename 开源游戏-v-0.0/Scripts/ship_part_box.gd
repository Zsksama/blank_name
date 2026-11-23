## 船的单个碰撞箱。挂在船下面，三个：帆（软）/ 舰体（硬）/ 炮台（硬）。
## 规则来自 23-M4：打帆穿过去、打舰体或炮台停下、炮台命中同时伤舰体。
extends Area2D

const PartKind := preload("res://Scripts/data/part_kind.gd")

## 所属部位（PartKind.HULL / SAIL / CANNON）
@export var part: int = PartKind.HULL
## 软箱：炮弹穿过去不消失（帆）
@export var soft: bool = false

## 炮弹进入时由 projectile.gd 调用。返回 true = 炮弹被拦下。
func receive_hit(proj: Area2D) -> bool:
	var ship := owner_ship()
	if ship == null:
		return false
	if proj.hit_parts.has(part):
		return not soft
	proj.hit_parts[part] = true
	ship.apply_part_hit(part, proj)
	return not soft

## 往上找带 apply_part_hit 的船节点
func owner_ship() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("apply_part_hit"):
			return n
		n = n.get_parent()
	return null
