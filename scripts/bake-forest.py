"""
bake-forest.py — ประกอบฉากป่าจาก GLB 8 ไฟล์แล้ว export เป็น USDZ ไฟล์เดียว

รัน: /Applications/Blender.app/Contents/MacOS/Blender --background --python scripts/bake-forest.py

ทำไมต้อง bake: RealityKit ไม่มี exponential fog และการกระจายของหลายร้อยชิ้นตอน
runtime แพงเกินสำหรับพื้นหลัง · กล้องไม่ขยับ (มีแค่ไจโรส่าย ±1.1) จึงตัดของนอก
กรวยกล้องทิ้งได้ และคำนวณระยะของแต่ละชิ้นล่วงหน้าได้ → แบ่ง material เป็น 8 แถบ
ตามระยะ ให้ Swift ไล่สีหมอกตามเวลาของวันทีหลัง

ระบบพิกัด: Blender เป็น Z-up · กล้องอยู่ (0,0,1.7) มองไปทาง +Y
X = ซ้ายขวา · Y = ระยะห่างจากกล้อง · Z = ความสูง
"""

import math
import os
import random
import sys

import bpy
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(REPO, "WBW", "Resources", "models")
OUT = os.path.join(REPO, "WBW", "Resources")

SEED = 20690829              # วันงาน 29 ส.ค. 2569 — seed คงที่ ผังเดิมทุกครั้งที่ bake
CAM_HEIGHT = 1.7
CAM_FOV_DEG = 55.0
ASPECT = 9.0 / 19.5          # จอมือถือแนวตั้ง
GYRO_MARGIN = 1.25           # เผื่อขอบ 25% ให้กล้องส่ายตามไจโรแล้วไม่เห็นขอบฉาก
FAR = 260.0                  # ไกลกว่านี้หมอกกลืนหมดแล้ว
BANDS = 8
CLEARING = (0.0, 6.0, 3.2)   # x, y, r — ที่ว่างสำหรับต้นไม้ที่โตตามเช็คอิน

# จำนวนตั้งต้น — จูนได้ ผลลัพธ์ต้องผ่านเกตขนาดไฟล์
COUNTS = {"tree_near": 60, "tree_far": 30, "grass": 450, "rock_small": 25, "rock_large": 10}

# ความสูงเป้าหมายของแต่ละแบบ (หน่วยฉาก = เมตร) — สัดส่วนตามเว็บ
HEIGHTS = {
    "tree": (3.2, 7.0), "grass": (0.25, 0.7),
    "rock_small": (0.3, 0.8), "rock_large": (0.9, 2.0), "mountain": (34.0, 80.0),
}


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(name):
    """import GLB แล้วคืน object เดียวที่ join แล้ว ยังไม่ normalize"""
    path = os.path.join(MODELS, name + ".glb")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in set(bpy.data.objects) - before if o.type == "MESH"]
    if not new:
        raise RuntimeError("ไม่พบ mesh ใน " + path)
    bpy.ops.object.select_all(action="DESELECT")
    for o in new:
        o.select_set(True)
    bpy.context.view_layer.objects.active = new[0]
    if len(new) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = "src_" + name
    return obj


def normalize(obj, height):
    """ย่อ/ขยายให้สูงตามที่ขอ · ฐานแตะ z=0 · จุดหมุนอยู่กลางแกน X/Y"""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    zs = [c.z for c in corners]
    xs = [c.x for c in corners]
    ys = [c.y for c in corners]
    src_h = max(zs) - min(zs)
    s = height / (src_h if src_h > 1e-6 else 1.0)

    obj.scale = (s, s, s)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.location = (
        -((min(xs) + max(xs)) / 2.0) * s,
        -((min(ys) + max(ys)) / 2.0) * s,
        -min(zs) * s,
    )
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    return obj


def ground_z(x, y):
    """พื้นลาดขึ้นเมื่อออกห่างจากทางเดิน + ขรุขระเล็กน้อย — สูตรเดียวกับที่พื้นใช้"""
    d = abs(x)
    rise = 0.02 * d * d / (1.0 + 0.05 * d)
    bump = 0.18 * math.sin(x * 0.7) * math.cos(y * 0.53)
    return rise + bump


def in_frustum(x, y, radius):
    """อยู่ในกรวยกล้อง (เผื่อขอบไจโรแล้ว) หรือไม่ · y คือระยะจากกล้อง"""
    if y <= 0.5 or y > FAR:
        return False
    half_w = math.tan(math.radians(CAM_FOV_DEG) * 0.5) * ASPECT * y * GYRO_MARGIN
    return abs(x) - radius <= half_w


