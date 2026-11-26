extends Node2D

signal enemy_sunk(ship: EnemyShip)
signal enemy_retreated(ship: EnemyShip)
signal boarding_nearby(enemy_name: String)
signal boarding_contact_started(ship: EnemyShip)
signal on_fort_damaged_tier(tier: int)
signal on_battle_finished(won: bool, by_fort_breach: bool)
signal ending_reached
signal boarding_finished(result: int)
signal morale_changed(value: float)

const PROJECTILE_SCENE := preload("res://Scenes/projectile.tscn")
const ENEMY_SCENE := preload("res://Scenes/enemy_ship.tscn")
const TURRET_SCENE := preload("res://Scenes/turret.tscn")
const ManagementSession := preload("res://Scripts/Management/management_session.gd")
const ManagementRules := preload("res://Scripts/Management/management_rules.gd")
const AMMO_KEYS := ["round", "chain", "grape"]
const PART_KEYS := {
	ShipParts.Part.HULL: "hull", ShipParts.Part.SAIL: "rigging", ShipParts.Part.CANNON: "guns",
}
const FORT_LIGHT_LOSS := [8, 12, 25]
const MAX_TURRETS := 6

@export_group("胜利条件")
@export var kills_to_win: int = 12

@export_group("敌船")
@export var enemy_config: EnemyShipConfig = preload("res://Data/Combat/enemy_e01.tres")
@export var spawn_interval: float = 4.0
@export var first_spawn_delay: float = 1.5
@export var spawn_x: float = 1330.0

@export_group("碉堡")
@export var turret_lanes: Array[int] = [0, 1, 3, 4]
@export var water_gate_lane: int = 2
@export var turret_x: float = 37.5
@export var turret_scale: float = 0.5
@export var max_fortress_hp: int = 400
@export var turret_fire_interval: float = 3.0
@export var turret_fire_range: float = 400.0
@export var turret_shell_speed: float = 1400.0
@export var turret_damage: float = 6.0

@export_group("水门")
@export var gate_launch_time: float = 1.6
@export var gate_breach_time: float = 2.2
@export var player_respawn_delay: float = 3.0
@export var player_sunk_light_loss: int = 10

@export_group("接舷提示")
@export var boarding_distance: float = 10.0
@export var boarding_cooldown: float = 3.0
## 换道完成后的多少秒内贴上来，算“换道重叠”（走固定伤害而不是撞角公式）。
@export var lane_overlap_window: float = 0.35
## 正在换道时蹭上来的敌船，等双方落位后再结算（侧面接触，不磨撞角）。
var _pending_scrape: EnemyShip = null

@export_group("结算")
@export_enum("easy", "normal", "hard") var difficulty := "normal"
@export var end_delay: float = 3.0
@export var management_scene: String = "res://Scenes/Management/management.tscn"

@onready var _lanes: Lanes = $Lanes
@onready var _config: CombatConfig = $CombatConfig
@onready var _turret_root: Fortress = $Fortress
@onready var _player: PlayerShip = $PlayerShip
@onready var _weapon: PlayerWeapon = $PlayerShip/Combat/Weapon
@onready var _crosshair: Node2D = $Crosshair
@onready var _enemies: Node2D = $Enemies
@onready var _projectiles: Node2D = $Projectiles
@onready var _status: Label = $HUD/Status
@onready var _banner: Label = $HUD/Banner
@onready var _alert_label: Label = $HUD/Alert

var kills: int = 0
var fortress_hp: float = 0.0
var fortress_hp_cap: float = 0.0
var lamp_value: int = 0
var defeats_left: int = 0
var is_over: bool = false
var management_session: ManagementSession
var _victory_pending := false
var _settled := false
var _breach_started := false
var _battle_start: Dictionary
var _worst_fort_tier := 0
var _fort_attack_announced := false
var _fort_hit_announced := false
var _alert_tween: Tween

var _turrets: Array[Node2D] = []
var _turret_timers: Array[float] = []
var _spawn_timer := 0.0
var _boarding_left := 0.0
var _boarding_contact_active := false
var _boarding: BoardingFight
var _rng := RandomNumberGenerator.new()
## 敌军气焰（M14 占位，接舷胜负会改它）。
var morale := 0.0


