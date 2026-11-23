## 部位编号常量（与 27-数据字典 的 part_hp[5] 顺序一致）。
## 用 preload 引用，避免 class_name 依赖编辑器缓存。
extends RefCounted

enum { HULL, SAIL, CANNON, RUDDER, RAM }
const COUNT := 5
const NAMES: Array[String] = ["舰体", "帆", "炮台", "舵", "撞角"]

## 三档状态阈值（23-M4）：> 0.75 正常，0.10 < x ≤ 0.75 破损，≤ 0.10 被破坏
const THRESHOLD_BROKEN := 0.75
const THRESHOLD_DESTROYED := 0.10

const STATE_NORMAL := 0
const STATE_BROKEN := 1
const STATE_DESTROYED := 2
