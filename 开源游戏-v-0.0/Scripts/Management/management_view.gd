extends Control

signal battle_started(snapshot: Dictionary)

const Compass := preload("res://Scripts/Management/management_compass.gd")
const Rules := preload("res://Scripts/Management/management_rules.gd")
const Session := preload("res://Scripts/Management/management_session.gd")

const INK := Color("#242d2a")
const MUTED := Color("#4e594e")
const SEAL := Color("#a63127")
const SCALAR_LABELS := {
	"materials": "材料", "research": "研究点", "light": "灯火",
	"ship_level": "船级", "fort_level": "堡级", "fort_hp": "碉堡耐久", "defeats_left": "余败场",
}
const STATUS_CELLS := [
	["materials", "材料", 0.86], ["round", "实心弹", 0.86], ["chain", "链弹", 0.86],
	["grape", "霰弹", 0.86], ["research", "研究点", 0.91], ["light", "灯火", 1.42],
	["day", "日历", 0.99], ["ship", "战船", 2.09], ["fort", "碉堡", 1.49],
]

var _session: Session
var _day := -1
var _event_index := 0
var _ledger_index := -1
var _ledger: Array[Dictionary] = []
var _badges := {}
var _status_values := {}
var _status_titles := {}
var _buttons: Dictionary[String, Button] = {}

@onready var _status: HBoxContainer = %Status
@onready var _event_page: Label = %EventPage
@onready var _event_title: Label = %EventTitle
@onready var _previous_event: Button = %PreviousEvent
@onready var _next_event: Button = %NextEvent
@onready var _compass: Compass = %Compass
@onready var _compass_hint: Label = %CompassHint
@onready var _preview_effect: RichTextLabel = %PreviewEffect
@onready var _budget: Label = %Budget
@onready var _story: Label = %Story
@onready var _choices: VBoxContainer = %Choices
@onready var _ledger_date: Label = %LedgerDate
@onready var _ledger_body: RichTextLabel = %LedgerBody
@onready var _ledger_scroll: ScrollContainer = %LedgerScroll
@onready var _ledger_page: Label = %LedgerPage
@onready var _previous_entry: Button = %PreviousEntry
@onready var _next_entry: Button = %NextEntry
@onready var _departure_status: Label = %DepartureStatus
@onready var _start: Button = %StartBattle


func _ready() -> void:
	_create_status_cells()
	_previous_event.pressed.connect(_move_event.bind(-1))
	_next_event.pressed.connect(_move_event.bind(1))
	_previous_entry.pressed.connect(_move_ledger.bind(-1))
	_next_entry.pressed.connect(_move_ledger.bind(1))
	_compass.choice_requested.connect(_choose)
	_start.pressed.connect(_depart)
	_refresh()


func bind_session(session: Session) -> void:
	if _session == session:
		return
	if _session != null:
		_session.changed.disconnect(_refresh)
	_session = session
	_day = -1
	if _session != null:
		_session.changed.connect(_refresh)
	if is_node_ready():
		_refresh()


func _refresh() -> void:
	visible = _session != null and _session.is_resting()
	if not visible:
		return
	var state := _session.get_state()
	if _day != state.day:
		_day = state.day
		_event_index = 0
		_ledger = _session.get_ledger()
		_ledger_index = _ledger.size() - 1
		_render_status(state)
		_render_event(state)
		_render_ledger()
	_render_order(state)


func _create_status_cells() -> void:
	for cell in STATUS_CELLS:
		if _status.get_child_count() > 0:
			_status.add_child(VSeparator.new())
		var stack := VBoxContainer.new()
		stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.size_flags_stretch_ratio = cell[2]
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		stack.add_theme_constant_override("separation", 2)
		var title := _label(cell[1], &"Muted")
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var value := _label("", &"Heading")
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(title)
		stack.add_child(value)
		_status.add_child(stack)
		_status_titles[cell[0]] = title
		_status_values[cell[0]] = value


