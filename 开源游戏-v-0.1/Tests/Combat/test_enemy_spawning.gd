extends SceneTree

const BATTLE := preload("res://Scenes/battle.tscn")
const MANAGEMENT_SESSION := preload("res://Scripts/Management/management_session.gd")
const SEED := 155827

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_level_rosters()
	_test_enemy_types()
	_test_retreat_speed()
	_test_fast_ship_sway()
	_test_fortress_hit_rate()
	_test_opening_wave()
	await _test_boarding_contact()
	_test_capacity()
	_test_formations()
	_test_required_snake_ends()
	_test_snake_limits()
	_test_snake_spacing()
	_test_butterfly_alert()
	await _test_victory_after_retreat()
	print("Enemy spawning checks: %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _test_level_rosters() -> void:
	var spawner := _spawner(EnemySpawner.LEVELS[1], SEED)
	var first_plan := spawner.purchased.duplicate()
	var cost := 0
	for config in first_plan:
		cost += config.cost
	_check(spawner.required.size() == 2 and spawner.required.all(
		func(config): return config.enemy_type == EnemyShipConfig.Type.NORMAL),
		"Level two includes two free normal ships")
	_check(cost >= 43 and cost <= 45 and spawner.enemy_total == first_plan.size() + 2,
		"The purchased roster independently spends the 45-point budget until less than three remains")
	spawner.begin(EnemySpawner.LEVELS[1], "easy", SEED, Vector2(6, 6), "")
	_check(spawner.purchased == first_plan, "The same seed reproduces the ordered roster")
	spawner.begin(EnemySpawner.LEVELS[0], "normal", SEED, Vector2(6, 6), "")
	_check(spawner.enemy_total == 15, "The normal multiplier applies to budget before purchasing")
	spawner.begin(EnemySpawner.LEVELS[0], "hard", SEED, Vector2(6, 6), "")
	_check(spawner.enemy_total == 20, "The hard multiplier applies to budget before purchasing")
	var level_five := EnemySpawner.LEVELS[4]
	_check(level_five.time_of_day == "night" and level_five.weather == "storm"
		and level_five.wave_amplitude_scale() > 1.0, "The fifth level exports storm metadata and wave amplitude")
	spawner.free()


func _test_enemy_types() -> void:
	var battle = _battle()
	var expected := [
		[40.0, 30.0, 15.0, 10.0, 20.0, 22.0, 3, 200.0, 4.0, Projectile.Visual.ARROW],
		[30.0, 40.0, 20.0, 10.0, 20.0, 16.0, 5, 200.0, 4.0, Projectile.Visual.ARROW],
		[50.0, 80.0, 30.0, 10.0, 30.0, 10.0, 8, 300.0, 10.0, Projectile.Visual.MATCHLOCK],
	]
	var colors: Array[Color] = []
	var player := battle.get_node("PlayerShip") as PlayerShip
	var projectiles := battle.get_node("Projectiles") as Node2D
	var texture := EnemySpawner.TYPES[EnemyShipConfig.Type.NORMAL].sprite
	for type in EnemyShipConfig.Type.values():
		var ship: EnemyShip = battle.spawn_enemy(0, EnemySpawner.TYPES[type])
		var stats: Array = expected[type]
		ship.position.x = 60.0 + stats[7]
		for part in ShipParts.Part.values():
			_check(ship.combat.parts.max_hp(part) == stats[part], "%s has the specified part HP" % ship.config.display_name)
		_check(ship.config.cost == stats[6] and ship._speed() == stats[5] and ship.config.attack_range == stats[7],
			"%s has the specified cost, speed and range" % ship.config.display_name)
		_check(ship.config.sprite == texture, "All types use the same ship texture")
		colors.append(ship.config.tint)
		var deck := ship.combat.hitbox(ShipParts.Part.CANNON)
		var hull := ship.combat.hitbox(ShipParts.Part.HULL)
		var marker := ship.get_node("Combat/Visual/WeaponDeck") as Node2D
		_check(deck.end.y <= hull.position.y and deck.get_center().x < ship.global_position.x
			and marker.global_position.is_equal_approx(deck.get_center()),
			"The visible weapons deck and HP bar follow the protruding hitbox")
		ship.step(0.01, player.combat, 60.0, true)
		ship.step(0.31, player.combat, 60.0, true)
		var shot := projectiles.get_child(-1) as Projectile
		_check(shot != null and shot.visual == stats[9] and shot.damage == stats[8] and ship._reload == 3.0,
			"%s fires the configured shot at its maximum range" % ship.config.display_name)
		if shot != null:
			var sprite := shot.get_node("Sprite2D") as Sprite2D
			var is_arrow: bool = stats[9] == Projectile.Visual.ARROW
			_check(not sprite.visible if is_arrow else sprite.visible and sprite.scale.x < 0.31,
				"Arrows use drawn strokes and matchlocks use smaller cannonball art")
	_check(colors[0].g > colors[0].r and colors[1].r > colors[1].b and colors[1].g > colors[1].b
		and colors[2].r > colors[2].g, "The three shared sprites have green, yellow, and red tints")
	battle.free()


func _test_retreat_speed() -> void:
	var battle = _battle()
	var player := battle.get_node("PlayerShip") as PlayerShip
	for config: EnemyShipConfig in EnemySpawner.TYPES.values():
		var ship: EnemyShip = battle.spawn_enemy(0, config, 850.0)
		ship.combat.parts.set_hp(ShipParts.Part.SAIL, ship.combat.parts.max_hp(ShipParts.Part.SAIL) * 0.5)
		ship.step(0.5, player.combat, 60.0, true)
		var advance := 850.0 - ship.position.x
		var turn_x := ship.position.x
		ship.step(0.5, player.combat, 60.0, true, 0.09)
		var retreat := ship.position.x - turn_x
		_check(ship.action == EnemyShip.Action.FLEE and advance > 0.0 and is_equal_approx(retreat, 3.0 * advance),
			"%s flees three times as fast as it advances with a damaged sail" % config.display_name)
		ship.free()
	battle.free()


func _test_fast_ship_sway() -> void:
	var battle = _battle()
	var player := battle.get_node("PlayerShip") as PlayerShip
	var fast: EnemyShip = battle.spawn_enemy(0, EnemySpawner.TYPES[EnemyShipConfig.Type.FAST], 600.0)
	fast._sway_phase = 0.0
	var distant := _measure_sway(fast, player, 180)
	_check(distant.fastest_right == 0.0 and distant.strongest_weave == 0.0 and is_equal_approx(fast.position.x, 534.0),
		"The fast ship moves straight at cruise speed before reaching the fortress")
	fast.position.x = 440.0
	fast._sway_phase = 0.0
	var running := _measure_sway(fast, player, 450)
	var advanced := fast.position.x < 375.0
	fast.position.x = 260.0
	var stationary := _measure_sway(fast, player, 450)
	_check(advanced and running.fastest_right > 10.0 and running.fastest_left < -15.0,
		"Near the fortress the fast ship reverses horizontally while making progress")
	_check(stationary.span > 15.0 and stationary.span < 20.0 and stationary.farthest_x <= 260.01
		and fast.action == EnemyShip.Action.ATTACK_FORTRESS, "The fast ship sways in a narrower band within firing range")
	_check(maxf(running.water_gap, stationary.water_gap) < 0.01,
		"A weaving fast ship keeps its keel on the lane waterline")
	_check(maxf(running.peak_speed, stationary.peak_speed) <= 22.01, "Horizontal movement is capped at 22 px/s")
	battle.free()


func _measure_sway(ship: EnemyShip, player: PlayerShip, frames: int) -> Dictionary:
	var high := -INF
	var low := INF
	var fastest_left := 0.0
	var fastest_right := 0.0
	var strongest_weave := 0.0
	var water_gap := 0.0
	var water_y := ship.lanes.lane_bottom_y(ship.lane_index)
	for frame in range(frames):
		var last := ship.position
		ship.step(1.0 / 60.0, player.combat, 60.0, true)
		var x := ship.position.x
		if frame > 100:
			high = maxf(high, x)
			low = minf(low, x)
		var speed := (x - last.x) * 60.0
		fastest_left = minf(fastest_left, speed)
		fastest_right = maxf(fastest_right, speed)
		strongest_weave = maxf(strongest_weave, ship.weave_strength)
		water_gap = maxf(water_gap, absf(ship.position.y - water_y))
	return {"span": high - low, "farthest_x": high, "fastest_left": fastest_left, "fastest_right": fastest_right,
		"peak_speed": maxf(-fastest_left, fastest_right), "water_gap": water_gap, "strongest_weave": strongest_weave}


func _test_fortress_hit_rate() -> void:
	var battle = _battle()
	battle._rng.seed = SEED
	var player := battle.get_node("PlayerShip") as PlayerShip
	var projectiles := battle.get_node("Projectiles") as Node2D
	var hits := [0, 0]
	for type in [EnemyShipConfig.Type.FAST, EnemyShipConfig.Type.NORMAL]:
		var config := EnemySpawner.TYPES[type]
		for i in range(24):
			var ship: EnemyShip = battle.spawn_enemy(0, config, 418.0)
			ship._sway_phase = TAU * i / 24.0
			ship.step(1.0 / 60.0, player.combat, 60.0, true)
			battle._turret_timers[0] = 0.0
			battle._update_turrets(0.0)
			if projectiles.get_child_count() == 0:
				ship.free()
				continue
			var shell := projectiles.get_child(0) as Projectile
			for frame in range(170):
				ship.step(1.0 / 60.0, player.combat, 60.0, true)
				shell._physics_process(1.0 / 60.0)
				if shell.is_queued_for_deletion():
					break
			if ship.combat.parts.hp(ShipParts.Part.HULL) < ship.combat.parts.max_hp(ShipParts.Part.HULL):
				hits[type] += 1
			shell.free()
			ship.free()
			for smoke in projectiles.get_children():
				smoke.free()
	print("Fortress hull hits at 418 px, over 24 phases each: fast %d, normal %d" % hits)
	_check(hits[1] == 24 and hits[0] <= 18, "Fast ships evade substantially more real fortress shots")
	battle.free()


func _test_opening_wave() -> void:
	var battle = _battle()
	var enemies := battle.get_node("Enemies") as Node2D
	var spawner := battle.get_node("EnemySpawner") as EnemySpawner
	var conch := spawner.get_node("Conch") as AudioStreamPlayer
	var cue_count := [0]
	spawner.batch_announced.connect(func(_formation, _arrivals):
		cue_count[0] += 1
		_check(conch.playing and enemies.get_child_count() == 0, "The conch begins before any ship enters")
	)
	_check(battle.enemy_total == 10, "The easy opening level buys ten fast ships with its budget of 30")
	battle.set_boarding_active(true)
	battle._update_spawn(12.0)
	_check(enemies.get_child_count() == 0 and cue_count[0] == 0, "Boarding freezes the batch countdown")
	battle.set_boarding_active(false)
	paused = true
	battle._update_spawn(12.0)
	_check(cue_count[0] == 0, "SceneTree pause also freezes the batch countdown")
	paused = false
	var elapsed := 0.0
	while elapsed < 10.2 and cue_count[0] == 0:
		elapsed += 0.1
		battle._update_spawn(0.1)
	battle.set_boarding_active(true)
	battle._update_spawn(12.0)
	_check(conch.stream_paused and enemies.get_child_count() == 0,
		"Boarding also freezes a batch whose conch has already started")
	battle.set_boarding_active(false)
	while elapsed < 11.0 and enemies.get_child_count() == 0:
		elapsed += 0.1
		battle._update_spawn(0.1)
	_check(enemies.get_child_count() >= 1 and enemies.get_child_count() <= 5 and elapsed >= 6.0,
		"The first wave enters after the batch interval and contains one to five ships")
	_check(cue_count[0] == 1, "A multi-ship batch has just one spawn cue")
	for enemy: EnemyShip in enemies.get_children():
		_check(enemy.config.speed == 22.0 and enemy.config.attack_damage == 4.0,
			"The first level only deploys fast ships")
	battle.free()


func _test_boarding_contact() -> void:
	var battle = _battle()
	var player := battle.get_node("PlayerShip") as PlayerShip
	var enemies := battle.get_node("Enemies") as Node2D
	var contact: EnemyShip = battle.spawn_enemy(player.lane_index)
	contact.position.x = player.position.x
	var notifications: Array[EnemyShip] = []
	battle.boarding_contact_started.connect(func(ship): notifications.append(ship))
	battle._check_boarding(0.0)
	battle._update_spawn(12.0)
	_check(notifications == [contact] and enemies.get_child_count() == 1,
		"The live boarding fight freezes automatic spawning as soon as boarding is announced")
	contact.position.x += 300.0
	battle._check_boarding(0.0)
	battle.set_boarding_active(false)
	battle._update_spawn(12.0)
	_check(enemies.get_child_count() == 1, "Separation or external resume cannot unpause spawning during a real boarding fight")
	contact.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 1000.0)
	await process_frame
	await process_frame
	battle._update_spawn(10.1)
	battle._update_spawn(0.66)
	_check(not battle._live_enemies().is_empty(), "The real fight ending resumes the same automatic spawn countdown")
	battle.free()


