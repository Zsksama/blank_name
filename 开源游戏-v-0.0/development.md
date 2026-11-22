# 休息经营 MVP 开发记录

依据实施计划和开发约定。在 `operation_dev` 上新增独立经营场景和模拟战斗入口。Godot AI MCP 和桌面验收使用项目副本，避免把验证产生的缓存带进工作区。

## 实现步骤

| 步骤 | 模块 | 完成条件 | 状态 |
| --- | --- | --- | --- |
| 1 | 战斗接口与经营会话 | `enter_rest(BattleResult)` 接收当前战果。鸣金返回 `BattleStart`，重打复用快照。重复、过期、乱序或无效输入不改变状态。 | 已实现并通过无头验收 |
| 2 | 事件与结算规则 | 草稿可回改，鸣金校验整单资金并锁定。下次经营依序结算四类事件，按最终灯火发放产出，记账并推进日历。 | 已实现并通过无头验收 |
| 3 | 经营界面 | 资源栏、罗盘、事件箭头、剧情选项、预览、账本和鸣金接入同一个会话。拖动与点击均能改选。 | 已实现并通过桌面验收 |
| 4 | 独立联调入口 | 模拟战斗供经营侧跑两轮循环。可查看开战快照，模拟胜败和重打。 | 已实现并通过模拟联调 |
| 5 | 验收与交接 | 运行 Godot 无头验收、Godot AI MCP 和桌面交互检查。记录接口、可复现命令与实测结果。 | 已完成，实际战斗接入待联调 |
| 6 | 罗盘回场修正 | 新一轮尚未选择时仍绘制灰色指针，指向当前推荐。确认选项后指针改为红色。 | 已修复并重跑回场验收 |

## 实现位置

- `Scripts/Management/management_session.gd` 持有库存、草稿、待结算订单、开战快照和账本。状态查询返回副本。
- `Scripts/Management/management_rules.gd` 集中配置试做数值，预览和结算调用同一套规则。
- `Scenes/Management/management.tscn` 提供可嵌入的经营界面，`management_demo.tscn` 是可直接运行的模拟入口。
- `Tests/Management/test_management.gd` 验证草稿隔离、整单预算、结算顺序、维修封顶、战果去重和重打。
- 界面采用纸墨木刻参考图。港口剧情背景使用 ImageGen，素材登记在项目的 `LICENSES.md`。

## 试做口径

- 战斗编号使用连续正整数，首次期望编号由会话构造参数指定。战果由战斗侧确认后交给经营，重打在战果确认前请求。
- 灯火档、三类弹药、船体三部位、初始资源、修理和产出用暂定配置。民意推荐按鸣金时的灯火锁定，固定产出使用下次结算后的灯火。
- 预算以当前库存预留整单成本。维修按战后剩余耐久计算，存在实际维修时收取配置费用。升级补齐新增耐久并保留原有损伤。
- 日历从第 1 日开始，每接纳一个战果推进一天。船体按舰体、帆索、火炮显示耐久。战斗侧负责回档入口。

## 战斗侧接入

战局控制器持有同一个会话实例。初战使用 `retry_battle()` 提供的开场快照，战斗结束后由战斗侧确认胜负、灯火及剩余败场数。接受结果后绑定经营场景。玩家鸣金时，经营场景通过 `battle_started(snapshot)` 发出下一战快照。每场战斗开打时将快照当作独立数据使用。

| 接口 | 时机与返回值 |
| --- | --- |
| `ManagementSession.new("normal", 1)` | 开局创建一次。可用难度为 `easy`、`normal`、`hard`。可指定首战编号，之后按连续整数递增。 |
| `retry_battle() -> Dictionary` | 取首次开战快照或重打尚未确认战果的当前战斗。经营阶段返回空字典。 |
| `enter_rest(result: Dictionary) -> bool` | 战斗侧确认进入休整时调用。编号必须匹配当前战斗。接收成功返回 `true`，无效值及重复、过期、乱序结果返回 `false`。 |
| `management.bind_session(session)` | 把会话绑定到 `management.tscn`。会话接受战果后显示经营，锁单后隐藏。 |
| `management.battle_started(snapshot)` | 玩家成功鸣金时发出。自行编写 UI 时也可直接调用会话的 `start_battle()`，校验未通过时返回空字典。 |

`BattleStart` 与 `BattleResult` 都是 Godot `Dictionary`。双方使用下列键名。

| 字段 | `BattleStart` | `BattleResult` |
| --- | --- | --- |
| `battle_id: int` | 本次开战编号 | 同一次战斗的编号 |
| `difficulty: String` | 会话难度 | — |
| `won: bool` | — | 由战斗侧确认 |
| `light: int` | 开战灯火 | 战后灯火，范围 0 至 100 |
| `ammo: Dictionary` | 开战弹药 | 战后弹药，键为 `round` 实心弹、`chain` 链弹、`grape` 霰弹 |
| `ship_level: int`、`fort_level: int` | 开战船堡等级 | — |
| `ship_hp: Dictionary` | 开战各部位耐久 | 战后耐久，键为 `hull` 舰体、`rigging` 帆索、`guns` 火炮 |
| `fort_hp: int` | 自动修复后的开战耐久 | 战后耐久 |
| `defeats_left: int` | 开战前还能承担的败场数 | 战斗侧更新后的余败场 |

