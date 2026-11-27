class_name ShipCombat
extends Node2D

signal sunk
signal blast_pushed(distance: float)

enum Team { ALLY, ENEMY }

const HITBOX_NAMES := [&"hit_sail", &"hit_hull", &"hit_cannon"]
const SAIL_SHADER := preload("res://Scripts/ship_sail.gdshader")
const FLASH_TEXTURE := preload("res://Assets/Art/Effects/muzzle_flash.png")

var parts: ShipParts
var team := Team.ALLY
var lane_index := 0
var previous_lane := -1
var min_gap := 0.0
var targetable := true
var size: Vector2
var sprite_faces_left := false
var muzzle_offset := Vector2(0.54, -0.08)

var _hitboxes: Array[CollisionShape2D] = []
var _hitbox_centers: Array[Vector2] = []
var _hitbox_bounds: Rect2
var _heading := 0.0
var _recoil: Tween
var _hit_flash: Tween
var _muzzle_flash: Sprite2D
var _sail_material: ShaderMaterial
var _sail_overlay: Sprite2D
var _hull_overlay: Sprite2D
var _sail_torn_texture: Texture2D
var _sail_ruined_texture: Texture2D
var _base_tint := Color.WHITE

@onready var _sprite: Sprite2D = $Sprite2D


func configure(
	profile: ShipDamageProfile, ship_size: Vector2, heading: float,
	texture: Texture2D = null, tint: Color = Color.WHITE
) -> void:
	parts = ShipParts.new(profile)
	size = ship_size
	if texture != null:
		_sprite.texture = texture
	if _sprite.texture != null:
		_sprite.scale = ship_size / _sprite.texture.get_size()
	_base_tint = tint
	_sprite.modulate = tint

	# 由炮弹在物理步内扫掠这些碰撞箱，按沿弹道的先后顺序处理。
	var area := Area2D.new()
	area.name = "Hitboxes"
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	add_child(area)
	var boxes := [profile.sail_box, profile.hull_box, profile.cannon_box]
	for index in range(boxes.size()):
		var rect: Rect2 = boxes[index]
		var box := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size * size
		box.name = HITBOX_NAMES[index]
		box.shape = shape
		area.add_child(box)
		_hitboxes.append(box)
		_hitbox_centers.append(rect.get_center() * size)
	face(heading)

	_muzzle_flash = Sprite2D.new()
	_muzzle_flash.name = "MuzzleFlash"
	_muzzle_flash.texture = FLASH_TEXTURE
	_muzzle_flash.scale = Vector2.ONE * 0.55
	_muzzle_flash.hide()
	add_child(_muzzle_flash)


func configure_damage_art(torn: Texture2D, ruined: Texture2D, burned: Texture2D, sail_cutout: Rect2) -> void:
	if _sprite.texture == null:
		return
	_sail_torn_texture = torn
	_sail_ruined_texture = ruined
	if torn != null or ruined != null:
		_sail_overlay = Sprite2D.new()
		_sail_overlay.name = "SailOverlay"
		_sprite.add_child(_sail_overlay)
	if ruined != null and sail_cutout.has_area():
		var texture_size := _sprite.texture.get_size()
		_sail_material = ShaderMaterial.new()
		_sail_material.shader = SAIL_SHADER
		_sail_material.set_shader_parameter("sail_region", Vector4(
			sail_cutout.position.x / texture_size.x, sail_cutout.position.y / texture_size.y,
			sail_cutout.end.x / texture_size.x, sail_cutout.end.y / texture_size.y))
		_sprite.material = _sail_material
	if burned != null:
		_hull_overlay = Sprite2D.new()
		_hull_overlay.name = "HullOverlay"
		_hull_overlay.texture = burned
		_sprite.add_child(_hull_overlay)
	parts.part_changed.connect(_refresh_damage_art)
	_refresh_damage_art(ShipParts.Part.SAIL, parts.hp(ShipParts.Part.SAIL), parts.condition(ShipParts.Part.SAIL))
	_refresh_damage_art(ShipParts.Part.HULL, parts.hp(ShipParts.Part.HULL), parts.condition(ShipParts.Part.HULL))


