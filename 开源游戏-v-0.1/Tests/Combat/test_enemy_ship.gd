extends SceneTree

const BATTLE := preload("res://Scenes/battle.tscn")
const ENEMY := preload("res://Data/Combat/enemy_e01.tres")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_template_and_overlap()
	_test_targets_and_recoil()
	_test_damage_and_conduction()
	_test_swept_hits()
	_test_retreat_and_sinking()
	_test_damaged_sail_retreat()
	_test_all_enemy_hulls_sink()
	_test_nested_damage()
	await _test_live_input()
	await _test_fortress_and_end_flow()
	print("Enemy ship checks: %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _test_template_and_overlap() -> void:
	var battle = _make_battle()
	var player: PlayerShip = battle.get_node("PlayerShip")
	var fortress: Fortress = battle.get_node("Fortress")

	var ships: Array[EnemyShip] = []
	var speeds: Array[float] = []
	for index in range(5):
		var ship: EnemyShip = battle.spawn_enemy(1)
		_check(ship != null, "Enemy %d can spawn in an occupied lane" % index)
		if ship == null:
			battle.free()
			return
		ships.append(ship)
		speeds.append(ship._speed())

	for tick in range(720):
		battle._physics_process(0.1)

	_check(ships[0].config.id == &"E-01", "The normal spawn entry loads the E-01 template")
	_check(float(speeds.min()) == 16.0 and float(speeds.max()) == 16.0,
		"Normal ships use the configured 16 px/s cruising speed")
	var fire_line := fortress.target_x(1) + ENEMY.attack_range
	for ship in ships:
		_close(ship.position.x, fire_line, "Every enemy reaches the arrow range and stops")
	_close(battle.fortress_hp, 400.0, "Advancing and reaching the stop line do not damage the fortress")
	_check(not ships[0].try_change_lane(0), "E-01 disables explicit lane changes by default")

	player.position.x = fire_line
	_check(player.try_change_lane(1) and player.lane_change_fail_reason.is_empty(),
		"The player can enter an occupied lane")

	var alternate := ENEMY.duplicate() as EnemyShipConfig
	alternate.speed = 105.0
	alternate.can_change_lane = true
	battle.enemy_config = alternate
	var faster: EnemyShip = battle.spawn_enemy(0)
	faster.position.x = 330.0
	_check(not faster.try_change_lane(1) and faster.lane_change_fail_reason == "有人",
		"An enabled enemy lane change reports occupied space")
	faster.position.x = 700.0
	battle._physics_process(0.5)
	_close(faster.position.x, 689.0, "The alternate resource is also bounded by the enemy speed cap")
	_check(faster.try_change_lane(3) and faster.lane_index == 3,
		"The same enemy scene can accept an open lane with an alternate template")
	battle.free()


func _test_targets_and_recoil() -> void:
	var battle = _make_battle()
	var player: PlayerShip = battle.get_node("PlayerShip")
	var enemy: EnemyShip = battle.spawn_enemy(2)
	var fortress: Fortress = battle.get_node("Fortress")
	var fire_line := fortress.target_x(2) + ENEMY.attack_range
	var encounter_x := fire_line + 80.0
	var sprite := enemy.combat.visual_sprite()
	_check(sprite.flip_h, "The new E-01 art is mirrored to face the fortress")
	battle._physics_process(0.2)
	_check(enemy.action == EnemyShip.Action.ADVANCE and _shots(battle).is_empty(),
		"An out-of-range enemy advances without firing")

	enemy.position.x = encounter_x
	player.position.x = encounter_x - 120.0
	var origin := enemy.combat.muzzle_position(-1.0)
	var target := player.combat.aim_point()
	battle._physics_process(0.1)
	_check(enemy.action == EnemyShip.Action.ATTACK_PLAYER and _shots(battle).is_empty(),
		"A same-lane player takes priority over the fortress and starts the target delay")
	_close(enemy.position.x, encounter_x, "Acquiring the player stops forward movement")
	battle._physics_process(0.29)
	_check(_shots(battle).is_empty(), "An enemy cannot fire before the full target delay")
	battle._physics_process(0.02)
	var shots := _shots(battle)
	_check(shots.size() == 1, "The enemy fires automatically after acquiring the target")
	if shots.size() != 1:
		battle.free()
		return
	var ball := shots[0]
	_check(ball.team == ShipCombat.Team.ENEMY and ball.lane_index == 2, "Enemy fire preserves its launch lane and team")
	_close(ball.damage, 4.0, "E-01 uses the arrow damage from its resource")
	_close(ball.velocity.length(), 850.0, "The enemy aims with its configured launch speed")
	var flight_time := (target.x - origin.x) / ball.velocity.x
	var point_at_target := origin + ball.velocity * flight_time + Vector2(0, 0.5 * ball.arc_gravity * flight_time ** 2)
	_check(point_at_target.distance_to(target) < 0.01, "The launch aims at the player's current point")
	_check(ball.global_position.distance_to(origin) < 0.01, "The arrow originates at the displayed weapons deck")
	_check(enemy.combat.muzzle_position(-1.0).distance_to(origin) < 0.01, "Arrows leave the deck without cannon recoil")
	_check(enemy.lane_index == 2 and enemy.position.is_equal_approx(Vector2(encounter_x, 489.6)),
		"Shooting an arrow leaves the logical lane and occupancy anchor in place")

	enemy.position.x = fire_line
	_check(player.try_change_lane(1), "The player can leave for an open lane")
	battle._physics_process(0.2)
	_check(enemy.action == EnemyShip.Action.ATTACK_FORTRESS and enemy.position.x == fire_line,
		"A player leaving the lane immediately switches to the fortress within range")
	_check(_shots(battle).size() == 1, "Switching targets preserves the existing reload")
	battle._physics_process(2.7)
	_check(_shots(battle).size() == 1, "A new target cannot bypass the full reload")
	battle._physics_process(0.12)
	_check(_shots(battle).size() == 2, "The enemy fires at the fortress when both timers clear")
	_close(enemy.position.x, fire_line, "The attacker holds the new firing line")
	battle.free()

	battle = _make_battle()
	player = battle.get_node("PlayerShip")
	enemy = battle.spawn_enemy(2)
	enemy.position.x = encounter_x
	player.position.x = encounter_x - 120.0
	battle._physics_process(0.1)
	enemy.position.x = fire_line
	_check(player.try_change_lane(1), "A reachable player can leave before the first shot")
	battle._physics_process(0.28)
	battle._physics_process(0.29)
	_check(_shots(battle).is_empty(), "A target switch restarts the 0.3-second delay even with a loaded cannon")
	battle._physics_process(0.02)
	_check(_shots(battle).size() == 1, "The new target is fired at after its own delay")
	battle.free()

	battle = _make_battle()
	player = battle.get_node("PlayerShip")
	enemy = battle.spawn_enemy(2)
	sprite = enemy.combat.visual_sprite()
	enemy.position.x = 730.0
	player.position.x = 910.0
	battle._physics_process(0.1)
	_check(not sprite.flip_h, "A player behind the enemy turns its cannon toward the right")
	player.position.x = 1250.0
	battle._physics_process(0.1)
	_check(enemy.action == EnemyShip.Action.ADVANCE and sprite.flip_h,
		"After losing a target astern, the advancing ship faces the fortress again")
	battle.free()


func _test_damage_and_conduction() -> void:
	var battle = _make_battle()
	var enemy: EnemyShip = battle.spawn_enemy(0)
	var other: EnemyShip = battle.spawn_enemy(4)
	var parts := enemy.combat.parts
	parts.rng.seed = 0
	var rng_state := parts.rng.state
	enemy.combat.receive_hit(ShipParts.Part.SAIL, ShipParts.Ammo.SOLID, 12.5)
	_close(parts.hp(ShipParts.Part.SAIL), 22.5, "Solid ammo uses the sail's damage multiplier")
	_close(parts.speed_multiplier(), 0.7, "A sail at the 75% boundary slows movement")
	_check(parts.rng.state == rng_state and parts.hp(ShipParts.Part.RUDDER) == 10.0,
		"A sail hit does not conduct damage")
	_close(other.combat.parts.hp(ShipParts.Part.SAIL), 30.0, "Ship instances keep independent HP")
	enemy.combat.receive_hit(ShipParts.Part.SAIL, ShipParts.Ammo.SOLID, 32.5)
	_close(parts.speed_multiplier(), 0.4, "A sail at the 10% boundary uses the destroyed multiplier")

	enemy.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 10.0)
	_check(parts.condition(ShipParts.Part.HULL) == ShipParts.Condition.DAMAGED,
		"The 75% threshold is inclusive")
	_close(parts.hp(ShipParts.Part.RUDDER), 10.0, "A roll above the hull-to-rudder chance does not conduct")
	_close(parts.hp(ShipParts.Part.RAM), 20.0, "A roll above the hull-to-ram chance does not conduct")
	enemy.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 26.0)
	_check(parts.condition(ShipParts.Part.HULL) == ShipParts.Condition.DESTROYED and enemy.combat.targetable,
		"At exactly 10% the hull is destroyed but still afloat")

	var config := ENEMY.duplicate() as EnemyShipConfig
	config.damage_profile = ENEMY.damage_profile.duplicate() as ShipDamageProfile
	config.damage_profile.hull_conduction_chance = Vector2.ONE
	config.damage_profile.cannon_conduction_chance = Vector2(1.0, 0.0)
	battle.enemy_config = config
	var third: EnemyShip = battle.spawn_enemy(1)
	third.position.x = 250.0
	third.combat.parts.rng.seed = 0
	third.combat.receive_hit(ShipParts.Part.CANNON, ShipParts.Ammo.EXPLOSIVE, 20.0)
	parts = third.combat.parts
	_close(parts.hp(ShipParts.Part.CANNON), 1.0, "Explosive ammo applies the cannon multiplier")
	_close(parts.hp(ShipParts.Part.HULL), 30.5, "A cannon hit adds half its damage to the hull once")
	_close(parts.hp(ShipParts.Part.RUDDER), 4.3, "A successful cannon conduction applies 30% of its main damage")
	_close(parts.hp(ShipParts.Part.RAM), 20.0, "Weapons companion damage does not recursively conduct from the hull")
	battle._physics_process(0.1)
	battle._physics_process(0.5)
	_check(third.action == EnemyShip.Action.ATTACK_FORTRESS and _shots(battle).is_empty(),
		"A destroyed cannon cannot fire at an eligible target")

	other.combat.receive_hit(ShipParts.Part.CANNON, ShipParts.Ammo.SOLID, 8.0)
	_close(other.combat.parts.advance_reload(3.0, 3.0), 0.6923077,
		"A damaged cannon stretches an in-progress reload by 30%")

	var custom := ENEMY.duplicate() as EnemyShipConfig
	custom.damage_profile = ENEMY.damage_profile.duplicate() as ShipDamageProfile
	custom.damage_profile.hull_conduction_chance = Vector2.ONE
	custom.damage_profile.hull_conduction_scale = Vector2(0.5, 0.1)
	battle.enemy_config = custom
	var configured: EnemyShip = battle.spawn_enemy(3)
	configured.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 10.0)
	_close(configured.combat.parts.hp(ShipParts.Part.RUDDER), 5.0, "A template tunes hull-to-rudder conduction separately")
	_close(configured.combat.parts.hp(ShipParts.Part.RAM), 19.0, "A template tunes hull-to-ram conduction separately")
	battle.free()