func _test_capacity() -> void:
	var level := EnemySpawner.LEVELS[2].duplicate() as EnemySpawnLevel
	level.formation_pool.assign([EnemySpawnLevel.Formation.BUTTERFLY])
	level.formation_chance = 1.0
	var spawner := _spawner(level, SEED)
	var signal_kinds: Array[int] = []
	spawner.batch_announced.connect(func(kind, _arrivals): signal_kinds.append(kind))
	var occupied := PackedInt32Array([2, 2, 2, 2, 2, 2, 2, 1, 0, 0])
	_check(spawner.advance(6.0, occupied, false).is_empty() and signal_kinds.is_empty(),
		"A full screen skips an entire batch without a conch")
	occupied[7] = 0
	spawner.advance(5.9, occupied, false)
	_check(signal_kinds.is_empty(), "Opening a slot does not replay the skipped batch")
	spawner.advance(0.11, occupied, false)
	var admitted := spawner.advance(0.66, occupied, false)
	_check(signal_kinds == [EnemySpawnLevel.Formation.NONE] and admitted.size() == 1,
		"Limited capacity downgrades the formation and keeps the total at 15")
	_check(admitted.size() == 1 and admitted[0].config.cost == 3 and admitted[0].lane >= 7,
		"The opening picks an inexpensive ship and avoids lanes with two ships")
	spawner.free()