def in_clearing(x, y, radius):
    cx, cy, cr = CLEARING
    return math.hypot(x - cx, y - cy) < cr + radius


def band_of(y):
    """แถบระยะ 0..7 — แบ่งแบบ log ให้ของใกล้ได้แถบละเอียดกว่าของไกล"""
    t = math.log(max(y, 1.0)) / math.log(FAR)
    return max(0, min(BANDS - 1, int(t * BANDS)))


def band_materials(obj, band, cache):
    """ก็อป material ของ object เป็นชุดของแถบนั้น ชื่อ <ชื่อเดิม>__band<N>

    สำคัญ: material_slots[i].link ค่า default คือ 'DATA' ซึ่งแปลว่า
    obj.material_slots[i].material = X เขียนทับ material ของ *mesh data*
    ไม่ใช่ของ object นี้อย่างเดียว — และทุก duplicate ที่ scatter() สร้างแชร์
    mesh data เดียวกัน (dup.data = src.data ใน place()) ถ้าไม่สลับ link เป็น
    'OBJECT' ก่อน assign ตัวที่วางทีหลังจะอ่าน base ที่ตัวก่อนหน้าเขียนทับไปแล้ว
    ชื่อจะพอกเป็น "Mat__band3__band5__band7..." ไม่รู้จบ กลายเป็น material ใหม่
    ทุกชิ้นแทนที่จะแชร์กันแค่ 8 แถบ (เจอจริงตอนรัน bake: MATERIAL BANDS ออกมา 585
    ทั้งที่ควรอยู่ 8-60 — คือบั๊กนี้)"""
    for i, slot in enumerate(obj.material_slots):
        base = slot.material
        if base is None:
            continue
        key = (base.name, band)
        if key not in cache:
            copy = base.copy()
            copy.name = "%s__band%d" % (base.name, band)
            cache[key] = copy
        slot.link = "OBJECT"
        obj.material_slots[i].material = cache[key]


def place(src, x, y, scale, rot, band, cache, collection):
    """วาง linked duplicate (แชร์ mesh data) ที่พิกัดที่ขอ"""
    dup = src.copy()          # copy() ไม่ copy mesh data → instance จริง
    dup.data = src.data
    dup.animation_data_clear()
    # src (template) ถูกตั้ง hide_render=True ไว้ตอน import (ไม่ให้ตัวต้นแบบเองโผล่)
    # แต่ .copy() ก็อป flag นี้มาด้วย — ถ้าไม่เปิดกลับ ของที่ scatter ทุกชิ้นจะ
    # หายไปตอน render/export (evaluation_mode="RENDER" เคารพ hide_render) เจอบั๊กนี้
    # จริงตอนรัน: MATERIAL BANDS นับได้ปกติ แต่ USD ที่ export ออกมาว่างเปล่า
    dup.hide_render = False
    dup.location = (x, y, ground_z(x, y))
    dup.rotation_euler = (0.0, 0.0, rot)
    dup.scale = (scale, scale, scale)
    collection.objects.link(dup)
    band_materials(dup, band, cache)
    return dup


def scatter(rand, src, count, y_range, x_spread, scale_range, footprint, band_cache, coll):
    """สุ่มวางแบบกันซ้อน · คืนจำนวนที่วางจริง (ที่ถูก cull ทิ้งไม่นับ)"""
    placed = []
    tries = 0
    while len(placed) < count and tries < count * 40:
        tries += 1
        y = rand.uniform(*y_range)
        half_w = math.tan(math.radians(CAM_FOV_DEG) * 0.5) * ASPECT * y * GYRO_MARGIN
        x = rand.uniform(-half_w - x_spread, half_w + x_spread)
        scale = rand.uniform(*scale_range)
        r = footprint * scale
        if not in_frustum(x, y, r) or in_clearing(x, y, r):
            continue
        if any(math.hypot(x - px, y - py) < (r + pr) * 0.62 for px, py, pr in placed):
            continue
        place(src, x, y, scale, rand.uniform(0, math.tau), band_of(y), band_cache, coll)
        placed.append((x, y, r))
    return len(placed)


