class_name ShipDamageProfile
extends Resource

## 耐久顺序为帆、舰体、火器与弓手、舵、撞角。倍率依次为实心、破帆、爆炸。
@export var max_hp := PackedFloat64Array([80.0, 100.0, 60.0, 10.0, 10.0])
@export var sail_multipliers := Vector3(0.60, 1.80, 0.70)
@export var hull_multipliers := Vector3(1.00, 0.25, 0.85)
@export var cannon_multipliers := Vector3(0.85, 0.20, 0.95)

## 两列分别对应舵和撞角。
@export var hull_conduction_chance := Vector2(0.15, 0.10)
@export var cannon_conduction_chance := Vector2(0.10, 0.10)
@export var hull_conduction_scale := Vector2(0.30, 0.30)
@export var cannon_conduction_scale := Vector2(0.30, 0.30)
@export_range(0.0, 1.0) var cannon_hull_damage_scale := 0.50

## 以朝右的船为基准，坐标和大小均相对于船的宽高。
@export var sail_box := Rect2(-0.23, -0.50, 0.44, 0.39)
@export var hull_box := Rect2(-0.48, 0.01, 0.96, 0.47)
@export var cannon_box := Rect2(0.25, -0.14, 0.20, 0.15)
