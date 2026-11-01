# Bakes the CC BY 4.0 "Japanese demon mask" (Eques_inferno, Sketchfab) into the yōkai head mesh (N3).
# Run with Blender headless (Blender 4.x, the glTF importer/exporter built in):
#   blender -b --factory-startup -P tools/bake_yokai_mask.py -- SRC.glb OUT.glb OUT_DIR TRIS
#   e.g. TRIS=1700 -> ~1.7k triangles; the textures go to OUT_DIR as yokai_mask_{albedo,orm,normal}.png
#   optional: WIDTH (m) and FRONT (m), defaults 0.176 and 0.135 (the N3 first bake)
# Note: the trailing `--` separates Blender's own arguments from ours.
# Source: face +X, up +Z, units arbitrary. Output (Godot frame): face +Z, up +Y, metres,
# centred on the head origin with the nose at z=FRONT and the flange inside the skull.
import bpy, sys, math
from mathutils import Matrix, Vector
argv = sys.argv; a = argv[argv.index("--") + 1:]
src, dst_glb, dst_dir, target_tris = a[0], a[1], a[2], int(a[3])
WIDTH = 0.176   # m across the cheeks (source Y span); default, see the optional 5th argument
FRONT = 0.135   # m: the nose tip sits this far in front of the head origin (Godot +Z); optional 6th argument
if len(a) > 4:
    WIDTH = float(a[4])
if len(a) > 5:
    FRONT = float(a[5])
CENTER_Y = -0.012
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for o in meshes:
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
ob.name = "YokaiMask"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = ob.data
# Triangulate, then decimate to the target triangle count (edge-collapse keeps the silhouette).
bpy.ops.object.mode_set(mode='OBJECT')
tris = sum(len(p.vertices) - 2 for p in me.polygons)
mod = ob.modifiers.new("tri", 'TRIANGULATE'); bpy.ops.object.modifier_apply(modifier=mod.name)
ratio = min(1.0, target_tris / max(1, tris))
dec = ob.modifiers.new("dec", 'DECIMATE'); dec.decimate_type = 'COLLAPSE'; dec.ratio = ratio
dec.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier=dec.name)
me = ob.data
tris_after = sum(len(p.vertices) - 2 for p in me.polygons)
print("TRIS", tris, "->", tris_after)
# Source axes -> Godot head frame (pre glTF export: Godot = (x, z, -y)): face X -> -Y, up Z -> Z, Y -> X.
M = Matrix(((0, 1, 0), (-1, 0, 0), (0, 0, 1))).to_4x4()
me.transform(M)
me.update()
vs = [v.co for v in me.vertices]
mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
span_x = (mx.x - mn.x)  # source Y span -> width
s = WIDTH / span_x
me.transform(Matrix.Scale(s, 4))
vs = [v.co for v in me.vertices]
mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
cx = (mn.x + mx.x) / 2.0
cz = (mn.z + mx.z) / 2.0
# Godot z = -blender y: the nose (min blender y) sits at Godot z = FRONT; the mask's centre is
# on the head's axis, its vertical centre at CENTER_Y.
shift = Vector((-cx, -FRONT - mn.y, -cz + CENTER_Y))
me.transform(Matrix.Translation(shift))
me.update()
vs = [v.co for v in me.vertices]
mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
print("SCALE", s, "BBOX_GODOT min", (mn.x, -mx.y, mn.z), "max", (mx.x, -mn.y, mx.z))
ob.location = (0, 0, 0); ob.rotation_euler = (0, 0, 0); ob.scale = (1, 1, 1)
# Export mesh only; the textures are written beside it and bound by the game's shader.
bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active = ob
bpy.ops.export_scene.gltf(filepath=dst_glb, export_format='GLB', use_selection=True,
                          export_materials='NONE', export_apply=True, export_yup=True)
# Textures from the source material (albedo, ORM, normal), kept at 1K.
src_imgs = {}
for im in bpy.data.images:
    src_imgs[im.name] = im
for name, out in [("Image_0", "yokai_mask_albedo.png"), ("Image_1", "yokai_mask_orm.png"), ("Image_2", "yokai_mask_normal.png")]:
    im = src_imgs.get(name)
    if im is None:
        print("MISSING", name); continue
    im.scale(1024, 1024) if im.size[0] != 1024 else None
    im.filepath_raw = dst_dir + "/" + out
    im.file_format = 'PNG'
    im.save()
    print("TEX", out, tuple(im.size))
