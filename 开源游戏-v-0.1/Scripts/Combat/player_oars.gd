extends Node2D

const OAR_ART := preload("res://Assets/Art/Characters/player_oar.png")
const OARLOCKS := [
	Vector2(12, 48), Vector2(18, 48), Vector2(24, 48), Vector2(30, 48),
	Vector2(36, 47), Vector2(42, 46), Vector2(48, 45),
]

var _oars: Array[Sprite2D] = []
var _phase := 0.0
var _effort := 0.0
var _heading := 1.0


func _ready() -> void:
	for oarlock: Vector2 in OARLOCKS:
		var oar := Sprite2D.new()
		oar.texture = OAR_ART
		oar.centered = false
		oar.offset = Vector2(-11.5, -4.0)
		oar.position = oarlock - Vector2(32, 32)
		add_child(oar)
		_oars.append(oar)
	update_stroke(0.0, 0.0)


func update_stroke(delta: float, direction: float) -> void:
	var rowing := not is_zero_approx(direction)
	_effort = move_toward(_effort, 1.0 if rowing else 0.0, delta * 6.0)
	if rowing:
		_heading = move_toward(_heading, direction, delta * 12.0)
	if _effort > 0.0:
		_phase = fposmod(_phase + delta * 1.38 * _effort, 1.0)
	for index in range(_oars.size()):
		var oar := _oars[index]
		var stroke := TAU * (_phase - float(index) * 0.025)
		# The blade extends into the water on the pull and feathers on the recovery.
		var rest_angle := 0.40 + float(index) * 0.028
		var sweep := -cos(stroke) * 0.65 * _heading
		var length := lerpf(0.58, 1.24, (1.0 + sin(stroke)) * 0.5)
		var pose := Transform2D(lerpf(rest_angle, sweep, _effort), oar.position)
		pose.x *= 0.86
		pose.y *= lerpf(0.68, length, _effort)
		# The supplied oar points down-left. Align its shaft with the stroke's local Y axis.
		oar.transform = pose.rotated_local(-PI / 4.0)


func _draw() -> void:
	for oarlock: Vector2 in OARLOCKS:
		var center := oarlock - Vector2(32, 32)
		draw_rect(Rect2(center - Vector2(1.5, 1.5), Vector2(3, 3)), Color("#281807"))
		draw_rect(Rect2(center - Vector2(0.5, 1.5), Vector2(1, 1)), Color("#c68148"))
