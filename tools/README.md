# tools/ — 角色骨骼化流水线

原素材 `assets/characters/rogue_knight/Rogue Knight.fbx` 是**无骨架的静态网格**（Godot 导入后 `Skeleton3D` 数量为 0）。
这里用 Godot 自身把静态网格加工成带骨架、蒙皮和动画的场景，全程可脚本复现，不依赖 Blender / Mixamo。

## 产出

- `scenes/player/rogue_knight_rigged.tscn` — 25 根骨骼 + 4 个蒙皮网格 + 4 段动画（idle / walk / run / attack）
- 被 `scenes/player/player.tscn` 的 `Visual/RogueKnight` 实例化

## 执行顺序（顺序不可颠倒，后一步覆盖前一步的产物）

```bash
cd <项目根目录>

# 1. 建骨架 + 蒙皮权重（会覆盖 rogue_knight_rigged.tscn）
godot --headless --path . --script res://tools/build_rig.gd

# 2. 生成动画库（覆盖上一步的同一文件，追加动画）
godot --headless --path . --script res://tools/build_anims.gd

# 3. 数值校验：各片段脚底高度 / 步幅 / 髋部范围
godot --path . --script res://tools/check_pose.gd

# 4. 渲染预览
godot --path . --resolution 620x820 --script res://tools/preview_rig.gd -- out.png walk 0.25 30 6.0
godot --path . --resolution 960x600 --script res://tools/preview_game.gd -- out.png walk
```

> 参数说明：`-- <输出文件> <片段名> <时间秒> <相机偏航角> <相机距离>`。
> `--resolution` 必须放在 `--` **之前**，否则会被当成用户参数忽略。

## 骨架结构

```
root
└─ hips ─┬─ spine ─ chest ─┬─ neck ─ head
         │                 ├─ clavicle.L/R ─ upper_arm ─ forearm ─ hand
         │                 └─ weapon_sword           （背后大剑，100% 刚性绑定）
         ├─ thigh.L/R ─ shin ─ foot ─ toe
         ├─ weapon_dagger.L/R                        （腰间双匕首，100% 刚性绑定）
```

- 所有骨骼的**静止 Basis 都是单位矩阵**，因此骨骼局部旋转轴与世界轴对齐（+X 正方向 = 肢体向后摆，+Z = 模型正面）。
  这让动画可以用简单欧拉角直接写，不必处理骨骼朝向。
- 权重算法：到骨段的距离的 4 次方反比取前 4 个影响，再做 3 轮邻接平滑。
- 裙摆/披风：离腿段 > 0.135 的腰部以下顶点绑 `hips` 0.82 + 同侧 `thigh` 0.18，避免被双腿撕成两片。
- 武器不参与自由蒙皮，三件武器各自 100% 绑在专用骨上，所以在动画里可以被单独移动。

## 调参入口

- 关节点位置：`build_rig.gd` 里 `bones.append([...])` 与 `_segs.append([...])` 两处**必须同步改**。
- 动画幅度/节奏：`build_anims.gd` 里的 `_pose_idle / _pose_walk / _pose_run / _attack_keys`。
- 改完必须重跑 build_rig → build_anims，并用 check_pose 确认脚底仍在 y≈0。

## 已知限制

- 长裙摆与小腿会互相穿插：裙摆只做刚性摆动，没有布料模拟。
- 动画步频是固定的：walk 片段对应约 0.87 m/s、run 约 1.8 m/s 的地面速度。
  `player_visual.gd` 用 `speed / 基准速度` 缩放播放速率并封顶，所以实际移速越高脚底打滑越明显
  （当前 `move_speed = 5.5` 已属快速冲刺，打滑约 3 倍）。要减轻打滑就把 `data/tuning.json`
  里的 `player.move_speed` 调到 2.5~3.0。
