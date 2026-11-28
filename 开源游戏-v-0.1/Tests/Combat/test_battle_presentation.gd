extends SceneTree

const BATTLE := preload("res://Scenes/battle.tscn")
const FAST := preload("res://Data/Combat/enemy_fast.tres")
const HEAVY := preload("res://Data/Combat/enemy_heavy.tres")

var _checks := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var battle = BATTLE.instantiate()
	battle.gate_launch_time = 0.0
	battle.spawn_interval_range = Vector2(9999.0, 9999.0)
	root.add_child(battle)
	battle.set_physics_process(false)
	var sea = battle.get_node_or_null("Lanes/SeaSurface")
	var tower = battle.get_node_or_null("Fortress/Watchtower")
	_check(sea != null, "M9 is installed in the normal battle scene")
	_check(tower != null, "M11 is installed under the fortress")
	if sea != null:
		await _test_water(battle, sea)
	if tower != null:
		await _test_watchtower(battle, tower)
	battle.free()
	print("Battle presentation checks: %d/%d passed" % [_checks - _failed, _checks])
	quit(0 if _failed == 0 else 1)


func _test_water(battle: Node, sea: Node) -> void:
	var player := battle.get_node("PlayerShip") as PlayerShip
	var lanes := battle.get_node("Lanes") as Lanes
	var weapon := player.get_node("Combat/Weapon") as PlayerWeapon
	weapon.set_process(false)
	var muzzle := weapon.muzzle_global()
	var bounds := player.combat.hitbox(ShipParts.Part.HULL)
	var position_before := player.global_position
	var far: float = sea.surface_y(0, 600.0)
	var near: float = sea.surface_y(4, 600.0)
	sea._process(0.3)
	_check(not is_equal_approx(sea.surface_y(0, 600.0) - far, sea.surface_y(4, 600.0) - near),
		"Lane wave motion differs with depth and phase")
	_check(player.global_position == position_before and player.combat.hitbox(ShipParts.Part.HULL) == bounds
		and weapon.muzzle_global() == muzzle, "M9 leaves the logical anchor, hitbox and firing origin fixed")
	var lane := player.lane_index
	var base := lanes.lane_bottom_y(lane)
	var before_pressure: float = sea.surface_y(lane, 600.0)
	player.position.x = 600.0
	sea._process(0.0)
	var under_ship: float = sea.surface_y(lane, 600.0)
	_check(absf(under_ship - base) < absf(before_pressure - base),
		"The hull locally reduces the swell on its active lane")
	player.global_position = position_before
	sea._process(0.0)
	var weather := EnemySpawner.LEVELS[4]
	sea.set_weather(weather.wave_amplitude_scale(), weather.wave_speed_scale())
	sea._process(0.0)
	_check(is_equal_approx(1.8 * absf(before_pressure - base), absf(sea.surface_y(lane, 600.0) - base)),
		"Level five's storm height scale increases the wave")
	var old_clock: float = sea._clock
	sea._process(0.25)
	_check(is_equal_approx(sea._clock - old_clock, 0.25 * weather.wave_speed_scale()),
		"Level five also advances the wave faster")
	sea.set_weather(1.0, 1.0)
	for index in range(36):
		lanes.splash_at(lane, 600.0)
	sea._process(0.1)
	_check(absf(sea.surface_y(lane, 600.0) - base) < 12.0, "Repeated impacts clamp wave disturbance")
	var snapshot: float = sea.surface_y(player.lane_index, 375.0)
	paused = true
	await create_timer(0.1, true, false, true).timeout
	_check(sea.surface_y(player.lane_index, 375.0) == snapshot, "A tree pause freezes the water")
	paused = false
	sea.waves_enabled = false
	sea._process(0.1)
	_check(is_equal_approx(sea.surface_y(player.lane_index, 375.0), lanes.lane_bottom_y(player.lane_index)),
		"The wave comparison switch leaves a flat water surface")
	sea.waves_enabled = true
	_test_reflections(battle, sea, lane, base)
	_test_lane_change_reflection(player, lanes, sea)
	_test_wave_detail(sea, lanes)
	_test_spray_pool(sea, lane, base)


