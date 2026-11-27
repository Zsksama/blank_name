extends SceneTree

const BATTLE := preload("res://Scenes/battle.tscn")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var battle = _battle()
	_check(battle.has_node("Boarding"), "The main battle installs the boarding controller")
	if battle.has_node("Boarding"):
		_test_hull_contact()
		await _test_contact_and_escape(battle)
		await _test_active_and_passive_approach()
		await _test_input_when_boarding_ends()
		await _test_impact_and_morale()
		_test_morale_retreat()
		await _test_victory_and_respawns()
		await _test_camera_and_cooldown()
		await _test_last_enemy()
	battle.free()
	print("Boarding checks: %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _test_hull_contact() -> void:
	var battle = _battle()
	var player := battle.get_node("PlayerShip") as PlayerShip
	var separated: EnemyShip = battle.spawn_enemy(player.lane_index, null, player.position.x + 160.0)
	separated.position.x += player.combat.hitbox(ShipParts.Part.HULL).end.x \
		- separated.combat.hitbox(ShipParts.Part.HULL).position.x + 1.0
	battle._check_boarding(0.0)
	_check(not battle.get_node("Boarding").active, "A one-pixel gap between same-lane hulls cannot start boarding")
	battle.free()


func _test_contact_and_escape(battle: Node) -> void:
	var player := battle.get_node("PlayerShip") as PlayerShip
	var weapon := player.get_node("Combat/Weapon") as PlayerWeapon
	var boarding = battle.get_node("Boarding")
	boarding.log_boarding = true
	var enemy: EnemyShip = battle.spawn_enemy(player.lane_index - 1, null, player.position.x)
	var contacts: Array[EnemyShip] = []
	var results: Array[int] = []
	battle.boarding_contact_started.connect(func(ship: EnemyShip): contacts.append(ship))
	battle.boarding_finished.connect(func(result: int): results.append(result))
	battle._check_boarding(0.0)
	_check(contacts.is_empty(), "Horizontal alignment across lanes cannot start boarding")
	var player_ram := player.combat.parts.hp(ShipParts.Part.RAM)
	var enemy_ram := enemy.combat.parts.hp(ShipParts.Part.RAM)
	player.try_change_lane(enemy.lane_index)
	for frame in range(65):
		await physics_frame
		if not player.is_switching():
			break
		battle._check_boarding(0.0)
	_check(contacts.is_empty() and not player.is_switching(), "Boarding waits until the switch has completed")
	battle._check_boarding(0.0)
	battle._check_boarding(0.0)
	_check(contacts == [enemy] and is_equal_approx(Engine.time_scale, 0.03), "Landing on the enemy begins one slowed fight")
	_check(player.combat.parts.hp(ShipParts.Part.HULL) == 95.0 and enemy.combat.parts.hp(ShipParts.Part.HULL) == 35.0
		and player.combat.parts.hp(ShipParts.Part.RAM) == player_ram and enemy.combat.parts.hp(ShipParts.Part.RAM) == enemy_ram,
		"A lane scrape takes five hull HP from each ship without wearing the rams")
	_check(not weapon.can_fire() and not player.try_change_lane(0), "The player cannot shoot or switch lanes during boarding")
	var player_bar := boarding.get_node("Interface/Overlay/PlayerHull") as ProgressBar
	var enemy_bar := boarding.get_node("Interface/Overlay/EnemyHull") as ProgressBar
	_check(player_bar.is_visible_in_tree() and player_bar.value == 95.0 and enemy_bar.value == 35.0
		and not battle.get_node("Crosshair").visible and battle.get_node("HUD/Morale").visible,
		"Both hull bars and morale are visible while normal aiming UI is hidden")
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, true, true)
	_check(is_equal_approx(boarding.qte_multiplier, 1.01), "A held Space key counts once and auto-repeat does not count")
	_key(KEY_SPACE, false)
	await create_timer(0.34, true, false, true).timeout
	_check(is_equal_approx(boarding.qte_multiplier, 1.0), "The QTE multiplier decays in real time")
	var start_x := player.position.x
	_key(KEY_T, true)
	await create_timer(0.82, true, false, true).timeout
	_check(results.is_empty(), "Holding T for less than a second does not escape")
	var ram_before_escape := player.combat.parts.hp(ShipParts.Part.RAM)
	await create_timer(0.25, true, false, true).timeout
	_key(KEY_T, false)
	_check(results == [1] and is_equal_approx(player.position.x, start_x - 200.0)
		and is_equal_approx(player.combat.parts.hp(ShipParts.Part.RAM), ram_before_escape * 0.85),
		"Holding T for one second escapes, moves 200 px and takes 15 percent of the remaining part HP")
	_check(not player.controls_locked and not player_bar.is_visible_in_tree() and battle.get_node("Crosshair").visible
		and is_equal_approx(Engine.time_scale, 1.0), "Escape restores controls, HUD and the time scale")
	var enemy_x := enemy.position.x
	enemy.step(0.25, player.combat, 60.0, true)
	_check(enemy.position.x == enemy_x, "The surviving enemy is briefly stunned after escape")
	player.position.x = enemy.position.x
	battle._check_boarding(0.0)
	_check(contacts.size() == 1, "Recontact with the same ship is blocked during cooldown")
	var next_enemy: EnemyShip = battle.spawn_enemy(player.lane_index, null, player.position.x + 15.0)
	battle._check_boarding(0.0)
	_check(contacts == [enemy, next_enemy], "A different eligible ship is independent of the first pair's cooldown")
	battle._freeze_combat()
	_check(results == [1] and player.controls_locked and is_equal_approx(Engine.time_scale, 1.0),
		"Battle termination cancels boarding without an escape outcome or unlocked combat controls")


