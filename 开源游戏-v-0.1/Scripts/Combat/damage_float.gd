class_name DamageFloat
extends RefCounted


static func spawn(host: Node, global_pos: Vector2, amount: float, tint: Color) -> void:
	if amount < 0.5:
		return
	var label := Label.new()
	label.text = "-%.1f" % amount
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 20)
	label.add_theme_color_override(&"font_color", tint)
	label.add_theme_color_override(&"font_outline_color", Color(0.05, 0.05, 0.07))
	label.add_theme_constant_override(&"outline_size", 4)
	host.add_child(label)
	label.position = global_pos + Vector2(-label.size.x * 0.5, -28.0)
	label.z_index = 120
	var tween := label.create_tween().set_parallel().set_ignore_time_scale(true)
	tween.tween_property(label, "position:y", label.position.y - 26.0, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)
