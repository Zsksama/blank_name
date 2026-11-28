extends Node2D

const DUST_COUNT := 30
const IMPACT_BEAT := 0.20
const SHAKE_TIME := 0.10
const OUR_CRIES := ["杀！", "杀贼！", "杀！", "毋恐！"]
const THEIR_CRIES := ["杀！", "呃啊！", "哦哦！"]
const OUR_COLOR := Color(1.0, 0.90, 0.59)
const THEIR_COLOR := Color(1.0, 0.65, 0.51)

class Chip:
	var point: Vector2
	var velocity: Vector2
	var life := 0.0
	var duration: float
	var color: Color


var _ships: Array[ShipCombat] = []
var _contact := Vector2.ZERO
var _player_direction := 1.0
var _clock := 0.0
var _thrust := 0.0
var _shake_left := 0.0
var _dust_left := 0.0
var _cry_left := 0.0
var _cry_index := 0
var _chips: Array[Chip] = []
var _chip_cursor := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 56
	for index in range(DUST_COUNT):
		_chips.append(Chip.new())
	hide()


func begin(player: ShipCombat, enemy: ShipCombat) -> void:
	_ships.assign([player, enemy])
	_clock = 0.0
	_thrust = 0.0
	_shake_left = 0.0
	_dust_left = 0.05
	_cry_left = 0.28
	_cry_index = 0
	var a := player.hitbox(ShipParts.Part.HULL)
	var b := enemy.hitbox(ShipParts.Part.HULL)
	_player_direction = 1.0 if a.get_center().x <= b.get_center().x else -1.0
	var x := (a.end.x + b.position.x) * 0.5 if _player_direction > 0.0 else (a.position.x + b.end.x) * 0.5
	_contact = to_local(Vector2(x, lerpf(a.position.y, b.position.y, 0.5) - 2.0))
	_scatter(9)
	show()
	queue_redraw()


func end() -> void:
	for ship in _ships:
		if is_instance_valid(ship):
			ship.set_boarding_pose(Vector2.ZERO, 1.0)
	_ships.clear()
	for chip in _chips:
		chip.life = 0.0
	for label in get_children():
		label.hide()
		label.queue_free()
	_shake_left = 0.0
	hide()


func on_qte() -> void:
	_thrust = 0.16
	_cry_left = minf(_cry_left, 0.84)


func on_exchange(player_damage: float, enemy_damage: float) -> void:
	_shake_left = SHAKE_TIME
	_scatter(6)
	if _vigor(_ships[0]) > 0.46 or _rng.randf() > 0.52:
		DamageFloat.spawn(self, _ships[0].aim_point(), player_damage, THEIR_COLOR)
	if _vigor(_ships[1]) > 0.46 or _rng.randf() > 0.52:
		DamageFloat.spawn(self, _ships[1].aim_point(), enemy_damage, OUR_COLOR)


func camera_shake() -> Vector2:
	var falloff := _shake_left / SHAKE_TIME
	return Vector2(sin(_clock * 137.0) * 2.0, cos(_clock * 108.0) * 1.15) * falloff


func advance(delta: float) -> void:
	_clock += delta
	_thrust = maxf(0.0, _thrust - delta)
	_shake_left = maxf(0.0, _shake_left - delta)
	var motion_time := maxf(0.0, _clock - IMPACT_BEAT)
	var effort := sin(motion_time * TAU / 1.5)
	var entry := 1.0 - smoothstep(0.0, IMPACT_BEAT, _clock)
	for side in range(_ships.size()):
		var ship := _ships[side]
		var direction := _player_direction * (1.0 if side == 0 else -1.0)
		var vigor := _vigor(ship)
		var tremor := Vector2(_rng.randf_range(-1.8, 1.8), _rng.randf_range(-1.5, 1.5)) * vigor * (1.0 - entry)
		var tap := 1.9 * sin(PI * _thrust / 0.16) if side == 0 else 0.0
		var push := 5.6 * effort * vigor + tap + 1.4 * entry
		var squeeze := maxf(entry * 0.05, maxf(0.0, effort) * 0.045 * vigor)
		ship.set_boarding_pose(tremor + Vector2(direction * push, 0.0), 1.0 - squeeze)
	_dust_left -= delta
	if _dust_left <= 0.0:
		_dust_left = _rng.randf_range(0.08, 0.16)
		_scatter(2)
	for chip in _chips:
		if chip.life <= 0.0:
			continue
		chip.life -= delta
		chip.velocity.y += 142.0 * delta
		chip.point += chip.velocity * delta
	_cry_left -= delta
	if _cry_left <= 0.0:
		_cry_left = _rng.randf_range(0.8, 1.2)
		_shout()
	queue_redraw()