func _ready() -> void:
	# 玩家先更新换道和移动，敌船再选目标，最后推进炮弹。
	process_physics_priority = 10
	_rng.randomize()
	_weapon.config = _config
	_weapon.shot_requested.connect(_on_player_shot)
	_weapon.state_changed.connect(_refresh_status)
	_player.sunk.connect(_on_player_sunk)
	_setup_boarding()
	water_gate_lane = _lanes.clamp_lane_index(water_gate_lane)
	_apply_battle_start()
	_player.combat.parts.part_changed.connect(_on_player_part_changed)
	_spawn_timer = first_spawn_delay
	_banner.text = ""
	_worst_fort_tier = fort_tier()
	_turret_root.show_damage(_worst_fort_tier)
	build_turrets()
	if fortress_hp <= 0.0:
		_start_gate_breach.call_deferred()
	else:
		_launch_player_from_gate()


func build_turrets() -> void:
	for turret in _turrets:
		_turret_root.remove_child(turret)
		turret.queue_free()
	_turrets.clear()
	_turret_timers.clear()

	var counts := PackedInt32Array()
	counts.resize(_lanes.lane_count)
	for lane in turret_lanes:
		if _turrets.size() >= MAX_TURRETS:
			break
		if lane < 0 or lane >= counts.size() or counts[lane] >= (1 if lane == water_gate_lane else 2):
			continue
		var turret: Node2D = TURRET_SCENE.instantiate()
		turret.lane_index = lane
		turret.position = Vector2(turret_x, _lanes.lane_center_y(lane) - counts[lane] * 24.0)
		turret.scale = Vector2.ONE * turret_scale
		_turret_root.add_child(turret)
		_turrets.append(turret)
		_turret_timers.append(turret_fire_interval * _rng.randf_range(0.2, 1.0))
		counts[lane] += 1
	_refresh_status()


func _process(_delta: float) -> void:
	_crosshair.global_position = get_global_mouse_position()


func _physics_process(delta: float) -> void:
	if is_over:
		return
	_update_spawn(delta)

	for child in _enemies.get_children():
		var ship := child as EnemyShip
		if ship != null:
			ship.step(delta, _player.combat, _lanes.sea_left, fortress_hp > 0.0, _config.gravity)

	_update_turrets(delta)
	_check_boarding(delta)
	if _boarding != null:
		_boarding.tick(delta)