def make_ground_texture():
    """ไล่สีเขียวของพื้นแบบ value-noise ที่คำนวณเป็นพิกเซลตรงๆ ใน Python (bilinear
    บนกริดสุ่ม grid_n x grid_n) แทนที่จะต่อ node Noise Texture -> Color Ramp

    เหตุผล: UsdPreviewSurface (ฟอร์แมตที่ generate_preview_surface แปลงให้ตอน
    export และเป็นสิ่งเดียวที่ Quick Look/RealityKit อ่าน) ไม่มีแนวคิดของ node
    graph แบบ procedural ของ Blender เลย มันรองรับแค่ค่าคงที่ หรือ image texture
    ตรวจสอบจริงแล้ว (usdcat ไฟล์ที่ export ออกมา): ตอนต่อ Noise->ColorRamp เข้า
    Base Color exporter จะ fallback ไปใช้ default_value ของ input เฉยๆ (เทาแบน
    0.8,0.8,0.8) ไม่ใช่สีที่ไล่จริง — ต้อง bake เป็นภาพก่อนสีถึงจะออกไปกับไฟล์จริง
    ใช้ SEED เดียวกับที่อื่นเพื่อให้ผัง reproducible"""
    size = 256
    grid_n = 14
    rnd = random.Random(SEED)
    grid = [[rnd.random() for _ in range(grid_n + 1)] for _ in range(grid_n + 1)]

    def smoothstep(t):
        return t * t * (3.0 - 2.0 * t)

    def sample(u, v):
        gx, gy = u * grid_n, v * grid_n
        x0, y0 = int(gx), int(gy)
        x0, y0 = min(x0, grid_n - 1), min(y0, grid_n - 1)
        tx, ty = smoothstep(gx - x0), smoothstep(gy - y0)
        a = grid[y0][x0] * (1 - tx) + grid[y0][x0 + 1] * tx
        b = grid[y0 + 1][x0] * (1 - tx) + grid[y0 + 1][x0 + 1] * tx
        return a * (1 - ty) + b * ty

    dark = (0.13, 0.24, 0.16)
    light = (0.34, 0.44, 0.26)
    pixels = [0.0] * (size * size * 4)
    for j in range(size):
        v = j / size
        for i in range(size):
            u = i / size
            t = sample(u, v)
            idx = (j * size + i) * 4
            pixels[idx + 0] = dark[0] + (light[0] - dark[0]) * t
            pixels[idx + 1] = dark[1] + (light[1] - dark[1]) * t
            pixels[idx + 2] = dark[2] + (light[2] - dark[2]) * t
            pixels[idx + 3] = 1.0

    img = bpy.data.images.new("GroundTex", width=size, height=size, alpha=False)
    img.pixels.foreach_set(pixels)
    img.pack()
    return img


