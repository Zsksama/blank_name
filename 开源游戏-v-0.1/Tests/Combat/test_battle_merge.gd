extends SceneTree

const ManagementSession := preload("res://Scripts/Management/management_session.gd")
const Ballistics := preload("res://Scripts/ballistics.gd")

var _checks := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(ok: bool, title: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL ", title)


func _run() -> void:
	await _test_fortress_integration()
	await _test_fortress_fire_and_ending()
	_test_nested_fort_hits()
	_test_next_battle_upgrades()
	var battle = load("res://Scenes/battle.tscn").instantiate()
	battle.first_spawn_delay = 9999.0
	battle.gate_launch_time = 0.0
	root.add_child(battle)
	current_scene = battle
	battle.set_physics_process(false)
	var player: PlayerShip = battle.get_node("PlayerShip")
	var lanes: Lanes = battle.get_node("Lanes")
	var weapon = get_first_node_in_group("player_weapon")
	_expect(weapon != null, "The main battle uses the collaborator's weapon")
	_expect(is_equal_approx(lanes.lane_height(), 115.2) and player.z_index == 19, "The ship uses the v2 sea layers")
	_expect(battle.get_node_or_null("Sea") == null and is_equal_approx(player.move_speed, 25.0), "V2 geometry and movement load at startup")
	var slots: Array = battle._turrets.map(func(turret): return turret.lane_index)
	_expect(slots == [0, 1, 3, 4], "Fort cannons protect four lanes and leave the water gate open")
	_expect(battle.get_node_or_null("WaterGateHint") == null, "M15 shows fire coverage from the cannons themselves")

	if weapon != null:
		weapon.set_process(false)
		var pivot: Vector2 = weapon.get_node("Turret0").global_position
		_expect(player.combat.hitbox(ShipParts.Part.CANNON).has_point(pivot) and pivot.x > player.position.x,
			"The cannon pivot is within the shared hitbox at the bow")
		_expect(weapon.angle_min == 0.0 and weapon.angle_max == 180.0, "The guns can aim over the full upper half-circle")
		_expect(is_equal_approx(Ballistics.angle_to_point(Vector2.ZERO, Vector2.LEFT), 180.0),
			"A horizontal target astern keeps the gun at 180 degrees")
		var can_answer_enemy_range := true
		for speed: float in weapon.config.shell_speed:
			can_answer_enemy_range = can_answer_enemy_range and not Projectile.velocity_for_speed(
				pivot, pivot + Vector2(400.0, 0.0), speed, weapon.config.gravity).is_zero_approx()
		_expect(can_answer_enemy_range, "Each type of ammunition can reach an enemy at 400 px")
		player.try_change_lane(1)
		weapon.turret_angle = 0.0
		var original_angle: float = weapon.turret_angle
		weapon._update_aim(1.0)
		_expect(player.is_switching() and not weapon.can_fire() and weapon.turret_angle != original_angle,
			"Transition keeps aiming and prevents firing")
		Input.action_press("move_right")
		var locked_x := player.position.x
		for tick in range(10):
			await physics_frame
		_expect(is_equal_approx(player.position.x, locked_x), "No horizontal motion while switching")
		for tick in range(32):
			await physics_frame
			if not player.is_switching():
				break
		Input.action_release("move_right")
		_expect(player.z_index == 15 and weapon.can_fire() and player.position.x > locked_x,
			"On the tick a lane change ends, both movement and firing are already unlocked")

		weapon.turret_angle = 22.0
		weapon._update_turret_sprites()
		weapon._update_preview()
		var preview: Line2D = weapon.get_node("Preview")
		var prediction := preview.to_global(preview.points[-1])
		var muzzle: Vector2 = weapon.muzzle_global(0)
		_expect(preview.to_global(preview.points[0]).distance_to(muzzle) < 0.01 and preview.z_index == player.z_index,
			"The preview starts at the displayed muzzle and stays beneath the lane water overlay")
		var start := player.position
		weapon.try_fire()
		var projectile: Projectile = battle.get_node("Projectiles").get_child(0)
		_expect(projectile.global_position.distance_to(muzzle) < 0.01 and absf(projectile.velocity.length() - weapon.config.shell_speed[0]) < 0.01,
			"The weapon enters the shared sweeper at the actual muzzle with the solid velocity")
		_expect(weapon.ammo[0] == 29 and player.position.x < start.x and player.position.y > start.y and player.lane_index == 1,
			"The shot spends ammo and translates the player in its current lane")
		var offset_x := player.position.x
		var splash_matched := false
		for tick in range(70):
			await physics_frame
			for splash in get_nodes_in_group("water_splash"):
				if splash.global_position.distance_to(prediction) < 1.0 and splash.z_index == 15:
					splash_matched = true
		_expect(splash_matched and not is_instance_valid(projectile), "Water catches the shell on the exact predicted lane line")
		_expect(player.position.y == start.y and player.position.x == offset_x, "Floating recovers while horizontal recoil persists")

		weapon.select_ammo(1)
		_expect(not weapon.can_fire() and weapon.switch_lock == 1.5, "Switching ammo locks both guns")
		weapon._update_reload(1.5)
		weapon.toggle_fire_mode()
		_expect((battle.get_node("HUD/Status") as Label).text.contains("齐射"), "The HUD displays the selected fire mode")
		weapon.try_fire()
		var volley: Array[Projectile] = []
		for shot in battle.get_node("Projectiles").get_children():
			if shot is Projectile and not shot.is_queued_for_deletion():
				volley.append(shot)
		_expect(volley.size() == 2 and weapon.ammo[1] == 18 and weapon.ammo[0] == 29,
			"Dual-gun volley spends only the selected ammo, once per gun")
		_expect(volley.size() == 2 and volley.all(func(shot): return shot.ammo == ShipParts.Ammo.ANTI_SAIL and absf(shot.velocity.length() - 680.0) < 0.01),
			"Both volley shells use the configured anti-sail speed and type")

	var foe: EnemyShip = battle.spawn_enemy(0)
	foe.position.x = 800.0
	var stacked: EnemyShip = battle.spawn_enemy(0)
	stacked.position.x = 800.0
	var other: EnemyShip = battle.spawn_enemy(1)
	other.position.x = 800.0
	var hull := foe.combat.aim_point()
	var explosive: Projectile = battle.launch_projectile(Vector2(800.0, hull.y), Vector2.LEFT * 300.0, 0,
		ShipCombat.Team.ALLY, 8.0, ShipParts.Ammo.EXPLOSIVE)
	explosive._physics_process(0.04)
	_expect(explosive.is_queued_for_deletion() and foe.combat.parts.hp(ShipParts.Part.SAIL) < 30.0
		and other.combat.parts.hp(ShipParts.Part.SAIL) == 30.0,
		"An explosive hit damages nearby parts only in its own lane")
	_expect(foe.position.x > 800.0 and stacked.position.x < 800.0 and other.position.x == 800.0,
		"A centered blast pushes overlapping enemies apart and leaves the next lane alone")
	var sail_overlay: Sprite2D = foe.combat.get_node_or_null("Sprite2D/SailOverlay")
	foe.combat.receive_hit(ShipParts.Part.SAIL, ShipParts.Ammo.ANTI_SAIL, 40.0)
	_expect(sail_overlay != null and sail_overlay.visible, "The E-01 keeps the collaborator's damaged sail art")

	var player_hull := player.combat.parts.hp(ShipParts.Part.HULL)
	player.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 60.0)
	var damaged_hull := player.combat.parts.hp(ShipParts.Part.HULL)
	player._update_repair(1.0)
	_expect(player_hull - damaged_hull == 60.0 and player.combat.parts.hp(ShipParts.Part.HULL) > damaged_hull,
		"Hostile damage and player repairs use the same part HP")

	var notices: Array[String] = []
	battle.boarding_nearby.connect(func(enemy_name: String): notices.append(enemy_name))
	foe.position.x = player.position.x
	stacked.position.x = player.position.x
	_expect(player.try_change_lane(0), "The player may switch into two overlapping enemy ships")
	battle._check_boarding(0.0)
	_expect(notices.is_empty(), "Boarding waits until the lane change is complete")
	for tick in range(90):
		if not player.is_switching():
			break
		await physics_frame
	battle._check_boarding(0.0)
	battle._check_boarding(2.0)
	_expect(notices == ["倭船"], "Continuous contact with overlapping ships emits a single boarding notice")
	foe.position.x += 200.0
	battle._check_boarding(2.0)
	_expect(notices.size() == 1, "Leaving one ship behind does not re-trigger while another is still alongside")
	stacked.position.x += 200.0
	battle._check_boarding(0.0)
	foe.position.x = player.position.x
	battle._check_boarding(0.0)
	_expect(notices.size() == 2, "A new approach can notify again after separation")

	battle.turret_lanes.assign([0, 1, 3, 4, 2, 2, 1, 3])
	battle.build_turrets()
	slots = battle._turrets.map(func(turret): return turret.lane_index)
	_expect(slots == [0, 1, 3, 4, 2, 1], "Upgrades permit one water-gate cannon and at most six total")

	battle.kills_to_win = 1
	var first: EnemyShip = battle.spawn_enemy(4)
	first.position.x = 700.0
	var second: EnemyShip = battle.spawn_enemy(4)
	second.position.x = 844.0
	for ship in [first, second]:
		ship.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 37.0)
	var sunk_events: Array[EnemyShip] = []
	battle.enemy_sunk.connect(func(enemy: EnemyShip): sunk_events.append(enemy))
	var entry := Vector2(772.0, lanes.lane_bottom_y(4) - 2.0)
	var blast: Projectile = battle.launch_projectile(entry, Vector2.DOWN * 250.0, 4,
		ShipCombat.Team.ALLY, 8.0, ShipParts.Ammo.EXPLOSIVE)
	blast._physics_process(0.04)
	_expect(not first.combat.targetable and not second.combat.targetable and battle.kills == 2 and sunk_events.size() == 2,
		"All sinks from the winning blast are counted and emit events")
	await process_frame
	_expect(battle.is_over, "The completed blast triggers victory")

	print("Merged battle checks: %d/%d passed" % [_checks - _failed, _checks])
	quit(_failed)