func _test_formations() -> void:
	var butterfly := EnemySpawner.LEVELS[2].duplicate() as EnemySpawnLevel
	butterfly.formation_pool.assign([EnemySpawnLevel.Formation.BUTTERFLY])
	butterfly.formation_chance = 1.0
	var spawner := _spawner(butterfly, SEED)
	var empty := PackedInt32Array([0, 0, 0, 0, 0])
	spawner.advance(6.0, empty, false)
	var group := spawner.advance(0.66, empty, false)
	var lanes: Array[int] = []
	for arrival in group:
		if not lanes.has(arrival.lane):
			lanes.append(arrival.lane)
	_check(group.size() == 5 and lanes.size() == 5, "The butterfly enters together across five different lanes")
	spawner.free()

	var snake := EnemySpawner.LEVELS[1].duplicate() as EnemySpawnLevel
	snake.formation_chance = 1.0
	snake.max_alive = 5
	spawner = _spawner(snake, SEED)
	var announced: Array[EnemySpawner.Arrival] = []
	spawner.batch_announced.connect(func(_kind, arrivals): announced.assign(arrivals))
	var saw_snake := false
	for i in range(8):
		var occupied := PackedInt32Array([0, 0, 0, 0, 0])
		announced.clear()
		spawner.advance(6.0, occupied, false)
		if announced.is_empty() or not announced[0].leads_snake:
			spawner.advance(0.66, occupied, false)
			continue
		saw_snake = true
		var head := announced[0]
		var tail := announced[announced.size() - 1]
		_check(announced.size() >= 4 and announced.size() <= 5, "A snake announces four or five ships together")
		_check(head.config.cost == 5 and tail.config.cost == 5 and announced.slice(1, -1).all(
			func(arrival: EnemySpawner.Arrival): return arrival.config.cost == 3),
			"The long snake places the two required normal ships at the ends")
		var chain := true
		for index in range(1, announced.size()):
			chain = chain and announced[index].lane == head.lane and announced[index].predecessor == announced[index - 1]
		_check(chain, "All ships queue behind the preceding ship on the same lane")
		occupied[head.lane] = 1
		_check(spawner.advance(0.66, occupied, false).is_empty(), "A snake waits together if its lane fills after the cue")
		occupied[head.lane] = 0
		var other_lane := (head.lane + 1) % occupied.size()
		occupied[other_lane] = 2
		_check(spawner.advance(0.1, occupied, false).is_empty(), "A snake waits together if world capacity shrinks after the cue")
		occupied[other_lane] = 0
		var entering := spawner.advance(0.1, occupied, false)
		_check(entering == announced and occupied[head.lane] == announced.size(),
			"The full announced batch enters the same lane in a single tick when space returns")
		break
	_check(saw_snake, "The fixed seed exercises the long snake")
	spawner.free()


