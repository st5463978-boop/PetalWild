#!/usr/bin/env python3
"""Build the first PetalWild veg villager: a jelly-bodied carrot.

Run from the repo root:

    ~/.local/blender/blender-4.2.9-linux-x64/blender -b -P art/characters/build_carrot.py

Writes:
    assets/characters/carrot.glb
    art/characters/carrot.blend
    art/characters/textures/carrot/*
    art/characters/previews/carrot_*.png
    art/characters/build_stats.json
"""

from __future__ import annotations

import json
import math
import os
import struct
import sys
import zlib
from pathlib import Path

import bpy
from mathutils import Vector

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
REPO = SCRIPT_DIR.parents[1]
GLB_PATH = REPO / "assets" / "characters" / "carrot.glb"
BLEND_PATH = SCRIPT_DIR / "carrot.blend"
TEX_DIR = SCRIPT_DIR / "textures" / "carrot"
PREVIEW_DIR = SCRIPT_DIR / "previews"
STATS_PATH = SCRIPT_DIR / "build_stats.json"

# 1 Blender unit = 1 metre. Matches existing veg people (~1.1–1.2 m).
# Face sits on +Y (Blender front view).

SPECIES = {
    "id": "carrot",
    "body_color": (1.0, 0.52, 0.12, 1.0),
    "body_deep": (0.96, 0.38, 0.07, 1.0),
    "body_light": (1.0, 0.74, 0.38, 1.0),
    "leaf_color": (0.48, 0.86, 0.30, 1.0),
    "leaf_deep": (0.28, 0.62, 0.16, 1.0),
    "cheek_color": (0.98, 0.45, 0.32, 1.0),
    "mouth_color": (0.42, 0.14, 0.14, 1.0),
    "eye_white": (0.98, 0.96, 0.92, 1.0),
    "eye_iris": (0.22, 0.12, 0.08, 1.0),
}

# Chubby carrot profile: (radius, z). Legs sit under the lowest ring.
BODY_PROFILE = [
    (0.048, 0.155),
    (0.082, 0.210),
    (0.125, 0.300),
    (0.170, 0.400),
    (0.210, 0.510),
    (0.238, 0.610),
    (0.248, 0.700),
    (0.232, 0.790),
    (0.185, 0.870),
    (0.118, 0.930),
    (0.058, 0.970),
    (0.020, 0.995),
]

SEGS = 22
MAX_TRIS = 5000


def radius_at(z: float) -> float:
    if z <= BODY_PROFILE[0][1]:
        return BODY_PROFILE[0][0]
    if z >= BODY_PROFILE[-1][1]:
        return BODY_PROFILE[-1][0]
    for i in range(len(BODY_PROFILE) - 1):
        r0, z0 = BODY_PROFILE[i]
        r1, z1 = BODY_PROFILE[i + 1]
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            t = t * t * (3.0 - 2.0 * t)
            return r0 + (r1 - r0) * t
    return BODY_PROFILE[-1][0]


# ---------------------------------------------------------------------------
# Tiny PNG writer (stdlib only)
# ---------------------------------------------------------------------------

