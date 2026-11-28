extends Control

signal battle_started(snapshot: Dictionary)

const Compass := preload("res://Scripts/Management/management_compass.gd")
const Rules := preload("res://Scripts/Management/management_rules.gd")
const Session := preload("res://Scripts/Management/management_session.gd")
const MATERIAL_ICON := preload("res://Assets/Art/UI/Management/materials.png")
const AMMO_ICON := preload("res://Assets/Art/UI/Management/ammo.png")
const LIGHT_ART := preload("res://Assets/Art/UI/Management/denghuo.png")
const LIGHT_FRAME_X := {"faint": 0, "warm": 32, "bright": 64}

const MUTED := Color("#4e594e")
const SEAL := Color("#a63127")
const SCALAR_LABELS := {
	"materials": "材料", "research": "研究点", "light": "灯火",
	"ship_level": "船级", "fort_level": "堡级", "fort_hp": "碉堡耐久", "defeats_left": "余败场",
}
var _session: Session
var _battle_scene: PackedScene
var _day := -1
var _event_index := 0
var _ledger_index := -1
var _ledger: Array[Dictionary] = []
var _badges := {}
var _status_values := {}
var _status_titles := {}
var _buttons: Dictionary[String, Button] = {}

@onready var _supplies: HBoxContainer = %Supplies
@onready var _defenses: HBoxContainer = %Defenses
@onready var _light_art: TextureRect = %LightArt
@onready var _light_value: Label = %LightValue
@onready var _calendar_day: Label = %CalendarDay
@onready var _event_page: Label = %EventPage
@onready var _event_title: Label = %EventTitle
@onready var _previous_event: Button = %PreviousEvent
@onready var _next_event: Button = %NextEvent
@onready var _compass: Compass = %Compass
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


func bind_session(session: Session, battle_scene: PackedScene = null) -> void:
	_battle_scene = battle_scene
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
	_supplies.add_child(_resource_icon(MATERIAL_ICON, Vector2(38, 34)))
	_add_status_cell(_supplies, "materials", "材料")
	_supplies.add_child(VSeparator.new())
	_supplies.add_child(_resource_icon(AMMO_ICON, Vector2(31, 31)))
	for key in Rules.AMMO_NAMES:
		_add_status_cell(_supplies, key, Rules.AMMO_NAMES[key])
	_supplies.add_child(VSeparator.new())
	_add_status_cell(_supplies, "research", "研究点")
	_add_status_cell(_defenses, "ship", "战船", 2.1)
	_defenses.add_child(VSeparator.new())
	_add_status_cell(_defenses, "fort", "碉堡")


func _resource_icon(texture: Texture2D, minimum_size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = minimum_size
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _add_status_cell(parent: HBoxContainer, key: String, caption: String, ratio: float = 1.0) -> void:
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_stretch_ratio = ratio
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 1)
	var title := _label(caption, &"Muted")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var value := _label("", &"Heading")
	value.add_theme_font_size_override("font_size", 22)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.mouse_filter = Control.MOUSE_FILTER_PASS
	stack.add_child(title)
	stack.add_child(value)
	parent.add_child(stack)
	_status_titles[key] = title
	_status_values[key] = value


func _render_status(state: Dictionary) -> void:
	for key in Rules.BALANCES:
		_status_values[key].text = str(state[key])
	for key in Rules.AMMO_NAMES:
		_status_values[key].text = str(state.ammo[key])
	var tier := Rules.light_tier(state.light)
	var light_frame := AtlasTexture.new()
	light_frame.atlas = LIGHT_ART
	light_frame.region = Rect2(LIGHT_FRAME_X[tier.id], 0, 32, 11)
	light_frame.filter_clip = true
	_light_art.texture = light_frame
	_light_value.text = "灯火 · %s %d" % [tier.title, state.light]
	_light_value.tooltip_text = "%d / 100" % state.light
	_calendar_day.text = "第 %d 日" % state.day

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

	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_badges.clear()
	var compass_options: Array[Dictionary] = []
	var options: Array = Rules.OPTIONS[event]
	var row_height := 46.0 if options.size() > 3 else 63.0
	for option in options:
		var available := Rules.option_available(event, option.id, state)
		_add_option(option, available, option.id == recommendation, row_height)
		if available:
			if option.id == recommendation:
				compass_options.push_front(option)
			else:
				compass_options.append(option)
	_compass.show_choices(compass_options, _session.get_draft()[event], recommendation)


func _add_option(option: Dictionary, available: bool, recommended: bool, row_height: float) -> void:
	var button := Button.new()
	button.name = option.id
	button.theme_type_variation = &"Choice"
	button.custom_minimum_size.y = row_height
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
	row.offset_left = 20
	row.offset_right = -20

	var badge := _label("◇", &"Heading")
	badge.custom_minimum_size.x = 30
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(badge)
	_badges[option.id] = badge

	var title := _label(option.title, &"Heading")
	title.custom_minimum_size.x = 104.0
	title.add_theme_font_size_override("font_size", 21)
	if not available:
		title.add_theme_color_override("font_color", MUTED)
	row.add_child(title)
	var detail := _label(option.description, &"Muted")
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_font_size_override("font_size", 16)
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(detail)

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
	var lines := PackedStringArray()
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
	_budget.text = "预留  材料 %d/%d  ·  研究 %d/%d" % [
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
		if _battle_scene != null:
			var battle := _battle_scene.instantiate()
			battle.management_session = _session
			get_tree().change_scene_to_node(battle)


func _label(content: String, variant: StringName) -> Label:
	var label := Label.new()
	label.text = content
	label.theme_type_variation = variant
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
