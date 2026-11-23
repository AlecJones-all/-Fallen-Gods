extends RefCounted
## 打击反馈纯视觉层：飘字/尸体碎裂/反弹光环/震屏/受击红闪/顿帧/波次横幅。
## 全部数组 + 宿主 _draw，零运行时新建节点；参数读 Data.tuning.juice（fail-fast 全量落表）。
## update 用真实 delta 驱动：combat_paused / 顿帧期间视觉照常收尾。

const COLOR_MOB_MELEE := Color(0.55, 0.6, 0.68)
const COLOR_MOB_RANGED := Color(0.75, 0.65, 0.3)
const COLOR_ELITE := Color(0.85, 0.35, 0.25)
const COLOR_BOSS := Color(0.5, 0.25, 0.65)
const COLOR_FLOATER := Color(1.0, 1.0, 1.0)
const COLOR_FLOATER_GOLD := Color(1.0, 0.85, 0.35)
const COLOR_BANNER := Color(1.0, 0.9, 0.55)

var shake_offset: Vector2 = Vector2.ZERO
var freeze_left: float = 0.0
var slowmo_left: float = 0.0

var _t: Dictionary = {}
var _font: Font = null
var _rng := RandomNumberGenerator.new()
var _floaters: Array = []
var _dying: Array = []
var _rings: Array = []
var _shake_amp: float = 0.0
var _shake_dur: float = 0.0
var _shake_left: float = 0.0
var _hurt_left: float = 0.0
var _banner_left: float = 0.0
var _banner_wave: int = 0


func _init() -> void:
	_t = Data.tuning.juice
	_font = load("res://assets/fonts/NotoSansSC-Bold.otf")
	_rng.randomize()


func reset() -> void:
	_floaters.clear()
	_dying.clear()
	_rings.clear()
	_shake_amp = 0.0
	_shake_dur = 0.0
	_shake_left = 0.0
	_hurt_left = 0.0
	_banner_left = 0.0
	freeze_left = 0.0
	slowmo_left = 0.0
	shake_offset = Vector2.ZERO


func is_animating() -> bool:
	return not _floaters.is_empty() or not _dying.is_empty() or not _rings.is_empty() \
		or _shake_left > 0.0 or _hurt_left > 0.0 or _banner_left > 0.0


# ================= 事件入口 =================

func hit_mob(m: Dictionary, amount: float) -> void:
	m.flash = float(_t.hit_flash_s)
	m.pop = float(_t.hit_pop_s)
	add_floater(m.pos + Vector2(0.0, -float(m.half) - 6.0), amount, m.kind == "elite")
	AudioManager.play_sfx("ball_hit", 0.1)


func add_floater(pos: Vector2, amount: float, gold: bool) -> void:
	var size: int = int(_t.floater_gold_font_size) if gold else int(_t.floater_font_size)
	var text: String = str(maxi(1, roundi(amount)))
	var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if _floaters.size() >= int(_t.floater_max):
		_floaters.pop_front()
	_floaters.append({
		"pos": pos - Vector2(w * 0.5, 0.0),
		"text": text,
		"size": size,
		"gold": gold,
		"t": float(_t.floater_life_s),
	})


func add_corpse(pos: Vector2, half: float, kind: String, ranged: bool) -> void:
	if _dying.size() >= int(_t.dying_max):
		_dying.pop_front()
	_dying.append({"pos": pos, "half": half, "kind": kind, "ranged": ranged, "t": float(_t.dying_s)})


func add_bounce_ring(pos: Vector2) -> void:
	if _rings.size() >= int(_t.bounce_ring_max):
		_rings.pop_front()
	_rings.append({"pos": pos, "t": float(_t.bounce_ring_s)})
	AudioManager.play_sfx("ball_bounce", 0.12)


func shake(amp: float, dur: float) -> void:
	var current: float = _shake_amp * clampf(_shake_left / maxf(_shake_dur, 0.0001), 0.0, 1.0)
	if amp >= current:
		_shake_amp = amp
		_shake_dur = dur
		_shake_left = dur


func on_player_hit(boss_hit: bool) -> void:
	_hurt_left = float(_t.hurt_flash_s)
	freeze_left = maxf(freeze_left, float(_t.freeze_s))
	if boss_hit:
		shake(float(_t.shake_boss_hit_px), float(_t.shake_boss_hit_s))
	else:
		shake(float(_t.shake_player_px), float(_t.shake_player_s))


func start_banner(wave_index: int) -> void:
	_banner_wave = wave_index
	_banner_left = float(_t.banner_slide_s) + float(_t.banner_hold_s) + float(_t.banner_fade_s)
	slowmo_left = float(_t.slowmo_s)


# ================= 推进（真实 delta） =================

func update(delta: float) -> void:
	freeze_left = maxf(0.0, freeze_left - delta)
	slowmo_left = maxf(0.0, slowmo_left - delta)
	_hurt_left = maxf(0.0, _hurt_left - delta)
	_banner_left = maxf(0.0, _banner_left - delta)
	if _shake_left > 0.0:
		_shake_left = maxf(0.0, _shake_left - delta)
		var k: float = _shake_left / maxf(_shake_dur, 0.0001)
		shake_offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * _shake_amp * k
	else:
		shake_offset = Vector2.ZERO
	for i in range(_floaters.size() - 1, -1, -1):
		_floaters[i].t -= delta
		if _floaters[i].t <= 0.0:
			_floaters.remove_at(i)
	for i in range(_dying.size() - 1, -1, -1):
		_dying[i].t -= delta
		if _dying[i].t <= 0.0:
			_dying.remove_at(i)
	for i in range(_rings.size() - 1, -1, -1):
		_rings[i].t -= delta
		if _rings[i].t <= 0.0:
			_rings.remove_at(i)


