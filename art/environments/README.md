# 场景模型与署名

三项静态模型已选作环境美术源件。每个目录收录一份带内嵌贴图的 GLB、一张独立模型预览和一张税卡实景试摆图。试摆使用税卡场景副本、原相机和原灯光，玩家站在资产旁作为比例参照。最终摆位、通行碰撞和同屏多实例性能待关卡接入时验证。

| 模型 | 三角面与贴图 | 实景观察 | 图片 |
|---|---|---|---|
| [石瞭望塔](石瞭望塔/石瞭望塔.glb) | 17,170 面，3 张 | 按 4.0 米高试摆，圆形垛口清楚，背光侧塔身偏暗。优先作为路侧地标。 | [造型](石瞭望塔/模型预览.png) · [税卡试摆](石瞭望塔/税卡试摆.png) |
| [苔石小屋](苔石小屋/苔石小屋.glb) | 66,322 面，2 张 | 按 3.6 米高试摆，斜屋顶可辨，入口在暗场中不突出。用于可进入建筑时需为入口安排光源或调整朝向。 | [造型](苔石小屋/模型预览.png) · [税卡试摆](苔石小屋/税卡试摆.png) |
| [苔石拱桥](苔石拱桥/苔石拱桥.glb) | 68,552 面，2 张 | 按 2.2 米高试摆，弧形石栏清楚。放入村道时再按两端地面高度和可通行宽度定尺寸。 | [造型](苔石拱桥/模型预览.png) · [税卡试摆](苔石拱桥/税卡试摆.png) |

## 署名与原件

下表保留原作标题、发布者和作品页。三个发布页的许可均为 [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)。本地下载包与作品页以标题、三角面数对应。归档时仅更换文件名，已逐项核对 SHA-256，模型内容与本地原件一致。两套预览由本项目在 Godot 中生成。发布使用时请随项目保留相应作品署名及许可链接。

| 作品 | 发布者 | 下载包原件 | 归档 GLB 的 SHA-256 |
|---|---|---|---|
| [Weathered Medieval Stone Watchtower](https://sketchfab.com/3d-models/weathered-medieval-stone-watchtower-b987b82f37d74994869d8dc008412353) | mana5677 | [GLB](../../assets/anim_src/weathered-medieval-stone-watchtower/source/830fdd30-7fc4-4093-9c2d-f5e83fe59072.glb) | `c1a658fba20dcedc22d539a324bbadcf9ddc12af4eb52d9b6065c0d0e65ce3e0` |
| [mossy medieval stone cottage 3d model free](https://sketchfab.com/3d-models/mossy-medieval-stone-cottage-3d-model-free-1bce58152cb64cceabe58d3e21e9cb72) | iGauravRajput | [GLB](../../assets/anim_src/mossy-medieval-stone-cottage-3d-model-free/source/694d137a-9c5d-4910-83eb-aec62c0c4cc5_glb.glb) | `ac235e3ef12985b0d0d233335e54876aa8c9cfb1d0c6e4f5748e9c7ec162e059` |
| [A stylized, moss-covered stone arch bridge 3d](https://sketchfab.com/3d-models/a-stylized-moss-covered-stone-arch-bridge-3d-3c03080c222043e5acd8202d371a3b32) | iGauravRajput | [GLB](../../assets/anim_src/a-stylized-moss-covered-stone-arch-bridge-3d/source/e1d9a327-2f3a-46fc-8abb-d5b42a02eae4_glb.glb) | `a037f5ec589ac1d7b0e5f06539f71fd575ef34b36eb82d536957208414846a76` |

---

## 第4 · 5关 · 礼拜堂与大教堂陈设

**实际在用的文件都在 [`白洗礼拜堂/`](白洗礼拜堂/)。**该目录同时放了第4关仪式道具和第5关四件基础场景件（`-游戏` 后缀为游戏件，已带节点缩放与米制尺寸，由 `scripts/art/glb_scene.gd` 运行时载入），未压缩导出放在 `白洗礼拜堂/源件/`，逐件说明见[目录内 README](白洗礼拜堂/README.md)。第4关场景 `scenes/levels/whitewash_chapel.tscn` 直接引用其中六件：

| 文件 | 三角面 | 场景内尺寸（宽×高×深） | 归属 |
|---|---|---|---|
| `沉没大教堂中殿-v2.glb` | 11,942 | 12.0 × 10.0 × 8.0 m | 第5关中殿；第4关暂作后殿拱廊 |
| `主教祭坛-游戏.glb` | 5,292 | 1.76 × 1.20 × 1.17 m | 第5关祭坛；第4关晋升台 |
| `唱诗班楼阳台-游戏.glb` | 7,884 | 6.0 × 4.0 × 3.0 m | 第5关楼上层 |
| `悬挂圣徒铁笼-游戏.glb` | 4,747 | 1.07 × 3.50 × 1.09 m | 第5关悬笼 |
| `记忆焚烧台-游戏.glb` | 5,190 | 1.60 × 1.10 × 1.00 m | 第4关仪式道具 |
| `双心跳祭龛-游戏.glb` | 4,925 | 1.20 × 1.80 × 1.00 m | 第4关仪式道具 |
| `大理石台座.glb` | 5,098 | 0.96 × 0.58 × 0.70 m | 第4关台前基座 |

另有两个源件目录（`主教祭坛/`、`唱诗班楼上层/` 等）**当前已不在仓库里**：那批 `tools/blender/l5_build.py` 生成的程序化件（闭顶肋拱、烘焙做旧贴图，中殿 37,636 面）在 2026-11-29 被新版替换并删除，备份留在 `.workbuddy/backup/l4_old_models_20261129.zip`。若之后要按 `art/previews/第5关_沉没大教堂/01~04` 重走 Blender 路线，可用该脚本重建，注意脚本输出到 `art/environments/`，需自行归入 `白洗礼拜堂/`。

## 第6关 · 根须阶梯

三件原本是 `art/environments/` 根目录下的无命名大 GLB（`20261128161425_40b73146` / `20261128163523_d34d6e2a` / `20261128185810_699aa254`），2026-11-29 经渲染核对后改名归入 [`根须阶梯/`](根须阶梯/)。

| 模型 | 三角面 | 尺寸（宽×高×深） | 说明 |
|---|---|---|---|
| [根须缠绕件-拱门台阶](根须阶梯/根须缠绕件-拱门台阶.glb) | 1,993,382 | 0.81 × 0.75 × 0.69 m | 尖拱券 + 5 级台阶，根须缠拱垂落至地面 |
| [根须缠绕件-壁柱](根须阶梯/根须缠绕件-壁柱.glb) | 1,991,120 | 0.69 × 0.72 × 0.71 m | 方形壁柱 + 基座，根须自柱头缠到基座 |
| [巨神血肉墙](根须阶梯/巨神血肉墙.glb) | 1,756,529 | 0.72 × 0.66 × 0.72 m | 白石石灰墙片 + 一段楼梯，裂缝渗出红色血肉膜 |

> 三件均为 175–200 万面、单件 68–73 MB、4096² 贴图、无节点缩放（即约 0.7 m 高，非米制）。**2026-11-29 判定：可直接使用**，摆放时放大约 4 倍即到 3 m 级；减面与按米制定标属后续性能优化。备注与用法见目录内 README。

