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