func _test_swept_hits() -> void:
	var battle = _make_battle()
	battle.get_node("CombatConfig").gravity = 0.0
	var first: EnemyShip = battle.spawn_enemy(1)
	first.position.x = 800.0
	var sail := first.combat.hitbox(ShipParts.Part.SAIL).get_center()
	var parts := first.combat.parts
	var wrong_lane: Projectile = battle.launch_projectile(sail, Vector2.ZERO, 2, ShipCombat.Team.ALLY, 10.0)
	wrong_lane._physics_process(0.05)
	_check(not wrong_lane.is_queued_for_deletion() and parts.hp(ShipParts.Part.SAIL) == 30.0,
		"Cross-lane overlap neither damages a ship nor consumes the shell")

	var friendly: Projectile = battle.launch_projectile(sail, Vector2.ZERO, 1, ShipCombat.Team.ENEMY, 10.0)
	friendly._physics_process(0.05)
	_check(not friendly.is_queued_for_deletion() and parts.hp(ShipParts.Part.SAIL) == 30.0,
		"A same-lane friendly ship does not intercept a shell")

	var through_sail: Projectile = battle.launch_projectile(sail, Vector2.ZERO, 1, ShipCombat.Team.ALLY, 10.0, ShipParts.Ammo.ANTI_SAIL)
	through_sail._physics_process(0.05)
	through_sail._physics_process(0.05)
	_close(parts.hp(ShipParts.Part.SAIL), 12.0, "A shell applies anti-sail damage only once while still in the box")
	_check(not through_sail.is_queued_for_deletion(), "Sail contact leaves the shell in flight")

	var from := sail + Vector2(-5.0, -80.0)
	var sweep: Projectile = battle.launch_projectile(from, Vector2(0, 1600), 1, ShipCombat.Team.ALLY, 10.0)
	sweep._physics_process(0.1)
	_close(parts.hp(ShipParts.Part.SAIL), 6.0, "A fast sweep hits the sail first even when crossing it in one tick")
	_close(parts.hp(ShipParts.Part.HULL), 30.0, "The same sweep continues into the hull")
	_check(sweep.is_queued_for_deletion(), "A hard hit stops the shell")
	sweep._physics_process(0.1)
	_close(parts.hp(ShipParts.Part.HULL), 30.0, "A spent shell cannot deal duplicate hard damage")

	var second: EnemyShip = battle.spawn_enemy(1)
	second.position.x = 1000.0
	var cannon := second.combat.hitbox(ShipParts.Part.CANNON).get_center()
	var cannon_shot: Projectile = battle.launch_projectile(cannon + Vector2(0, -22), Vector2(0, 400), 1, ShipCombat.Team.ALLY, 10.0)
	cannon_shot._physics_process(0.1)
	_check(cannon_shot.is_queued_for_deletion(), "The cannon is a hard hitbox")
	_close(second.combat.parts.hp(ShipParts.Part.HULL), 35.75, "A physical cannon hit gives its hull companion damage")

	var backward: Projectile = battle.launch_projectile(Vector2(second.position.x + 100.0, second.combat.aim_point().y), Vector2(-3000, 0), 1, ShipCombat.Team.ALLY, 10.0)
	backward._physics_process(0.15)
	_close(second.combat.parts.hp(ShipParts.Part.HULL), 25.75, "The nearest hard impact wins when moving left")
	_close(parts.hp(ShipParts.Part.HULL), 30.0, "A farther ship cannot intercept through the nearer ship")

	var custom := ENEMY.duplicate() as EnemyShipConfig
	custom.damage_profile = ENEMY.damage_profile.duplicate() as ShipDamageProfile
	custom.damage_profile.sail_box = Rect2(0.6, -0.25, 0.2, 0.2)
	battle.enemy_config = custom
	var tall_ship: EnemyShip = battle.spawn_enemy(4)
	tall_ship.position.x = 850.0
	sail = tall_ship.combat.hitbox(ShipParts.Part.SAIL).get_center()
	var extended_hit: Projectile = battle.launch_projectile(sail, Vector2.ZERO, 4, ShipCombat.Team.ALLY, 10.0)
	extended_hit._physics_process(0.1)
	_close(tall_ship.combat.parts.hp(ShipParts.Part.SAIL), 24.0, "The broad phase includes all configured hitboxes")
	battle.free()


