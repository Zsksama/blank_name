extends RefCounted

const EVENT_IDS := ["regular", "upgrade", "repair", "forge"]
const AMMO_NAMES := {"round": "实心弹", "chain": "破帆弹", "grape": "爆炸弹"}
const PART_NAMES := {"hull": "舰体", "rigging": "帆索", "guns": "火炮"}
const EVENTS := {
	"regular": {
		"title": "常规经营",
		"story": "战船返港，码头重新开市。乡民聚在仓廒前，等你定下这一日的营生。",
	},
	"upgrade": {
		"title": "船堡升级",
		"story": "船匠翻开图样，堡工也带来了工事清单。研究点可用来改进一处设施。",
	},
	"repair": {
		"title": "修理调度",
		"story": "工匠先备好木料与石灰，等下一战的损伤查明后再动工。满耐久时这笔工料留在仓中。",
	},
	"forge": {
		"title": "铸造弹药",
		"story": "炉火已经架起。铸匠能赶制一批炮弹，请为后续战事选好弹种。",
	},
}

const OPTIONS := {
	"regular": [
		{
			"id": "mobilize", "title": "积极备战", "description": "调集人手往炮台运弹，清点火药与备件。",
			"yield": {"light": -6, "ammo": {"round": 3, "chain": 1, "grape": 1}},
			"bonus": {"light": 3, "ammo": {"round": 2}},
		},
		{
			"id": "trade", "title": "大力经营", "description": "重开货仓与集市，召回歇业的商贩和手工匠。",
			"yield": {"materials": 6, "research": 1, "light": -3},
			"bonus": {"materials": 2, "light": 4},
		},
		{
			"id": "rest", "title": "平安度日", "description": "暂停加派差役，让船户修网归家，点亮街巷。",
			"yield": {"materials": 2, "light": 10},
			"bonus": {"research": 1, "light": 4},
		},
	],
	"upgrade": [
		{
			"id": "upgrade_ship", "title": "升级战船", "description": "加固肋骨与帆桁，提高各部位耐久上限。",
			"asset": "ship", "costs": {"research": 4},
		},
		{
			"id": "upgrade_fort", "title": "升级碉堡", "description": "增设炮位，重砌外墙，提高碉堡耐久上限。",
			"asset": "fort", "costs": {"research": 5},
		},
		{"id": "skip", "title": "暂缓升级", "description": "留存研究点，继续使用现有图样。"},
	],
	"repair": [
		{
			"id": "repair_ship", "title": "修理战船", "description": "派船匠补上各受损部位。",
			"asset": "ship", "amount": 25, "costs": {"materials": 6},
		},
		{
			"id": "repair_fort", "title": "修理碉堡", "description": "调石匠补砌裂隙与破口。",
			"asset": "fort", "amount": 35, "costs": {"materials": 5},
		},
		{"id": "skip", "title": "暂缓修理", "description": "先把工料留在仓中，应对后续损伤。"},
	],
	"forge": [
		{
			"id": "forge_round", "title": "铸实心弹", "description": "开炉浇铸铁丸，备作常用炮弹。",
			"yield": {"ammo": {"round": 8}}, "costs": {"materials": 4},
		},
		{
			"id": "forge_chain", "title": "铸破帆弹", "description": "以铁链连接弹头，瞄准敌帆与桅索。",
			"yield": {"ammo": {"chain": 5}}, "costs": {"materials": 6},
		},
		{
			"id": "forge_grape", "title": "铸爆炸弹", "description": "备好能在命中或落水时爆炸的炮弹。",
			"yield": {"ammo": {"grape": 5}}, "costs": {"materials": 8},
		},
		{"id": "skip", "title": "暂缓铸弹", "description": "封炉存料，留待下一次铸造。"},
	],
}

const LIGHT_TIERS := [
	{
		"id": "faint", "title": "渺茫", "minimum": 0, "recommendation": "rest",
		"output": {"materials": 4, "research": 2, "ammo": {"round": 1, "chain": 1}},
	},
	{
		"id": "warm", "title": "温和", "minimum": 35, "recommendation": "mobilize",
		"output": {"materials": 7, "research": 3, "ammo": {"round": 2, "chain": 1, "grape": 1}},
	},
	{
		"id": "bright", "title": "明亮", "minimum": 70, "recommendation": "trade",
		"output": {"materials": 10, "research": 4, "ammo": {"round": 3, "chain": 2, "grape": 1}},
	},
]
const DIFFICULTIES := {
	"easy": {"light": 75, "defeats_left": 3, "fort_auto_repair": 16},
	"normal": {"light": 60, "defeats_left": 2, "fort_auto_repair": 12},
	"hard": {"light": 45, "defeats_left": 1, "fort_auto_repair": 8},
}
const INITIAL_STOCK := {
	"materials": 4, "research": 1, "ammo": {"round": 8, "chain": 4, "grape": 2},
}
const SHIP_BASE_HP := {"hull": 100, "rigging": 80, "guns": 60}
const SHIP_HP_PER_LEVEL := 10
const FORT_BASE_HP := 100
const FORT_HP_PER_LEVEL := 20
const MAX_LEVEL := 3
const FORT_AUTO_REPAIR_BY_BATTLE: Dictionary[int, int] = {}
const BALANCES := ["materials", "research"]
const CHANGING_SCALARS := [
	"materials", "research", "light", "ship_level", "fort_level", "fort_hp", "defeats_left",
]