func _render_status(state: Dictionary) -> void:
	for key in Rules.BALANCES:
		_status_values[key].text = str(state[key])
	for key in Rules.AMMO_NAMES:
		_status_values[key].text = str(state.ammo[key])
	_status_values.light.text = "%s %d" % [Rules.light_tier(state.light).title, state.light]
	_status_values.light.tooltip_text = "%d / 100" % state.light
	_status_values.light.add_theme_color_override("font_color", Color("#276361"))
	_status_values.day.text = "第 %d 日" % state.day

	var caps := Rules.ship_caps(state.ship_level)
	var part_status := PackedStringArray()
	var part_detail := PackedStringArray()
	for key in Rules.PART_NAMES:
		part_status.append("%s %d%%" % [Rules.PART_NAMES[key], roundi(100.0 * state.ship_hp[key] / caps[key])])
		part_detail.append("%s %d / %d" % [Rules.PART_NAMES[key], state.ship_hp[key], caps[key]])
	_status_titles.ship.text = "战船 · %d 级" % state.ship_level
	_status_values.ship.add_theme_font_size_override("font_size", 15)
	_status_values.ship.text = "  ".join(part_status)
	_status_values.ship.tooltip_text = "\n".join(part_detail)
	_status_titles.fort.text = "碉堡 · %d 级" % state.fort_level
	_status_values.fort.add_theme_font_size_override("font_size", 17)
	_status_values.fort.text = "%d / %d" % [state.fort_hp, Rules.fort_cap(state.fort_level)]


func _move_event(offset: int) -> void:
	_event_index = clampi(_event_index + offset, 0, Rules.EVENT_IDS.size() - 1)
	var state := _session.get_state()
	_render_event(state)
	_render_order(state)


func _render_event(state: Dictionary) -> void:
	var event: String = Rules.EVENT_IDS[_event_index]
	var recommendation: String = Rules.light_tier(state.light).recommendation if event == "regular" else ""
	_event_page.text = "事件 %d / %d" % [_event_index + 1, Rules.EVENT_IDS.size()]
	_event_title.text = Rules.EVENTS[event].title
	_story.text = Rules.EVENTS[event].story
	_previous_event.disabled = _event_index == 0
	_next_event.disabled = _event_index == Rules.EVENT_IDS.size() - 1
	_compass_hint.text = "拖动罗盘选项"

	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_badges.clear()
	var compass_options: Array[Dictionary] = []
	for option in Rules.OPTIONS[event]:
		var available := Rules.option_available(event, option.id, state)
		_add_option(option, available, option.id == recommendation)
		if available:
			if option.id == recommendation:
				compass_options.push_front(option)
			else:
				compass_options.append(option)
	_compass.show_choices(compass_options, _session.get_draft()[event], recommendation)


func _add_option(option: Dictionary, available: bool, recommended: bool) -> void:
	var button := Button.new()
	button.name = option.id
	button.custom_minimum_size.y = 62.0
	button.toggle_mode = true
	button.disabled = not available
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.accessibility_name = option.title
	button.accessibility_description = option.description
	button.pressed.connect(_choose.bind(option.id))
	_choices.add_child(button)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	button.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -14

	var badge := _label("◇", &"Heading")
	badge.custom_minimum_size.x = 28
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(badge)
	_badges[option.id] = badge

	var copy := VBoxContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 0)
	var title := _label(option.title, &"Heading")
	title.add_theme_font_size_override("font_size", 22)
	copy.add_child(title)
	var detail := _label(option.description, &"Muted")
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(detail)
	row.add_child(copy)

	var costs: Dictionary = option.get("costs", {})
	var tag := ""
	for key in costs:
		tag = "%d %s" % [costs[key], SCALAR_LABELS[key]]
	if recommended:
		tag = "民意"
	if not available:
		tag = "已达上限"
	if not tag.is_empty():
		var tag_label := _label(tag, &"Muted")
		tag_label.add_theme_color_override("font_color", SEAL if recommended else MUTED)
		row.add_child(tag_label)
	_buttons[option.id] = button


func _choose(choice: String) -> void:
	var event: String = Rules.EVENT_IDS[_event_index]
	if _session.select(event, choice):
		_sync_choice(_session.get_draft()[event])


func _sync_choice(selection: String) -> void:
	_compass.set_selection(selection)
	for id in _buttons:
		var selected := id == selection
		_buttons[id].set_pressed_no_signal(selected)
		_badges[id].text = "◆" if selected else "◇"
		_badges[id].add_theme_color_override("font_color", SEAL if selected else MUTED)


