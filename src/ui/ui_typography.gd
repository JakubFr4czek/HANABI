class_name UiTypography
extends RefCounted
## Lettering for world-space menus: Cinzel (Roman inscription capitals, SIL OFL)
## for Latin text with Yuji Boku (brush, SIL OFL) as the fallback that supplies
## every kanji. Both are bundled: system fonts do not exist on Quest.

const LATIN_PATH := "res://assets/fonts/Cinzel-Variable.ttf"
## OpenType axis tag "wght" (the TextServer's tag encoding: four ASCII bytes).
const AXIS_WEIGHT := 0x77676874

static var _cache: Dictionary = {}


## [param weight] 400 regular … 700 bold (the variable font's wght axis).
static func font(weight: int = 500) -> Font:
	if _cache.has(weight):
		return _cache[weight]
	var base := load(LATIN_PATH) as Font
	var f: Font = base
	if base != null:
		var fv := FontVariation.new()
		fv.base_font = base
		fv.variation_opentype = {AXIS_WEIGHT: weight}
		fv.fallbacks = [MemorialTypography.engraving_font()]
		f = fv
	else:
		f = MemorialTypography.engraving_font()
	_cache[weight] = f
	return f
