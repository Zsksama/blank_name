extends Node2D

var lane_index: int = 0


func muzzle_position() -> Vector2:
	return $Muzzle.global_position
