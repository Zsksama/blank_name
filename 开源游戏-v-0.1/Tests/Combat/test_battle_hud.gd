extends SceneTree

const BATTLE := preload("res://Scenes/battle.tscn")

var _checks := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL ", message)


func _battle(storm := false) -> Node2D:
	var battle := BATTLE.instantiate()
	battle.gate_launch_time = 0.0
	battle.spawn_interval_range = Vector2(9999, 9999)
	if storm:
		var storm_levels: Array[EnemySpawnLevel] = [EnemySpawner.LEVELS[4]]
		battle.spawn_levels = storm_levels
	root.add_child(battle)
	battle.set_physics_process(false)
	return battle


func _run() -> void:
	var battle := _battle()
	var player: PlayerShip = battle.get_node("PlayerShip")
	var lanes: Lanes = battle.get_node("Lanes")
	var hud := battle.get_node("HUD")
	var ammunition := hud.get_node_or_null("AmmoAndParts/Ammo")
	_check(ammunition != null and hud.has_node("Lamp") and hud.has_node("ReloadRing"),
		"The battle starts with the new anchored HUD")
	if ammunition != null:
		await process_frame
		await _test_hud(battle, player, ammunition)

	player.lock_controls()
	player._set_gate_lane(0)
	player.position.x = 430.0
	var hull_width := player.combat.size.x
	player.sail_back_to_gate(battle.water_gate_lane, battle._gate_approach(hull_width),
		battle._gate_passage(), battle._gate_berth(hull_width), 0.8)
	for tick in range(8):
		await physics_frame
	_check(player.position.y > lanes.lane_bottom_y(0) and player.z_index >= lanes.content_z(2),
		"The upper-lane return ship draws above the intervening water")
	for tick in range(22):
		await physics_frame
	_check(player.lane_index == 2 and player.z_index == lanes.content_z(2),
		"The returning player restores the destination lane layer")
	for tick in range(21):
		await physics_frame
	_check(player.global_position.is_equal_approx(battle._gate_berth(hull_width)),
		"The returning player finishes inside the reference gate while the keel meets the sill")

	var ship: EnemyShip = battle.spawn_enemy(0, null, 500.0)
	ship.combat.receive_hit(ShipParts.Part.HULL, ShipParts.Ammo.SOLID, 12.0)
	var floats := lanes.get_children().filter(func(child): return child is Label and child.text == "-12")
	_check(floats.size() == 1, "A regular shell shows the resolved hull damage once")
	var sky := battle.get_node_or_null("DaySky") as TextureRect
	_check(sky != null and sky.visible and sky.size.is_equal_approx(Vector2(root.get_visible_rect().size.x, 144.0)),
		"Clear daytime draws the new sky across the playable width")
	_check(battle.has_node("Rain") and not battle.get_node("Rain").visible, "Clear daytime has no rain")
	battle.free()

	battle = _battle()
	_test_morale(battle)
	battle.free()

	battle = _battle(true)
	_check(battle.has_node("Rain") and battle.get_node("Rain").visible, "The storm level starts with rain")
	if battle.has_node("Rain"):
		battle.rain_enabled = false
		_check(not battle.get_node("Rain").visible, "The rain switch takes effect in the active level")
	battle.free()
	print("Battle HUD checks: %d/%d passed" % [_checks - _failed, _checks])
	quit(int(_failed > 0))


