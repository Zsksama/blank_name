class_name Fortress
extends Node2D

@export var damage_textures: Array[Texture2D]

@onready var watchtower: Watchtower = $Watchtower
@onready var _visual: Sprite2D = $FortVisual


func show_damage(tier: int) -> void:
	_visual.texture = damage_textures[tier]