func _test_active_and_passive_approach() -> void:
	var battle = _battle()
	var player := battle.get_node("PlayerShip") as PlayerShip
	var boarding = battle.get_node("Boarding")
	var normal: EnemyShip = battle.spawn_enemy(player.lane_index, null, player.position.x + 116.0)
	normal.combat.parts.set_hp(ShipParts.Part.CANNON, 0.0)
	var start_x := normal.position.x
	normal.step(1.0, player.combat, 60.0, true)
	_check(normal.position.x == start_x, "An ordinary ranged ship retains its player stop behavior")
	Input.action_press("move_right")
	battle.set_physics_process(true)
	var active_deadline := Time.get_ticks_msec() + 2000
	while not boarding.active and Time.get_ticks_msec() < active_deadline:
		await physics_frame
	Input.action_release("move_right")
	_check(boarding.active and player.combat.parts.hp(ShipParts.Part.RAM) == 32.0,
		"Steering the actual player into contact reaches the frontal ram path at current ship speeds")
	battle.free()
	_check(is_equal_approx(Engine.time_scale, 1.0), "Exiting an active battle restores the time scale")

	battle = _battle()
	player = battle.get_node("PlayerShip") as PlayerShip
	boarding = battle.get_node("Boarding")
	var fast_config := load("res://Data/Combat/enemy_fast.tres") as EnemyShipConfig
	var fast: EnemyShip = battle.spawn_enemy(player.lane_index, fast_config, player.position.x + 110.0)
	var fast_start := fast.position.x
	battle.set_physics_process(true)
	var deadline := Time.get_ticks_msec() + 5000
	while not boarding.active and Time.get_ticks_msec() < deadline:
		await physics_frame
	_check(boarding.active and fast.position.x < fast_start - 7.0 and player.position.x == 500.0,
		"A fast ship can create contact while the player is stationary")
	var follower: EnemyShip = battle.spawn_enemy(player.lane_index, fast_config, fast.position.x + fast.config.min_gap)
	follower.step(3.0, player.combat, 60.0, true)
	_check(follower.position.x >= fast.position.x + fast.config.min_gap - 0.01,
		"A following fast ship leaves space behind a ship that has boarded the player")
	battle.free()


func _test_input_when_boarding_ends() -> void:
	var battle = _battle()
	var player := battle.get_node("PlayerShip") as PlayerShip
	var weapon := player.get_node("Combat/Weapon") as PlayerWeapon
	var boarding = battle.get_node("Boarding")
	battle.spawn_enemy(player.lane_index, null, player.position.x)
	battle._check_boarding(0.0)
	var ammo_before := weapon.ammo[0]
	await physics_frame
	Input.action_press("move_down")
	Input.action_press("fire")
	boarding.cancel()
	await physics_frame
	await physics_frame
	_check(not player.is_switching() and weapon.ammo[0] == ammo_before,
		"A movement or fire press from the exit frame cannot carry over from boarding")
	Input.action_press("fire")
	await physics_frame
	await physics_frame
	Input.action_release("fire")
	_check(weapon.ammo[0] == ammo_before - 1, "A fresh press after boarding can fire immediately")
	battle.free()


