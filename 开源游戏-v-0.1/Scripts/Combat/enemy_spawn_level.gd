class_name EnemySpawnLevel
extends Resource

enum Formation { NONE, SNAKE, BUTTERFLY }

@export var level_id := 1
@export var display_name: String
@export_enum("day", "night") var time_of_day := "day"
@export_enum("clear", "storm") var weather := "clear"
@export_range(0, 500, 1, "or_greater") var budget := 30
@export var allowed_types: Array[EnemyShipConfig.Type] = []
@export var must_spawn: Dictionary[EnemyShipConfig.Type, int] = {}
@export var formation_pool: Array[Formation] = []
## 第 2 关优先把两艘必出普通船放在长蛇阵的头尾。
@export var reserve_required_for_snake := false
@export_range(0.0, 1.0, 0.01) var formation_chance := 0.4
@export_range(1, 15) var max_alive := 15
@export var storm_wave_scale := 1.4


func wave_amplitude_scale() -> float:
	return storm_wave_scale if weather == "storm" else 1.0
