import argparse
import json
import subprocess
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--glb", required=True)
    parser.add_argument("--usdz", required=True)
    parser.add_argument("--collision", required=True)
    parser.add_argument("--preview", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--usdzip", required=True)
    if "--" not in sys.argv:
        raise RuntimeError("missing_argument_marker")
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:])


def mesh_objects():
    return [item for item in bpy.context.scene.objects if item.type == "MESH"]


def reject_unsupported_scene_content():
    unsupported = [item for item in bpy.context.scene.objects if item.type in {"CAMERA", "LIGHT"}]
    if unsupported or bpy.data.actions:
        raise RuntimeError("unsupported_scene_content")


def bound_texture_resolution(limit=1024):
    for image in bpy.data.images:
        width, height = image.size
        largest = max(width, height)
        if largest > limit:
            scale = limit / largest
            image.scale(max(1, round(width * scale)), max(1, round(height * scale)))


def world_bounds(objects):
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    if not points:
        raise RuntimeError("no_meshes")
    return (
        Vector((min(point.x for point in points), min(point.y for point in points), min(point.z for point in points))),
        Vector((max(point.x for point in points), max(point.y for point in points), max(point.z for point in points))),
    )


def select(objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def make_collision(lower, upper):
    bpy.ops.mesh.primitive_cube_add(location=(0, 0, 0))
    collision = bpy.context.active_object
    collision.name = "ReframeCollisionAABB"
    collision.dimensions = upper - lower
    collision.location = (lower + upper) / 2
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return collision


def render_preview(lower, upper, path):
    center = (lower + upper) / 2
    size = max((upper - lower).x, (upper - lower).y, (upper - lower).z)
    bpy.ops.object.camera_add(location=(center.x + size * 2.4, center.y - size * 2.4, center.z + size * 1.8))
    camera = bpy.context.active_object
    bpy.context.scene.camera = camera
    direction = center - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.ops.object.light_add(type="AREA", location=(center.x + size, center.y - size, center.z + size * 2))
    bpy.context.active_object.data.energy = 1200
    bpy.context.active_object.data.shape = "DISK"
    bpy.context.active_object.data.size = size * 3
    bpy.context.scene.render.engine = "BLENDER_EEVEE"
    bpy.context.scene.render.resolution_x = 512
    bpy.context.scene.render.resolution_y = 512
    bpy.context.scene.render.resolution_percentage = 100
    bpy.context.scene.render.image_settings.file_format = "PNG"
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def reopen_delivery_glb(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    if not mesh_objects():
        raise RuntimeError("delivery_glb_reopen_failed")


def main():
    args = parse_args()
    for target in (args.glb, args.usdz, args.collision, args.preview, args.manifest):
        Path(target).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.source)
    reject_unsupported_scene_content()
    bound_texture_resolution()
    visible = mesh_objects()
    if not visible:
        raise RuntimeError("no_meshes")
    lower, upper = world_bounds(visible)
    shift = Vector((-(lower.x + upper.x) / 2, -(lower.y + upper.y) / 2, -lower.z))
    for obj in visible:
        obj.location += shift
    bpy.context.view_layer.update()
    lower, upper = world_bounds(visible)
    select(visible)
    bpy.ops.export_scene.gltf(filepath=args.glb, export_format="GLB", use_selection=True, export_animations=False)
    usda = f"{args.usdz}.usda"
    bpy.ops.wm.usd_export(filepath=usda, export_materials=True, export_textures_mode="NEW", selected_objects_only=True)
    subprocess.run([args.usdzip, "--arkitAsset", usda, args.usdz], check=True)
    collision = make_collision(lower, upper)
    select([collision])
    bpy.ops.export_scene.gltf(filepath=args.collision, export_format="GLB", use_selection=True, export_animations=False)
    collision.hide_render = True
    render_preview(lower, upper, args.preview)
    dimensions = upper - lower
    Path(args.manifest).write_text(json.dumps({
        "dimensions_m": {"width": dimensions.x, "height": dimensions.z, "depth": dimensions.y},
        "blender_version": bpy.app.version_string,
    }, sort_keys=True), encoding="utf-8")
    Path(usda).unlink(missing_ok=True)
    reopen_delivery_glb(args.glb)


if __name__ == "__main__":
    main()