func _test_fortress_integration() -> void:
	var battle = load("res://Scenes/battle.tscn").instantiate()
	battle.first_spawn_delay = 9999.0
	root.add_child(battle)
	current_scene = battle
	var player: PlayerShip = battle.get_node("PlayerShip")
	var weapon = player.get_node("Combat/Weapon")
	var fortress: Sprite2D = battle.get_node_or_null("Fortress/FortVisual")
	_expect(fortress != null and fortress.texture.resource_path.ends_with("fort_intact.png"),
		"The normal battle scene uses the imported fortress art")
	_expect(player.position.x < 60.0 and not weapon.can_fire(), "The first ship sails out through the water gate")
	if fortress == null:
		current_scene = null
		battle.free()
		return

	await create_timer(battle.gate_launch_time + 0.08).timeout
	var tiers: Array[int] = []
	battle.on_fort_damaged_tier.connect(func(tier: int): tiers.append(tier))
	var start_light: int = battle.lamp_value
	battle._on_fortress_hit(160.0)
	_expect(fortress.texture.resource_path.ends_with("fort_damaged.png") and battle.lamp_value == start_light - 8,
		"The 60 percent tier updates art and light immediately")
	battle.fortress_hp += 10.0
	battle._on_fortress_hit(10.0)
	battle._on_fortress_hit(140.0)
	_expect(tiers == [1, 2] and fortress.texture.resource_path.ends_with("fort_broken.png")
		and battle.lamp_value == start_light - 20, "The 25 percent tier charges once, even across a repeated crossing")

	var ammo: Array[int] = weapon.ammo.duplicate()
	weapon.try_fire()
	player.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 100.0)
	_expect(not battle.is_over and not player.combat.targetable, "Sinking leaves the battle running")
	await create_timer(battle.player_respawn_delay + 0.05).timeout
	_expect(player.lane_index == battle.water_gate_lane and player.position.x < 60.0 and not weapon.can_fire(),
		"A sunk player respawns inside the gate and sails out before it can fire")
	await create_timer(battle.gate_launch_time).timeout
	_expect(player.combat.targetable and weapon.ammo[0] == ammo[0] - 1,
		"Leaving the gate restores the ship and preserves its spent ammunition")

	var farther: EnemyShip = battle.spawn_enemy(0)
	farther.position.x = 320.0
	var nearer: EnemyShip = battle.spawn_enemy(2)
	nearer.position.x = 345.0
	nearer.action = EnemyShip.Action.FLEE
	var finished: Array[bool] = []
	battle.on_battle_finished.connect(func(won: bool, _breach: bool): finished.append(won))
	battle.end_delay = 0.0
	battle._on_fortress_hit(100.0)
	_expect(battle.is_over and not weapon.can_fire() and fortress.texture.resource_path.ends_with("fort_gone.png"),
		"A breach immediately reveals the open gate and locks player controls")
	_expect(finished.is_empty() and tiers == [1, 2, 3], "Defeat is recorded after the entrance, with the breach tier charged once")
	battle._on_fortress_hit(100.0)
	await create_timer(battle.gate_breach_time * 0.6).timeout
	_expect(nearer.position.x < 345.0 and farther.position.x == 320.0,
		"The enemy closest to the water gate sails in, even if another enemy has a smaller X")
	await create_timer(battle.gate_breach_time + 0.2).timeout
	_expect(finished == [false] and current_scene.scene_file_path.ends_with("/management.tscn"),
		"Gate entry submits one defeat and opens the real management scene")
	var rest := current_scene
	var session = rest.get("_session")
	if session != null:
		var state: Dictionary = session.get_state()
		var delta: Dictionary = session.get_ledger()[0].battle_delta
		_expect(state.defeats_left == 1 and state.fort_hp == 0 and delta.ammo.round == -1,
			"Management receives the actual fortress HP, stock, and remaining defeats")
		_expect(session.select("regular", "rest"), "The management transition keeps the rest session usable")
		rest._depart()
		await process_frame
		await process_frame
		_expect(current_scene.scene_file_path.ends_with("/battle.tscn") and current_scene.defeats_left == 1,
			"The gong starts a new real battle with the same defeat allowance")
		_expect(current_scene.fortress_hp > 0.0 and current_scene.fortress_hp < 400.0,
			"The next battle receives the repaired fortress HP")
	if current_scene != null:
		current_scene.free()
		current_scene = null