func _vigor(ship: ShipCombat) -> float:
	var parts := ship.parts
	var hp := parts.hp(ShipParts.Part.HULL) / maxf(parts.max_hp(ShipParts.Part.HULL), 1.0)
	return lerpf(0.26, 1.0, smoothstep(0.0, 0.42, hp))


func _shout() -> void:
	var ours := _cry_index % 2 == 0
	var opening := _cry_index == 0
	_cry_index += 1
	var speaker := _ships[0 if ours else 1]
	if _vigor(speaker) < 0.46 and _rng.randf() < 0.55:
		return
	var message: String
	if ours:
		message = "愿杀贼！" if opening else OUR_CRIES[_rng.randi_range(0, OUR_CRIES.size() - 1)]
	else:
		message = THEIR_CRIES[_rng.randi_range(0, THEIR_CRIES.size() - 1)]
	var point := to_global(_contact + Vector2(-20.0 if ours else 20.0, -37.0))
	DamageFloat.caption(self, point, message, OUR_COLOR if ours else THEIR_COLOR, 17)


func _scatter(count: int) -> void:
	for index in range(count):
		var chip := _chips[_chip_cursor]
		_chip_cursor = (_chip_cursor + 1) % DUST_COUNT
		chip.point = _contact + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-2.5, 2.5))
		chip.velocity = Vector2(_rng.randf_range(-35.0, 35.0), _rng.randf_range(-49.0, -14.0))
		chip.duration = _rng.randf_range(0.20, 0.40)
		chip.life = chip.duration
		chip.color = Color(1.0, 0.88, 0.49) if index % 3 == 0 else Color(0.77, 0.44, 0.22)


func _draw() -> void:
	for index in range(_ships.size()):
		var ship := _ships[index]
		if is_instance_valid(ship):
			_draw_boarders(ship, _player_direction * (1.0 if index == 0 else -1.0))
	for chip in _chips:
		if chip.life > 0.0:
			draw_line(chip.point, chip.point - chip.velocity * 0.045,
				Color(chip.color, chip.life / chip.duration), 1.45, true)


func _draw_boarders(ship: ShipCombat, direction: float) -> void:
	var deck := to_local(ship.visible_part_position(ShipParts.Part.HULL))
	var bow := deck.x + direction * ship.size.x * 0.31
	var ink := Color(0.13, 0.12, 0.11)
	var frame := floori(_clock * 8.0) % 2
	for index in range(2):
		var foot := Vector2(bow - direction * index * 8.0, deck.y - ship.size.y * 0.145)
		var lean := direction * (1.5 if (frame + index) % 2 == 0 else 0.0)
		var head := foot + Vector2(lean, -7.5)
		var arm := head + Vector2(direction * 4.8, -2.5 if lean == 0.0 else 3.8)
		draw_line(foot - Vector2(2.0, 0.0), head, ink, 1.8, true)
		draw_line(foot + Vector2(1.3, 0.0), head, ink, 1.8, true)
		draw_circle(head, 1.55, ink)
		draw_line(head + Vector2(0.0, 2.5), arm, OUR_COLOR.darkened(0.48), 1.15, true)