func _test_retreat_and_sinking() -> void:
	var battle = _make_battle()
	var left: EnemyShip = battle.spawn_enemy(0)
	left.position.x = 1186.0
	var blocker: EnemyShip = battle.spawn_enemy(0)
	var events := {"sunk": 0, "retreated": 0}
	battle.enemy_sunk.connect(func(_ship: EnemyShip): events.sunk += 1)
	battle.enemy_retreated.connect(func(_ship: EnemyShip): events.retreated += 1)
	left.set_morale(1, 1)
	battle._physics_process(0.1)
	_check(left.action == EnemyShip.Action.FLEE and left.position.x > 1186.0 and blocker.position.x < 1330.0,
		"Retreating and advancing ships can move independently in the same lane")

	var fleeing: EnemyShip = battle.spawn_enemy(3)
	fleeing.set_morale(1, 1)
	battle._physics_process(0.7)
	_check(fleeing.action == EnemyShip.Action.FLEE and not fleeing.combat.targetable and events.retreated == 1,
		"Retreat emits its own event once when the ship exits")
	_check(battle.kills == 0 and events.sunk == 0, "Retreat does not count as a kill")

	# Give a fresh instance deterministic conduction without changing the live shared profile.
	var config := ENEMY.duplicate() as EnemyShipConfig
	config.damage_profile = ENEMY.damage_profile.duplicate() as ShipDamageProfile
	config.damage_profile.hull_conduction_chance = Vector2.ONE
	battle.enemy_config = config
	var struck: EnemyShip = battle.spawn_enemy(4)
	struck.combat.parts.set_hp(ShipParts.Part.RAM, 10.0)
	struck.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 35.0)
	_check(struck.combat.parts.hp(ShipParts.Part.RUDDER) == 0.0 and struck.combat.parts.hp(ShipParts.Part.RAM) == 0.0,
		"A successful hull conduction can destroy the two hidden parts")
	_check(struck.combat.targetable, "The ship stays afloat after losing rudder and ram")
	struck.set_morale(0, 1)
	struck.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 5.0)
	struck.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 5.0)
	battle._physics_process(0.2)
	_check(struck.action == EnemyShip.Action.SINK and not struck.combat.targetable,
		"Zero hull removes the ship from combat immediately and takes priority over retreat")
	_check(battle.kills == 1 and events.sunk == 1 and events.retreated == 1,
		"Only a single sinking and reward event are emitted")
	battle.free()


