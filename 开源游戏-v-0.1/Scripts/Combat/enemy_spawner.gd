class_name EnemySpawner
extends Node

signal batch_announced(formation: EnemySpawnLevel.Formation, arrivals: Array[Arrival])

const MAX_ALIVE := 15
const MAX_PER_LANE := 2
const MAX_PER_BATCH := 5
const OPENING_FRACTION := 0.2
const CONCH_LEAD := 0.65
const DIFFICULTY_MULTIPLIERS := {"easy": 1.0, "normal": 1.5, "hard": 2.0}
const TYPES: Dictionary[EnemyShipConfig.Type, EnemyShipConfig] = {
	EnemyShipConfig.Type.FAST: preload("res://Data/Combat/enemy_fast.tres"),
	EnemyShipConfig.Type.NORMAL: preload("res://Data/Combat/enemy_e01.tres"),
	EnemyShipConfig.Type.HEAVY: preload("res://Data/Combat/enemy_heavy.tres"),
}
const LEVELS: Array[EnemySpawnLevel] = [
	preload("res://Data/Combat/Levels/level_01.tres"),
	preload("res://Data/Combat/Levels/level_02.tres"),
	preload("res://Data/Combat/Levels/level_03.tres"),
	preload("res://Data/Combat/Levels/level_04.tres"),
	preload("res://Data/Combat/Levels/level_05.tres"),
]


class Arrival:
	var config: EnemyShipConfig
	var lane: int
	var offset_x: float
	var leads_snake := false
	var waits_for_lane := false
	var keep_entry_spacing := true
	var predecessor: Arrival
	var ship: EnemyShip

	func _init(ship_config: EnemyShipConfig, lane_index: int, entry_offset: float = 0.0) -> void:
		config = ship_config
		lane = lane_index
		offset_x = entry_offset


var enemy_total := 0
var required: Array[EnemyShipConfig] = []
var purchased: Array[EnemyShipConfig] = []

var _level: EnemySpawnLevel
var _rng := RandomNumberGenerator.new()
var _interval: Vector2
var _time_to_batch := 0.0
var _time_to_entry := 0.0
var _opening_count := 0
var _remaining: Array[EnemyShipConfig] = []
var _snake_escorts: Array[EnemyShipConfig] = []
var _announced: Array[Arrival] = []
var _snake_tails: Array[Arrival] = []
var _formation := EnemySpawnLevel.Formation.NONE
var _cue: AudioStreamPlayer


func _ready() -> void:
	_cue = AudioStreamPlayer.new()
	_cue.name = "Conch"
	add_child(_cue)


func begin(level: EnemySpawnLevel, difficulty: String, fixed_seed: int, interval: Vector2, sound_path: String) -> void:
	_level = level
	_interval = Vector2(minf(interval.x, interval.y), maxf(interval.x, interval.y))
	_cue.stop()
	_cue.stream = null
	if not sound_path.is_empty() and ResourceLoader.exists(sound_path, "AudioStream"):
		_cue.stream = load(sound_path) as AudioStream
	if fixed_seed == -1:
		_rng.randomize()
	else:
		_rng.seed = fixed_seed
	var multiplier: float = DIFFICULTY_MULTIPLIERS.get(difficulty, 1.5)
	var budget := maxf(0.0, level.budget * multiplier)
	var money := budget
	required.clear()
	for type in level.must_spawn:
		if TYPES.has(type):
			for i in range(level.must_spawn[type]):
				required.append(TYPES[type])

	purchased.clear()
	var affordable: Array[EnemyShipConfig] = []
	for type in level.allowed_types:
		var config: EnemyShipConfig = TYPES.get(type)
		if config != null and config.cost > 0 and not affordable.has(config):
			affordable.append(config)
	while not affordable.is_empty():
		# 等价于重抽买不起的类型，直接从买得起的类型里均匀抽取。
		affordable = affordable.filter(func(config: EnemyShipConfig) -> bool: return config.cost <= money)
		if affordable.is_empty():
			break
		var config := affordable[_rng.randi_range(0, affordable.size() - 1)]
		purchased.append(config)
		money -= config.cost

	enemy_total = required.size() + purchased.size()
	_opening_count = ceili(enemy_total * OPENING_FRACTION)
	_remaining.assign(purchased)
	_snake_escorts.clear()
	if level.reserve_required_for_snake and level.formation_pool.has(EnemySpawnLevel.Formation.SNAKE):
		_snake_escorts.assign(required)
	else:
		_remaining.append_array(required)
	_announced.clear()
	_snake_tails.clear()
	_time_to_entry = 0.0
	_time_to_batch = _next_interval()
	print("[M14] 第 %d 关 · %s · 种子 %d · 预算 %d × %.1f = %.1f · 余额 %.1f · 共 %d 艘 · 必出 %s · 购入 %s" % [
		level.level_id, level.display_name, _rng.seed, level.budget, multiplier, budget, money, enemy_total,
		_composition(required), _composition(purchased),
	])