def write_png(path: Path, width: int, height: int, rgba: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(
            ">I", zlib.crc32(tag + data) & 0xFFFFFFFF
        )

    raw = b"".join(b"\x00" + rgba[y * width * 4 : (y + 1) * width * 4] for y in range(height))
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def mix3(a, b, t):
    return tuple(lerp(a[i], b[i], t) for i in range(3))


def to_u8(rgb, a=1.0) -> bytes:
    return bytes(
        [
            max(0, min(255, int(rgb[0] * 255 + 0.5))),
            max(0, min(255, int(rgb[1] * 255 + 0.5))),
            max(0, min(255, int(rgb[2] * 255 + 0.5))),
            max(0, min(255, int(a * 255 + 0.5))),
        ]
    )


def bake_body_albedo(path: Path, size: int) -> None:
    deep = SPECIES["body_deep"][:3]
    mid = SPECIES["body_color"][:3]
    light = SPECIES["body_light"][:3]
    pixels = bytearray()
    for y in range(size):
        v = y / max(size - 1, 1)
        band = mix3(deep, light, v * 0.55 + 0.28)
        for x in range(size):
            u = x / max(size - 1, 1)
            ridge = 0.5 + 0.5 * math.cos(u * math.tau * 5.0)
            shade = 0.94 + 0.08 * ridge
            # Soft belly highlight in the upper-middle third.
            highlight = math.exp(-((v - 0.62) ** 2) / 0.045) * math.exp(-((u - 0.5) ** 2) / 0.08)
            col = mix3(tuple(c * shade for c in band), light, highlight * 0.35)
            pixels.extend(to_u8(col))
    write_png(path, size, size, bytes(pixels))


def bake_leaf_albedo(path: Path, size: int) -> None:
    deep = SPECIES["leaf_deep"][:3]
    lit = SPECIES["leaf_color"][:3]
    pixels = bytearray()
    for y in range(size):
        v = y / max(size - 1, 1)
        for x in range(size):
            u = x / max(size - 1, 1)
            midrib = math.exp(-((u - 0.5) ** 2) / 0.006)
            vein = 0.5 + 0.5 * math.cos((v * 7.0 + abs(u - 0.5) * 4.0) * math.pi)
            col = mix3(deep, lit, 0.35 + v * 0.45 + vein * 0.08)
            col = mix3(col, deep, midrib * 0.35)
            pixels.extend(to_u8(col))
    write_png(path, size, size, bytes(pixels))


# ---------------------------------------------------------------------------
# Scene reset
# ---------------------------------------------------------------------------

def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = 48
    scene.frame_current = 1


# ---------------------------------------------------------------------------
# Mesh helpers
# ---------------------------------------------------------------------------

def new_mesh_object(name: str, verts, faces, uvs=None, smooth=True) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    if uvs is not None:
        uv = mesh.uv_layers.new(name="UVMap")
        for loop in mesh.loops:
            uv.data[loop.index].uv = uvs[loop.vertex_index]
    if smooth:
        for poly in mesh.polygons:
            poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def lathe(name: str, profile, segs: int) -> bpy.types.Object:
    verts = []
    uvs = []
    for r, z in profile:
        for i in range(segs):
            a = (i / segs) * math.tau
            ridge = 1.0 + 0.018 * math.cos(a * 5.0)
            x = math.cos(a) * r * ridge
            y = math.sin(a) * r * ridge
            verts.append((x, y, z))
            uvs.append((i / segs, (z - profile[0][1]) / max(profile[-1][1] - profile[0][1], 1e-6)))
    # pole caps
    verts.append((0.0, 0.0, profile[0][1] - 0.012))
    uvs.append((0.5, 0.0))
    verts.append((0.0, 0.0, profile[-1][1] + 0.004))
    uvs.append((0.5, 1.0))
    bottom = len(verts) - 2
    top = len(verts) - 1
    faces = []
    rings = len(profile)
    for row in range(rings - 1):
        for i in range(segs):
            a = row * segs + i
            b = row * segs + (i + 1) % segs
            c = (row + 1) * segs + (i + 1) % segs
            d = (row + 1) * segs + i
            faces.append((a, b, c, d))
    for i in range(segs):
        faces.append((bottom, i, (i + 1) % segs))
        last = (rings - 1) * segs
        faces.append((top, last + (i + 1) % segs, last + i))
    return new_mesh_object(name, verts, faces, uvs)


def capsule(name: str, radius: float, height: float, segs=10, rings=8) -> bpy.types.Object:
    """Closed capsule along +Z, single pole verts so the ends do not collapse to black."""
    verts = []
    uvs = []
    half = height * 0.5
    verts.append((0.0, 0.0, -half - radius))
    uvs.append((0.5, 0.0))
    for j in range(1, rings):
        v = j / rings
        if v < 0.25:
            t = v / 0.25
            phi = math.pi + t * (math.pi * 0.5)
            rr = max(radius * math.sin(phi), radius * 0.12)
            z = -half + radius * math.cos(phi)
        elif v > 0.75:
            t = (v - 0.75) / 0.25
            phi = math.pi * 0.5 * t
            rr = max(radius * math.cos(phi), radius * 0.12)
            z = half + radius * math.sin(phi)
        else:
            t = (v - 0.25) / 0.5
            rr = radius
            z = -half + t * height
        for i in range(segs):
            a = (i / segs) * math.tau
            verts.append((math.cos(a) * rr, math.sin(a) * rr, z))
            uvs.append((i / segs, v))
    verts.append((0.0, 0.0, half + radius))
    uvs.append((0.5, 1.0))
    bottom = 0
    top = len(verts) - 1
    faces = []
    for i in range(segs):
        faces.append((bottom, 1 + (i + 1) % segs, 1 + i))
    rows = rings - 2
    for j in range(rows):
        for i in range(segs):
            a = 1 + j * segs + i
            b = 1 + j * segs + (i + 1) % segs
            c = 1 + (j + 1) * segs + (i + 1) % segs
            d = 1 + (j + 1) * segs + i
            faces.append((a, b, c, d))
    last = 1 + (rings - 2) * segs
    for i in range(segs):
        faces.append((top, last + i, last + (i + 1) % segs))
    return new_mesh_object(name, verts, faces, uvs)


def sphere(name: str, radius: float, segs=12, rings=8) -> bpy.types.Object:
    verts = [(0.0, 0.0, radius)]
    uvs = [(0.5, 1.0)]
    for j in range(1, rings):
        v = j / rings
        phi = v * math.pi
        rr = radius * math.sin(phi)
        z = radius * math.cos(phi)
        for i in range(segs):
            a = (i / segs) * math.tau
            verts.append((math.cos(a) * rr, math.sin(a) * rr, z))
            uvs.append((i / segs, 1.0 - v))
    verts.append((0.0, 0.0, -radius))
    uvs.append((0.5, 0.0))
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
    return new_mesh_object(name, verts, faces, uvs)


def leaf_blade(name: str, length: float, width: float) -> bpy.types.Object:
    """Simple rounded leaf in XY, growing +Z from the origin."""
    verts = []
    uvs = []
    rows = 7
    cols = 6
    for j in range(rows + 1):
        v = j / rows
        z = v * length
        # pointed tip, wider mid
        span = width * math.sin(v * math.pi) * (1.0 - 0.15 * v)
        bend = (v * v) * 0.08
        for i in range(cols + 1):
            u = i / cols
            x = (u - 0.5) * 2.0 * span
            y = bend + 0.012 * math.sin(u * math.pi) * math.sin(v * math.pi)
            verts.append((x, y, z))
            uvs.append((u, v))
    faces = []
    for j in range(rows):
        for i in range(cols):
            a = j * (cols + 1) + i
            b = a + 1
            c = a + cols + 2
            d = a + cols + 1
            faces.append((a, b, c, d))
    return new_mesh_object(name, verts, faces, uvs)


def smile(name: str) -> bpy.types.Object:
    verts = []
    uvs = []
    segs = 10
    for i in range(segs + 1):
        t = i / segs
        a = math.pi + t * math.pi
        x = math.cos(a) * 0.038
        z = math.sin(a) * 0.016
        for k, y in enumerate((0.0, 0.006)):
            verts.append((x, y, z))
            uvs.append((t, float(k)))
    faces = []
    for i in range(segs):
        a = i * 2
        faces.append((a, a + 2, a + 3, a + 1))
    return new_mesh_object(name, verts, faces, uvs)


def join_objects(name: str, objects: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = name
    objects[0].data.name = name
    return objects[0]


def transform(obj: bpy.types.Object, loc=None, rot=None, scale=None) -> None:
    if loc is not None:
        obj.location = loc
    if rot is not None:
        obj.rotation_euler = rot
    if scale is not None:
        obj.scale = scale
    bpy.context.view_layer.update()
    mw = obj.matrix_world.copy()
    obj.data.transform(mw)
    obj.matrix_world.identity()
    obj.data.update()


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

def image_from_png(name: str, path: Path) -> bpy.types.Image:
    img = bpy.data.images.load(str(path), check_existing=True)
    img.name = name
    img.pack()
    return img


def principled(name: str, color, roughness=0.28, transmission=0.0, sss=0.0, tex=None, alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    out = nt.nodes.get("Material Output")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    if "Transmission Weight" in bsdf.inputs:
        bsdf.inputs["Transmission Weight"].default_value = transmission
    elif "Transmission" in bsdf.inputs:
        bsdf.inputs["Transmission"].default_value = transmission
    if "Subsurface Weight" in bsdf.inputs:
        bsdf.inputs["Subsurface Weight"].default_value = sss
    elif "Subsurface" in bsdf.inputs:
        bsdf.inputs["Subsurface"].default_value = sss
    if "Subsurface Radius" in bsdf.inputs:
        bsdf.inputs["Subsurface Radius"].default_value = (0.4, 0.18, 0.08)
    if "Coat Weight" in bsdf.inputs and transmission > 0.0:
        bsdf.inputs["Coat Weight"].default_value = 0.22
        bsdf.inputs["Coat Roughness"].default_value = 0.08
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        mat.blend_method = "BLEND"
    if tex is not None:
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = tex
        node.location = (-300, 200)
        nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def assign(obj: bpy.types.Object, mat: bpy.types.Material) -> None:
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)


# ---------------------------------------------------------------------------
# Armature
# ---------------------------------------------------------------------------

def make_armature() -> bpy.types.Object:
    data = bpy.data.armatures.new("CarrotArmature")
    data.display_type = "OCTAHEDRAL"
    arm = bpy.data.objects.new("CarrotArmature", data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = data.edit_bones

    def bone(name, head, tail, parent=None):
        b = eb.new(name)
        b.head = head
        b.tail = tail
        b.use_deform = True
        if parent is not None:
            b.parent = eb[parent]
            b.use_connect = False
        return b

    bone("Root", (0, 0, 0.0), (0, 0, 0.08))
    bone("Body", (0, 0, 0.16), (0, 0, 0.58), "Root")
    bone("Head", (0, 0, 0.62), (0, 0, 0.88), "Body")
    bone("LeafTop", (0, 0, 0.92), (0, 0, 1.12), "Head")
    bone("Arm_L", (0.20, 0.04, 0.62), (0.32, 0.10, 0.52), "Body")
    bone("Arm_R", (-0.20, 0.04, 0.62), (-0.32, 0.10, 0.52), "Body")
    bone("Leg_L", (0.07, 0.02, 0.15), (0.075, 0.05, 0.02), "Root")
    bone("Leg_R", (-0.07, 0.02, 0.15), (-0.075, 0.05, 0.02), "Root")
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def skin(obj: bpy.types.Object, arm: bpy.types.Object, weights) -> None:
    """weights(co) -> dict bone_name -> weight."""
    groups = {}
    for name in ("Root", "Body", "Head", "LeafTop", "Arm_L", "Arm_R", "Leg_L", "Leg_R"):
        groups[name] = obj.vertex_groups.new(name=name)
    for i, v in enumerate(obj.data.vertices):
        w = weights(v.co)
        total = sum(w.values()) or 1.0
        for name, value in w.items():
            groups[name].add([i], value / total, "REPLACE")
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    mod.use_vertex_groups = True
    obj.parent = arm


def jelly_weights(co: Vector) -> dict:
    x, y, z = co.x, co.y, co.z
    w = {"Root": 0.05, "Body": 0.7, "Head": 0.0, "LeafTop": 0.0, "Arm_L": 0.0, "Arm_R": 0.0, "Leg_L": 0.0, "Leg_R": 0.0}
    if z > 0.66:
        t = min(1.0, (z - 0.66) / 0.26)
        w["Head"] = 0.15 + 0.75 * t
        w["Body"] = 0.85 - 0.75 * t
    if z > 0.92:
        w["LeafTop"] = min(1.0, (z - 0.92) / 0.12)
        w["Head"] = max(0.15, w["Head"] - w["LeafTop"] * 0.5)
    if z < 0.18 and abs(x) > 0.025:
        side = "Leg_L" if x > 0 else "Leg_R"
        w[side] = 1.0
        w["Body"] = 0.0
        w["Root"] = 0.0
        w["Head"] = 0.0
    if z > 0.46 and z < 0.70 and abs(x) > 0.19:
        side = "Arm_L" if x > 0 else "Arm_R"
        w[side] = 1.0
        w["Body"] = 0.0
        w["Head"] = 0.0
    return w


def parent_bone(obj: bpy.types.Object, arm: bpy.types.Object, bone: str) -> None:
    obj.parent = arm
    obj.parent_type = "BONE"
    obj.parent_bone = bone
    # Keep world pose after parenting to the bone tail.
    bpy.context.view_layer.update()


# ---------------------------------------------------------------------------
# Character
# ---------------------------------------------------------------------------

def build_meshes(arm, body_tex, leaf_tex):
    jelly_mat = principled(
        "carrot_jelly",
        SPECIES["body_color"],
        roughness=0.16,
        transmission=0.10,
        sss=0.18,
        tex=body_tex,
    )
    leaf_mat = principled("carrot_leaf", SPECIES["leaf_color"], roughness=0.42, sss=0.08, tex=leaf_tex)
    white_mat = principled("carrot_eye_white", SPECIES["eye_white"], roughness=0.08)
    iris_mat = principled("carrot_eye_iris", SPECIES["eye_iris"], roughness=0.35)
    highlight_mat = principled("carrot_eye_highlight", (1, 1, 1, 1), roughness=0.02)
    mouth_mat = principled("carrot_mouth", SPECIES["mouth_color"], roughness=0.45)
    cheek_mat = principled("carrot_cheek", SPECIES["cheek_color"], roughness=0.32, sss=0.2)

    body = lathe("CarrotBody", BODY_PROFILE, SEGS)
    face_z = 0.72
    face_r = radius_at(face_z)

    # Stubby nubs, not stick arms.
    arm_l = capsule("CarrotArm_L", 0.050, 0.14, segs=10, rings=8)
    transform(arm_l, loc=(0.24, 0.05, 0.60), rot=(0.85, 0.0, -1.15))
    arm_r = capsule("CarrotArm_R", 0.050, 0.14, segs=10, rings=8)
    transform(arm_r, loc=(-0.24, 0.05, 0.60), rot=(0.85, 0.0, 1.15))
    hand_l = sphere("CarrotHand_L", 0.052, segs=10, rings=6)
    transform(hand_l, loc=(0.32, 0.11, 0.52))
    hand_r = sphere("CarrotHand_R", 0.052, segs=10, rings=6)
    transform(hand_r, loc=(-0.32, 0.11, 0.52))

    leg_l = capsule("CarrotLeg_L", 0.052, 0.12, segs=10, rings=7)
    transform(leg_l, loc=(0.07, 0.02, 0.09))
    leg_r = capsule("CarrotLeg_R", 0.052, 0.12, segs=10, rings=7)
    transform(leg_r, loc=(-0.07, 0.02, 0.09))
    foot_l = sphere("CarrotFoot_L", 0.058, segs=10, rings=6)
    transform(foot_l, loc=(0.075, 0.05, 0.035), scale=(1.2, 1.4, 0.72))
    foot_r = sphere("CarrotFoot_R", 0.058, segs=10, rings=6)
    transform(foot_r, loc=(-0.075, 0.05, 0.035), scale=(1.2, 1.4, 0.72))

    jelly = join_objects(
        "CarrotJelly",
        [body, arm_l, arm_r, hand_l, hand_r, leg_l, leg_r, foot_l, foot_r],
    )
    assign(jelly, jelly_mat)
    skin(jelly, arm, jelly_weights)

    # Two chunky fronds like the garden close-up, plus a small third sprout.
    stem_l = capsule("CarrotStem_L", 0.022, 0.20, segs=8, rings=5)
    transform(stem_l, loc=(0.04, 0.01, 1.08), rot=(0.12, 0.0, 0.28))
    stem_r = capsule("CarrotStem_R", 0.020, 0.18, segs=8, rings=5)
    transform(stem_r, loc=(-0.035, 0.015, 1.06), rot=(0.08, 0.0, -0.34))
    blade_l = sphere("CarrotBlade_L", 0.09, segs=10, rings=6)
    transform(blade_l, loc=(0.10, 0.03, 1.24), rot=(0.2, 0.1, 0.4), scale=(0.85, 0.28, 1.55))
    blade_r = sphere("CarrotBlade_R", 0.08, segs=10, rings=6)
    transform(blade_r, loc=(-0.09, 0.04, 1.20), rot=(0.18, -0.08, -0.45), scale=(0.8, 0.26, 1.45))
    blade_c = sphere("CarrotBlade_C", 0.055, segs=8, rings=5)
    transform(blade_c, loc=(0.01, -0.02, 1.16), rot=(0.4, 0.0, 0.1), scale=(0.7, 0.24, 1.2))
    leaves = join_objects("CarrotLeaf", [stem_l, stem_r, blade_l, blade_r, blade_c])
    assign(leaves, leaf_mat)
    skin(leaves, arm, lambda _co: {"LeafTop": 1.0})

    # Face on +Y.
    fy = face_r * 0.90
    parts = []
    for side, sx in (("L", 1.0), ("R", -1.0)):
        white = sphere(f"CarrotEyeWhite_{side}", 0.068, segs=12, rings=8)
        transform(white, loc=(0.078 * sx, fy + 0.016, face_z + 0.01), scale=(1.08, 0.78, 1.18))
        assign(white, white_mat)
        iris = sphere(f"CarrotEyeIris_{side}", 0.040, segs=10, rings=6)
        transform(iris, loc=(0.080 * sx, fy + 0.038, face_z - 0.004), scale=(1.0, 0.7, 1.08))
        assign(iris, iris_mat)
        shine = sphere(f"CarrotEyeShine_{side}", 0.014, segs=8, rings=5)
        transform(shine, loc=(0.096 * sx, fy + 0.054, face_z + 0.016))
        assign(shine, highlight_mat)
        cheek = sphere(f"CarrotCheek_{side}", 0.032, segs=8, rings=5)
        transform(cheek, loc=(0.135 * sx, fy - 0.008, face_z - 0.09), scale=(1.25, 0.55, 0.78))
        assign(cheek, cheek_mat)
        parts.extend([white, iris, shine, cheek])

    mouth = smile("CarrotMouth")
    transform(mouth, loc=(0.0, fy + 0.022, face_z - 0.085), rot=(0.18, 0.0, 0.0))
    assign(mouth, mouth_mat)
    parts.append(mouth)

    face = join_objects("CarrotFace", parts)
    skin(face, arm, lambda _co: {"Head": 1.0})

    return jelly, leaves, face


# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------

def _clear_pose(arm: bpy.types.Object) -> None:
    for bone in arm.pose.bones:
        bone.location = (0, 0, 0)
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0, 0, 0)
        bone.scale = (1, 1, 1)


def _kf(bone, frame, loc=None, rot=None, scale=None) -> None:
    if loc is not None:
        bone.location = loc
        bone.keyframe_insert("location", frame=frame)
    if rot is not None:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = rot
        bone.keyframe_insert("rotation_euler", frame=frame)
    if scale is not None:
        bone.scale = scale
        bone.keyframe_insert("scale", frame=frame)


def _make_cyclic(action: bpy.types.Action) -> None:
    for fcurve in action.fcurves:
        for kp in fcurve.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.easing = "EASE_IN_OUT"
            kp.handle_left_type = "AUTO_CLAMPED"
            kp.handle_right_type = "AUTO_CLAMPED"
        mod = fcurve.modifiers.new("CYCLES")
        mod.mode_before = "REPEAT"
        mod.mode_after = "REPEAT"


def _push_nla(arm: bpy.types.Object, action: bpy.types.Action, name: str) -> None:
    if arm.animation_data is None:
        arm.animation_data_create()
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    start = int(action.frame_range[0])
    track.strips.new(name, start, action)
    arm.animation_data.action = None


def animate(arm: bpy.types.Object) -> None:
    arm.animation_data_create()
    bones = arm.pose.bones

    # --- idle: 48 frames, gentle bob ---
    idle = bpy.data.actions.new("idle")
    idle.use_fake_user = True
    arm.animation_data.action = idle
    _clear_pose(arm)
    for frame, phase in ((1, 0.0), (13, 0.5), (25, 1.0), (37, 1.5), (48, 2.0)):
        s = math.sin(phase * math.pi)
        c = math.cos(phase * math.pi)
        _kf(bones["Root"], frame, loc=(0.0, 0.0, 0.012 * s), rot=(0.02 * s, 0.0, 0.015 * c))
        _kf(bones["Body"], frame, rot=(0.03 * s, 0.0, 0.0), scale=(1.0 + 0.018 * s, 1.0 + 0.012 * s, 1.0 - 0.02 * s))
        _kf(bones["Head"], frame, rot=(0.04 * s, 0.0, 0.02 * c))
        _kf(bones["LeafTop"], frame, rot=(0.08 * s, 0.06 * c, 0.04 * s))
        _kf(bones["Arm_L"], frame, rot=(0.08 * s, 0.0, 0.05 * c))
        _kf(bones["Arm_R"], frame, rot=(0.08 * c, 0.0, -0.05 * s))
        _kf(bones["Leg_L"], frame, rot=(0.03 * s, 0.0, 0.0))
        _kf(bones["Leg_R"], frame, rot=(0.03 * c, 0.0, 0.0))
    idle.frame_range = (1, 48)
    _make_cyclic(idle)
    _push_nla(arm, idle, "idle")

    # --- walk: 24 frames, in-place cycle ---
    walk = bpy.data.actions.new("walk")
    walk.use_fake_user = True
    arm.animation_data.action = walk
    _clear_pose(arm)
    for frame, phase in ((1, 0.0), (7, 0.5), (13, 1.0), (19, 1.5), (24, 2.0)):
        s = math.sin(phase * math.pi)
        c = math.cos(phase * math.pi)
        _kf(bones["Root"], frame, loc=(0.0, 0.0, 0.03 * abs(s)), rot=(0.04 * s, 0.0, 0.06 * c))
        _kf(bones["Body"], frame, rot=(0.06 * s, 0.0, 0.05 * c), scale=(1.0 + 0.03 * abs(s), 1.0, 1.0 - 0.025 * abs(s)))
        _kf(bones["Head"], frame, rot=(0.05 * s, 0.0, 0.04 * c))
        _kf(bones["LeafTop"], frame, rot=(0.18 * s, 0.1 * c, 0.08 * s))
        _kf(bones["Arm_L"], frame, rot=(-0.55 * s, 0.0, 0.12))
        _kf(bones["Arm_R"], frame, rot=(0.55 * s, 0.0, -0.12))
        _kf(bones["Leg_L"], frame, rot=(0.7 * s, 0.0, 0.0))
        _kf(bones["Leg_R"], frame, rot=(-0.7 * s, 0.0, 0.0))
    walk.frame_range = (1, 24)
    _make_cyclic(walk)
    _push_nla(arm, walk, "walk")

    # Rest pose for export / still frames.
    _clear_pose(arm)
    bpy.context.scene.frame_set(1)


# ---------------------------------------------------------------------------
# Export + render
# ---------------------------------------------------------------------------

def count_tris() -> dict:
    counts = {}
    total = 0
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        mesh = obj.data
        tris = 0
        for p in mesh.polygons:
            tris += len(p.vertices) - 2
        counts[obj.name] = tris
        total += tris
    counts["total"] = total
    return counts


def export_glb() -> None:
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    kwargs = dict(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=False,
        export_animations=True,
        export_nla_strips=True,
        export_force_sampling=True,
        export_skins=True,
        export_morph=False,
        export_lights=False,
        export_cameras=False,
        export_apply=False,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_anim_single_armature=True,
    )
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError:
        kwargs.pop("export_anim_single_armature", None)
        bpy.ops.export_scene.gltf(**kwargs)


def setup_preview_world() -> None:
    scene = bpy.context.scene
    world = bpy.data.worlds.new("CarrotWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.62, 0.78, 0.92, 1.0)
    bg.inputs["Strength"].default_value = 0.55
    scene.world = world

    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4.5
    sun.data.color = (1.0, 0.93, 0.78)
    sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(48), math.radians(12), math.radians(35))
    bpy.context.collection.objects.link(sun)

    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "AREA"))
    fill.data.energy = 80.0
    fill.data.size = 2.4
    fill.data.color = (0.75, 0.86, 1.0)
    fill.location = (-1.6, 1.8, 1.4)
    fill.rotation_euler = (math.radians(70), 0, math.radians(-35))
    bpy.context.collection.objects.link(fill)

    rim = bpy.data.objects.new("Rim", bpy.data.lights.new("Rim", "AREA"))
    rim.data.energy = 40.0
    rim.data.size = 1.2
    rim.data.color = (1.0, 0.85, 0.55)
    rim.location = (1.2, -1.4, 1.1)
    rim.rotation_euler = (math.radians(65), 0, math.radians(140))
    bpy.context.collection.objects.link(rim)

    # Small garden patch so the stills match the reference mood.
    ground = bpy.data.meshes.new("Ground")
    gverts = [(-1.4, -1.4, 0), (1.4, -1.4, 0), (1.4, 1.4, 0), (-1.4, 1.4, 0)]
    ground.from_pydata(gverts, [], [(0, 1, 2, 3)])
    grobj = bpy.data.objects.new("Ground", ground)
    bpy.context.collection.objects.link(grobj)
    gmat = principled("ground", (0.38, 0.58, 0.28, 1.0), roughness=0.85)
    assign(grobj, gmat)

    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam

    scene.render.resolution_x = 720
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.cycles.denoiser = "OPENIMAGEDENOISE"
    scene.cycles.use_adaptive_sampling = True