func _test_damaged_sail_retreat() -> void:
	var battle = _make_battle()
	var hull := ShipParts.Part.HULL
	var sail := ShipParts.Part.SAIL
	var crippled: EnemyShip = battle.spawn_enemy(0, ENEMY, 800.0)
	var fast := EnemySpawner.TYPES[EnemyShipConfig.Type.FAST] as EnemyShipConfig
	var right := maxf(crippled.lanes.sea_right, root.get_visible_rect().end.x)
	var near_edge: EnemyShip = battle.spawn_enemy(1, fast, right - 1.0)
	var intact: EnemyShip = battle.spawn_enemy(3, fast, right - 64.0)
	var cap := crippled.combat.parts.max_hp(hull)
	var fast_cap := near_edge.combat.parts.max_hp(hull)
	crippled.combat.parts.set_hp(sail, crippled.combat.parts.max_hp(sail) * 0.75)
	near_edge.combat.parts.set_hp(hull, fast_cap * 0.5)
	near_edge.combat.parts.set_hp(sail, 0.0)
	var events := {"sunk": [], "escaped": []}
	battle.enemy_sunk.connect(func(ship: EnemyShip): events.sunk.append(ship))
	battle.enemy_retreated.connect(func(ship: EnemyShip): events.escaped.append(ship))

	battle._physics_process(1.0)
	_close(crippled.combat.parts.hp(hull), cap, "Sail damage does not drain the hull before retreat")
	var turn_x := crippled.position.x
	battle.morale_bias = -0.91
	for tick in range(60):
		battle._physics_process(1.0 / 60.0)
	_close(crippled.combat.parts.hp(hull), cap * 5.0 / 6.0, "A torn sail drains a sixth of the hull cap per second")
	_close(near_edge.combat.parts.hp(hull), fast_cap / 3.0, "A destroyed sail drains even beside the exit")
	_close(intact.combat.parts.hp(hull), fast_cap, "An intact sail does not drain the hull during retreat")
	_check(crippled.position.x > turn_x and crippled.action == EnemyShip.Action.FLEE,
		"The torn-sail ship continues retreating while it takes damage")

	for tick in range(120):
		battle._physics_process(1.0 / 60.0)
	_check(events.sunk == [near_edge] and near_edge.action == EnemyShip.Action.SINK and near_edge.position.x <= right,
		"The half-health ship with a destroyed sail sinks beside the exit in three seconds")
	_check(events.escaped == [intact] and intact.combat.parts.hp(hull) == fast_cap,
		"The intact ship exits at full hull health and only emits retreat")
	for tick in range(180):
		battle._physics_process(1.0 / 60.0)
	_check(events.sunk == [near_edge, crippled] and not crippled.combat.targetable
		and events.escaped == [intact] and battle.kills == 2 and battle.enemies_defeated == 3,
		"The full-health torn-sail ship sinks inside six seconds and the roster settles each ship once")
	battle.free()