func _test_fortress_fire_and_ending() -> void:
	var battle = load("res://Scenes/battle.tscn").instantiate()
	battle.difficulty = "hard"
	battle.gate_launch_time = 0.0
	battle.gate_breach_time = 0.1
	battle.first_spawn_delay = 9999.0
	root.add_child(battle)
	current_scene = battle
	battle.set_physics_process(false)
	var player: PlayerShip = battle.get_node("PlayerShip")
	player.sail_from_gate(0, 350.0, 350.0, 0.0)
	var nearer: EnemyShip = battle.spawn_enemy(0)
	nearer.position.x = 380.0
	var farther: EnemyShip = battle.spawn_enemy(0)
	farther.position.x = 450.0
	var gate_enemy: EnemyShip = battle.spawn_enemy(2)
	gate_enemy.position.x = 380.0
	battle._update_turrets(4.0)
	var projectiles := battle.get_node("Projectiles") as Node2D
	_expect(projectiles.get_child_count() == 1, "The installed cannon fires only into its own lane")
	if projectiles.get_child_count() == 1:
		var shell: Projectile = projectiles.get_child(0)
		_expect(shell.arc_gravity == 0.0 and shell.lane_index == 0, "The fortress fires a straight shell in its own lane")
		shell._physics_process(0.4)
		_expect(nearer.combat.parts.hp(ShipParts.Part.HULL) < 40.0 and farther.combat.parts.hp(ShipParts.Part.HULL) == 40.0
			and player.combat.parts.hp(ShipParts.Part.HULL) == 100.0 and gate_enemy.combat.parts.hp(ShipParts.Part.HULL) == 40.0,
			"Fortress fire hits the foremost enemy and passes through the allied ship")
	var ending := [0]
	battle.ending_reached.connect(func(): ending[0] += 1)
	battle._on_fortress_hit(400.0)
	await create_timer(0.45).timeout
	_expect(battle.defeats_left == 0 and ending[0] == 1 and current_scene == battle,
		"A last defeat emits the ending hook once and keeps the terminal view")
	current_scene = null
	battle.free()