def aim_camera(loc, target=(0.0, 0.05, 0.55)) -> None:
    cam = bpy.context.scene.camera
    cam.location = loc
    direction = Vector(target) - Vector(loc)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_still(path: Path) -> None:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(path)
    try:
        bpy.ops.render.render(write_still=True)
    except Exception as exc:  # noqa: BLE001
        print("Cycles render failed, falling back to Workbench:", exc)
        bpy.context.scene.render.engine = "BLENDER_WORKBENCH"
        sh = bpy.context.scene.display.shading
        sh.light = "STUDIO"
        sh.color_type = "MATERIAL"
        sh.show_shadows = True
        sh.show_cavity = True
        bpy.ops.render.render(write_still=True)


def render_previews(arm: bpy.types.Object) -> None:
    setup_preview_world()
    # Front
    aim_camera((0.0, 2.15, 0.72), (0.0, 0.0, 0.55))
    render_still(PREVIEW_DIR / "carrot_front.png")
    # Three-quarter, the money angle from the garden close-up.
    aim_camera((1.35, 1.75, 0.85), (0.0, 0.02, 0.52))
    render_still(PREVIEW_DIR / "carrot_threequarter.png")
    # Walk pose.
    walk = bpy.data.actions.get("walk")
    if walk is not None:
        arm.animation_data.action = walk
        bpy.context.scene.frame_set(7)
        bpy.context.view_layer.update()
        aim_camera((1.45, 1.55, 0.7), (0.0, 0.04, 0.48))
        render_still(PREVIEW_DIR / "carrot_walk.png")
        arm.animation_data.action = None
        bpy.context.scene.frame_set(1)
        _clear_pose(arm)