func advance(delta: float, occupied: PackedInt32Array, suspended: bool) -> Array[Arrival]:
	_cue.stream_paused = suspended
	var entering: Array[Arrival] = []
	if suspended:
		return entering

	if not _announced.is_empty():
		_time_to_entry -= delta
		if _time_to_entry <= 0.0:
			for arrival in _announced:
				if arrival.waits_for_lane:
					_snake_tails.append(arrival)
				elif _can_enter(arrival.lane, occupied):
					_enter(arrival, occupied, entering)
				else:
					_remaining.append(arrival.config)
			_announced.clear()

	var tail_index := 0
	while tail_index < _snake_tails.size():
		var tail := _snake_tails[tail_index]
		if _can_enter(tail.lane, occupied):
			_snake_tails.remove_at(tail_index)
			_enter(tail, occupied, entering)
			print("[M14] 长蛇阵尾船入场 · 第 %d 道 · %s" % [tail.lane + 1, tail.config.display_name])
		else:
			tail_index += 1

	if _pool_size() > 0:
		_time_to_batch -= delta
		if _time_to_batch <= 0.0 and _announced.is_empty():
			_time_to_batch = _next_interval()
			_announced = _select_batch(occupied)
			if not _announced.is_empty():
				_time_to_entry = CONCH_LEAD
				if _cue.stream != null:
					_cue.play()
				_log_batch()
				batch_announced.emit(_formation, _announced.duplicate())
	return entering


func is_exhausted() -> bool:
	return _pool_size() == 0 and _announced.is_empty() and _snake_tails.is_empty()


func _select_batch(occupied: PackedInt32Array) -> Array[Arrival]:
	_formation = EnemySpawnLevel.Formation.NONE
	var room := _room(occupied)
	if room <= 0:
		return []
	var slots: Array[int] = []
	var open_lanes: Array[int] = []
	var empty_lanes: Array[int] = []
	for lane in range(occupied.size()):
		if occupied[lane] < MAX_PER_LANE:
			open_lanes.append(lane)
			for slot in range(MAX_PER_LANE - occupied[lane]):
				slots.append(lane)
		if occupied[lane] == 0:
			empty_lanes.append(lane)
	if slots.is_empty():
		return []

	# 第 2 关的两艘必出普通船始终担任头尾，直到有可编队的航道。
	if _remaining.is_empty() and _snake_escorts.size() == 2:
		if room < 2 or empty_lanes.is_empty():
			return []
		_formation = EnemySpawnLevel.Formation.SNAKE
		return _snake(empty_lanes[_rng.randi_range(0, empty_lanes.size() - 1)])

	if not _level.formation_pool.is_empty() and _rng.randf() < _level.formation_chance:
		var pattern := _level.formation_pool[_rng.randi_range(0, _level.formation_pool.size() - 1)]
		match pattern:
			EnemySpawnLevel.Formation.SNAKE:
				if not _in_opening() and room >= 2 and _pool_size() >= 2 and not empty_lanes.is_empty():
					_formation = pattern
					return _snake(empty_lanes[_rng.randi_range(0, empty_lanes.size() - 1)])
			EnemySpawnLevel.Formation.BUTTERFLY:
				var count := mini(occupied.size(), MAX_PER_BATCH)
				if count >= 2 and mini(room, mini(_pool_size(), open_lanes.size())) >= count:
					_formation = pattern
					return _spread(open_lanes, count, false)

	var available := _remaining.size() if not _remaining.is_empty() else _snake_escorts.size()
	var batch_limit := mini(MAX_PER_BATCH, mini(available, mini(room, slots.size())))
	return _spread(slots, _rng.randi_range(1, batch_limit))