static func light_tier(light: int) -> Dictionary:
	for i in range(LIGHT_TIERS.size() - 1, 0, -1):
		if light >= LIGHT_TIERS[i].minimum:
			return LIGHT_TIERS[i]
	return LIGHT_TIERS[0]


static func ship_caps(level: int) -> Dictionary:
	var caps := {}
	for part in SHIP_BASE_HP:
		caps[part] = SHIP_BASE_HP[part] + (level - 1) * SHIP_HP_PER_LEVEL
	return caps


static func fort_cap(level: int) -> int:
	return FORT_BASE_HP + (level - 1) * FORT_HP_PER_LEVEL


static func auto_fort_repair(state: Dictionary, battle_id: int) -> int:
	var default_amount: int = DIFFICULTIES[state.difficulty].fort_auto_repair
	var amount: int = FORT_AUTO_REPAIR_BY_BATTLE.get(battle_id, default_amount)
	return mini(amount, fort_cap(state.fort_level) - state.fort_hp)


static func option(event: String, choice: String) -> Dictionary:
	for candidate in OPTIONS.get(event, []):
		if candidate.id == choice:
			return candidate
	return {}


static func option_available(event: String, choice: String, state: Dictionary) -> bool:
	var selected := option(event, choice)
	if selected.is_empty():
		return false
	return event != "upgrade" or choice == "skip" or state[selected.asset + "_level"] < MAX_LEVEL


static func order_costs(draft: Dictionary) -> Dictionary:
	var totals := {"materials": 0, "research": 0}
	for event in EVENT_IDS:
		var costs: Dictionary = option(event, draft[event]).get("costs", {})
		for key in costs:
			totals[key] += costs[key]
	return totals


static func settle(state: Dictionary, order: Dictionary) -> Dictionary:
	var settled := state.duplicate(true)
	var items: Array[Dictionary] = []
	if not order.is_empty():
		for event in EVENT_IDS:
			var choice: String = order.choices[event]
			var selected := option(event, choice)
			if selected.is_empty():
				continue
			var before := settled.duplicate(true)
			var repair_skipped := _apply_option(settled, event, selected)
			var favored: bool = event == "regular" and choice == order.recommendation
			var bonus_delta := {}
			if favored:
				var before_bonus := settled.duplicate(true)
				_add_resources(settled, selected.bonus)
				bonus_delta = changes_between(before_bonus, settled)
			items.append({
				"event": event, "choice": choice, "delta": changes_between(before, settled),
				"favored": favored, "bonus_delta": bonus_delta, "repair_skipped": repair_skipped,
			})

	var tier := light_tier(settled.light)
	var before_output := settled.duplicate(true)
	_add_resources(settled, tier.output)
	return {
		"state": settled, "items": items, "tier": tier.id,
		"fixed_output": changes_between(before_output, settled),
	}


static func changes_between(before: Dictionary, after: Dictionary) -> Dictionary:
	var changes := {}
	for key in CHANGING_SCALARS:
		var change: int = after[key] - before[key]
		if change != 0:
			changes[key] = change
	for group in ["ammo", "ship_hp"]:
		var group_changes := {}
		for key in before[group]:
			var change: int = after[group][key] - before[group][key]
			if change != 0:
				group_changes[key] = change
		if not group_changes.is_empty():
			changes[group] = group_changes
	return changes


static func _apply_option(state: Dictionary, event: String, selected: Dictionary) -> bool:
	if selected.id == "skip":
		return false
	if event == "repair" and not _repair(state, selected.asset, selected.amount):
		return true
	if event == "upgrade":
		_upgrade(state, selected.asset)

	var costs: Dictionary = selected.get("costs", {})
	for key in costs:
		state[key] -= costs[key]
	_add_resources(state, selected.get("yield", {}))
	return false


static func _repair(state: Dictionary, asset: String, amount: int) -> bool:
	if asset == "fort":
		var healed := mini(amount, fort_cap(state.fort_level) - state.fort_hp)
		state.fort_hp += healed
		return healed > 0

	var repaired := false
	var caps := ship_caps(state.ship_level)
	for part in caps:
		var healed := mini(amount, caps[part] - state.ship_hp[part])
		state.ship_hp[part] += healed
		repaired = repaired or healed > 0
	return repaired


static func _upgrade(state: Dictionary, asset: String) -> void:
	if asset == "fort":
		state.fort_level += 1
		state.fort_hp += FORT_HP_PER_LEVEL
		return
	state.ship_level += 1
	for part in state.ship_hp:
		state.ship_hp[part] += SHIP_HP_PER_LEVEL


static func _add_resources(state: Dictionary, gains: Dictionary) -> void:
	for key in BALANCES:
		state[key] += gains.get(key, 0)
	state.light = clampi(state.light + gains.get("light", 0), 0, 100)
	var ammo: Dictionary = gains.get("ammo", {})
	for key in ammo:
		state.ammo[key] += ammo[key]
