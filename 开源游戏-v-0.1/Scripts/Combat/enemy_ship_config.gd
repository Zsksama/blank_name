class_name EnemyShipConfig
extends Resource

enum Type { FAST, NORMAL, HEAVY }

const MAX_SPEED := 22.0

@export_group("身份")
@export var id: StringName
@export var display_name: String
@export var enemy_type := Type.NORMAL
@export_range(1, 100, 1, "or_greater") var cost := 5
@export var sprite: Texture2D = preload("res://Assets/Art/Characters/ship_enemy_shared.png")
@export var size := Vector2(120.0, 56.0)
@export var tint := Color.WHITE
@export var sprite_faces_left := false
## 船底相对于贴图中心的纵向比例。
@export var art_keel_ratio := 0.43
@export var sail_cutout := Rect2(101, 33, 116, 53)
@export var sail_torn_texture: Texture2D = preload("res://Assets/Art/Effects/sail_torn_small.png")
@export var sail_ruined_texture: Texture2D = preload("res://Assets/Art/Effects/sail_ruined_small.png")
@export var hull_burn_texture: Texture2D = preload("res://Assets/Art/Effects/hull_burn_small.png")

@export_group("航行")
@export var speed := 16.0
@export var speed_variance := 0.0
@export var stop_distance := 320.0
## 为 0 时，发现射程内玩家后原地开火。
@export var player_stop_distance := 0.0
@export var min_gap := 144.0
@export var can_change_lane := false
@export var lane_change_margin := 180.0
## 船体中心到堡前沿进入这个距离后，才会沿水线躲闪。
@export var sway_fortress_range := 400.0
## 推进时的回摆强度，配合频率换算成沿水线的回摆速度。
@export var sway_advance := 0.0
## 停船开火时沿停位线内侧往返的半幅，单位为像素。
@export var sway_idle := 0.0
@export var sway_advance_hz := 0.0
@export var sway_idle_hz := 0.0

@export_group("攻击")
@export var attack_style := Projectile.Visual.ARROW
@export var attack_range := 200.0
@export var attack_damage := 4.0
@export var attack_interval := 3.0
@export var target_switch_delay := 0.3
@export var projectile_speed := 850.0
@export var projectile_gravity := 0.0
## 出弹点相对于船尺寸的比例。X 按船头方向取正值。
@export var muzzle_offset := Vector2(0.42, -0.02)

@export_group("接舷")
@export var approaches_for_boarding := false
@export var boarding_tonnage := 1.0
@export var boarding_power := 80.0
@export var boarding_power_variance := 10.0

@export_group("部位")
@export var damage_profile: ShipDamageProfile = preload("res://Data/Combat/enemy_parts.tres")
## 可用 [帆, 舰体, 火器与弓手, 舵, 撞角] 覆盖默认耐久，各型仍共用部位规则。
@export var part_hp := PackedFloat64Array()


func build_damage_profile() -> ShipDamageProfile:
	if part_hp.is_empty():
		return damage_profile
	var profile := damage_profile.duplicate() as ShipDamageProfile
	profile.max_hp = part_hp
	return profile
