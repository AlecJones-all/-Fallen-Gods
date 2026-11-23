extends SceneTree

func _init() -> void:
	var look := TaTokens.framed()
	look.color_bg = Color("#101018")
	look.color_panel = Color("#1b1b26")
	look.color_card = Color("#20202e")
	look.color_surface = Color("#20202e")
	look.color_surface_hover = Color("#2a2a3c")
	look.color_surface_pressed = Color("#32324a")
	look.color_text = Color("#f2f2f7")
	look.color_muted = Color("#9a9ab2")
	look.color_accent = Color("#e8c05a")
	look.color_border = Color("#4a4a60")
	look.color_danger = Color("#e05555")
	look.face = load("res://assets/fonts/NotoSansSC-Regular.otf")
	look.face_title = load("res://assets/fonts/NotoSansSC-Bold.otf")
	look.face_bold = load("res://assets/fonts/NotoSansSC-Bold.otf")
	look.fallback_fonts = [look.face]
	var err := TaLook.save(look)
	print("THEME_SAVE err=", err)
	quit()