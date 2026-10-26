class_name Elements
## The four elements (docs/GDD.md, section 5) and their colors.

const NONE := "none"
const SAKURA := "sakura"
const STORM := "storm"
const INK := "ink"
const SHADOW := "shadow"
const ALL: Array[String] = [NONE, SAKURA, STORM, INK, SHADOW]

## Trail / VFX color. Values above 1 make the color glow.
static func color(element: String) -> Color:
	match element:
		SAKURA: return Color(1.6, 0.35, 0.9)
		STORM: return Color(0.35, 0.9, 2.0)
		INK: return Color(0.02, 0.02, 0.03)
		SHADOW: return Color(0.8, 0.25, 1.6)
	return Color(1.1, 1.15, 1.3)


## Ink is drawn dark over the scene (normal blend); the rest add light.
static func is_additive(element: String) -> bool:
	return element != INK
