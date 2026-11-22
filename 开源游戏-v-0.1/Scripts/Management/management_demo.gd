extends Control

const ManagementView := preload("res://Scripts/Management/management_view.gd")
const Rules := preload("res://Scripts/Management/management_rules.gd")
const Session := preload("res://Scripts/Management/management_session.gd")

var _session := Session.new()
var _snapshot := {}
var _retry_count := 0

@onready var _management: ManagementView = $Management
@onready var _battle_panel: Control = %BattlePanel
@onready var _battle_title: Label = %BattleTitle
@onready var _battle_snapshot: Label = %BattleSnapshot
@onready var _retry_status: Label = %RetryCount


func _ready() -> void:
	get_window().title = "港口休整 · 经营联调"
	_management.bind_session(_session)
	_management.battle_started.connect(_show_battle)
	%MockWin.pressed.connect(_return_from_battle.bind(true))
	%MockLoss.pressed.connect(_return_from_battle.bind(false))
	%Retry.pressed.connect(_retry)
	var opening := _session.retry_battle()
	_session.enter_rest({
		"battle_id": opening.battle_id, "won": true,
		"light": opening.light, "defeats_left": opening.defeats_left, "ammo": opening.ammo,
		"ship_hp": {"hull": 76, "rigging": 52, "guns": 49}, "fort_hp": 68,
	})


func _show_battle(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	_retry_count = 0
	_render_snapshot()
	_battle_panel.show()


func _retry() -> void:
	_snapshot = _session.retry_battle()
	_retry_count += 1
	_render_snapshot()


func _render_snapshot() -> void:
	_battle_title.text = "模拟开战 · 第 %d 战" % _snapshot.battle_id
	var lines := PackedStringArray()
	lines.append("难度  %s    灯火  %d / 100    余败场  %d" % [
		_snapshot.difficulty, _snapshot.light, _snapshot.defeats_left,
	])
	var ammo := PackedStringArray()
	for key in Rules.AMMO_NAMES:
		ammo.append("%s %d" % [Rules.AMMO_NAMES[key], _snapshot.ammo[key]])
	lines.append("弹药  " + "   ".join(ammo))
	var ship := PackedStringArray()
	var caps := Rules.ship_caps(_snapshot.ship_level)
	for key in Rules.PART_NAMES:
		ship.append("%s %d/%d" % [Rules.PART_NAMES[key], _snapshot.ship_hp[key], caps[key]])
	lines.append("战船 · %d 级    %s" % [_snapshot.ship_level, "   ".join(ship)])
	lines.append("碉堡 · %d 级    耐久 %d/%d" % [
		_snapshot.fort_level, _snapshot.fort_hp, Rules.fort_cap(_snapshot.fort_level),
	])
	_battle_snapshot.text = "\n".join(lines)
	_retry_status.text = (
		"已重打 %d 次，复用开战时的补给与耐久" % _retry_count if _retry_count > 0
		else "选择战果以返回经营并结算订单"
	)


func _return_from_battle(won: bool) -> void:
	if _snapshot.is_empty():
		return
	var result := {
		"battle_id": _snapshot.battle_id, "won": won,
		"light": clampi(_snapshot.light + (3 if won else -24), 0, 100),
		"defeats_left": maxi(0, _snapshot.defeats_left - (0 if won else 1)),
		"ammo": {
			"round": maxi(0, _snapshot.ammo.round - 5),
			"chain": maxi(0, _snapshot.ammo.chain - 2),
			"grape": maxi(0, _snapshot.ammo.grape - 2),
		},
		"ship_hp": {
			"hull": maxi(0, _snapshot.ship_hp.hull - (18 if won else 30)),
			"rigging": maxi(0, _snapshot.ship_hp.rigging - 12),
			"guns": maxi(0, _snapshot.ship_hp.guns - 8),
		},
		"fort_hp": maxi(0, _snapshot.fort_hp - (18 if won else 33)),
	}
	if _session.enter_rest(result):
		_snapshot.clear()
		_battle_panel.hide()