func _test_reflections(battle: Node, sea: Node, lane: int, water_y: float) -> void:
	var ball: Projectile = battle.launch_projectile(Vector2(660.0, water_y - 14.0), Vector2.RIGHT, lane,
		ShipCombat.Team.ALLY, 1.0, ShipParts.Ammo.SOLID, 0.0)
	var arrow: Projectile = battle.launch_projectile(Vector2(690.0, water_y - 14.0), Vector2.LEFT, lane,
		ShipCombat.Team.ENEMY, 1.0, ShipParts.Ammo.SOLID, 0.0, Projectile.Visual.ARROW)
	var shot_id := ball.get_node("Sprite2D").get_instance_id()
	var arrow_id := arrow.get_node("Sprite2D").get_instance_id()
	sea._process(0.0)
	var mirror: Sprite2D = sea._sources[shot_id].mirror
	_check(mirror.visible and mirror.z_index == ball.z_index + 2 and not sea._sources.has(arrow_id),
		"Cannonballs are reflected above the cover and arrows are excluded")
	sea.reflections_enabled = false
	sea._process(0.0)
	_check(not mirror.visible, "One switch hides the current reflections")
	ball.free()
	arrow.free()
	_check(not sea._sources.has(shot_id), "Spent shots release their reflection registration")
	sea.reflections_enabled = true


func _test_lane_change_reflection(player: PlayerShip, lanes: Lanes, sea: SeaSurface) -> void:
	var position_before := player.position
	player.position.x = 500.0
	sea._process(0.0)
	var art := player.combat.visual_sprite()
	var mirror: Sprite2D = sea._sources[art.get_instance_id()].mirror
	var starting_lane := player.lane_index
	for destination in [starting_lane - 1, starting_lane]:
		var source_lane := player.lane_index
		_check(player.try_change_lane(destination), "The player begins a real lane change")
		var continuous := true
		var aligned := true
		for frame in range(41):
			if frame > 0:
				player._physics_process(player.lane_switch_time / 40.0)
			sea._process(0.0)
			var mix_amount := clampf(inverse_lerp(lanes.lane_bottom_y(source_lane),
				lanes.lane_bottom_y(destination), player.position.y), 0.0, 1.0)
			var art_origin := sea.to_local(art.global_position)
			var expected_plane := lerpf(sea.surface_y(source_lane, art_origin.x),
				sea.surface_y(destination, art_origin.x), mix_amount)
			continuous = continuous and mirror.visible
			aligned = aligned and absf(0.5 * (mirror.position.y + art_origin.y) - expected_plane) < 0.01
		_check(continuous and aligned, "The mirror stays visible at the interpolated surface on every switch frame")
	player.position = position_before


func _test_wave_detail(sea: SeaSurface, lanes: Lanes) -> void:
	var horizon := sea.get_node("WaterLayers/WaterBand0") as Polygon2D
	var near_water := sea.get_node("WaterLayers/WaterBand4") as Polygon2D
	var material := horizon.material as ShaderMaterial
	_check(material != null and near_water.material == material,
		"The same water material carries ripples from the horizon to the near lanes")
	if material == null:
		return
	var before: float = material.get_shader_parameter(&"water_clock")
	var tint := Color(0.74, 0.85, 1.0)
	sea.set_weather(1.8, 1.28, tint)
	sea.reflections_enabled = false
	sea._process(0.25)
	var after: float = material.get_shader_parameter(&"water_clock")
	_check(is_equal_approx(after - before, 0.32) and material.get_shader_parameter(&"detail_tint") == tint,
		"Surface details use the weather clock and tint even with reflections disabled")
	var row_count := sea._profile_image.get_height()
	var last_sample := sea._profile_image.get_width() - 1
	var middle := floori(last_sample * 0.5)
	var x := lerpf(lanes.sea_left, lanes.sea_right, float(middle) / last_sample)
	var profile_y := sea._profile_image.get_pixel(middle, 3).r
	_check(row_count == lanes.lane_count + 1 and is_equal_approx(profile_y, sea.to_global(Vector2(x, sea.surface_y(2, x))).y),
		"The surface detail profile follows the actual waterline with reflections disabled")
	sea.waves_enabled = false
	sea._process(0.25)
	_check(is_zero_approx(material.get_shader_parameter(&"detail_amount")),
		"Disabling waves hides the animated surface details")
	sea.set_weather(1.0, 1.0)
	sea.waves_enabled = true
	sea.reflections_enabled = true
	sea._process(0.0)


func _test_spray_pool(sea: Node, lane: int, water_y: float) -> void:
	var spray = sea.get_node("WaterLayers/Spray%d" % lane)
	var height := func(x: float) -> float: return sea.surface_y(lane, x)
	var splashed := false
	spray.debris(Vector2(500.0, water_y - 16.0), ShipParts.Part.HULL)
	for frame in range(20):
		spray.advance(0.05, height)
		splashed = splashed or spray._drops.any(func(drop): return drop.spray and drop.life > 0.0)
	_check(splashed, "Falling fragments are replaced with spray when they reach the wave")
	var pool_size: int = spray._drops.size()
	for tick in range(300):
		spray.debris(Vector2(500.0, water_y - 20.0), ShipParts.Part.SAIL)
		spray.splash(Vector2(500.0, water_y), 8)
		spray.advance(0.1, height)
	_check(spray._drops.size() == pool_size, "A thirty-second barrage does not grow the spray pool")


