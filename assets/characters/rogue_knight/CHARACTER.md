# 这个模型是谁 —— 阿舍尔 · 刃守

> 本文件用于把**美术资产**与**剧情设定**对应起来。以后任何人打开这个目录，都能知道这堆网格、骨骼、动画到底属于哪个角色。
> **设定正文以 `故事线/` 为准，本文件只做对应与资产说明，不另立设定。**

## 一、角色身份

| 项 | 内容 | 出处 |
|---|---|---|
| 姓名 | 阿舍尔（Ashel） | `故事线/03_三个开局身份 (2).md` 第 7 行 |
| 物种 | 烬裔（巨神血脉残留人种），皮肤下有**暗红烬纹**，愤怒时发烫 | 同上第 9 行 |
| 身份 | 三个开局身份之**身份一** | 同上 |
| **职业** | 近战系「**刃守**」亲和 | 同上第 13 行 |
| 独有能力 | 烬视（看见世界的血肉真相）；听心跳（听出隐藏房间与谎言）；烬纹过载（自伤换伤害） | 同上 |
| 动机 | 复仇 → 救莉薇娅 → 不再替任何人单方面做决定 | `故事线/07_角色档案.md` 第 13 行 |

**注意**：「刃守」是他**已成文的职业名**，不是新造词。同世界观另有两个「X守」（治疗系「慈守」、隐藏体系「名守」），命名法统一。
「执火者」在现有文档中**查无此项**，属未入档的称号，若要使用需先在 `07_角色档案.md` 补记。

## 二、这个模型由什么构成

源文件：`Rogue Knight.fbx`（Tramicful 原作，CC BY 4.0，见 `ATTRIBUTION.md`），导入后是**无骨架静态网格**，现在的骨架、蒙皮、动画全部由本项目脚本生成。

### 网格（4 个，共 10,393 顶点 / 14,323 三角面）

| 网格名 | 顶点 | 贴图 | 在角色身上的作用 |
|---|---|---|---|
| `Plane_006` | 7,281 | Rogue Knight texture.png | **身体本体**：铠甲、披风、头盔、手套、靴子 |
| `Cube_002` | 1,942 | Dagger Hand paint.png | 腰侧**左右两把匕首**——纯装饰，不参与任何攻击 |
| `Cube_009` | 1,122 | Dagger Hand paint.png | **双手大剑**（1.95 m），常握右手，是他的主武器 |
| `Plane_002` | 48 | Rogue Knight texture.png | 碎片，几乎不可见 |

### 骨骼（36 根）

- **22 根映射自 Mixamo**（便于日后接入任何 Mixamo 动作）：
  `Hips / Spine / Spine1 / Spine2 / Neck / Head / Left·Right Shoulder·Arm·ForeArm·Hand / Left·Right UpLeg·Leg·Foot·ToeBase`
- `root`
- `socket_weapon.R` —— 右手武器挂点，大剑与连弩都挂在这
- **12 根裙摆链骨**：`skirt_F/B/L/R` 各 3 节，让披风能摆动而不是硬邦邦

### 动画（9 段，全部重定向自 Mixamo，非手 K）

| 片段 | 时长 | 来源 | 用途 |
|---|---|---|---|
| `idle` | 1.2 s | idle（下身）+ Great Sword Walk（上身定格） | 待机 |
| `walk` | 1.1 s | Sword And Shield Walk（下身）+ Great Sword Walk（上身） | 行走 |
| `run` | 0.7 s | Sword And Shield Run（下身）+ Great Sword Walk（上身，前倾 8°、摆臂 ×1.4） | 奔跑 |
| `strafe` | 1.0 s | Great Sword Strafe（已原地化） | 侧向移动 |
| `attack_blade` | **0.6 s** | Great Sword Slash **裁掉前摇**（保留 0.30~0.78 段）+ 46° 躯干横扫 | 大剑横砍 |
| `fire_xbow` | 0.7 s | Firing Rifle | 连弩射击 |
| `aim_xbow` | 1.0 s | Firing Rifle 首帧定格 | 连弩待机/瞄准 |
| `hit` | 1.33 s | Hit To Body | 受击 |
| `death` | 3.03 s | Death | 死亡 |

> 上下半身来自不同片段是刻意的：Mixamo 没有"持大剑跑步"，且 `Sword And Shield` 系列带盾牌手臂。只用它的**下半身**、上半身统一取 `Great Sword Walk` 的持剑姿势，就能消除盾牌污染并保证剑始终被正确握住。

### 武器对应关系

| 游戏里 | 实际渲染 |
|---|---|
| `WEAPON_BLADE`（长剑，按 1） | `Cube_009` 大剑可见；连弩隐藏 |
| `WEAPON_CROSSBOW`（连弩，按 2） | 程序化连弩可见（弩身/弩臂/弦/握把/已上膛弩箭）；大剑隐藏 |
| 腰侧双匕首 | 始终显示，**仅装饰** |

## 三、文件在哪

| 用途 | 路径 |
|---|---|
| 原始素材 | `assets/characters/rogue_knight/Rogue Knight.fbx` |
| Mixamo 动作源 | `assets/anim_src/*.fbx`（**不应随仓库分发**） |
| 骨架+蒙皮生成器 | `tools/build_rig_v2.gd` |
| 动画重定向生成器 | `tools/build_anim_v2.gd` |
| 验收工具 | `tools/check_v2.gd`（脚底接触/原地性）、`tools/preview_scene.gd`（渲染） |
| **成品场景** | `scenes/player/rogue_knight_v2.tscn` |
| 游戏中引用点 | `scenes/player/player.tscn` → `FacingWedge/Visual/RogueKnight` |
| 动画驱动 | `scripts/player/player_visual.gd` |
| 旧版（回滚用，仍在） | `scenes/player/rogue_knight_rigged.tscn` |

## 四、如何重建

```bash
godot --headless --path . --script res://tools/build_rig_v2.gd   # 骨架 + 蒙皮 + 大剑入右手 + 连弩
godot --headless --path . --script res://tools/build_anim_v2.gd  # 9 段动画
godot --headless --path . --script res://tools/check_v2.gd       # 数值验收
```
顺序不可颠倒，第二步会覆盖第一步产出的同一场景文件。改完必须跑 `check_v2` 确认：**walk 双脚同时离地应为 0 帧**。

## 五、已知待处理

1. **发光颜色与设定冲突**：模型自带绿色辉光，但档案写明烬纹是**暗红**、愤怒发烫。二者未统一，需决定改色（材质色相）还是改设定（如"冷烬"）。
2. **连弩握持角度未调好**：与大剑共用 `socket_weapon.R`，而该挂点是为"行走时剑朝上"定的，导致弩身偏斜、体积偏大。修法：给弩单独挂点骨并按待机枪口朝前重新定向。
3. **「执火者」未入档**：需先在 `故事线/07_角色档案.md` 决定是否作为称号收录。