func _test_impact_and_morale() -> void:
	var battle = _battle()
	var player := battle.get_node("PlayerShip") as PlayerShip
	var boarding = battle.get_node("Boarding")
	var config := (load("res://Data/Combat/enemy_e01.tres") as EnemyShipConfig).duplicate() as EnemyShipConfig
	config.set("boarding_power_variance", 0.0)
	var enemy: EnemyShip = battle.spawn_enemy(player.lane_index, config, player.position.x)
	enemy.combat.parts.set_hp(ShipParts.Part.RAM, 0.0)
	enemy.combat.parts.set_hp(ShipParts.Part.HULL, 40.0, 100.0)
	boarding.try_engage(enemy, 25.0, false)
	_check(is_equal_approx(player.combat.parts.hp(ShipParts.Part.HULL), 98.5)
		and is_equal_approx(enemy.combat.parts.hp(ShipParts.Part.HULL), 35.0),
		"Frontal damage is mitigated by the defender's own ram and snapshots both sides before wear")
	var lamps := [34, 35, 70, 70]
	var biases := [-0.10, -0.50, -0.80, -0.95]
	var expected_enemy_damage := [5.4, 6.0, 6.6, 6.6]
	var expected_player_damage := [5.76, 4.32, 3.60, 6.24]
	for index in range(lamps.size()):
		battle.lamp_value = lamps[index]
		battle.morale_bias = biases[index]
		var player_before := player.combat.parts.hp(ShipParts.Part.HULL)
		var enemy_before := enemy.combat.parts.hp(ShipParts.Part.HULL)
		boarding._exchange()
		_check(is_equal_approx(player_before - player.combat.parts.hp(ShipParts.Part.HULL), expected_player_damage[index])
			and is_equal_approx(enemy_before - enemy.combat.parts.hp(ShipParts.Part.HULL), expected_enemy_damage[index]),
			"Boarding exchange reads real lamp and morale tiers, sample %d" % index)
	battle.free()


func _test_morale_retreat() -> void:
	var battle = _battle()
	var player := battle.get_node("PlayerShip") as PlayerShip
	var enemy: EnemyShip = battle.spawn_enemy(player.lane_index + 1, null, 900.0)
	battle.morale_bias = -0.89
	battle._physics_process(0.1)
	_check(enemy.action != EnemyShip.Action.FLEE, "A ship holds its normal behavior above ten percent morale")
	battle.morale_bias = -0.91
	battle._physics_process(0.1)
	_check(enemy.action == EnemyShip.Action.FLEE and battle.enemies_defeated == 0,
		"Morale below ten percent starts the ship's own retreat without counting a defeat yet")
	enemy.position.x = 1345.0
	battle._physics_process(0.1)
	_check(battle.enemies_defeated == 1 and battle.kills == 0 and not battle.is_over,
		"A retreat counts only after exit and keeps the queued roster in the victory check")
	battle.free()


func _test_victory_and_respawns() -> void:
	var battle = _battle()
	var player := battle.get_node("PlayerShip") as PlayerShip
	battle.get_node("Boarding").log_boarding = true
	var results: Array[int] = []
	battle.boarding_finished.connect(func(result: int): results.append(result))
	var enemy: EnemyShip = battle.spawn_enemy(player.lane_index, null, player.position.x)
	battle._check_boarding(0.0)
	enemy.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 1000.0)
	await create_timer(0.05, true, false, true).timeout
	_check(results == [0] and battle.kills == 1 and battle.enemies_defeated == 1 and is_equal_approx(battle.morale_bias, -0.25),
		"Boarding victory via the existing projectile path records one sink and one morale penalty")
	var immediate: float = battle.enemy_morale
	battle._advance_morale(2.0)
	_check(immediate > battle.enemy_morale and is_equal_approx(battle.enemy_morale,
		float(battle.enemy_total - 1) / float(battle.enemy_total) - 0.25),
		"The ship's morale penalty completes over two seconds on top of the boarding penalty")
	battle.gate_launch_time = 0.2
	for index in range(3):
		Engine.time_scale = 0.5 if index == 0 else 1.0
		player.position.x = 500.0
		var foe: EnemyShip = battle.spawn_enemy(player.lane_index, null, player.position.x)
		player.combat.parts.set_hp(ShipParts.Part.HULL, 1.0)
		battle._check_boarding(0.0)
		battle.get_node("Boarding").call("_exchange")
		_check(not player.combat.targetable and results.size() == index + 2 and results.back() == 2,
			"Boarding loss %d runs the shared sinking flow" % (index + 1))
		await create_timer(0.085, true, false, true).timeout
		_check(not player.combat.targetable and player.position.x < 60.0,
			"Relaunch %d starts behind the water gate" % (index + 1))
		await create_timer(0.46 if index == 0 else 0.24, true, false, true).timeout
		_check(player.combat.targetable and not player.controls_locked and player.lane_index == battle.water_gate_lane
			and absf(player.position.x - 124.25) < 1.0 and player.combat.parts.hp(ShipParts.Part.HULL) == 100.0,
			"The water gate relaunches the ship after loss %d" % (index + 1))
		foe.free()
	_check(battle.lamp_value == 30 and is_equal_approx(battle.morale_bias, -0.25),
		"Three losses charge lamp value once each without changing boarding morale bias")
	battle.free()


