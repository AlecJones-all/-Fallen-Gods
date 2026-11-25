# 02 模块规格（kit）

- 机器可读：`data/kit/tithe_gate_kit.json`
- 校验：`tests/spec_probe` 里的「模块规格」段（与关卡数据双向对账）
- 覆盖：当前场景全部 17 个模块（P0 10 个 + P1 道具）

## 一、三条硬规则

1. **原点在底部中心**：`y=0` 是接地面，`+x` 是模块正面，`+z` 是右手侧。所有 parts 的 `offset` 都相对这个原点。
2. **吸附分两类**：
   - `snap: tile` —— 可拼接件（地面/墙/栅栏），宽度必须是 2m 的整数倍，摆的时候按 2m 步进；
   - `snap: object` —— 独立物件（门梁/税亭/道具），尺寸自由，按位置摆。
3. **碰撞三选一**：
   - `parts`：每个 `collide: true` 的 part 单独生成碰撞体（墙体、门梁、税亭、栅栏）；
   - `hull_85`：整体包络缩到 85% 一个碰撞盒（道具——刻意比视觉小，等距下玩家会低估自身体积）；
   - `none`：不碰撞（地面、挂灯、担架）。

## 二、模块表

| 模块 | 名称 | 尺寸 w×h×d | parts | 碰撞 | 吸附 | 材质 | 优先级 |
|---|---|---|---|---|---|---|---|
| `ground_tile` | 地面瓦片 | 2×0.1×2 | 1 | none | tile | plaster | p0 |
| `wall_panel` | 墙体 | 2×3×0.4 | 1 | parts | tile | plaster | p0 |
| `gate_arch` | 骨拱 | 5.2×3.4×1.2 | 21 | parts | object | bone/cloth_rot/plaster/stone_crack | p0 |
| `fence_stake` | 铁箍木桩 | 2×1.3×0.3 | 7 | parts | tile | cloth_rot/iron_rust/wood_dry | p0 |
| `booth_half` | 半开税亭 | 4×2.6×4 | 6 | parts | object | wood_dry | p0 |
| `cart_hand` | 板车 | 3×1.4×2.2 | 1 | hull_85 | object | wood_dry | p0 |
| `barrel_oil` | 圣油桶 | 0.9×1.2×0.9 | 1 | hull_85 | object | wood_dry | p0 |
| `sack_grain` | 粮袋 | 0.8×0.6×0.6 | 1 | hull_85 | object | cloth_rot | p0 |
| `scale_toll` | 秤 | 1.2×1.7×0.8 | 3 | hull_85 | object | iron_rust/wood_dry | p0 |
| `lantern_hook` | 挂灯 | 0.4×1.65×0.4 | 2 | none | object | glow/wood_dry | p0 |
| `stretcher` | 担架 | 2×0.3×0.8 | 1 | none | object | cloth_rot | p1 |
| `chain_hang` | 垂下铁链 | 0.32×2.55×0.32 | 11 | none | object | bone/iron_rust | p1 |
| `cage_hanging` | 悬挂铁笼 | 2.8×3.4×1.5 | 30 | parts | object | bone/iron_rust/stone_crack/wood_dry | p1 |
| `cross_stake` | 十字木桩 | 1.2×2.6×0.8 | 5 | parts | object | bone/cloth_rot/iron_rust/wood_dry | p1 |
| `ledger_board` | 账册板 | 1.2×1.7×0.3 | 10 | none | object | blood_dry/bone/cloth_rot/iron_rust/wood_dry | p1 |
| `rubble_pile` | 碎石骨堆 | 2×0.9×2 | 7 | hull_85 | object | bone/stone_crack | p1 |
| `blood_decal` | 干血渍 | 1.6×0.09×1.6 | 13 | none | object | blood_dry | p1 |

**注**：门梁 5.2m 宽是因为包住两侧 1.2m 的石墩；净宽 4m 记在关卡 JSON 的 `landmarks.gate_arch.opening` 里，是两个不同的数。

## 三、怎么加一个模块

1. 在 `tithe_gate_kit.json` 的 `modules` 里加一条：`id` 用 snake_case，`size` 写包络，`parts` 拆件。
2. 在 `data/levels/tithe_gate.json` 的 `items` 里加同 `id` 的条目（`mesh` 字段填模块 id），尺寸必须一致。
3. 跑 `spec_probe`：会检查 id 唯一、part 不越出包络、材质槽存在、尺寸与关卡一致、kit 里没有没人用的模块。
4. 在 `tithe_gate_graybox.gd` 里 `_place_module("你的id", 位置, yaw)` 摆上去。

## 四、为什么灰盒阶段就要拆件

- 阶段 5 换正式模型时，**每个 part 就是一个可替换的网格**，不用重新决定"这堵墙由几块组成"。
- 碰撞策略写在数据里，换模型时碰撞不会跟着变。
- 门梁这种组合件（2 石墩 + 2 立柱 + 横梁 + 旗）拆开之后，换皮只需要替换 6 个 part 的材质/网格。

## 五、材质：3A 程序化（阶段 5）

没有美术资源，所以不买贴图、不展 UV，用代码现场生成：`scripts/art/kit_art.gd`。

| 做法 | 原因 |
|---|---|
| **世界三平面映射**（`uv1_triplanar` + `uv1_world_triplanar`） | BoxMesh 不用展 UV，任意尺寸都不会拉伸；改模块尺寸贴图自动跟着走 |
| **运行时光栅化贴图**（128×128） | 每个材质族一张：石材颗粒 + 碎屑、木纹正弦条纹 + 板缝、铁件划痕、布料经纬、土路碎石、石板缝 |
| **同一高度场算法线** | 颜色和凹凸用同一份噪声，不会出现"花纹在这个位置、凸起在另一个位置" |
| **一套材质一个实例** | 6 个 StandardMaterial3D 全场共用，draw call 不随构件数增加 |

材质族与用途：

| 材质 | 底色 | 用途 |
|---|---|---|
| `stone` | 0.38 冷灰 | 墙体 |
| `pave` | 0.41 暖灰 | 卡口铺地、门梁石墩、路面 |
| `dirt` | 0.36 土黄 | 村口道路面 |
| `mud` | 0.29 深褐 | 收储院地面 |
| `wood` | 0.38 棕 | 栅栏、税亭、板车、桶 |
| `iron` | 0.30 偏冷金属 | 铁笼、秤、挂灯 |
| `cloth` | 0.52 米色 | 粮袋、旗、担架 |

**已知取舍**：三平面映射会让木纹在横竖两个方向都出现，近距离看偏"编筐"。要根治得按模块给 UV，代价是每个模块都要重做贴图——现阶段不值当，等英雄件（门梁、税亭）转 3B 建模时一并解决。