func _test_next_battle_upgrades() -> void:
	var session := ManagementSession.new("easy")
	for upgrade in ["upgrade_fort", "upgrade_ship", "skip"]:
		var start := session.retry_battle()
		_expect(session.enter_rest({
			"battle_id": start.battle_id, "won": true, "light": start.light,
			"defeats_left": start.defeats_left, "ammo": start.ammo, "ship_hp": start.ship_hp, "fort_hp": start.fort_hp,
		}), "The upgrade fixture settles a real management order")
		session.select("regular", "trade")
		session.select("upgrade", upgrade)
		if session.start_battle().is_empty():
			_expect(false, "The next battle accepts an affordable upgrade order")
			return

	var battle = load("res://Scenes/battle.tscn").instantiate()
	battle.management_session = session
	battle.gate_launch_time = 0.0
	root.add_child(battle)
	var player: PlayerShip = battle.get_node("PlayerShip")
	_expect(battle.fortress_hp_cap == 480.0 and battle.turret_lanes.has(battle.water_gate_lane),
		"A fortress upgrade adds durability and a cannon in the water-gate lane")
	_expect(player.combat.parts.max_hp(ShipParts.Part.HULL) == 110.0,
		"A ship upgrade increases durability in actual combat")
	battle._on_fortress_hit(40.0)
	player.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 8.0)
	var result: Dictionary = battle._build_result(true)
	_expect(result.ship_hp.hull == 102 and result.fort_hp == 110,
		"Returning a battle result preserves the units used for upgraded durability")
	battle.free()


func _test_nested_fort_hits() -> void:
	var battle = load("res://Scenes/battle.tscn").instantiate()
	battle.gate_launch_time = 0.0
	root.add_child(battle)
	var finish_count := [0]
	battle.on_battle_finished.connect(func(_won: bool, _breach: bool): finish_count[0] += 1)
	battle.on_fort_damaged_tier.connect(func(tier: int):
		if tier == 1:
			battle._on_fortress_hit(90.0)
	)
	battle._on_fortress_hit(310.0)
	_expect(finish_count[0] == 1 and battle.management_session.get_state().light == 15,
		"Synchronous damage from a tier listener cannot duplicate the loss or omit a light penalty")
	battle.free()
