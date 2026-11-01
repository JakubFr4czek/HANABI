class_name WorldGenLook
extends RefCounted
## Applies a WorldGenProfile's sky, fog, ambient and moon to the scene's
## Environment and Moon light. The run and the World Gen preview both call it,
## so the preview shows what the game shows.


## Depth fog that dissolves the forest into the milk colour (GDD §9), with the
## background set to the same colour so nothing outlines the forest edge.
static func apply_fog(env: Environment, world: WorldGenProfile) -> void:
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = world.fog_color()
	env.fog_light_energy = 1.0
	env.fog_depth_begin = world.fog_start
	env.fog_depth_end = world.fog_end
	env.fog_depth_curve = world.fog_curve
	env.volumetric_fog_enabled = world.volumetric_fog
	env.background_mode = Environment.BG_COLOR
	env.background_color = world.fog_color()
	env.fog_density = 1.0
	env.fog_height_density = 0.0
	env.fog_sky_affect = 1.0


## Ambient, exposure and glow: the light of the forest is the fog itself.
static func apply_light(env: Environment, world: WorldGenProfile) -> void:
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = world.fog_color()
	env.ambient_light_energy = world.ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_exposure = world.exposure
	env.glow_intensity = world.glow_intensity
	env.glow_hdr_threshold = 1.7


static func apply_moon(moon: DirectionalLight3D, world: WorldGenProfile) -> void:
	moon.light_color = world.moon_color()
	moon.light_energy = world.moon_energy
	moon.light_specular = 0.0
	# Soft mist, not a hard edge: the moon's cast shadow on the floor is off (N4 fix1).
	moon.shadow_enabled = false
