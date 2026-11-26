extends SceneTree

const SESSION_PATH := "res://Scripts/Management/management_session.gd"
const Compass := preload("res://Scripts/Management/management_compass.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	if not ResourceLoader.exists(SESSION_PATH):
		push_error("Management session is missing")
		quit(1)
		return

	var session_script := load(SESSION_PATH) as Script
	if session_script == null or not session_script.can_instantiate():
		push_error("Management session could not be instantiated")
		quit(1)
		return

	_check_delayed_settlement(session_script)
	_check_locked_recommendation(session_script)
	_check_full_repairs(session_script)
	_check_battle_result_validation(session_script)
	_check_compass_reentry(session_script)
	print("Management checks: %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _check_delayed_settlement(session_script: Script) -> void:
	var session = session_script.new()
	_check(session.enter_rest(_result()), "Opening result is accepted")
	var first_state: Dictionary = session.get_state()
	var first_ledger: Array = session.get_ledger()
	_check(first_state.day == 1 and first_ledger.size() == 1, "Opening rest moves the calendar once")
	_check(first_state.materials == 11 and first_state.research == 4, "Opening rest includes fixed output")
	_check(first_state.ammo == {"round": 10, "chain": 5, "grape": 3}, "Opening ammo includes fixed output")
	_check(first_ledger[0].order_items.is_empty(), "Opening rest settles no earlier order")
	_check(session.start_battle().is_empty(), "Regular management choice is required")

	_check(session.select("regular", "trade") and session.select("regular", "mobilize"), "Regular choice can be edited")
	_check(session.select("upgrade", "upgrade_fort"), "Over-budget choices can be drafted")
	_check(session.select("repair", "repair_ship") and session.select("forge", "forge_grape"), "Optional drafts can coexist")
	var preview: Dictionary = session.preview()
	_check(preview.shortages == {"materials": 3, "research": 1}, "Full reservation shows both shortfalls")
	_check(session.start_battle().is_empty() and session.is_resting(), "An unaffordable order cannot start battle")
	_check(session.get_state() == first_state and session.get_ledger() == first_ledger, "Draft and failed commit leave state and history alone")
	_check(session.select("upgrade", "upgrade_ship") and session.select("forge", "forge_round"), "Draft can be brought within budget")
	_check(session.get_draft().repair == "repair_ship", "Editing one event retains the others")
	_check(session.preview().items[0].bonus_delta == {"light": 3, "ammo": {"round": 2}}, "Preview includes the recommended choice bonus")

	var start: Dictionary = session.start_battle()
	_check(start.battle_id == 2 and start.difficulty == "normal" and start.defeats_left == 2, "BattleStart carries round metadata")
	_check(start.light == 60 and start.ammo == first_state.ammo, "BattleStart omits future ammo and lamp changes")
	_check(start.ship_level == 1 and start.ship_hp == first_state.ship_hp and start.fort_level == 1, "BattleStart omits future upgrade and repair")
	_check(start.fort_hp == 80, "Battles start with one automatic fort repair")
	_check(session.get_state().materials == 11 and session.get_ledger() == first_ledger, "Commit retains funds and history until return")
	var retry_point: Dictionary = start.duplicate(true)
	start.ammo.round = 0
	_check(session.retry_battle() == retry_point, "Retry returns an independent copy of the locked BattleStart")
	_check(session.start_battle().is_empty() and not session.select("regular", "rest"), "A locked order cannot be committed or edited again")
	_check(session.retry_battle() == retry_point and session.get_state().fort_hp == 80, "Repeated start and retry cannot heal again")

	var result := {
		"battle_id": 2, "won": false, "light": 36, "defeats_left": 1,
		"ammo": {"round": 5, "chain": 3, "grape": 1},
		"ship_hp": {"hull": 55, "rigging": 80, "guns": 58}, "fort_hp": 47,
	}
	_check(session.enter_rest(result), "Next result can settle the order")
	var second_state: Dictionary = session.get_state()
	var ledger: Array = session.get_ledger()
	var entry: Dictionary = ledger[1]
	_check(second_state.day == 2 and ledger.size() == 2, "Exactly one calendar day and entry are added")
	_check(second_state.light == 33 and entry.tier == "faint", "Fixed output uses the lamp tier after the order")
	_check(second_state.materials == 5 and second_state.research == 2, "Actual costs and fixed output are recorded in stock")
	_check(second_state.ammo == {"round": 19, "chain": 5, "grape": 2}, "Order ammunition survives on top of reported battle stock")
	_check(second_state.ship_level == 2 and second_state.ship_hp == {"hull": 90, "rigging": 90, "guns": 70}, "Repair uses the post-upgrade caps and actual battle damage")
	_check(second_state.fort_hp == 47 and second_state.defeats_left == 1, "Remaining fort durability and losses come from battle")
	_check(entry.auto_fort_repair == 12 and entry.battle_delta.fort_hp == -33 and not entry.won, "Ledger separates automatic repair from battle damage")
	var event_ids: Array = entry.order_items.map(func(item: Dictionary) -> String: return item.event)
	_check(event_ids == ["regular", "upgrade", "repair", "forge"], "Ledger follows settlement order")
	_check(entry.order_items[0].bonus_delta == {"light": 3, "ammo": {"round": 2}}, "Ledger records the recommendation bonus")
	_check(entry.order_items[2].delta.ship_hp == {"hull": 25, "guns": 2}, "Ledger reports actual repair up to cap")
	_check(entry.fixed_output == {"materials": 4, "research": 2, "ammo": {"round": 1, "chain": 1}}, "Ledger reports actual fixed yield")
	_check(not session.enter_rest(result) and not session.enter_rest(_result()), "Duplicate and stale results are rejected")
	_check(session.get_state() == second_state and session.get_ledger() == ledger, "Rejected results change no resources, date or history")
	_check(session.retry_battle().is_empty() and session.get_draft().regular == "", "Return consumes retry point and opens a fresh draft")


func _check_locked_recommendation(session_script: Script) -> void:
	var session = session_script.new()
	var first := _result()
	first.light = 70
	session.enter_rest(first)
	session.select("regular", "trade")
	session.start_battle()
	var second := _result(2)
	second.light = 34
	_check(session.enter_rest(second), "Lower lamp tier is accepted after battle")
	var entry: Dictionary = session.get_ledger()[1]
	_check(entry.order_items[0].bonus_delta == {"materials": 2, "light": 4}, "Lower battle lamp tier cannot change the locked recommendation")
	_check(entry.tier == "warm" and session.get_state().light == 35, "Bonus can lift the final fixed-output tier")


func _check_full_repairs(session_script: Script) -> void:
	for repair in ["repair_ship", "repair_fort"]:
		var session = session_script.new()
		var first := _result()
		first.fort_hp = 96
		_check(session.enter_rest(first), "Repair scenario accepts the opening result")
		session.select("regular", "trade")
		session.select("repair", repair)
		var start: Dictionary = session.start_battle()
		_check(start.fort_hp == 100, "Automatic repair is capped")
		var result := _result(2)
		result.ship_hp = {"hull": 100, "rigging": 80, "guns": 60}
		result.fort_hp = 100
		_check(session.enter_rest(result), "Full durability is a valid battle result")
		var entry: Dictionary = session.get_ledger()[1]
		_check(entry.order_items[2].repair_skipped and entry.order_items[2].delta.is_empty(), "Full durability skips the repair fee")
		_check(session.get_state().materials == 24 and entry.auto_fort_repair == 4, "Inventory and automatic repair reflect the effective amounts")


func _check_battle_result_validation(session_script: Script) -> void:
	var session = session_script.new("hard", 7)
	var opening: Dictionary = session.retry_battle()
	_check(opening.battle_id == 7 and opening.difficulty == "hard", "First battle ID and difficulty can be supplied")
	_check(not session.enter_rest(_result(8)), "Future result cannot skip a battle")
	var malformed := _result(7)
	malformed.ammo.round = -1
	_check(not session.enter_rest(malformed), "Negative ammunition result is rejected")
	malformed = _result(7)
	malformed.ship_hp.guns = 900
	_check(not session.enter_rest(malformed), "Unrepresentable durability result is rejected")
	malformed = _result(7)
	malformed.won = "true"
	_check(not session.enter_rest(malformed), "Non-boolean victory is rejected")
	_check(session.retry_battle() == opening and session.get_ledger().is_empty(), "Invalid inputs leave the opening battle retryable")
	_check(session.enter_rest(_result(7)), "The expected result remains acceptable")
	var state_copy: Dictionary = session.get_state()
	state_copy.ammo.round = 0
	var ledger_copy: Array = session.get_ledger()
	ledger_copy[0].fixed_output.materials = 0
	_check(session.get_state().ammo.round > 0 and session.get_ledger()[0].fixed_output.materials > 0, "Views cannot mutate session state or ledger through copies")
	_check(not session.select("regular", "skip") and not session.select("unknown", "skip"), "Invalid event or choice is rejected")
	_check(session.select("forge", "forge_chain") and session.select("forge", "skip"), "An optional event can return to skip")


func _check_compass_reentry(session_script: Script) -> void:
	var compass := Compass.new()
	var options: Array[Dictionary] = [
		{"id": "mobilize", "title": "积极备战"},
		{"id": "trade", "title": "大力经营"},
		{"id": "rest", "title": "平安度日"},
	]
	var session = session_script.new()
	session.enter_rest(_result())
	session.select("regular", "trade")
	compass.show_choices(options, session.get_draft().regular, "mobilize")
	_check(not is_equal_approx(compass.get("_needle_angle"), -PI / 2.0), "Selected compass needle points away from the initial recommendation")

	session.start_battle()
	session.enter_rest(_result(2))
	compass.show_choices(options, session.get_draft().regular, "mobilize")
	_check(is_equal_approx(compass.get("_needle_angle"), -PI / 2.0), "Compass parks on the recommendation when returning to a fresh draft")
	_check(session.preview().requires_regular and session.start_battle().is_empty(), "The parked needle does not confirm a choice")
	compass.free()


func _result(battle_id: int = 1) -> Dictionary:
	return {
		"battle_id": battle_id, "won": true, "light": 60, "defeats_left": 2,
		"ammo": {"round": 8, "chain": 4, "grape": 2},
		"ship_hp": {"hull": 76, "rigging": 52, "guns": 49}, "fort_hp": 68,
	}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
