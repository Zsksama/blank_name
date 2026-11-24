class_name CombatConfig
extends Node

@export_group("弹道")
@export var gravity: float = 900.0
@export var drag_k: float = 0.0

@export_group("弹种：实心 / 破帆 / 爆炸")
@export var shell_speed: Array[float] = [520.0, 680.0, 420.0]
@export var shell_damage: Array[float] = [12.0, 5.0, 8.0]
@export var pierce_count: Array[int] = [0, 1, 0]
@export var pierce_damage_falloff: float = 0.6

@export_group("爆炸弹")
@export var explode_radius: float = 60.0
@export var explode_self_damage: bool = false
