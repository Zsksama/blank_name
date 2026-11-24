extends SceneTree

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
	var battle = load("res://Scenes/battle.tscn").instantiate()
	battle.first_spawn_delay = 9999.0
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
		_expect(player.combat.hitbox(ShipParts.Part.CANNON).has_point(weapon.get_node("Turret0").global_position),
			"The cannon pivot is within the shared cannon hitbox")
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
		var start := player.position
		weapon.try_fire()
		var projectile: Projectile = battle.get_node("Projectiles").get_child(0)
		_expect(projectile.global_position.distance_to(muzzle) < 0.01 and absf(projectile.velocity.length() - 520.0) < 0.01,
			"The weapon enters the shared sweeper at the actual muzzle with the solid velocity")
		_expect(weapon.ammo[0] == 29 and player.position.x < start.x and player.position.y > start.y and player.lane_index == 1,
			"The shot spends ammo and translates the player in its current lane")
		var offset_x := player.position.x
		var splash_matched := false
		for tick in range(62):
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
	var other: EnemyShip = battle.spawn_enemy(1)
	other.position.x = 800.0
	var hull := foe.combat.aim_point()
	var explosive: Projectile = battle.launch_projectile(hull + Vector2(8, 0), Vector2.LEFT * 300.0, 0,
		ShipCombat.Team.ALLY, 8.0, ShipParts.Ammo.EXPLOSIVE)
	explosive._physics_process(0.04)
	_expect(explosive.is_queued_for_deletion() and foe.combat.parts.hp(ShipParts.Part.SAIL) < 30.0
		and other.combat.parts.hp(ShipParts.Part.SAIL) == 30.0,
		"An explosive hit damages nearby parts only in its own lane")
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
	# At the legal 144 px center spacing, the hull edges can approach within 60 px.
	other.position.x = player.position.x + other.config.min_gap
	var player_x := player.position.x
	battle._check_boarding(0.0)
	battle._check_boarding(0.8)
	_expect(notices == ["倭船"] and player.position.x == player_x, "Boarding can be signaled at legal spacing without moving either ship")
	other.position.x += 100.0
	battle._check_boarding(0.3)
	_expect(notices.size() == 1, "Leaving boarding range cancels further notices")

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
