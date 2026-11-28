class_name DamageFloat
extends RefCounted


static func spawn(host: Node, global_pos: Vector2, amount: float, tint: Color) -> void:
	if amount < 0.5:
		return
	caption(host, global_pos + Vector2.UP * 28.0, "-%.1f" % amount, tint, 16)


static func caption(host: Node, global_pos: Vector2, message: String, tint: Color, font_size: int) -> void:
	var label := Label.new()
	label.text = message
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.scale = Vector2.ONE * 0.5
	label.add_theme_font_size_override(&"font_size", font_size * 2)
	label.add_theme_color_override(&"font_color", tint)
	label.add_theme_color_override(&"font_outline_color", Color(0.05, 0.05, 0.07))
	label.add_theme_constant_override(&"outline_size", 7)
	host.add_child(label)
	label.global_position = global_pos - Vector2(label.get_combined_minimum_size().x * 0.25, 0.0)
	label.z_index = 120
	var tween := label.create_tween().set_parallel().set_ignore_time_scale(true)
	tween.tween_property(label, "position:y", label.position.y - 18.0, 0.63)
	tween.tween_property(label, "modulate:a", 0.0, 0.36).set_delay(0.27)
	tween.chain().tween_callback(label.queue_free)
