## 跨场景会话：战斗 <-> 经营 的唯一数据通道。
##
## 用法（本版流程 = 一场战斗 + 一次经营就结束）：
##   1. 主场景开打前调用 begin_run()，拿到 BattleStart 快照；
##   2. 战斗结束时把 BattleResult 交给 submit_result()；
##   3. 经营场景读 session（它的 enter_rest 已经接受战果，处于休整态）。
##
## 键名严格按开发说明里的 BattleStart / BattleResult 契约，不要自己加字段。
extends Node

const Session := preload("res://Scripts/Management/management_session.gd")

## 当前这局的经营会话（RefCounted，本身不发信号以外的状态）
var session: RefCounted = null
## 本场战斗的开场快照（BattleStart），空字典 = 没有会话，按旧的大厅节奏跑
var battle_start: Dictionary = {}


func begin_run(difficulty: String = "normal", first_battle_id: int = 1) -> Dictionary:
	session = Session.new(difficulty, first_battle_id)
	battle_start = session.retry_battle()
	return battle_start.duplicate(true)


func has_session() -> bool:
	return session != null and not battle_start.is_empty()


## 提交战果；成功返回 true（会话进入休整态）
func submit_result(result: Dictionary) -> bool:
	if not has_session():
		return false
	return bool(session.enter_rest(result))


## 切到经营场景后，把会话交给经营界面（由 autoload 执行，切场景不会被打断）
var last_bound: bool = false


func bind_pending_scene() -> void:
	last_bound = false
	await get_tree().process_frame
	await get_tree().process_frame
	var scene: Node = get_tree().current_scene
	if scene != null and session != null and scene.has_method("bind_session"):
		scene.bind_session(session)
		last_bound = true


## 重开一局（本版基本用不到，留给“重玩”按钮）
func reset() -> void:
	session = null
	battle_start.clear()
