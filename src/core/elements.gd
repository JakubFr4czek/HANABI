class_name Elements
## The four elements (docs/GDD.md, section 5), their evolutions, and their colors.

const NONE := "none"
const SAKURA := "sakura"
const STORM := "storm"
const INK := "ink"
const SHADOW := "shadow"
const BLACK_LIGHTNING := "black_lightning"
const PHANTOM_PETALS := "phantom_petals"
const ALL: Array[String] = [NONE, SAKURA, STORM, INK, SHADOW]
const COMBAT_ELEMENTS: Array[String] = [SAKURA, STORM, INK, SHADOW]

## Trail / VFX color. Values above 1 make the color glow.
static func color(element: String) -> Color:
	match element:
		SAKURA: return Color(1.6, 0.35, 0.9)
		STORM: return Color(0.35, 0.9, 2.0)
		INK: return Color(0.02, 0.02, 0.03)
		SHADOW: return Color(0.8, 0.25, 1.6)
		BLACK_LIGHTNING: return Color(0.45, 0.95, 2.2)
		PHANTOM_PETALS: return Color(1.55, 0.32, 1.55)
	return Color(1.1, 1.15, 1.3)


## Readable accent color for UI, seals, and talismans (keeps Ink visible on dark stone).
static func accent_color(element: String) -> Color:
	match element:
		SAKURA: return Color(1.0, 0.32, 0.74)
		STORM: return Color(0.32, 0.82, 1.0)
		INK: return Color(0.56, 0.68, 0.94)
		SHADOW: return Color(0.78, 0.34, 1.0)
		BLACK_LIGHTNING: return Color(0.46, 0.88, 1.0)
		PHANTOM_PETALS: return Color(1.0, 0.36, 0.92)
	return Color(0.85, 0.88, 0.96)


## Quadrant bit index on the floor spawn seal: 0=Sakura, 1=Storm, 2=Ink, 3=Shadow.
static func seal_index(element: String) -> int:
	match element:
		SAKURA: return 0
		STORM: return 1
		INK: return 2
		SHADOW: return 3
	return -1


## Ink is drawn dark over the scene (normal blend); the rest add light.
static func is_additive(element: String) -> bool:
	return element != INK


## Short kanji label for memorial stele / build summaries (GDD §5–6).
static func build_label(element: String) -> String:
	match element:
		SAKURA: return "桜"
		STORM: return "雷"
		INK: return "墨"
		SHADOW: return "影"
		BLACK_LIGHTNING: return "黒雷"
		PHANTOM_PETALS: return "幻影桜"
	return "—"


## One-glyph engraving for each ability, shown on the wrist plate next to its
## button pip (slot 1 = A, slot 2 = B): 千本桜, 花舞, 雷切, 紫電, 墨返, 影縄,
## 影武者, 闇渡り.
static func ability_glyph(element: String, slot: int) -> String:
	match element:
		SAKURA: return "千" if slot == 1 else "舞"
		STORM: return "切" if slot == 1 else "電"
		INK: return "返" if slot == 1 else "縄"
		SHADOW: return "武" if slot == 1 else "渡"
	return ""


## Romanised ability name (menu footer, logs).
static func ability_name(element: String, slot: int) -> String:
	match element:
		SAKURA: return "Senbonzakura" if slot == 1 else "Hanamai"
		STORM: return "Raikiri" if slot == 1 else "Shiden"
		INK: return "Sumi-gaeshi" if slot == 1 else "Kage-nawa"
		SHADOW: return "Kagemusha" if slot == 1 else "Yami-watari"
	return ""