func _test_all_enemy_hulls_sink() -> void:
	var battle = _make_battle()
	var sunk_ships: Array[EnemyShip] = []
	battle.enemy_sunk.connect(func(ship: EnemyShip): sunk_ships.append(ship))
	var hull := ShipParts.Part.HULL
	for config: EnemyShipConfig in EnemySpawner.TYPES.values():
		var ship: EnemyShip = battle.spawn_enemy(0, config, 550.0)
		ship.combat.parts.set_hp(hull, 1.0)
		_check(ship.combat.targetable, "%s stays afloat below the hull destruction threshold" % config.display_name)
		ship.combat.parts.set_hp(hull, 0.0)
		ship.combat.receive_hit(hull, ShipParts.Ammo.SOLID, 5.0)
		_check(not ship.combat.targetable and ship.action == EnemyShip.Action.SINK and sunk_ships.count(ship) == 1,
			"%s sinks exactly once when its hull HP is set to zero" % config.display_name)

		var boarded: EnemyShip = battle.spawn_enemy(1, config, 550.0)
		boarded.boarding_locked = true
		boarded.combat.apply_raw_damage(hull, boarded.combat.parts.max_hp(hull))
		_check(boarded.action == EnemyShip.Action.SINK and sunk_ships.count(boarded) == 1,
			"%s sinks at zero hull HP during boarding" % config.display_name)

		var shelled: EnemyShip = battle.spawn_enemy(2, config, 550.0)
		shelled.combat.parts.set_hp(hull, 1.0)
		shelled.combat.receive_hit(ShipParts.Part.CANNON, ShipParts.Ammo.SOLID, 10.0)
		_check(shelled.action == EnemyShip.Action.SINK and sunk_ships.count(shelled) == 1,
			"%s sinks when a weapons hit depletes the hull" % config.display_name)
	_check(battle.kills == 9 and battle.enemies_defeated == 9, "Each sinking reaches battle bookkeeping once")
	battle.free()


