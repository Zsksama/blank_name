extends Node2D

## 单个海道炮台：只管"我在哪条道、炮口在哪"，开火由 battle_manager 统一调度。
## 每个海道一个，大小 96x96，摆在左侧陆地贴水的一侧。

## 炮口相对炮台中心的位置（贴图 96x96，炮管朝右、略高于中心）
@export var muzzle_offset: Vector2 = Vector2(48, 0)

var lane_index: int = 0

func muzzle_position() -> Vector2:
	return global_position + muzzle_offset