func _test_required_snake_ends() -> void:
	var level := EnemySpawner.LEVELS[1].duplicate() as EnemySpawnLevel
	level.formation_chance = 0.0
	var spawner := _spawner(level, SEED)
	var last_batch: Array[EnemySpawner.Arrival] = []
	for i in range(16):
		var occupied := PackedInt32Array([0, 0, 0, 0, 0])
		spawner.advance(6.0, occupied, false)
		last_batch = spawner.advance(0.66, occupied, false)
		if spawner.is_exhausted():
			break
	_check(last_batch.size() == 4 and last_batch[0].leads_snake
		and last_batch[0].config.enemy_type == EnemyShipConfig.Type.NORMAL
		and last_batch[3].config.enemy_type == EnemyShipConfig.Type.NORMAL
		and last_batch.all(func(arrival): return arrival.lane == last_batch[0].lane),
		"The required normal ships still lead and cap a full snake when every chance roll failed")
	spawner.free()


func _test_snake_limits() -> void:
	for limits: Vector2i in [Vector2i(0, 15), Vector2i(45, 3)]:
		var level := EnemySpawner.LEVELS[1].duplicate() as EnemySpawnLevel
		level.budget = limits.x
		level.max_alive = limits.y
		level.formation_chance = 1.0
		var spawner := _spawner(level, SEED)
		var entered := 0
		var only_plain := true
		for i in range(20):
			var occupied := PackedInt32Array([0, 0, 0, 0, 0])
			spawner.advance(6.0, occupied, false)
			var arrivals := spawner.advance(0.66, occupied, false)
			entered += arrivals.size()
			only_plain = only_plain and arrivals.size() <= limits.y and arrivals.all(func(arrival): return not arrival.leads_snake)
			if spawner.is_exhausted():
				break
		_check(spawner.is_exhausted() and entered == spawner.enemy_total and only_plain,
			"A level without room or ships for a full snake still dispatches its entire roster")
		spawner.free()