func _test_watchtower(battle: Node, tower: Node) -> void:
	_check(not tower.visible, "An empty sea has no watchtower marker")
	var heavy: EnemyShip = battle.spawn_enemy(0, HEAVY, 725.0)
	var fast: EnemyShip = battle.spawn_enemy(1, FAST, 690.0)
	heavy.horizontal_speed = -10.0
	fast.horizontal_speed = 0.0
	await physics_frame
	await process_frame
	_check(tower.target == fast and tower.target_part == ShipParts.Part.SAIL,
		"The closest ship is marked even when a farther ship has higher horizontal speed")
	heavy.position.x = 670.0
	tower.refresh_target()
	_check(tower.target == fast, "A valid target keeps its lock when another ship comes closer")
	var hull := ShipParts.Part.HULL
	var before := fast.combat.parts.hp(hull)
	var hull_box := fast.combat.hitbox(hull)
	var combat_config := battle.get_node("CombatConfig") as CombatConfig
	combat_config.shell_damage[0] = 8.0
	battle._on_player_shot(Vector2(hull_box.position.x - 12.0, hull_box.get_center().y),
		Vector2.RIGHT * 400.0, fast.lane_index, ShipParts.Ammo.SOLID)
	var shell := battle.get_node("Projectiles").get_child(-1) as Projectile
	shell._physics_process(0.08)
	_check(is_equal_approx(before - fast.combat.parts.hp(hull), 1.5 * combat_config.shell_damage[0]),
		"The player's projectile gets 50 percent more hull damage while the sail is marked")
	fast.combat.receive_hit(ShipParts.Part.SAIL, ShipParts.Ammo.ANTI_SAIL, 100.0)
	await process_frame
	await process_frame
	_check(tower.target == fast and tower.marker_color == Color.BLACK,
		"The destroyed sail turns the marker black without breaking the lock")
	var player := battle.get_node("PlayerShip") as PlayerShip
	player.position.x = 960.0
	var boarder: EnemyShip = battle.spawn_enemy(player.lane_index, null, player.position.x)
	boarder.horizontal_speed = 0.0
	var boarding := battle.get_node("Boarding") as BoardingFight
	_check(boarding.try_engage(boarder, 0.0, false), "The ordinary boarding entry connects to the watchtower")
	var mark: Transform2D = tower.global_transform
	var wave_clock: float = battle.get_node("Lanes").sea._clock
	fast.global_position.x += 40.0
	fast.combat.receive_hit(hull, ShipParts.Ammo.SOLID, 100.0)
	await create_timer(0.12, true, false, true).timeout
	_check(tower.target == fast and tower.global_transform == mark, "A boarding lock holds its last visual pose")
	var wave_elapsed: float = battle.get_node("Lanes").sea._clock - wave_clock
	_check(wave_elapsed > 0.0 and wave_elapsed < 0.025 and boarding.get_node("Interface/Overlay").visible,
		"The wave slows with the world while the boarding interface is active")
	boarding.cancel()
	_check(tower.target == heavy and tower.target_part == ShipParts.Part.CANNON,
		"Finishing boarding immediately marks the remaining ship's weapons")
	heavy.position.x = 320.0
	var unmarked: EnemyShip = battle.spawn_enemy(1, HEAVY, 320.0)
	var heavy_hp := heavy.combat.parts.hp(hull)
	var unmarked_hp := unmarked.combat.parts.hp(hull)
	battle._turret_timers.fill(0.0)
	battle._update_turrets(0.0)
	var fort_shots := 0
	for child in battle.get_node("Projectiles").get_children():
		var fort_shell := child as Projectile
		if fort_shell != null and not fort_shell.is_queued_for_deletion():
			fort_shots += 1
			fort_shell._physics_process(2.0)
	_check(fort_shots == 2, "The automated fortress fires at both heavy ships")
	var normal_damage := unmarked_hp - unmarked.combat.parts.hp(hull)
	_check(normal_damage > 0.0 and is_equal_approx(heavy_hp - heavy.combat.parts.hp(hull), normal_damage * 1.5),
		"The fortress projectile applies the same damage multiplier")
	unmarked.free()
	battle.fortress_hp = 0.0
	battle.get_node("Fortress").show_damage(3)
	heavy.global_position.x = 1341.0
	heavy.step(2.0, player.combat, 60.0, false, 0.01)
	await physics_frame
	await process_frame
	_check(tower.target == boarder and tower.visible, "The tower retargets after retreat even at a ruined fortress")
	boarder.free()
	await physics_frame
	await process_frame
	_check(tower.target == null and not tower.visible, "The marker hides when the last target leaves the tree")


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL ", message)
