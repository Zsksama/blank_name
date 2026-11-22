extends RefCounted
## BattleResult and BattleStart are dictionaries with the fields documented in development.md.

signal changed

const Rules := preload("res://Scripts/Management/management_rules.gd")

var _state: Dictionary
var _draft := {}
var _pending_order := {}
var _battle_start: Dictionary
var _ledger: Array[Dictionary] = []


func _init(difficulty: String = "normal", first_battle_id: int = 1) -> void:
	first_battle_id = maxi(1, first_battle_id)
	if not Rules.DIFFICULTIES.has(difficulty):
		difficulty = "normal"
	var settings: Dictionary = Rules.DIFFICULTIES[difficulty]
	_state = Rules.INITIAL_STOCK.duplicate(true)
	_state.merge({
		"battle_id": first_battle_id - 1, "day": 0, "difficulty": difficulty,
		"light": settings.light, "defeats_left": settings.defeats_left,
		"ship_level": 1, "ship_hp": Rules.ship_caps(1),
		"fort_level": 1, "fort_hp": Rules.fort_cap(1),
	})
	_battle_start = _make_battle_start(first_battle_id)


func is_resting() -> bool:
	return _battle_start.is_empty()


func get_state() -> Dictionary:
	return _state.duplicate(true)


func get_draft() -> Dictionary:
	return _draft.duplicate()


func get_ledger() -> Array[Dictionary]:
	return _ledger.duplicate(true)


func select(event: String, choice: String) -> bool:
	if not is_resting() or not Rules.option_available(event, choice, _state):
		return false
	if _draft[event] != choice:
		_draft[event] = choice
		changed.emit()
	return true


func preview() -> Dictionary:
	if not is_resting():
		return {}
	var battle_id: int = _state.battle_id + 1
	var auto_repair := Rules.auto_fort_repair(_state, battle_id)
	var projected := _state.duplicate(true)
	projected.fort_hp += auto_repair
	var simulated := Rules.settle(projected, _draft_order())
	var costs := Rules.order_costs(_draft)
	return {
		"costs": costs, "shortages": _shortages(costs), "requires_regular": _draft.regular.is_empty(),
		"items": simulated.items, "fixed_output": simulated.fixed_output, "tier": simulated.tier,
		"auto_fort_repair": auto_repair,
	}


## Returns an empty dictionary if the order is incomplete, unaffordable or already locked.
func start_battle() -> Dictionary:
	if not is_resting() or _draft.regular.is_empty():
		return {}
	if not _shortages(Rules.order_costs(_draft)).is_empty():
		return {}

	var battle_id: int = _state.battle_id + 1
	var repair := Rules.auto_fort_repair(_state, battle_id)
	_pending_order = _draft_order()
	_pending_order.auto_fort_repair = repair
	_state.fort_hp += repair
	_battle_start = _make_battle_start(battle_id)
	var snapshot := _battle_start.duplicate(true)
	changed.emit()
	return snapshot


## On a new session, returns the opening battle. During rest there is no retry point.
func retry_battle() -> Dictionary:
	return _battle_start.duplicate(true)


## Accepts the confirmed result of the outstanding battle exactly once.
func enter_rest(result: Dictionary) -> bool:
	if not _is_valid_result(result):
		return false

	var merged := _state.duplicate(true)
	for key in ["light", "defeats_left", "fort_hp"]:
		merged[key] = result[key]
	for group in ["ammo", "ship_hp"]:
		for key in merged[group]:
			merged[group][key] = result[group][key]
	var battle_delta := Rules.changes_between(_state, merged)
	var settled := Rules.settle(merged, _pending_order)

	_state = settled.state
	_state.battle_id = result.battle_id
	_state.day += 1
	_ledger.append({
		"battle_id": result.battle_id, "day": _state.day, "won": result.won,
		"battle_delta": battle_delta, "auto_fort_repair": _pending_order.get("auto_fort_repair", 0),
		"order_items": settled.items, "tier": settled.tier, "fixed_output": settled.fixed_output,
	})
	_pending_order.clear()
	_battle_start.clear()
	_draft = {"regular": "", "upgrade": "skip", "repair": "skip", "forge": "skip"}
	changed.emit()
	return true


func _draft_order() -> Dictionary:
	return {"choices": _draft.duplicate(), "recommendation": Rules.light_tier(_state.light).recommendation}


func _shortages(costs: Dictionary) -> Dictionary:
	var shortages := {}
	for key in Rules.BALANCES:
		var missing: int = costs[key] - _state[key]
		if missing > 0:
			shortages[key] = missing
	return shortages


func _make_battle_start(battle_id: int) -> Dictionary:
	return {
		"battle_id": battle_id, "difficulty": _state.difficulty, "light": _state.light,
		"ammo": _state.ammo.duplicate(), "ship_level": _state.ship_level, "ship_hp": _state.ship_hp.duplicate(),
		"fort_level": _state.fort_level, "fort_hp": _state.fort_hp, "defeats_left": _state.defeats_left,
	}


func _is_valid_result(result: Dictionary) -> bool:
	if is_resting() or typeof(result.get("battle_id")) != TYPE_INT:
		return false
	if result.battle_id != _battle_start.battle_id or typeof(result.get("won")) != TYPE_BOOL:
		return false
	if not _valid_amount(result.get("light"), 100) or not _valid_amount(result.get("defeats_left")):
		return false
	if not _valid_amount(result.get("fort_hp"), Rules.fort_cap(_battle_start.fort_level)):
		return false
	if typeof(result.get("ammo")) != TYPE_DICTIONARY or typeof(result.get("ship_hp")) != TYPE_DICTIONARY:
		return false
	for kind in Rules.AMMO_NAMES:
		if not _valid_amount(result.ammo.get(kind)):
			return false
	var caps := Rules.ship_caps(_battle_start.ship_level)
	for part in caps:
		if not _valid_amount(result.ship_hp.get(part), caps[part]):
			return false
	return true


func _valid_amount(value: Variant, maximum: int = 9223372036854775807) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value <= maximum
