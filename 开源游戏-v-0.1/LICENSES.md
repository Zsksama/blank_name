# LICENSES · 第三方素材登记

> 依据：`策划agent原始修改区/07-素材与授权.md` 第四、五节。
> 规则：**下载那一刻就登记**，不要等提交前补。CC0 也要登记来源与许可证明。
> 原始素材放 `LICENSES/<许可>/`，修改后的素材另存，不要覆盖原件。

## 一、素材登记表

| 素材名称 | 作者 | 来源网址 | 许可证 | 下载日期 | 是否修改 | 修改内容 | 许可文件 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 示例：Medieval Village Tileset | 某某 | https://… | CC BY 4.0 | 2026-11-21 | 是 | 调色、裁剪 | LICENSE.txt |
| 出怪海螺 `Assets/Audio/SFX/enemy_spawn.ogg` | 待项目组确认 | 策划配套文件 `音效音乐/enemy_spawn.ogg`，文件元数据标注使用 LMMS | 待项目组确认 | 2026-11-27 | 否 | 原文件复制至项目资源目录 | 待补录 |

> 上表示例行在正式提交前删掉。

## 二、本项目自产内容

| 内容 | 产出方 | 说明 |
| --- | --- | --- |
| 占位色块贴图（T-002/T-003 用） | 程序自产 | 临时占位，正式美术到位后替换 |
| 全部游戏脚本与场景 | 程序 | 本次比赛期间原创 |
| 沿海堡完整态 `Assets/Art/Environment/fort_coastal_intact.png` | 美术组交付 | 源图为 `美术任务＆素材/素材/堡.png`，在 Godot 中裁取左侧 112×360 |
| 白天天空 `Assets/Art/Environment/sky_day.png` | 美术组交付 | 源图为 `美术任务＆素材/素材/白天天空2.png`，按地平线裁切 |
| 空仓音效 `Assets/Audio/SFX/empty_ammo.wav` | 程序合成 | 短促的金属空击提示音 |
| 经营界面 `Assets/Art/UI/Management/` | 美术组交付 | `美术任务＆素材/素材/ui` 的框图、灯火、日历，以及 `美术任务＆素材/素材` 的材料、弹药图标 |
| 主角船船身和木桨 | 美术组交付 | `美术任务＆素材/素材/主角船` 的 `zhujuechuan.png` 和 `chuanjiang.png`。后者以 `player_oar.png` 接入 |

## 三、AI 生成内容

> 用了 AI 生成的图/音/文，都要在这里记：工具、用途、生成内容、人工修改。
> 最终需并入提交材料《AI 使用与素材声明》。

| 工具 | 用途 | 生成内容 | 人工修改 |
| --- | --- | --- | --- |
| OpenAI ImageGen | 经营场景剧情背景 | `Assets/Art/UI/management_harbor.png`，参考纸墨木刻风格生成的沿海港口插画 | 使用生成原图，Godot 按视口比例裁切显示 |
| OpenAI ImageGen | 三类敌船的共用船图 | `Assets/Art/Characters/ship_enemy_shared.png`，以现有船图为参考重画同一朝向、轮廓和甲板布局，使用可染色的中性帆布和木色 | 清理轮廓外的低透明度像素并缩放至 270×180，游戏内按船型着色 |
| Codex、Godot Image | 主角船帆与划桨 | 基于美术组船身绘制 `Assets/Art/Characters/player_ship_sails.png`，包含完整、破损、毁坏三态。使用美术组木桨制作划水循环 | — |
| OpenAI ImageGen | 沿海堡的破损、破坏、门毁三态 | `Assets/Art/Environment/fort_coastal_damaged.png`、`fort_coastal_broken.png`、`fort_coastal_open.png`，由美术组的堡图派生裂纹、坍塌和透明水门，门毁图沿用破坏态墙面 | 在 Godot 中裁取左侧 296×941，并与完整态统一显示范围 |
| OpenAI ImageGen | 沿海堡的早期炮位原型 | `Assets/Art/Environment/fort_cannon_embrasure.png`，参考原堡图的石材颜色与视角绘制石砌矩形炮孔 | 试做时截取炮管和炮孔供场景联调 |

## 四、游戏内署名（主菜单「制作人员 / Credits」页）

> 逐条抄第一部分里许可为 CC BY / CC BY-SA 的素材；CC0 可只写来源。
> 结构见 `07-素材与授权.md` 第四节，本条待 HUD/主菜单（美06）落地后实现。
