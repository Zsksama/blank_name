extends SceneTree

const BATTLE := preload("res://Scenes/battle.tscn")
const SHELL_COUNT := 40
const WARMUP_SECONDS := 3.0
const SAMPLE_SECONDS := 8.0

var _battle: Node2D
var _lanes: Lanes
var _shells: Node2D
var _serial := 0
var _box_count := 0
var _physics_ms: Array[float] = []
var _sample_physics := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 60
	_battle = BATTLE.instantiate()
	var config: EnemyShipConfig = _battle.enemy_config.duplicate()
	config.attack_range = 0.0
	_battle.enemy_config = config
	_battle.spawn_interval_range = Vector2(3600.0, 3600.0)
	_battle.turret_fire_range = 0.0
	root.add_child(_battle)
	current_scene = _battle
	_lanes = _battle.get_node("Lanes")
	_shells = _battle.get_node("Projectiles")
	_box_count = _battle.get_node("PlayerShip/Combat/Hitboxes").get_child_count()
	for index in range(9):
		var ship: EnemyShip = _battle.spawn_enemy(index % 5)
		ship.position.x = 640.0 if index < 5 else 930.0
		_box_count += ship.get_node("Combat/Hitboxes").get_child_count()
	physics_frame.connect(_fill_shells)

	await create_timer(WARMUP_SECONDS).timeout
	var started := Time.get_ticks_usec()
	var frame_times: Array[float] = []
	var seconds := 0.0
	var last := started
	_sample_physics = true
	while seconds < SAMPLE_SECONDS:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_times.append(float(now - last) / 1000.0)
		seconds = float(now - started) / 1_000_000.0
		last = now
	var viewport := root.get_visible_rect().size
	print("Enemy stress: %dx%d, 10 ships, %d hitboxes, %d shells per physics tick" % [
		int(viewport.x), int(viewport.y), _box_count, SHELL_COUNT,
	])
	print("Enemy stress: %.2f FPS, frame p95 %.2f ms, physics p95 %.2f ms (%d ticks)" % [
		float(frame_times.size()) / seconds, _p95(frame_times), _p95(_physics_ms), _physics_ms.size(),
	])
	quit()


func _fill_shells() -> void:
	if _sample_physics:
		_physics_ms.append(1000.0 * Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
	var live := 0
	for child in _shells.get_children():
		if child is Projectile and not child.is_queued_for_deletion():
			live += 1
	for _index in range(live, SHELL_COUNT):
		var lane := _serial % 5
		var y := _lanes.lane_center_y(lane)
		var from := Vector2(330.0 + float(_serial % 7) * 33.0, y)
		var to := Vector2(680.0 + float(_serial % 17) * 24.0, y + float(_serial % 9) - 4.0)
		var gravity: float = _battle.get_node("CombatConfig").gravity
		var velocity := Projectile.velocity_for_time(from, to, 0.45 + 0.08 * float(_serial % 4), gravity)
		_battle.launch_projectile(from, velocity, lane, ShipCombat.Team.ALLY, 0.0)
		_serial += 1


func _p95(samples: Array[float]) -> float:
	samples.sort()
	return samples[ceili(samples.size() * 0.95) - 1]