func _test_camera_and_cooldown() -> void:
	var battle = _battle()
	var player := battle.get_node("PlayerShip") as PlayerShip
	var boarding = battle.get_node("Boarding")
	var enemy: EnemyShip = battle.spawn_enemy(player.lane_index, null, 124.25)
	player.position.x = 124.25
	Engine.time_scale = 0.8
	battle._check_boarding(0.0)
	await create_timer(0.40, true, false, true).timeout
	_check(boarding.active and _camera_in_map(battle), "The boarding camera stays inside the map at the left edge")
	boarding._exchange()
	await process_frame
	await process_frame
	_check(_camera_in_map(battle), "Damage feedback shakes within the same camera clamp")
	_key(KEY_T, true)
	await create_timer(1.1, true, false, true).timeout
	_key(KEY_T, false)
	_check(not boarding.active and player.position.x > 98.0 and player.position.x < 99.0
		and is_equal_approx(Engine.time_scale, 0.8), "Escape stops at the sea wall and restores the previous time scale")
	await create_timer(0.4, true, false, true).timeout
	_check(root.get_camera_2d() == null, "The normal world camera returns after the effect ends")
	battle._check_boarding(0.0)
	_check(not boarding.active, "A sea wall escape cannot immediately start another fight with the same enemy")
	await create_timer(2.65, true, false, true).timeout
	player.position.x = 1200.0
	enemy.position.x = 1200.0
	battle._check_boarding(0.0)
	await create_timer(0.40, true, false, true).timeout
	_check(boarding.active and _camera_in_map(battle),
		"A continuously touching pair can board after cooldown, with the camera clamped at the opposite edge")
	battle.free()
	_check(is_equal_approx(Engine.time_scale, 0.8), "Leaving during a second fight restores the original non-default scale")
	Engine.time_scale = 1.0


func _camera_in_map(battle: Node) -> bool:
	var camera := root.get_camera_2d()
	if camera == null or camera.zoom.x < 2.0:
		return false
	var background := battle.get_node("Background") as Sprite2D
	var bounds := background.global_transform * background.get_rect()
	var view_size := root.get_visible_rect().size / camera.zoom
	var visible := Rect2(camera.get_screen_center_position() - view_size * 0.5, view_size)
	return bounds.grow(0.1).encloses(visible)


func _test_last_enemy() -> void:
	var level := EnemySpawnLevel.new()
	level.must_spawn[EnemyShipConfig.Type.NORMAL] = 1
	var battle = _battle(level)
	var player := battle.get_node("PlayerShip") as PlayerShip
	var boarding = battle.get_node("Boarding")
	var sequence: Array[String] = []
	battle.boarding_finished.connect(func(result: int):
		if result == 0 and is_equal_approx(battle.morale_bias, -0.25):
			sequence.append("boarding")
	)
	battle.on_battle_finished.connect(func(won: bool, _by_breach: bool):
		if won:
			sequence.append("battle")
	)
	battle._update_spawn(10000.0)
	battle._update_spawn(0.7)
	var enemy := battle.get_node("Enemies").get_child(0) as EnemyShip
	enemy.lane_index = player.lane_index
	enemy.position.x = player.position.x
	battle._check_boarding(0.0)
	var start := Time.get_ticks_msec()
	while sequence.size() < 2 and Time.get_ticks_msec() - start < 10400:
		await process_frame
	var seconds := (Time.get_ticks_msec() - start) / 1000.0
	_check(seconds >= 6.0 and seconds <= 10.4, "A normal ship takes roughly six to ten real seconds to board")
	_check(sequence == ["boarding", "battle"] and battle.kills == 1 and not boarding.active,
		"The last boarding defeat finishes boarding and credits morale before settling battle once")
	print("Normal ship boarding duration: %.2f s" % seconds)
	battle.free()


func _battle(level: EnemySpawnLevel = null):
	var battle := BATTLE.instantiate()
	battle.gate_launch_time = 0.0
	battle.player_respawn_delay = 0.05
	battle.turret_lanes.clear()
	battle.spawn_seed = 155827
	battle.spawn_interval_range = Vector2(9999.0, 9999.0)
	if level != null:
		battle.spawn_levels.assign([level])
	root.add_child(battle)
	battle.set_physics_process(false)
	battle.get_node("PlayerShip").position.x = 500.0
	return battle


func _key(code: Key, pressed: bool, repeated: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = repeated
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", message)