func _update_spawn(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		spawn_enemy()
		_spawn_timer = spawn_interval


func spawn_enemy(lane: int = -1) -> EnemyShip:
	var index := _rng.randi_range(0, _lanes.lane_count - 1) if lane == -1 else lane
	if is_over or index != _lanes.clamp_lane_index(index):
		return null

	var ship: EnemyShip = ENEMY_SCENE.instantiate()
	ship.config = enemy_config
	ship.lanes = _lanes
	ship.speed_cap = _player.move_speed
	ship.lane_index = index
	ship.position = _enemies.to_local(Vector2(spawn_x, _lanes.lane_bottom_y(index)))
	ship.sunk.connect(_on_enemy_sunk)
	ship.retreated.connect(enemy_retreated.emit)
	ship.fired.connect(_on_enemy_fired.bind(ship))
	_enemies.add_child(ship)
	return ship


func _on_enemy_sunk(ship: EnemyShip) -> void:
	if is_over:
		return
	kills += 1
	_refresh_status()
	enemy_sunk.emit(ship)
	if kills >= kills_to_win and not _victory_pending:
		# 同一物理帧可能有一发爆炸击沉多艘船，登记完再停战。
		_victory_pending = true
		_finish.call_deferred(true)


func _on_enemy_fired(origin: Vector2, velocity: Vector2, lane: int, damage: float, ship: EnemyShip) -> void:
	if ship.action == EnemyShip.Action.ATTACK_FORTRESS and not _fort_attack_announced:
		_fort_attack_announced = true
		_show_alert("贼船出没")
	launch_projectile(origin, velocity, lane, ShipCombat.Team.ENEMY, damage)


func _on_fortress_hit(damage: float) -> void:
	if is_over or _victory_pending or damage <= 0.0:
		return
	var previous_hp := fortress_hp
	fortress_hp = maxf(0.0, fortress_hp - damage)
	if fortress_hp <= 0.0:
		_freeze_combat()
	var tier := fort_tier()
	_turret_root.show_damage(tier)
	var last_tier := _worst_fort_tier
	_worst_fort_tier = maxi(tier, _worst_fort_tier)
	for crossed in range(last_tier + 1, tier + 1):
		lamp_value = maxi(0, lamp_value - FORT_LIGHT_LOSS[crossed - 1])
	_refresh_status()
	for crossed in range(last_tier + 1, tier + 1):
		on_fort_damaged_tier.emit(crossed)
	if fortress_hp <= 0.0:
		_start_gate_breach()
	elif previous_hp > fortress_hp_cap * 0.5 and fortress_hp <= fortress_hp_cap * 0.5:
		_fort_hit_announced = true
		_show_alert("台已半圮")
	elif not _fort_hit_announced:
		_fort_hit_announced = true
		_show_alert("贼攻城")


func fort_tier() -> int:
	if fortress_hp <= 0.0:
		return 3
	var ratio := fortress_hp / maxf(fortress_hp_cap, 1.0)
	if ratio <= 0.25:
		return 2
	return 1 if ratio <= 0.6 else 0


func _show_alert(message: String) -> void:
	if _alert_tween != null:
		_alert_tween.kill()
	_alert_label.text = message
	_alert_label.modulate.a = 1.0
	_alert_tween = create_tween()
	_alert_tween.tween_interval(1.6)
	_alert_tween.tween_property(_alert_label, "modulate:a", 0.0, 0.9)


func _gate_entrance() -> Vector2:
	return _lanes.to_global(Vector2(_lanes.sea_left, _lanes.lane_bottom_y(water_gate_lane)))


func _launch_player_from_gate() -> void:
	var entrance_x := _gate_entrance().x
	_player.sail_from_gate(water_gate_lane, entrance_x - 48.0,
		entrance_x + _player.combat.size.x * 0.5 + 26.0, gate_launch_time)


func _on_player_sunk(player: PlayerShip) -> void:
	lamp_value = maxi(0, lamp_value - player_sunk_light_loss)
	_refresh_status()
	await get_tree().create_timer(player_respawn_delay, false, true).timeout
	if not is_over and player.combat.parts.is_sunk():
		_launch_player_from_gate()


func _start_gate_breach() -> void:
	if _breach_started:
		return
	_breach_started = true
	if not is_over:
		_freeze_combat()
	_show_alert("城陷矣")
	var entrance := _gate_entrance()
	var closest: EnemyShip
	var closest_distance := INF
	for child in _enemies.get_children():
		var ship := child as EnemyShip
		if ship == null or not ship.combat.targetable:
			continue
		var distance := ship.global_position.distance_squared_to(entrance)
		if distance < closest_distance:
			closest = ship
			closest_distance = distance
	if closest == null:
		_finish(false)
		return
	var sail := closest.sail_into_gate(water_gate_lane, entrance, entrance.x - 62.0, gate_breach_time)
	sail.finished.connect(_finish.bind(false))
	await get_tree().create_timer(gate_breach_time + 0.25, false, true).timeout
	_finish(false)


func _update_turrets(delta: float) -> void:
	for index in range(_turrets.size()):
		_turret_timers[index] = maxf(0.0, _turret_timers[index] - delta)
		if _turret_timers[index] > 0.0:
			continue
		var turret: Node2D = _turrets[index]
		var origin: Vector2 = turret.muzzle_position()
		var lane: int = turret.lane_index
		var target := _frontmost_enemy_in_lane(lane, origin.x + turret_fire_range)
		if target == null:
			continue
		var aim := target.combat.aim_point()
		launch_projectile(origin, origin.direction_to(aim) * turret_shell_speed,
			lane, ShipCombat.Team.ALLY, turret_damage, ShipParts.Ammo.SOLID, 0.0)
		_turret_timers[index] = turret_fire_interval


func _frontmost_enemy_in_lane(lane: int, max_x: float) -> EnemyShip:
	var best: EnemyShip = null
	for child in _enemies.get_children():
		var ship := child as EnemyShip
		if ship == null or not ship.combat.targetable or ship.lane_index != lane:
			continue
		if ship.global_position.x > max_x:
			continue
		if best == null or ship.global_position.x < best.global_position.x:
			best = ship
	return best


## 是不是刚换完道（用于区分“换道重叠”与“正面撞上”）。
func _recently_switched(ship: Node, now_ms: int) -> bool:
	if ship == null:
		return false
	var stamp: int = int(ship.get("lane_switch_finished_ms"))
	return stamp > 0 and now_ms - stamp <= int(lane_overlap_window * 1000.0)


func _check_boarding(delta: float) -> void:
	_boarding_left = maxf(0.0, _boarding_left - delta)
	if _boarding == null or _boarding.active:
		_boarding_contact_active = false
		_pending_scrape = null
		return
	if not _player.combat.targetable or _player.controls_locked:
		_boarding_contact_active = false
		_pending_scrape = null
		return
	# 硬门槛零：玩家自己的换道必须已经彻底结束（换道途中不接触舷）。
	var player_settled: bool = _player.is_lane_switch_done()
	var player_hull := _player.combat.hitbox(ShipParts.Part.HULL)
	var candidate: EnemyShip
	var nearest := INF
	var player_lane: int = _player.lane_index
	for child in _enemies.get_children():
		var ship := child as EnemyShip
		if ship == null or not ship.combat.targetable:
			continue
		# 硬门槛一：航道编号必须一致（换道途中 lane_index 已是目标道，但 y 还没到，
		# 所以 _boarding_gap 里还有一道竖直重叠判定把关）。
		if ship.lane_index != player_lane:
			continue
		# 硬门槛一之二：敌船自己的换道也必须结束。
		# 任一方还在换道：这是“从上下滑过来蹭上”的侧面接触，先记下来，
		# 等双方都落到本道里再按“换道重叠”结算（不磨撞角）。
		if not player_settled or not ship.is_lane_switch_done():
			if _pending_scrape == null:
				_pending_scrape = ship
			continue
		# 硬门槛二：左右真正贴上才触发（竖直不重叠时 _boarding_gap 返回 INF）。
		if _boarding_gap(ship, player_hull) >= boarding_distance:
			continue
		var distance := absf(ship.global_position.x - _player.global_position.x)
		if distance < nearest:
			nearest = distance
			candidate = ship
	if candidate == null:
		_boarding_contact_active = false
		return
	if _boarding_left > 0.0:
		return
	var relative := absf(_player.velocity.x) + candidate.config.speed
	# lane_overlap：本次接触发生在一方“刚换完道”的窗口内 → 接舷按固定伤害算（T-402 规则 5）。
	# 侧面蹭：刚才换道时贴上来过（pending），或者双方合速度低于轻碰阈值（慢慢贴上去的）。
	var overlap := _pending_scrape != null
	_pending_scrape = null
	if not _boarding.try_engage(candidate, relative, overlap):
		return
	_boarding_contact_active = true
	_boarding_left = boarding_cooldown
	var enemy_name := candidate.config.display_name
	boarding_contact_started.emit(candidate)
	boarding_nearby.emit(enemy_name)


func _setup_boarding() -> void:
	_boarding = BoardingFight.new()
	_boarding.name = "Boarding"
	add_child(_boarding)
	_boarding.setup(self, _player)
	_boarding.morale_changed.connect(_on_boarding_morale)
	_boarding.finished.connect(boarding_finished.emit)
	set_morale(morale)


func set_morale(value: float) -> void:
	morale = clampf(value, -100.0, 100.0)
	if _boarding != null:
		_boarding.set_morale_tier(morale_tier())
	morale_changed.emit(morale)


## 气焰四档：≥75 高涨(1.2)、≥25 平稳(0.9)、≥−25 低落(0.75)、更低 崩溃反扑(1.3)。
func morale_tier() -> int:
	if morale >= 75.0:
		return 0
	if morale >= 25.0:
		return 1
	if morale >= -25.0:
		return 2
	return 3


func _on_boarding_morale(delta: float) -> void:
	set_morale(morale + delta)


## 接舷只看“左右两面”：舰体箱竖直方向必须重叠，否则不触发。
## 这样换道途中（y 还在两条道之间滑）不会误触发，等真正贴到同一高度才算撞上。
func _boarding_gap(ship: EnemyShip, player_hull: Rect2) -> float:
	if ship.lane_index != _player.lane_index:
		return INF
	var enemy_hull := ship.combat.hitbox(ShipParts.Part.HULL)
	if enemy_hull.end.y < player_hull.position.y or enemy_hull.position.y > player_hull.end.y:
		return INF
	return maxf(enemy_hull.position.x - player_hull.end.x, player_hull.position.x - enemy_hull.end.x)


func _on_player_shot(origin: Vector2, velocity: Vector2, lane: int, ammo_type: ShipParts.Ammo) -> void:
	launch_projectile(origin, velocity, lane, ShipCombat.Team.ALLY, _config.shell_damage[ammo_type], ammo_type)


func _on_player_part_changed(_part: ShipParts.Part, _hp: float, _condition: ShipParts.Condition) -> void:
	_refresh_status()


func launch_projectile(
	origin: Vector2, velocity: Vector2, lane: int, team: ShipCombat.Team,
	damage: float, ammo_type: ShipParts.Ammo = ShipParts.Ammo.SOLID, gravity: float = NAN
) -> Projectile:
	var ball: Projectile = PROJECTILE_SCENE.instantiate()
	ball.position = _projectiles.to_local(origin)
	ball.arc_gravity = _config.gravity if is_nan(gravity) else gravity
	ball.velocity = velocity
	ball.lane_index = lane
	ball.team = team
	ball.damage = damage
	ball.ammo = ammo_type
	ball.lanes = _lanes
	if team == ShipCombat.Team.ALLY and is_nan(gravity):
		ball.drag_k = _config.drag_k
		ball.pierce_left = _config.pierce_count[ammo_type]
		ball.pierce_damage_falloff = _config.pierce_damage_falloff
		if ammo_type == ShipParts.Ammo.EXPLOSIVE:
			ball.explode_radius = _config.explode_radius
			ball.explode_push_distance = _config.explode_push_distance
			if _config.explode_self_damage:
				ball.explosion_owner = _player.combat
	if team == ShipCombat.Team.ENEMY:
		var height := _lanes.sea_bottom - _lanes.sea_top
		ball.fortress_bounds = Rect2(_lanes.sea_left - 16.0, _lanes.sea_top, 16.0, height)
		ball.fortress_hit.connect(_on_fortress_hit)
	_projectiles.add_child(ball)
	return ball


func _freeze_combat() -> void:
	is_over = true
	_player.lock_controls()
	_crosshair.hide()
	$HUD/ReloadRing.hide()
	_weapon.set_process(false)
	_weapon.set_physics_process(false)
	_weapon.set_process_unhandled_input(false)
	for child in _projectiles.get_children():
		if child is Projectile:
			child.set_physics_process(false)
			child.queue_free()


func _finish(won: bool) -> void:
	if _settled:
		return
	_settled = true
	if not is_over:
		_freeze_combat()
	if not won:
		defeats_left = maxi(0, defeats_left - 1)
	var reached_ending := not won and defeats_left == 0
	_banner.text = "守住了！" if won else ("堡已破 · 乡兵尽没" if reached_ending else "堡已破 · 乡兵击退了倭寇")
	_banner.add_theme_color_override("font_color", Color(0.85, 0.78, 0.45) if won else Color(0.72, 0.3, 0.28))
	_refresh_status()
	if not management_session.enter_rest(_build_result(won)):
		push_error("经营会话拒绝战果，无法继续结算")
		return
	on_battle_finished.emit(won, not won)
	if reached_ending:
		ending_reached.emit()
		return
	if won and not _player.combat.parts.is_sunk():
		_player.sail_back_to_gate(water_gate_lane, _gate_entrance().x - 48.0, minf(end_delay, gate_launch_time))
	refresh_after_end(won)


func refresh_after_end(_won: bool) -> void:
	await get_tree().create_timer(end_delay).timeout
	if not is_inside_tree():
		return
	var packed := load(management_scene) as PackedScene
	if packed == null:
		push_error("无法加载经营场景：%s" % management_scene)
		return
	var rest := packed.instantiate()
	if rest.has_method("bind_session"):
		rest.bind_session(management_session, load(scene_file_path) as PackedScene)
	var error := get_tree().change_scene_to_node(rest)
	if error != OK:
		rest.free()
		push_error("无法进入经营场景（%d）" % error)


func _apply_battle_start() -> void:
	if management_session == null:
		management_session = ManagementSession.new(difficulty, 1, _ammo_snapshot())
	_battle_start = management_session.retry_battle()
	lamp_value = _battle_start.light
	defeats_left = _battle_start.defeats_left
	var fort_level: int = _battle_start.fort_level
	var fort_hp_scale := float(max_fortress_hp) / ManagementRules.fort_cap(1)
	fortress_hp_cap = fort_hp_scale * ManagementRules.fort_cap(fort_level)
	fortress_hp = fort_hp_scale * _battle_start.fort_hp
	if fort_level >= 2 and not turret_lanes.has(water_gate_lane):
		turret_lanes.append(water_gate_lane)
	if fort_level >= 3:
		for lane in turret_lanes:
			if lane != water_gate_lane and turret_lanes.count(lane) == 1:
				turret_lanes.append(lane)
				break
	for index in range(AMMO_KEYS.size()):
		_weapon.ammo[index] = _battle_start.ammo[AMMO_KEYS[index]]
	var parts := _player.combat.parts
	var base_caps := ManagementRules.ship_caps(1)
	var caps := ManagementRules.ship_caps(_battle_start.ship_level)
	for part: ShipParts.Part in PART_KEYS:
		var key: String = PART_KEYS[part]
		var hp_scale := parts.max_hp(part) / float(base_caps[key])
		parts.set_hp(part, hp_scale * _battle_start.ship_hp[key], hp_scale * caps[key])


func _ammo_snapshot() -> Dictionary:
	var snapshot := {}
	for index in range(AMMO_KEYS.size()):
		snapshot[AMMO_KEYS[index]] = _weapon.ammo[index]
	return snapshot


func _build_result(won: bool) -> Dictionary:
	var caps := ManagementRules.ship_caps(_battle_start.ship_level)
	var parts := _player.combat.parts
	var ship_hp := {}
	for part: ShipParts.Part in PART_KEYS:
		var key: String = PART_KEYS[part]
		ship_hp[key] = roundi(float(caps[key]) * parts.hp(part) / maxf(parts.max_hp(part), 1.0))
	var fort_cap := ManagementRules.fort_cap(_battle_start.fort_level)
	return {
		"battle_id": _battle_start.battle_id, "won": won,
		"light": lamp_value, "defeats_left": defeats_left, "ammo": _ammo_snapshot(),
		"fort_hp": roundi(fort_cap * fortress_hp / maxf(fortress_hp_cap, 1.0)), "ship_hp": ship_hp,
	}


func _refresh_status() -> void:
	var ammo_names := ["实心", "破帆", "爆炸"]
	var ammo_labels := PackedStringArray()
	for index in range(_weapon.ammo.size()):
		var selected := "▶" if index == _weapon.ammo_selected else " "
		ammo_labels.append("%s%s%d" % [selected, ammo_names[index], _weapon.ammo[index]])

	var labels := ["舰体", "帆", "炮台", "舵", "撞角"]
	var parts := _player.combat.parts
	var order := [ShipParts.Part.HULL, ShipParts.Part.SAIL, ShipParts.Part.CANNON, ShipParts.Part.RUDDER, ShipParts.Part.RAM]
	var hp_labels := PackedStringArray()
	for index in range(order.size()):
		var part: ShipParts.Part = order[index]
		var ratio := parts.hp(part) / maxf(parts.max_hp(part), 0.001)
		hp_labels.append("%s%d%%" % [labels[index], roundi(ratio * 100.0)])
	var fort_percent := roundi(100.0 * fortress_hp / maxf(fortress_hp_cap, 1.0))
	var level := "·"
	match _turrets.size():
		4: level = "Ⅰ"
		5: level = "Ⅱ"
		6: level = "Ⅲ"
	var slots := "■".repeat(_turrets.size()) + "□".repeat(MAX_TURRETS - _turrets.size())
	var fire_mode := "单发" if _weapon.fire_mode == 0 else "齐射"
	_status.text = "%s  ·  %s    击沉 %d/%d    堡%s %d%%  %s\n%s    灯火 %d    余败场 %d" % [
		"  ".join(ammo_labels), fire_mode, kills, kills_to_win, level, fort_percent, slots,
		"  ".join(hp_labels), lamp_value, defeats_left,
	]