func _test_hud(battle: Node2D, player: PlayerShip, ammunition: Node) -> void:
	var hud = battle.get_node("HUD")
	var weapon: PlayerWeapon = player.get_node("Combat/Weapon")
	var first := ammunition.get_node("Ammo1") as Button
	var second := ammunition.get_node("Ammo2") as Button
	var third := ammunition.get_node("Ammo3") as Button
	var ring = hud.get_node("ReloadRing")
	_check(ring.position.x > battle.get_node("Lanes").sea_left
		and ammunition.get_global_rect().position.x > battle.get_node("Lanes").sea_left,
		"The ammunition and reloading controls leave the whole fortress visible")
	_check(first.text.contains(str(weapon.ammo[0])) and first.button_pressed, "Selected ammo has a count and highlight")
	var original_ammo := weapon.ammo.duplicate()
	await _click(second.get_global_rect().get_center())
	_check(weapon.ammo_selected == 1 and ring.weapon.ammo_selected == 1 and second.button_pressed,
		"The upper and lower ammo controls share the selected weapon slot")
	await _click(ring.get_global_rect().get_center() + Vector2(-17, -11))
	_check(weapon.ammo_selected == 0 and first.button_pressed, "A lower ammo control updates the upper capsules")
	_check(weapon.ammo == original_ammo, "Clicking ammo controls never fires the cannons")
	weapon._update_reload(2.0)
	await _click(Vector2(814.0, 250.0))
	_check(weapon.ammo[0] == original_ammo[0] - 1, "A separate click on water still fires the cannon")
	weapon.ammo[2] = 0
	weapon.state_changed.emit()
	await _click(third.get_global_rect().get_center())
	_check(weapon.ammo_selected == 0 and hud.get_node("AmmoAndParts/EmptyMessage").visible
		and hud.get_node("EmptyClick").stream != null, "An empty ammo click shows the feedback without switching")

	var part_row := hud.get_node("AmmoAndParts/Parts")
	var part_labels := ["撞角", "火器与弓手", "舰体", "帆", "舵"]
	for index in range(part_labels.size()):
		_check(part_row.get_child(index).tooltip_text.begins_with(part_labels[index]), "Correct part order at slot %d" % index)
	var sail = part_row.get_child(3)
	var cap := player.combat.parts.max_hp(ShipParts.Part.SAIL)
	player.combat.parts.set_hp(ShipParts.Part.SAIL, cap * 0.75)
	var damaged: Color = sail.tint
	player.combat.parts.set_hp(ShipParts.Part.SAIL, cap * 0.10)
	_check(sail.tint != damaged and sail.tooltip_text.ends_with("10%"), "The sail shows the 75% and 10% transitions")

	battle.enemies_defeated = 8
	battle._refresh_status()
	_check(hud.get_node("EnemyCount").text == "敌人 8 / %d" % battle.enemy_total, "Enemy progress uses resolved enemies and the full roster")
	var lamp_y: float = hud.get_node("Lamp").position.y
	var ammo_y: float = hud.get_node("AmmoAndParts").position.y
	var reload_y: float = ring.position.y
	hud.set_boarding(true)
	await hud._boarding_tween.finished
	_check(hud.get_node("Lamp").position.y == lamp_y and hud.get_node("AmmoAndParts").position.y < ammo_y
		and ring.position.y < reload_y, "Boarding raises the combat controls while the lamp stays fixed")
	hud.set_boarding(false)

	var pause_button := hud.get_node("Pause") as Button
	await _click(pause_button.get_global_rect().get_center())
	_check(paused and hud.get_node("Grayscale/Screen").visible, "Pause freezes the battle and grays the screen")
	await _click(pause_button.get_global_rect().get_center())
	_check(not paused and not hud.get_node("Grayscale/Screen").visible, "The same control resumes the battle")


func _test_morale(battle: Node2D) -> void:
	var player: PlayerShip = battle.get_node("PlayerShip")
	var bar: ProgressBar = battle.get_node("HUD/Morale/Bar")
	var percent: Label = battle.get_node("HUD/Morale/Percent")
	var count: Label = battle.get_node("HUD/EnemyCount")
	battle.enemies_defeated = 8
	battle._refresh_status()
	battle._on_boarding_morale_changed(-25.0)
	_check(is_equal_approx(bar.value, battle.enemy_morale) and percent.text == "22%",
		"The morale HUD immediately reflects the boarding penalty")
	var sunk: EnemyShip = battle.spawn_enemy(0, null, 810.0)
	var survivor: EnemyShip = battle.spawn_enemy(1, null, 900.0)
	battle.morale_bias = 0.098 - float(battle.enemy_total - 9) / float(battle.enemy_total)
	sunk.combat.apply_raw_damage(ShipParts.Part.HULL, sunk.combat.parts.max_hp(ShipParts.Part.HULL))
	var before: float = battle.enemy_morale
	_check(before > 0.10 and is_equal_approx(bar.value, before),
		"A sinking applies the immediate morale penalty and leaves the rest to decay")
	player.combat.apply_raw_damage(ShipParts.Part.HULL, player.combat.parts.max_hp(ShipParts.Part.HULL))
	battle._physics_process(0.0)
	_check(not player.combat.targetable and survivor.action != EnemyShip.Action.FLEE
		and is_equal_approx(bar.value, before),
		"Player sinking does not trigger retreat while the displayed morale is above ten percent")
	battle._physics_process(2.0)
	_check(survivor.action == EnemyShip.Action.FLEE and is_equal_approx(bar.value, 0.098) and percent.text == "9%",
		"The continuous drop crosses the retreat threshold in the AI and in the displayed percent together")
	_check(count.text == "敌人 9 / %d" % battle.enemy_total, "Turning to flee does not change the resolved enemy count")


func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		# push_input dispatches GUI events without modifying Input's action polling state.
		if pressed:
			Input.action_press(&"fire")
		else:
			Input.action_release(&"fire")
		root.push_input(click, true)
		await physics_frame
		await process_frame
