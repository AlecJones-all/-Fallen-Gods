# Mixamo 动画下载清单

把下载的 FBX 直接放进本目录（`assets/anim_src/`）。**只要骨骼动画，不要网格。**

## 下载参数（每次都要确认这 5 项）

| 选项 | 取值 | 原因 |
|---|---|---|
| Format | **FBX Binary (.fbx)** | Godot / Blender 都能读 |
| Skin | **Without Skin** | 只要骨骼动画，避免带入 Mixamo 自己的模型 |
| **In Place** | **勾选** | 否则动画自带根位移，会和 `CharacterBody3D` 的位移叠加成双倍速度 |
| Frame Rate | **30** | 与项目动画帧率一致 |
| Keyframe Reduction | **none** | 不做减帧，避免脚部抽搐 |

> `In Place` 在下载弹窗的左下角，容易被忽略——这是最容易出错的一项。

## 文件清单

| # | 文件名（必须这样命名） | Mixamo 搜索关键词 | 优先级 | 说明 |
|---|---|---|---|---|
| 1 | `idle.fbx` | `Idle` → 选 "Breathing Idle" 一类 | **必下** | 循环，幅度要小 |
| 2 | `walk.fbx` | `Walk` | **必下** | 原地循环，不要带转身 |
| 3 | `run.fbx` | `Run` 或 `Jogging` | **必下** | 原地循环 |
| 4 | `atk_blade.fbx` | `Sword Slash` / `Standing Melee Attack Horizontal` | **必下** | 单手持剑横砍，时长 ~1 秒 |
| 5 | `aim_xbow.fbx` | `Aim Recurve Bow` | **必下** | 持弩瞄准的循环姿势 |
| 6 | `fire_xbow.fbx` | `Firing Rifle` | **必下** | 有后坐力的单发，时长 ~0.8 秒 |
| 7 | `hit.fbx` | `Hit Reaction` / `Taking A Punch` | 建议 | 受击顿挫，~0.6 秒 |
| 8 | `death.fbx` | `Dying` / `Death From Front` | 建议 | 倒地，播完停在最后一帧 |
| 9 | `dash.fbx` | `Dodging` / `Quick Roll` | 可选 | 对应空格冲刺，~0.5 秒 |

## 挑选原则

1. **起止姿势接近自然站姿**——两端姿势差越大，和其他动作混合时越容易"抖一下"。
2. **不要选带位移的动作**（如 "Walk Turn"、"Run To Stop"），会破坏原地循环。
3. 找不到完全对应的就用相近的——重定向时我可以改节奏、裁长度、加/减幅度。
4. 单个文件不要超过 ~2 秒，除了 death。

## 最少验证量

**先只下 `idle.fbx`。** 确认能正常下载、不是空文件（正常约 100KB~1MB），再回来下其余 8 个。链路通了再批量，避免白点 9 次。

## 版权

Mixamo 的角色与动画对个人/商业/非营利项目免版税，但**不能把动画文件本身单独再分发或转售**。打包进比赛作品没问题；不要在仓库里公开分发 `assets/anim_src/` 里的原始 FBX。

## 下载之后的流程（我负责）

1. Blender 导入 FBX，用 `mixamorig:` 骨骼的动作重定向到项目自建骨架
2. 烘焙成骨骼动画，导出给 Godot
3. Godot 侧按 `idle / walk / run / atk_blade / aim_xbow / fire_xbow / hit / death / dash` 命名建立动画库
4. 接进 `player.gd` 的战斗状态机
