extends Area3D

## 最小交互：靠近显示浮标，按 E 在屏幕底部弹一行剧情文本。
## 不依赖 HUD / InputMap / 全局单例——所有节点都在本脚本里建，拆掉不影响别处。

const FONT_SCALE := 1.0
const RADIUS := 2.4
const READ_SECONDS := 6.0

@export var title: String = ""
@export var body: String = ""
@export var label_height: float = 2.2

var _mark: Label3D
var _panel: PanelContainer
var _text: Label
var _near := false
var _reading := false
var _timer := 0.0
var _read := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player
	monitoring = true

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	shape.position = Vector3(0.0, 1.0, 0.0)
	add_child(shape)

	_mark = Label3D.new()
	_mark.name = "Mark"
	_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mark.no_depth_test = true
	_mark.font_size = 64
	_mark.pixel_size = 0.0075 * FONT_SCALE
	_mark.outline_size = 14
	_mark.outline_modulate = Color(0.05, 0.04, 0.03, 0.95)
	_mark.modulate = Color(0.86, 0.79, 0.62)
	_mark.position = Vector3(0.0, label_height, 0.0)
	_mark.text = ""
	_mark.visible = false
	add_child(_mark)

	_build_panel()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ReadLayer"
	layer.layer = 3
	add_child(layer)

	_panel = PanelContainer.new()
	_panel.name = "ReadPanel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 180.0
	_panel.offset_right = -180.0
	_panel.offset_top = -132.0
	_panel.offset_bottom = -28.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.05, 0.90)
	style.border_width_left = 3
	style.border_color = Color(0.55, 0.42, 0.20, 0.85)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(18.0)
	_panel.add_theme_stylebox_override("panel", style)

	_text = Label.new()
	_text.name = "ReadText"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.add_theme_font_size_override("font_size", 22)
	_text.add_theme_color_override("font_color", Color(0.84, 0.80, 0.70))
	_panel.add_child(_text)

	layer.add_child(_panel)


func _on_body_entered(node: Node3D) -> void:
	if node.is_in_group(&"player"):
		_near = true


func _on_body_exited(node: Node3D) -> void:
	if node.is_in_group(&"player"):
		_near = false
		_stop_reading()


func _input(event: InputEvent) -> void:
	if not _near or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.keycode != KEY_E or not key.pressed or key.echo:
		return
	if _reading:
		_stop_reading()
	else:
		_start_reading()
	get_viewport().set_input_as_handled()


func _start_reading() -> void:
	_reading = true
	_read = true
	_timer = READ_SECONDS
	_text.text = body if not body.is_empty() else title
	_panel.visible = true
	_mark.visible = false


func _stop_reading() -> void:
	_reading = false
	_timer = 0.0
	if _panel != null:
		_panel.visible = false


func _process(delta: float) -> void:
	if _reading:
		_timer -= delta
		if _timer <= 0.0:
			_stop_reading()
		return

	if _mark == null:
		return
	_mark.visible = _near
	if _near:
		_mark.text = "[E] %s" % (title if not _read else "%s（已读）" % title)