耐久和库存均为非负整数。耐久上限由 `ManagementRules.ship_caps(level)` 和 `fort_cap(level)` 计算。战斗中的结果按开战等级校验。要重打时，战斗侧先调用 `retry_battle()`，再重新载入现场。战果提交成功后，当前订单和该场重打点已消费。

```gdscript
const ManagementSession := preload("res://Scripts/Management/management_session.gd")
var session := ManagementSession.new("normal", 1)
var first_start := session.retry_battle()
var first_result := {
	"battle_id": first_start.battle_id,
	"won": true,
	"light": 60,
	"ammo": {"round": 8, "chain": 4, "grape": 2},
	"ship_hp": {"hull": 76, "rigging": 52, "guns": 49},
	"fort_hp": 68,
	"defeats_left": 2,
}
# 战斗侧确认进入休整后调用。绑好会话的经营场景会刷新。
var accepted := session.enter_rest(first_result)
```

以该示例战果进入首轮，先后选积极备战、升级战船、修理战船、铸实心弹，鸣金得到以下 `BattleStart`。

```gdscript
{
	"battle_id": 2, "difficulty": "normal", "light": 60, "defeats_left": 2,
	"ammo": {"round": 10, "chain": 5, "grape": 3},
	"ship_level": 1, "ship_hp": {"hull": 76, "rigging": 52, "guns": 49},
	"fort_level": 1, "fort_hp": 80,
}
```

## 本地运行

在 Godot 打开 `Scenes/Management/management_demo.tscn` 后按 **F6**。联调场景自动注入第 1 战战果。选完订单后鸣金，快照页可以模拟胜利、失败或重打。

在 Godot 项目根目录运行以下命令。Windows 用本机 Godot 可执行文件替换 `godot`。

```powershell
godot --headless --path . --import
godot --path . res://Scenes/Management/management_demo.tscn
godot --headless --path . --script res://Tests/Management/test_management.gd
```

## 验收记录 · 2026-11-22

### 无头验收

- Godot 4.7.2 的 `test_management.gd` 通过 64/64 项断言。覆盖首轮产出、订单预算、战后结算顺序、满耐久免修理费、自动修堡封顶、重复鸣金、无效及重复战果、重打和罗盘回场。
- 使用 Git 中的项目配置和无插件的临时副本，从空缓存导入，然后分别启动经营联调场景和原战斗主场景。进程均以 0 退出，引擎日志无错误。

### Godot AI MCP

- 在隔离副本中创建经营场景和联调场景的根节点。重新加载实现后，MCP 成功启动联调场景，运行时助手返回 `live`。
- 罗盘修复后再次用 MCP 选择大力经营、鸣金、模拟失败。第 2 日画面可见灰色指针指向新灯火档推荐的平安度日，账本为 2/2。鸣金保持禁用，等待当轮常规经营确认。

### Windows 桌面验收

- 在 1280×720 用鼠标点击选项、拖动罗盘、切换事件再返回，核对指针、选中项和预览。库存、日历与账本在草稿修改期间维持原值。
- 验证升级碉堡提示缺 1 研究点，修船和铸霰弹合计提示缺 3 材料。改为升级船和铸实心弹后鸣金，开战船级仍为 1，弹药为 10/5/3，碉堡耐久由 68 升到 80。重打后开战数值一致。
- 模拟失败后进入第 2 日，材料 5、研究点 2、弹药 19/5/2、灯火 33、船级 2，碉堡耐久 47。滚动账本检查订单、维修和渺茫档固定产出，再在两日之间翻页。
- 在 1600×720 查看宽窗口的资源栏、三栏和鸣金按钮。中栏随窗口加宽，右下角鸣金可见。

### Markdown 与 Git

- 用 UTF-8 严格读取 `.local/AGENTS.md`、`.local/plan.md` 和本文件，均可解码。`git check-ignore` 确认三份文件命中根目录的 `/.local` 规则。

### 实际战斗联调

战斗侧接入后，需要核对实际弹药余量、各部位损伤、余败场数和回档调用次序。目前双向接口使用模拟战果验收。

## 港口插画

素材使用内置 ImageGen 生成，保存至 `Assets/Art/UI/management_harbor.png`。生成提示词如下。

> Create a single full-bleed panoramic 2D game background for an original Chinese coastal harbor management game. Art only. Match a Chinese woodblock print rendered as crisp handcrafted pixel art: ivory warm paper ground (#f5edda), dark near-black ink outlines (#202827), layered blue-green slate mountain silhouettes (#638482), muted teal seawater, tiny ochre touches. Wide elevated shore view during a quiet day between battles. Tidewater and two wooden junks with dark battened sails at left, a curving stone quay at right with low white plaster houses and dark tiled roofs, and a modest Chinese coastal watchtower atop the distant ridge. Graded clusters of discrete rectangular pixels, large high-contrast silhouettes, subtle paper grain, restrained flat colors. Keep the important sails, rooftops, and shoreline within the middle 60 percent of the image height for a wide UI crop. Maximum landscape aspect ratio, cohesive illustrated scene. No writing, no lettering, no interface, no frame, no borders, no watercolor blur, no combat.
