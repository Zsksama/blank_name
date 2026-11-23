## 全局战斗配置：对应 27-数据字典「五、全局配置（不随存档变）」。
## 所有数值都在这一个节点上调，代码里不出现魔法数字。
extends Node

@export_group("弹道")
## 重力（px/s²），正数向下
@export var gravity: float = 900.0
## 空气阻力系数，0 = 不算阻力
@export var drag_k: float = 0.0

@export_group("弹种：0 实心 / 1 破帆 / 2 爆炸")
@export var shell_speed: Array[float] = [1050.0, 1150.0, 820.0]
@export var shell_damage: Array[float] = [12.0, 5.0, 8.0]
## 行 = 弹种，列 = 部位（舰体 / 帆 / 炮台 / 舵 / 撞角）
@export var damage_mult_vs_part: Array = [
	[1.0, 0.6, 0.85, 1.0, 1.0],
	[0.25, 1.8, 0.2, 0.25, 0.25],
	[0.85, 0.7, 0.95, 0.85, 0.85],
]
## 破帆弹打穿帆之后还能再穿几次
@export var pierce_count: Array[int] = [0, 1, 0]
## 穿透后这一发的伤害衰减比例
@export var pierce_damage_falloff: float = 0.6

@export_group("爆炸弹")
@export var explode_radius: float = 60.0
## 自伤开关：简单关、普通/困难开（难度未接，先用这个布尔）
@export var explode_self_damage: bool = false

@export_group("命中规则")
## 炮台命中时，额外对舰体结算的伤害比例（按同一发的基础伤害算）
@export var cannon_extra_hull_ratio: float = 1.0

@export_group("传导")
@export var conduction_ratio: float = 0.3
## 行 = 来源（0 舰体 / 1 炮台），列 = 目标（0 舵 / 1 撞角）；值为「破损」档概率
@export var conduction_prob_broken: Array = [[0.15, 0.10], [0.10, 0.10]]
## 「被破坏」档统一概率
@export var conduction_prob_destroyed: float = 0.30

func _ready() -> void:
	add_to_group("combat_config")