func _test_snake_spacing() -> void:
	var battle = _battle("res://Assets/Audio/SFX/enemy_spawn.ogg", 2, SEED, "normal")
	var spawner := battle.get_node("EnemySpawner") as EnemySpawner
	var lanes := battle.get_node("Lanes") as Lanes
	var alert := battle.get_node("HUD/Alert") as Label
	var snake: Array[EnemySpawner.Arrival] = []
	spawner.batch_announced.connect(func(kind, arrivals):
		if kind == EnemySpawnLevel.Formation.SNAKE and snake.is_empty():
			snake.assign(arrivals)
	)
	var in_view := false
	var stays_in_line := true
	var showed_cue := false
	for tick in range(800):
		battle._physics_process(0.1)
		showed_cue = showed_cue or (alert.text.contains("长蛇阵") and alert.modulate.a > 0.0)
		if snake.is_empty() or not snake.all(func(arrival):
			return is_instance_valid(arrival.ship) and arrival.ship.combat.targetable):
			continue
		var head := snake[0].ship
		for index in range(1, snake.size()):
			var previous := snake[index - 1].ship
			var ship := snake[index].ship
			var gap := ship.global_position.x - previous.global_position.x
			stays_in_line = stays_in_line and ship.formation_predecessor == previous \
				and ship.lane_index == head.lane_index and gap >= 143.99
		var tail := snake[snake.size() - 1].ship
		if tail.global_position.x + tail.config.size.x * 0.5 <= lanes.sea_right:
			in_view = true
			break
	_check(snake.size() >= 4 and snake.size() <= 5 and in_view,
		"The U-06 seed brings at least four same-batch ships on screen together")
	_check(in_view and stays_in_line, "The same-lane ships stay ordered and separated during the whole approach")
	_check(showed_cue, "The seeded snake announces its formation through the battle HUD")
	battle.free()