func _spread(slots: Array[int], count: int, keep_entry_spacing: bool = true) -> Array[Arrival]:
	var batch: Array[Arrival] = []
	for i in range(count):
		var lane: int = slots.pop_at(_rng.randi_range(0, slots.size() - 1))
		var arrival := Arrival.new(_take(_in_opening(), false), lane, _rng.randf_range(-28.0, 0.0))
		arrival.keep_entry_spacing = keep_entry_spacing
		batch.append(arrival)
	return batch


func _snake(lane: int) -> Array[Arrival]:
	var count := _rng.randi_range(2, mini(3, _pool_size()))
	var head := Arrival.new(_take_snake_end(), lane, -20.0)
	head.leads_snake = true
	var tail := Arrival.new(_take_snake_end(), lane)
	if count == 2:
		tail.predecessor = head
		return [head, tail]
	var middle := Arrival.new(_take(true, false), lane)
	middle.predecessor = head
	tail.predecessor = middle
	tail.waits_for_lane = true
	return [head, middle, tail]


func _take_snake_end() -> EnemyShipConfig:
	if not _snake_escorts.is_empty():
		return _snake_escorts.pop_front()
	return _take(false, true)


func _take(cheapest: bool, strongest: bool) -> EnemyShipConfig:
	var pool := _remaining if not _remaining.is_empty() else _snake_escorts
	var index := _rng.randi_range(0, pool.size() - 1)
	if cheapest or strongest:
		for i in range(pool.size()):
			if (cheapest and pool[i].cost < pool[index].cost) or (strongest and pool[i].cost > pool[index].cost):
				index = i
	return pool.pop_at(index)


func _in_opening() -> bool:
	return enemy_total - _pool_size() < _opening_count


func _pool_size() -> int:
	return _remaining.size() + _snake_escorts.size()


func _next_interval() -> float:
	return _rng.randf_range(_interval.x, _interval.y)


func _room(occupied: PackedInt32Array) -> int:
	var live := 0
	for count in occupied:
		live += count
	return clampi(_level.max_alive, 1, MAX_ALIVE) - live


func _can_enter(lane: int, occupied: PackedInt32Array) -> bool:
	return _room(occupied) > 0 and occupied[lane] < MAX_PER_LANE


func _enter(arrival: Arrival, occupied: PackedInt32Array, entering: Array[Arrival]) -> void:
	occupied[arrival.lane] += 1
	entering.append(arrival)


func _log_batch() -> void:
	var formation_name: String = ["普通", "长蛇阵", "蝴蝶阵"][_formation]
	var entries := PackedStringArray()
	for arrival in _announced:
		var staging := "（等空位）" if arrival.waits_for_lane else ""
		entries.append("%d 道 %s%s" % [arrival.lane + 1, arrival.config.display_name, staging])
	print("[M14] 批次 · %s · %s" % [formation_name, "、".join(entries)])


func _composition(configs: Array[EnemyShipConfig]) -> String:
	var counts := PackedStringArray()
	for config: EnemyShipConfig in TYPES.values():
		var count := configs.count(config)
		if count > 0:
			counts.append("%s×%d" % [config.display_name, count])
	return "、".join(counts) if not counts.is_empty() else "无"