func _render_order(state: Dictionary) -> void:
	var event: String = Rules.EVENT_IDS[_event_index]
	var selection: String = _session.get_draft()[event]
	_sync_choice(selection)
	var preview := _session.preview()
	var lines := PackedStringArray(["按现况估算，实际以战果为准"])
	if selection.is_empty():
		lines.append("选择一项以查看变化")
	else:
		for item in preview.items:
			if item.event == event:
				lines.append(_format_changes(item.delta))
				if item.favored:
					lines.append("民意加成  " + _format_changes(item.bonus_delta))
				if item.repair_skipped:
					lines.append("满耐久时免修理费")
				break
	_preview_effect.text = "\n".join(lines)
	_budget.text = "整单预留  材料 %d/%d  ·  研究 %d/%d" % [
		preview.costs.materials, state.materials, preview.costs.research, state.research,
	]

	var blockers := PackedStringArray()
	if preview.requires_regular:
		blockers.append("请先选择常规经营")
	var shortage := PackedStringArray()
	for key in preview.shortages:
		shortage.append("%s %d" % [SCALAR_LABELS[key], preview.shortages[key]])
	if not shortage.is_empty():
		blockers.append("预算不足，缺 " + "、".join(shortage))
	_start.disabled = not blockers.is_empty()
	_departure_status.add_theme_color_override("font_color", SEAL if _start.disabled else MUTED)
	_departure_status.text = "\n".join(blockers) if _start.disabled else (
		"开战前自动修堡 +%d" % preview.auto_fort_repair if preview.auto_fort_repair > 0 else "碉堡已满耐久"
	)


func _move_ledger(offset: int) -> void:
	_ledger_index = clampi(_ledger_index + offset, 0, _ledger.size() - 1)
	_render_ledger()


func _render_ledger() -> void:
	var entry := _ledger[_ledger_index]
	_ledger_date.text = "第 %d 日 · 第 %d 战" % [entry.day, entry.battle_id]
	_ledger_page.text = "%d / %d" % [_ledger_index + 1, _ledger.size()]
	_previous_entry.disabled = _ledger_index == 0
	_next_entry.disabled = _ledger_index == _ledger.size() - 1

	var lines := PackedStringArray()
	lines.append("[b]战果 · %s[/b]\n%s" % ["胜利" if entry.won else "败退", _format_changes(entry.battle_delta)])
	if entry.auto_fort_repair > 0:
		lines.append("开战前修堡  [color=#276361]+%d[/color]" % entry.auto_fort_repair)
	if not entry.order_items.is_empty():
		lines.append("\n[b]上轮订单[/b]")
		for item in entry.order_items:
			var title: String = Rules.option(item.event, item.choice).title
			if item.choice == "skip":
				lines.append(title)
				continue
			var effect := "满耐久 · 免修理费" if item.repair_skipped else _format_changes(item.delta)
			lines.append("%s\n%s" % [title, effect])
			if item.favored:
				lines.append("民意加成  " + _format_changes(item.bonus_delta))
	for tier in Rules.LIGHT_TIERS:
		if tier.id == entry.tier:
			lines.append("\n[b]固定产出 · %s[/b]\n%s" % [tier.title, _format_changes(entry.fixed_output)])
			break
	_ledger_body.text = "\n".join(lines)
	_ledger_scroll.set_deferred("scroll_vertical", 0)


func _depart() -> void:
	var snapshot := _session.start_battle()
	if not snapshot.is_empty():
		battle_started.emit(snapshot)


func _label(content: String, variant: StringName) -> Label:
	var label := Label.new()
	label.text = content
	label.theme_type_variation = variant
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _format_changes(delta: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in SCALAR_LABELS:
		if delta.has(key):
			parts.append(_format_change(SCALAR_LABELS[key], delta[key]))
	for key in delta.get("ammo", {}):
		parts.append(_format_change(Rules.AMMO_NAMES[key], delta.ammo[key]))
	for key in delta.get("ship_hp", {}):
		parts.append(_format_change(Rules.PART_NAMES[key], delta.ship_hp[key]))
	return "暂无变化" if parts.is_empty() else "  ".join(parts)


func _format_change(title: String, amount: int) -> String:
	var color := "#276361" if amount > 0 else "#9f3025"
	return "%s [color=%s]%+d[/color]" % [title, color, amount]
