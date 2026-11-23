class_name TaThemeText
extends Object

# AGENT: Text faces for the generated Theme. Called from TaThemeBuilder.make().
# INVARIANT: RichTextLabel [b]/[i]/[s] and TaBold/TaItalic use look faces. Bold
# derives from face when face_bold is null. Italic is never faked: a FontVariation
# slant leaves straight stems upright in Godot 4.7, so null face_italic stays upright.
# fallback_fonts reaches every face the Theme sets (titles, captions, badges, tags too),
# through a FontVariation: a copy of a variation, never a wrap (a variation over a
# variation keeps only the outer settings). The caller's Font is never edited.
# DO NOT: Public DSL. Do not bundle fonts here.

const BOLD_EMBOLDEN := 0.6


static func apply(theme: Theme, look: TaTokens, regular: Font) -> void:
	if not look.fallback_fonts.is_empty() and regular != null:
		regular = with_fallbacks(regular, look)
		theme.default_font = regular
	var bold := with_fallbacks(bold_face(look, regular), look)
	var italic := with_fallbacks(italic_face(look, regular), look)
	var size := theme.default_font_size
	if regular != null:
		theme.set_font("normal_font", "RichTextLabel", regular)
	if bold != null:
		theme.set_font("bold_font", "RichTextLabel", bold)
		theme.set_font("bold_italics_font", "RichTextLabel", bold)
	if italic != null:
		theme.set_font("italics_font", "RichTextLabel", italic)
	for item in ["bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		theme.set_font_size(item, "RichTextLabel", size)
	theme.set_type_variation("TaBold", "Label")
	if bold != null:
		theme.set_font("font", "TaBold", bold)
	theme.set_type_variation("TaItalic", "Label")
	if italic != null:
		theme.set_font("font", "TaItalic", italic)
	theme.set_color("font_color", "TaItalic", look.color_muted)
	chain_every_face(theme, look)


## look.fallback_fonts on every font the Theme sets. Only the body, bold, and italic had
## it, so titles, captions, badges, and tags showed emoji as boxes on web exports.
static func chain_every_face(theme: Theme, look: TaTokens) -> void:
	if look.fallback_fonts.is_empty():
		return
	var chained := {}
	for type_name in theme.get_font_type_list():
		for item in theme.get_font_list(type_name):
			var font := theme.get_font(item, type_name)
			if font == null:
				continue
			# One chained copy per face, shared like the face was.
			if not chained.has(font):
				chained[font] = with_fallbacks(font, look)
			if chained[font] != font:
				theme.set_font(item, type_name, chained[font])


## `font` plus look.fallback_fonts, as a FontVariation. Returns `font` unchanged when
## there is nothing to add (or it already carries the chain).
static func with_fallbacks(font: Font, look: TaTokens) -> Font:
	if font == null or look.fallback_fonts.is_empty():
		return font
	var chain: Array[Font] = []
	for existing in font.fallbacks:
		chain.append(existing)
	var added := false
	for extra in look.fallback_fonts:
		if extra != null and extra != font and not chain.has(extra):
			chain.append(extra)
			added = true
	if not added:
		return font
	var chained: FontVariation
	if font is FontVariation:
		# Copied: a wrap lost the title tracking, the count face's trimmed line, embolden.
		chained = (font as FontVariation).duplicate() as FontVariation
	else:
		chained = FontVariation.new()
		chained.base_font = font
		# A kit pixel face stays one (TaPixelFont.kit_id reads this).
		for key in [TaPixelFont.META_FACE, TaPixelFont.META_SCALE]:
			if font.has_meta(key):
				chained.set_meta(key, font.get_meta(key))
	chained.fallbacks = chain
	return chained


## Bold face for look. face_bold wins; else an emboldened copy of regular.
## Pixel keeps the pixel face: embolden breaks the integer grid.
static func bold_face(look: TaTokens, regular: Font) -> Font:
	if look.face_bold != null:
		return TaThemeBuilder.face_at(look.face_bold, look.font_size)
	if regular == null or look.is_pixel():
		return regular
	var bold := FontVariation.new()
	bold.base_font = regular
	bold.variation_embolden = BOLD_EMBOLDEN
	bold.fallbacks = regular.fallbacks
	return bold


## face_italic, else regular (upright). See the file header for why.
static func italic_face(look: TaTokens, regular: Font) -> Font:
	if look.face_italic != null:
		return look.face_italic
	return regular
