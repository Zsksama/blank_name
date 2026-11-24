class_name ShipParts
extends RefCounted

signal part_changed(part: Part, hp: float, condition: Condition)

enum Part { SAIL, HULL, CANNON, RUDDER, RAM }
enum Condition { NORMAL, DAMAGED, DESTROYED }
enum Ammo { SOLID, ANTI_SAIL, EXPLOSIVE }

const DAMAGE_THRESHOLD := 0.75
const DESTROYED_THRESHOLD := 0.10
const SPEED_MULTIPLIERS := [1.0, 0.7, 0.4]
const LANE_SWITCH_MULTIPLIERS := [1.0, 1.4, INF]
const RAM_DAMAGE_MULTIPLIERS := [1.0, 0.5, 0.0]

var rng := RandomNumberGenerator.new()

var _profile: ShipDamageProfile
var _hp: PackedFloat64Array


func _init(profile: ShipDamageProfile) -> void:
	_profile = profile
	_hp = profile.max_hp.duplicate()


func hp(part: Part) -> float:
	return _hp[part]


func max_hp(part: Part) -> float:
	return _profile.max_hp[part]


func repair_toward(part: Part, amount: float, cap: float) -> void:
	if amount <= 0.0 or _hp[part] >= cap:
		return
	_hp[part] = minf(cap, _hp[part] + amount)
	part_changed.emit(part, _hp[part], condition(part))


func condition(part: Part) -> Condition:
	var ratio := _hp[part] / maxf(_profile.max_hp[part], 0.001)
	if ratio <= DESTROYED_THRESHOLD:
		return Condition.DESTROYED
	if ratio <= DAMAGE_THRESHOLD:
		return Condition.DAMAGED
	return Condition.NORMAL


func is_sunk() -> bool:
	return _hp[Part.HULL] <= 0.0


func speed_multiplier() -> float:
	return SPEED_MULTIPLIERS[condition(Part.SAIL)]


func can_fire() -> bool:
	return condition(Part.CANNON) != Condition.DESTROYED


func reload_multiplier() -> float:
	return 1.0 if condition(Part.CANNON) == Condition.NORMAL else 1.3


func advance_reload(remaining: float, delta: float) -> float:
	return maxf(0.0, remaining - delta / reload_multiplier())


func lane_switch_multiplier() -> float:
	return LANE_SWITCH_MULTIPLIERS[condition(Part.RUDDER)]


func ram_damage_multiplier() -> float:
	return RAM_DAMAGE_MULTIPLIERS[condition(Part.RAM)]


func apply_hit(part: Part, ammo: Ammo, damage: float) -> bool:
	if is_sunk() or damage <= 0.0:
		return false

	var previous_hp := _hp.duplicate()
	match part:
		Part.SAIL:
			_damage(part, damage * _profile.sail_multipliers[ammo])
		Part.HULL:
			var impact := damage * _profile.hull_multipliers[ammo]
			_damage(part, impact)
			_conduct_damage(impact, _profile.hull_conduction_chance, _profile.hull_conduction_scale)
		Part.CANNON:
			var impact := damage * _profile.cannon_multipliers[ammo]
			_damage(part, impact)
			_damage(Part.HULL, impact * _profile.cannon_hull_damage_scale)
			_conduct_damage(impact, _profile.cannon_conduction_chance, _profile.cannon_conduction_scale)
		_:
			return false

	var changed := false
	for index in range(_hp.size()):
		if _hp[index] != previous_hp[index]:
			changed = true
			var changed_part := index as Part
			part_changed.emit(changed_part, _hp[index], condition(changed_part))
	return changed


func _damage(part: Part, damage: float) -> void:
	_hp[part] = maxf(0.0, _hp[part] - maxf(0.0, damage))


func _conduct_damage(impact: float, chance: Vector2, scale: Vector2) -> void:
	if rng.randf() < chance.x:
		_damage(Part.RUDDER, impact * scale.x)
	if rng.randf() < chance.y:
		_damage(Part.RAM, impact * scale.y)