# ================= 绘制（宿主 CanvasItem，震屏变换内） =================

func draw_world(ci: CanvasItem) -> void:
	var ring_dur: float = float(_t.bounce_ring_s)
	for r in _rings:
		var k: float = 1.0 - float(r.t) / ring_dur
		var rad: float = lerpf(float(_t.bounce_ring_r0_px), float(_t.bounce_ring_r1_px), k)
		ci.draw_arc(r.pos, rad, 0.0, TAU, 20, Color(1.0, 1.0, 1.0, (1.0 - k) * 0.7), 2.0)
	var die_dur: float = float(_t.dying_s)
	for d in _dying:
		var k: float = clampf(float(d.t) / die_dur, 0.0, 1.0)
		var h: float = float(d.half) * k
		var col: Color = _corpse_color(d.kind, d.ranged)
		col.a = k
		ci.draw_rect(Rect2(d.pos - Vector2(h, h), Vector2(h * 2.0, h * 2.0)), col)


func draw_floaters(ci: CanvasItem) -> void:
	var life: float = float(_t.floater_life_s)
	for f in _floaters:
		var k: float = clampf(float(f.t) / life, 0.0, 1.0)
		var pos: Vector2 = f.pos + Vector2(0.0, -float(_t.floater_rise_px) * (1.0 - k))
		var base: Color = COLOR_FLOATER_GOLD if f.gold else COLOR_FLOATER
		ci.draw_string_outline(_font, pos, f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, f.size, 4, Color(0.0, 0.0, 0.0, k * 0.8))
		ci.draw_string(_font, pos, f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, f.size, Color(base, k))


# ================= 绘制（屏幕空间，不随震屏） =================

func draw_screen(ci: CanvasItem, view_size: Vector2) -> void:
	if _hurt_left > 0.0:
		_draw_hurt_edges(ci, view_size)
	if _banner_left > 0.0:
		_draw_banner(ci, view_size)


func _corpse_color(kind: String, ranged: bool) -> Color:
	if kind == "elite":
		return COLOR_ELITE
	if kind == "boss":
		return COLOR_BOSS
	if ranged:
		return COLOR_MOB_RANGED
	return COLOR_MOB_MELEE


func _draw_hurt_edges(ci: CanvasItem, vs: Vector2) -> void:
	var a: float = (_hurt_left / float(_t.hurt_flash_s)) * float(_t.hurt_alpha)
	var d: float = float(_t.hurt_edge_px)
	var clear := Color(0.85, 0.1, 0.1, 0.0)
	var solid := Color(0.85, 0.1, 0.1, a)
	ci.draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0.0), Vector2(vs.x, d), Vector2(0.0, d)]),
		PackedColorArray([solid, solid, clear, clear]))
	ci.draw_polygon(
		PackedVector2Array([Vector2(0.0, vs.y - d), Vector2(vs.x, vs.y - d), Vector2(vs.x, vs.y), Vector2(0.0, vs.y)]),
		PackedColorArray([clear, clear, solid, solid]))
	ci.draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(d, 0.0), Vector2(d, vs.y), Vector2(0.0, vs.y)]),
		PackedColorArray([solid, clear, clear, solid]))
	ci.draw_polygon(
		PackedVector2Array([Vector2(vs.x - d, 0.0), Vector2(vs.x, 0.0), Vector2(vs.x, vs.y), Vector2(vs.x - d, vs.y)]),
		PackedColorArray([clear, solid, solid, clear]))


func _draw_banner(ci: CanvasItem, vs: Vector2) -> void:
	var slide: float = float(_t.banner_slide_s)
	var fade: float = float(_t.banner_fade_s)
	var total: float = slide + float(_t.banner_hold_s) + fade
	var elapsed: float = total - _banner_left
	var text: String = "第%d波 · 肃清" % (_banner_wave + 1)
	var px: int = int(_t.banner_font_size)
	var tw: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var cx: float = vs.x * 0.5
	var x: float = cx
	if elapsed < slide:
		var k: float = elapsed / slide
		k = 1.0 - (1.0 - k) * (1.0 - k)
		x = lerpf(-tw, cx, k)
	var a: float = 1.0
	if _banner_left < fade:
		a = _banner_left / fade
	var y: float = vs.y * 0.35
	var pad: float = 16.0
	ci.draw_rect(Rect2(x - tw * 0.5 - pad, y - float(px) - pad * 0.5, tw + pad * 2.0, float(px) + pad), Color(0.05, 0.03, 0.08, 0.65 * a))
	var tp := Vector2(x - tw * 0.5, y)
	ci.draw_string_outline(_font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 6, Color(0.0, 0.0, 0.0, 0.8 * a))
	ci.draw_string(_font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(COLOR_BANNER, a))