func _test_nested_damage() -> void:
	var battle = _make_battle()
	var enemy: EnemyShip = battle.spawn_enemy(0)
	var events := {"sunk": 0}
	battle.enemy_sunk.connect(func(_ship: EnemyShip): events.sunk += 1)
	enemy.combat.parts.part_changed.connect(func(part: ShipParts.Part, hp: float, _condition: ShipParts.Condition):
		if part == ShipParts.Part.HULL and hp > 0.0:
			enemy.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 40.0)
	)
	enemy.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 10.0)
	_check(events.sunk == 1 and battle.kills == 1, "Nested lethal damage still emits exactly one sinking")
	battle.free()


func _test_live_input() -> void:
	var battle = _make_battle()
	var player: PlayerShip = battle.get_node("PlayerShip")
	player.set_physics_process(true)
	battle.set_physics_process(true)
	Input.action_press("move_down")
	await physics_frame
	await physics_frame
	Input.action_release("move_down")
	_check(player.lane_index == 3 and player.is_switching(), "The normal move action starts a lane change")
	Input.action_press("fire")
	await physics_frame
	await physics_frame
	Input.action_release("fire")
	_check(battle.get_node("PlayerShip/Combat/Weapon").ammo[0] == 30, "The player cannot fire while changing lanes")
	await create_timer(0.64).timeout
	_check(is_equal_approx(player.position.y, 604.8) and not player.is_switching(), "The player settles into the new lane")
	Input.action_press("fire")
	await physics_frame
	await physics_frame
	Input.action_release("fire")
	var shots := _shots(battle)
	_check(battle.get_node("PlayerShip/Combat/Weapon").ammo[0] == 29 and shots.size() == 1 and shots[0].lane_index == 3,
		"The normal fire action consumes ammo and uses the new lane")
	battle.free()