func _test_butterfly_alert() -> void:
	var battle = _battle("", 4, 155830)
	var alert := battle.get_node("HUD/Alert") as Label
	for i in range(100):
		battle._physics_process(0.1)
	_check(alert.text.is_empty(), "Ordinary batches do not show a formation alert")
	for i in range(110):
		battle._physics_process(0.1)
	_check(alert.text.contains("蝴蝶阵") and alert.modulate.a > 0.0,
		"The seeded butterfly announces its formation through the battle HUD")
	battle.free()


func _test_victory_after_retreat() -> void:
	var battle = _battle("res://Assets/Audio/SFX/missing.ogg")
	var enemies := battle.get_node("Enemies") as Node2D
	var player := battle.get_node("PlayerShip") as PlayerShip
	var steps := 0
	while battle.enemies_defeated < 9 and steps < 900:
		battle._update_spawn(0.1)
		for ship: EnemyShip in enemies.get_children():
			if battle.enemies_defeated < 9 and ship.combat.targetable:
				ship.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 999.0)
		steps += 1
	battle._advance_morale(2.0)
	_check(battle.kills == 9 and is_equal_approx(battle.enemy_morale, 0.1) and not battle.is_over,
		"The purchased total is the morale denominator and nine sinks cannot clear the level")
	var finished: Array[bool] = []
	battle.on_battle_finished.connect(func(won: bool, _breach: bool): finished.append(won))
	while battle.enemies_defeated < 10 and steps < 1200:
		battle._update_spawn(0.1)
		for ship: EnemyShip in enemies.get_children():
			if ship.combat.targetable:
				ship.position.x = 1345.0
				ship.set_morale(0.05, 0.1)
				ship.step(0.1, player.combat, 60.0, true)
		steps += 1
	await process_frame
	_check(finished == [true] and battle.kills == 9 and battle.enemies_defeated == 10,
		"The final retreat resolves the level even with a missing conch asset")
	battle.free()


func _spawner(level: EnemySpawnLevel, fixed_seed: int) -> EnemySpawner:
	var spawner := EnemySpawner.new()
	root.add_child(spawner)
	spawner.begin(level, "easy", fixed_seed, Vector2(6, 6), "")
	return spawner


func _battle(sound_path: String = "res://Assets/Audio/SFX/enemy_spawn.ogg", level_id: int = 1,
		fixed_seed: int = SEED, difficulty: String = "easy"):
	var battle = BATTLE.instantiate()
	battle.difficulty = difficulty
	battle.management_session = MANAGEMENT_SESSION.new(difficulty, level_id)
	battle.spawn_seed = fixed_seed
	battle.spawn_sound_path = sound_path
	battle.gate_launch_time = 0.0
	root.add_child(battle)
	battle.set_physics_process(false)
	return battle


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
