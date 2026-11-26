class_name EnemyShipConfig
extends Resource

@export_group("身份")
@export var id: StringName
@export var display_name: String
@export var sprite: Texture2D
@export var size := Vector2(120.0, 56.0)
@export var tint := Color.WHITE
@export var sprite_faces_left := false
## 船底相对于贴图中心的纵向比例。
@export var art_keel_ratio: float = 0.5
@export var sail_cutout := Rect2()
@export var sail_torn_texture: Texture2D
@export var sail_ruined_texture: Texture2D
@export var hull_burn_texture: Texture2D

@export_group("航行")
@export var speed := 18.0
@export var speed_variance := 6.0
@export var attack_maneuver_distance := 24.0
@export var stop_distance := 320.0
@export var min_gap := 144.0
@export var can_change_lane := false
@export var lane_change_margin := 180.0

@export_group("攻击")
@export var attack_range := 400.0
@export var attack_damage := 8.0
@export var attack_interval := 3.0
@export var target_switch_delay := 0.3
@export var projectile_speed := 850.0
## 炮口相对于船尺寸的比例。X 按船头方向取正值。
@export var muzzle_offset := Vector2(0.54, -0.08)

@export_group("部位")
@export var damage_profile: ShipDamageProfile