func _refresh_damage_art(part: ShipParts.Part, _hp: float, condition: ShipParts.Condition) -> void:
	match part:
		ShipParts.Part.SAIL:
			var ruined := condition == ShipParts.Condition.DESTROYED
			if _sail_material != null:
				_sail_material.set_shader_parameter("sail_destroyed", ruined)
			if _sail_overlay != null:
				_sail_overlay.texture = _sail_ruined_texture if ruined else _sail_torn_texture
				_sail_overlay.visible = condition != ShipParts.Condition.NORMAL and _sail_overlay.texture != null
				_align_overlay(_sail_overlay, part)
		ShipParts.Part.HULL:
			if _hull_overlay != null:
				_hull_overlay.visible = condition != ShipParts.Condition.NORMAL
				_hull_overlay.self_modulate.a = 1.0 if condition == ShipParts.Condition.DESTROYED else 0.55
				_align_overlay(_hull_overlay, part)
		ShipParts.Part.CANNON:
			if team == Team.ENEMY:
				var tint := Color(0.62, 0.58, 0.55) if condition == ShipParts.Condition.DESTROYED else Color.WHITE
				_sprite.modulate = _base_tint * tint


func _align_overlay(overlay: Sprite2D, part: ShipParts.Part) -> void:
	if overlay == null or overlay.texture == null:
		return
	var box := _hitboxes[part]
	var box_size := (box.shape as RectangleShape2D).size
	overlay.position = box.position / _sprite.scale
	overlay.scale = box_size / _sprite.scale / overlay.texture.get_size()
	overlay.flip_h = _sprite.flip_h


func occupies_lane(index: int) -> bool:
	return targetable and (lane_index == index or previous_lane == index)


func hitbox(part: ShipParts.Part) -> Rect2:
	var box := _hitboxes[part]
	var box_size := (box.shape as RectangleShape2D).size
	return box.global_transform * Rect2(-box_size * 0.5, box_size)


func hitbox_bounds() -> Rect2:
	return global_transform * _hitbox_bounds


func aim_point() -> Vector2:
	return _hitboxes[ShipParts.Part.HULL].global_position


func receive_hit(part: ShipParts.Part, ammo: ShipParts.Ammo, damage: float) -> void:
	if not targetable or not parts.apply_hit(part, ammo, damage):
		return
	if _finish_if_sunk():
		return

	if _hit_flash != null:
		_hit_flash.kill()
	_sprite.self_modulate = Color(1.6, 1.3, 1.15)
	_hit_flash = create_tween()
	_hit_flash.tween_property(_sprite, "self_modulate", Color.WHITE, 0.15)


## 接舷直接扣指定部位，仍使用炮击共用的击沉通知。
func apply_raw_damage(part: ShipParts.Part, damage: float) -> void:
	if not targetable or parts.is_sunk() or damage <= 0.0:
		return
	parts.set_hp(part, parts.hp(part) - damage)
	_finish_if_sunk()


func _finish_if_sunk() -> bool:
	# 部位信号的同步监听也可能已经处理了致死伤害。
	if not targetable:
		return true
	if not parts.is_sunk():
		return false
	targetable = false
	sunk.emit()
	return true


func face(heading: float) -> void:
	if heading == _heading:
		return
	_heading = heading
	_sprite.flip_h = (heading < 0.0) != sprite_faces_left
	for index in range(_hitboxes.size()):
		var center := _hitbox_centers[index]
		var box := _hitboxes[index]
		box.position = Vector2(center.x * _heading, center.y)
		var box_size := (box.shape as RectangleShape2D).size
		var rect := Rect2(box.position - box_size * 0.5, box_size)
		_hitbox_bounds = rect if index == 0 else _hitbox_bounds.merge(rect)
	_align_overlay(_sail_overlay, ShipParts.Part.SAIL)
	_align_overlay(_hull_overlay, ShipParts.Part.HULL)


func muzzle_position(heading: float) -> Vector2:
	var offset := size * muzzle_offset * Vector2(heading, 1.0)
	return to_global(_sprite.position + offset.rotated(_sprite.rotation))


func recoil(heading: float, origin: Vector2) -> void:
	if _recoil != null:
		_recoil.kill()
	_sprite.position = Vector2(-heading * 9.0, 3.0)
	_sprite.rotation = -heading * 0.06
	_muzzle_flash.global_position = origin
	_muzzle_flash.show()
	_recoil = create_tween().set_parallel()
	_recoil.tween_property(_sprite, "position", Vector2.ZERO, 0.20)
	_recoil.tween_property(_sprite, "rotation", 0.0, 0.20)
	_recoil.tween_callback(_muzzle_flash.hide).set_delay(0.08)


func play_sinking() -> Tween:
	if _recoil != null:
		_recoil.kill()
	_muzzle_flash.hide()
	var sink := create_tween().set_parallel()
	sink.tween_property(_sprite, "position:y", _sprite.position.y + 22.0, 0.50)
	sink.tween_property(_sprite, "rotation", _heading * 0.24, 0.50)
	sink.tween_property(_sprite, "modulate:a", 0.0, 0.50)
	return sink


func reset_sinking_pose() -> void:
	_sprite.position = Vector2.ZERO
	_sprite.rotation = 0.0
	_sprite.modulate = _base_tint
