class_name DamageFloat
extends Node2D

## 伤害飘字：在受击位置冒一个 "-N"，上飘淡出后自毁。
## 由 ShipCombat.receive_hit() 调用，挂在战斗场景根节点下（避免跟随船只的 1/4 缩放）。

const FONT_SIZE := 20
const RISE := 36.0
const LIFE := 0.7
const OUTLINE := 4


static func spawn(host: Node, global_pos: Vector2, amount: float, tint: Color) -> void:
	if host == null or amount < 1.0:
		return
	var node := Label.new()
	node.name = "DamageFloat"
	node.text = "-%d" % roundi(amount)
	node.add_theme_font_size_override("font_size", FONT_SIZE)
	node.add_theme_color_override("font_color", tint)
	node.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.07, 0.9))
	node.add_theme_constant_override("outline_size", OUTLINE)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.z_index = 120
	node.z_as_relative = false
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE

	host.add_child(node)
	var root := host as Node2D
	var start := global_pos + Vector2(-14.0, -24.0)
	node.position = root.to_local(start) if root != null else start

	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "position:y", node.position.y - RISE, LIFE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "modulate:a", 0.0, LIFE * 0.55).set_delay(LIFE * 0.45)
	tween.set_parallel(false)
	tween.tween_callback(node.queue_free)
