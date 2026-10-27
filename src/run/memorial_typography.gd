class_name MemorialTypography
extends RefCounted
## Stele / shrine engraving font (Yuji Boku, SIL OFL — see assets/fonts/LICENSE.txt).

const FONT_PATH := "res://assets/fonts/YujiBoku-Regular.ttf"

static var _font: Font


static func engraving_font() -> Font:
	if _font != null:
		return _font
	_font = load(FONT_PATH) as Font
	return _font


static func stele_label(text: String, size: int, pixel_size: float, color: Color, pos: Vector3) -> Label3D:
	var lbl := OfudaTalisman.make_label(text, engraving_font(), size, pixel_size, color, pos)
	lbl.outline_size = 8
	lbl.outline_modulate = Color(0.02, 0.01, 0.02, 0.92)
	lbl.modulate = color
	return lbl