def build_ground(coll):
    """พื้น — grid ที่ยกตามสูตร ground_z เดียวกับที่ของทุกชิ้นยืนอยู่"""
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=80, y_subdivisions=80, size=2.0)
    g = bpy.context.view_layer.objects.active
    g.name = "Ground"
    g.scale = (200.0, 200.0, 1.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    g.location = (0.0, FAR * 0.5, 0.0)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    for v in g.data.vertices:
        v.co.z = ground_z(v.co.x, v.co.y)

    mat = bpy.data.materials.new("GroundMat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = make_ground_texture()
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    g.data.materials.append(mat)
    if g.name not in coll.objects:
        coll.objects.link(g)
        bpy.context.scene.collection.objects.unlink(g)
    return g


def export(filepath, root_prim_path=None):
    """export USDZ · ชื่อพารามิเตอร์ของ wm.usd_export ต่างกันตามเวอร์ชัน Blender
    จึงส่งเฉพาะตัวที่มีอยู่จริงใน RNA แทนการเดา"""
    props = bpy.ops.wm.usd_export.get_rna_type().properties.keys()
    kwargs = {"filepath": filepath}
    for key, value in (
        ("export_materials", True),
        ("export_textures", True),
        ("use_instancing", True),
        ("generate_preview_surface", True),
        ("evaluation_mode", "RENDER"),
    ):
        if key in props:
            kwargs[key] = value
    # Blender 5.1 เปลี่ยน export_textures (bool) เป็น export_textures_mode (enum
    # KEEP/PRESERVE/NEW) — RNA ไม่มี export_textures แล้วเลยไม่ติด loop บนเลย
    # ตั้งเป็น NEW ให้ชัดเจน (ค่า default ของตัวมันเองก็คือ NEW อยู่แล้ว กันเวอร์ชัน
    # ถัดไปเปลี่ยน default โดยไม่รู้ตัว)
    if "export_textures" not in props and "export_textures_mode" in props:
        kwargs["export_textures_mode"] = "NEW"
    # brief ระบุว่า root ของ forest.usdz ต้องเป็น Xform ชื่อ Forest ตัวเดียว —
    # default ของ Blender คือ path "/root" (ตรวจแล้วด้วย usdcat ว่าได้ "root" จริง
    # ไม่ใช่ "Forest") ต้องสั่ง root_prim_path ตรงๆ ถึงจะได้ชื่อที่ spec ต้องการ
    if root_prim_path and "root_prim_path" in props:
        kwargs["root_prim_path"] = root_prim_path
    print("USD export kwargs:", sorted(kwargs.keys()))
    bpy.ops.wm.usd_export(**kwargs)


def bake_tree():
    """tree.usdz — ต้นเดียว สูง 1.0 พอดี ให้ Swift คูณ scale ตามขั้นได้ตรงๆ"""
    clear_scene()
    src = import_glb("tree")
    normalize(src, 1.0)
    src.name = "Tree"
    export(os.path.join(OUT, "tree.usdz"))


def build_forest():
    """ประกอบฉากป่าในหน่วยความจำทั้งหมด ยังไม่ export — แยกออกจาก bake_forest()
    เพื่อให้ render-check.py เรียกดูฉากจากมุมกล้องก่อน export ได้ โดยไม่ต้อง
    export ซ้ำซ้อน (เกต Quick Look ของ Task 1 ใช้ทั้งสองอย่างประกอบกัน)"""
    clear_scene()
    rand = random.Random(SEED)

    coll = bpy.data.collections.new("Forest")
    bpy.context.scene.collection.children.link(coll)
    cache = {}

    sources = {}
    for key, glb, height in (
        ("tree", "tree", sum(HEIGHTS["tree"]) / 2),
        ("grass", "grass", sum(HEIGHTS["grass"]) / 2),
        ("rock_small", "rock-small", sum(HEIGHTS["rock_small"]) / 2),
        ("rock_large", "rock-large", sum(HEIGHTS["rock_large"]) / 2),
        ("mountain_snow", "mountain-snow", 60.0),
        ("mountain_ridge", "mountain-ridge", 60.0),
        ("snowy_hills", "snowy-hills", 60.0),
        ("signpost", "signpost", 2.2),
    ):
        obj = import_glb(glb)
        normalize(obj, height)
        obj.hide_render = True
        sources[key] = obj

    build_ground(coll)

    stats = {}
    stats["tree_near"] = scatter(rand, sources["tree"], COUNTS["tree_near"],
                                 (3.0, 26.0), 4.0, (0.65, 1.45), 1.6, cache, coll)
    stats["tree_far"] = scatter(rand, sources["tree"], COUNTS["tree_far"],
                                (26.0, 90.0), 10.0, (0.9, 1.7), 1.9, cache, coll)
    stats["grass"] = scatter(rand, sources["grass"], COUNTS["grass"],
                             (1.5, 22.0), 2.0, (0.7, 1.9), 0.22, cache, coll)
    stats["rock_small"] = scatter(rand, sources["rock_small"], COUNTS["rock_small"],
                                  (2.0, 24.0), 3.0, (0.5, 1.3), 0.35, cache, coll)
    stats["rock_large"] = scatter(rand, sources["rock_large"], COUNTS["rock_large"],
                                  (4.0, 30.0), 4.0, (0.6, 1.4), 0.9, cache, coll)

    # ภูเขาปิดฉากหลัง — วางมือ ไม่สุ่ม เพราะมีไม่กี่ลูกและตำแหน่งสำคัญกว่าความหลากหลาย
    mountains = 0
    for key, x, y, h in (
        ("mountain_ridge", -95.0, 175.0, 62.0),
        ("mountain_snow", 40.0, 210.0, 88.0),
        ("snowy_hills", 110.0, 165.0, 48.0),
        ("mountain_ridge", 15.0, 245.0, 74.0),
        ("mountain_snow", -55.0, 235.0, 66.0),
        ("snowy_hills", -20.0, 140.0, 40.0),
    ):
        src = sources[key]
        dup = src.copy()
        dup.data = src.data
        dup.hide_render = False  # เหตุผลเดียวกับใน place() — src ต้นแบบถูกซ่อนตอน render ไว้
        s = h / 60.0
        dup.location = (x, y, ground_z(x, y) - h * 0.03)
        dup.scale = (s, s, s)
        dup.rotation_euler = (0.0, 0.0, rand.uniform(0, math.tau))
        coll.objects.link(dup)
        band_materials(dup, BANDS - 1, cache)
        mountains += 1
    stats["mountain"] = mountains

    sx, sy = 3.4, 11.0
    place(sources["signpost"], sx, sy, 1.0, -0.5, band_of(sy), cache, coll)
    stats["signpost"] = 1

    for obj in sources.values():
        bpy.data.objects.remove(obj, do_unlink=True)

    print("SCATTER STATS:", stats)
    print("MATERIAL BANDS:", len(cache))
    return stats, cache


def bake_forest():
    build_forest()
    export(os.path.join(OUT, "forest.usdz"), root_prim_path="/Forest")


if __name__ == "__main__":
    bake_tree()
    bake_forest()
    print("BAKE OK")
