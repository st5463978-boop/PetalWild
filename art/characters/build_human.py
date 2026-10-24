#!/usr/bin/env python3
"""Faceless mannequin human. Cast > Humans. About 1.7 m, no face.

    blender -b -P art/characters/build_human.py
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy

SCRIPT_DIR = Path(__file__).resolve().parent
REPO = SCRIPT_DIR.parents[1]
GLB_PATH = REPO / "assets" / "characters" / "human.glb"
PREVIEW_DIR = SCRIPT_DIR / "previews"
MAX_TRIS = 5000
CLAY = (0.86, 0.78, 0.70, 1.0)


def reset() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0


def mesh_obj(name, verts, faces) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def capsule(name, radius, height, segs=12, rings=8):
    verts = [(0.0, 0.0, -height * 0.5 - radius)]
    half = height * 0.5
    for j in range(1, rings):
        v = j / rings
        if v < 0.25:
            t = v / 0.25
            phi = math.pi + t * math.pi * 0.5
            rr = max(radius * math.sin(phi), radius * 0.15)
            z = -half + radius * math.cos(phi)
        elif v > 0.75:
            t = (v - 0.75) / 0.25
            phi = math.pi * 0.5 * t
            rr = max(radius * math.cos(phi), radius * 0.15)
            z = half + radius * math.sin(phi)
        else:
            rr = radius
            z = -half + ((v - 0.25) / 0.5) * height
        for i in range(segs):
            a = (i / segs) * math.tau
            verts.append((math.cos(a) * rr, math.sin(a) * rr, z))
    verts.append((0.0, 0.0, half + radius))
    faces = []
    for i in range(segs):
        faces.append((0, 1 + (i + 1) % segs, 1 + i))
    rows = rings - 2
    for j in range(rows):
        for i in range(segs):
            a = 1 + j * segs + i
            b = 1 + j * segs + (i + 1) % segs
            c = 1 + (j + 1) * segs + (i + 1) % segs
            d = 1 + (j + 1) * segs + i
            faces.append((a, b, c, d))
    last = 1 + (rings - 2) * segs
    south = len(verts) - 1
    for i in range(segs):
        faces.append((south, last + i, last + (i + 1) % segs))
    return mesh_obj(name, verts, faces)


def place(obj, loc, rot=None, scale=None) -> None:
    obj.location = loc
    if rot:
        obj.rotation_euler = rot
    if scale:
        obj.scale = scale
    bpy.context.view_layer.update()
    obj.data.transform(obj.matrix_world.copy())
    obj.matrix_world.identity()


def clay(name) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = CLAY
    bsdf.inputs["Roughness"].default_value = 0.82
    return mat


def assign(obj, mat) -> None:
    obj.data.materials.append(mat)


def join(name, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = name
    return objects[0]


def build() -> bpy.types.Object:
    mat = clay("human_clay")
    torso = capsule("Torso", 0.16, 0.55, segs=14, rings=8)
    place(torso, (0.0, 0.0, 1.05))
    hips = capsule("Hips", 0.15, 0.16, segs=12, rings=6)
    place(hips, (0.0, 0.0, 0.78), scale=(1.15, 0.9, 0.8))
    head = capsule("Head", 0.11, 0.08, segs=14, rings=8)
    place(head, (0.0, 0.0, 1.52))
    neck = capsule("Neck", 0.05, 0.06, segs=8, rings=4)
    place(neck, (0.0, 0.0, 1.38))
    parts = [torso, hips, head, neck]
    for side, sx in (("L", 1.0), ("R", -1.0)):
        arm = capsule(f"Arm{side}", 0.045, 0.28, segs=8, rings=6)
        place(arm, (0.24 * sx, 0.0, 1.12), rot=(0.15, 0.0, 0.15 * sx))
        forearm = capsule(f"Fore{side}", 0.038, 0.24, segs=8, rings=5)
        place(forearm, (0.30 * sx, 0.04, 0.82), rot=(0.4, 0.0, 0.05 * sx))
        hand = capsule(f"Hand{side}", 0.04, 0.02, segs=8, rings=4)
        place(hand, (0.32 * sx, 0.08, 0.66), scale=(0.7, 1.1, 0.55))
        thigh = capsule(f"Thigh{side}", 0.07, 0.32, segs=10, rings=6)
        place(thigh, (0.09 * sx, 0.0, 0.58))
        shin = capsule(f"Shin{side}", 0.05, 0.32, segs=8, rings=6)
        place(shin, (0.09 * sx, 0.02, 0.28))
        foot = capsule(f"Foot{side}", 0.045, 0.04, segs=8, rings=4)
        place(foot, (0.09 * sx, 0.06, 0.06), scale=(0.9, 1.6, 0.55))
        parts.extend([arm, forearm, hand, thigh, shin, foot])
    body = join("HumanBody", parts)
    assign(body, mat)
    return body


def render(obj) -> None:
    scene = bpy.context.scene
    world = bpy.data.worlds.new("HumanWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.75, 0.85, 0.95, 1.0)
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4.0
    sun.data.color = (1.0, 0.89, 0.66)
    sun.rotation_euler = (0.9, 0.2, 0.4)
    bpy.context.collection.objects.link(sun)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    cam.location = (1.6, 2.4, 1.35)
    from mathutils import Vector

    direction = Vector((0.0, 0.0, 0.9)) - Vector(cam.location)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x = 720
    scene.render.resolution_y = 900
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.cycles.use_denoising = True
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(PREVIEW_DIR / "human_threequarter.png")
    scene.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)


def main() -> None:
    reset()
    body = build()
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    if tris >= MAX_TRIS:
        raise SystemExit(f"human tris {tris}")
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(GLB_PATH), export_format="GLB", export_yup=True)
    render(body)
    stats = {"species": "human", "cast": "humans", "tris": {"HumanBody": tris, "total": tris}, "height_m": 1.7, "glb": "assets/characters/human.glb"}
    (SCRIPT_DIR / "build_stats_human.json").write_text(json.dumps(stats, indent=2) + "\n")
    print("HUMAN_BUILD_OK", tris, GLB_PATH.stat().st_size)


if __name__ == "__main__":
    main()
    sys.argv = [sys.argv[0]]
