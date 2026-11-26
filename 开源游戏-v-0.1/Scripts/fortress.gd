class_name Fortress
extends Node2D

@export var damage_textures: Array[Texture2D]

## 望楼模块的标记接口。
var is_marked := false

@onready var _visual: Sprite2D = $FortVisual


func show_damage(tier: int) -> void:
	_visual.texture = damage_textures[tier]