def save_blend() -> None:
    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))


def main() -> None:
    os.chdir(REPO)
    reset_scene()
    TEX_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    body_hi = TEX_DIR / "body_albedo_512.png"
    body_lo = TEX_DIR / "body_albedo_128.png"
    leaf_hi = TEX_DIR / "leaf_albedo_256.png"
    leaf_lo = TEX_DIR / "leaf_albedo_64.png"
    bake_body_albedo(body_hi, 512)
    bake_body_albedo(body_lo, 128)
    bake_leaf_albedo(leaf_hi, 256)
    bake_leaf_albedo(leaf_lo, 64)

    body_tex = image_from_png("carrot_body_albedo", body_hi)
    leaf_tex = image_from_png("carrot_leaf_albedo", leaf_hi)

    arm = make_armature()
    build_meshes(arm, body_tex, leaf_tex)
    animate(arm)

    counts = count_tris()
    if counts["total"] >= MAX_TRIS:
        raise SystemExit(f"tri count {counts['total']} exceeds {MAX_TRIS}")

    export_glb()
    render_previews(arm)
    save_blend()

    stats = {
        "species": SPECIES["id"],
        "tris": counts,
        "height_m": 1.18,
        "scale": "1 blender unit = 1 metre",
        "armature": ["Root", "Body", "Head", "Arm_L", "Arm_R", "Leg_L", "Leg_R", "LeafTop"],
        "actions": ["idle", "walk"],
        "glb": str(GLB_PATH.relative_to(REPO)),
        "textures": {
            "high": ["art/characters/textures/carrot/body_albedo_512.png", "art/characters/textures/carrot/leaf_albedo_256.png"],
            "low": ["art/characters/textures/carrot/body_albedo_128.png", "art/characters/textures/carrot/leaf_albedo_64.png"],
        },
    }
    STATS_PATH.write_text(json.dumps(stats, indent=2) + "\n")
    print("CARROT_BUILD_OK", json.dumps(counts))
    print("glb", GLB_PATH, "bytes", GLB_PATH.stat().st_size)


if __name__ == "__main__":
    # Blender -P executes the file as a script; argv after `--` is ours.
    main()
    # Keep Blender from treating leftover CLI flags as errors.
    sys.argv = [sys.argv[0]]
