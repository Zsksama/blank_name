extends CharacterBody2D
@export var move_speed: float = 300.0
@export var lanes_path: NodePath = ^"../Lanes"
## 换道阻尼强度：越大越快贴上道中心，越小越"漂"
@export_range(1.0, 40.0, 0.5) var lane_change_smoothing: float = 20.0
var _target_lane: int = 0
var _lanes: Node

func _ready() -> void:
	_lanes = get_node_or_null(lanes_path)
	if _lanes:
		_target_lane = _lanes.lane_index_at_y(global_position.y)

func _physics_process(delta: float) -> void:
	var dir_x: float = Input.get_axis("move_left", "move_right")
	velocity.x = dir_x * move_speed
	
	# 找不到海道时退回自由四向移动
	if _lanes == null:
		velocity.y = Input.get_axis("move_up", "move_down") * move_speed
		move_and_slide()
		return
	
	velocity.y = 0.0
	if Input.is_action_just_pressed("move_up"):
		_target_lane -= 1
	if Input.is_action_just_pressed("move_down"):
		_target_lane += 1

	move_and_slide()

	_target_lane = _lanes.clamp_lane_index(_target_lane)
	var target_y: float = _lanes.lane_center_y(_target_lane)
	var weight: float = 1.0 - exp(-lane_change_smoothing * delta)
	global_position.y = lerp(global_position.y, target_y, weight)

## 炮口位置：船体贴图 96x40，炮口在右侧边缘。开火由 battle_manager 负责，这里只提供坐标。
func muzzle_position() -> Vector2:
	return global_position + Vector2(52.0, 0.0)

## 当前所在（正在前往）的海道序号。
func current_lane() -> int:
	return _target_lane