func _test_fortress_and_end_flow() -> void:
	var battle = _make_battle()
	current_scene = battle
	battle.end_delay = 0.0
	battle.get_node("CombatConfig").gravity = 0.0
	battle.fortress_hp = 16.0
	var player: PlayerShip = battle.get_node("PlayerShip")
	var origin := player.combat.aim_point() + Vector2(130, 0)
	var shell: Projectile = battle.launch_projectile(origin, Vector2(-2000, 0), 2, ShipCombat.Team.ENEMY, 8.0)
	shell._physics_process(0.2)
	_close(player.combat.parts.hp(ShipParts.Part.HULL), 92.0, "Hostile shots use the same hull rule on the player")
	_close(battle.fortress_hp, 16.0, "The first valid hard impact shields the fortress")

	player.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 100.0)
	_check(not player.combat.targetable and not battle.is_over, "Player sinking does not defeat the fortress")
	var fortress: Fortress = battle.get_node("Fortress")
	for lane in [0, 4]:
		var y: float = battle.get_node("Lanes").lane_center_y(lane)
		var x := fortress.target_x(lane) + 70.0
		shell = battle.launch_projectile(Vector2(x, y), Vector2(-1000, 0), lane, ShipCombat.Team.ENEMY, 8.0)
		shell._physics_process(0.1)
	_close(battle.fortress_hp, 0.0, "Confirmed enemy impacts in different lanes share the same fortress HP")
	_check(battle.is_over and battle.get_node("HUD/Banner").text == "堡已破 · 乡兵击退了倭寇",
		"Zero shared fortress HP triggers defeat")
	await create_timer(0.15).timeout
	_check(current_scene != null and current_scene.scene_file_path.ends_with("/management.tscn"),
		"A breach without a surviving enemy still settles into management")
	if current_scene != null:
		var finished := current_scene
		current_scene = null
		finished.queue_free()


func _make_battle():
	var battle = BATTLE.instantiate()
	battle.spawn_interval_range = Vector2(9999.0, 9999.0)
	battle.gate_launch_time = 0.0
	battle.turret_fire_range = 0.0
	root.add_child(battle)
	battle.set_physics_process(false)
	battle.get_node("PlayerShip").set_physics_process(false)
	battle.get_node("PlayerShip").position.x = 420.0
	return battle


func _shots(battle: Node) -> Array[Projectile]:
	var result: Array[Projectile] = []
	for child in battle.get_node("Projectiles").get_children():
		if child is Projectile and not child.is_queued_for_deletion():
			result.append(child)
	return result


func _close(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) < 0.01, "%s (got %s, expected %s)" % [message, actual, expected])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
