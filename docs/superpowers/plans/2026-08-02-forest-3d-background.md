# Forest 3D Background + Check-in Progress Tree — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the app's five static background images with one persistent RealityKit forest scene, and grow a tree on Home one stage per base the participant has checked into.

**Architecture:** A Blender script bakes the eight GLB models from the companion website into a single `forest.usdz`, plus a separate `tree.usdz` that is scaled per stage. `ForestSceneHost` owns the only `RealityView` in the app, lives at `RootView`, and survives every phase and tab change; screens push `day` and `plantStep` into it through a `.forestBackground(day:plantStep:)` modifier and never import RealityKit. Light colour, direction, and per-distance-band fog tint are computed each frame from a Swift port of the website's six-key sun cycle. A new SUS endpoint reports which bases the participant has checked into, which drives both the tree's stage and the scene's time of day.

**Tech Stack:** SwiftUI + RealityKit + CoreMotion + XCTest, iOS 18.0 deployment target, XcodeGen; Go 1.x + chi + pgx (SUS); Blender 5.1.2 Python API for the offline bake.

**Spec:** `docs/superpowers/specs/2026-08-02-forest-3d-background-design.md`

## Global Constraints

- **Two repos, both ours.** iOS is `/Users/park/wbw-ios-fontend`. SUS is `/Users/park/Student-Union-Server` — Park co-owns it and edits it directly. Commit in each repo separately. There is **no** rule against modifying SUS.
- **A third repo is read-only here:** `/Users/park/su-wbw-website`. Read models and code from it; never write to it. This spec explicitly does not change it.
- Create the working branches before Task 1:
  - iOS: `git checkout -b feature/forest-3d` from the current `feature/chat-v2` HEAD (that is where the two specs live).
  - SUS: `git checkout -b feat/wbw-progress` from `feat/wbw-chat`.
- **`WBW/Config.swift` has an uncommitted modification** setting `Config.backend = .susLan` with a `⚠️ ชั่วคราว ห้าม commit` comment. Never stage that file. If a task needs a different backend, change it and leave it unstaged.
- iOS deployment target is **18.0**. `RealityView`, `PerspectiveCamera`, and `Entity(named:in:)` are all available; no `if #available` is needed for them. `glassEffect` usage already in the codebase stays behind its existing `if #available(iOS 26.0, *)`.
- Colours come only from `WBW/Config.swift` — `wbwCream`, `wbwInk`, `wbwGold`, `wbwGreen` — plus the cream `Color(red: 250/255, green: 247/255, blue: 240/255)` already used in `NotificationsView`. Do not invent named colours.
- Swift comments in this repo are **Thai**. Go comments in SUS are **Thai**. Match both.
- New `.swift` files under `WBW/` (including subfolders) are picked up by XcodeGen's `sources: - WBW`. **Run `xcodegen generate` after creating any new file**, before building.
- `WBW.xcodeproj/` is **gitignored**. Never `git add` it — the command fails on an ignored path. Stage only source, test, resource, and config files by explicit path.
- iOS build: `cd /Users/park/wbw-ios-fontend && xcodegen generate && xcodebuild -scheme WBW -configuration Debug -destination 'generic/platform=iOS Simulator' build`
- iOS test: `cd /Users/park/wbw-ios-fontend && xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17'`
- Xcode builds take minutes. Use a Bash timeout of up to `600000` ms.
- Pass `-configuration Debug` explicitly for anything you intend to drive from the simulator — a plain `xcodebuild build` does not default to Debug, and `#if DEBUG` launch hooks compile out silently.
- SUS local stack: `cd /Users/park/Student-Union-Server && docker compose up -d` → API on `127.0.0.1:8080`, Postgres on `127.0.0.1:5432`, database `sudb`, user `admin`. Inspect with `docker exec postgres-db psql -U admin -d sudb -c '<sql>'`.
- SUS has **no database-backed test harness** and this plan does not add one. Its only Go tests are pure unit tests (`internal/service/wbw_push_service_test.go`, `internal/model/booth_model_test.go`). SQL is therefore verified with `curl` against the running local stack, with the expected JSON written out in the step. Do not claim a query is tested when it was only compiled.
- **Do not change any existing endpoint's response shape.** The website and the shipped app both read this backend. `GET /wbw/me/progress` is new; everything else stays byte-identical.
- Blender: `/Applications/Blender.app/Contents/MacOS/Blender --background --python <script>`. Version installed is 5.1.2.
- The eight GLB models are **CC BY**. `public/models/CREDITS.md` must be copied alongside them and the credit must appear on screen (Task 8).

---

## Environment setup (do this once, before Task 1)

- [ ] **Step A: Create both branches**

```bash
cd /Users/park/wbw-ios-fontend && git checkout -b feature/forest-3d && git status --short
cd /Users/park/Student-Union-Server && git checkout feat/wbw-chat && git checkout -b feat/wbw-progress
```

Expected: iOS shows only ` M WBW/Config.swift` as modified. SUS shows a clean tree on the new branch.

- [ ] **Step B: Copy the models into the iOS repo**

```bash
cd /Users/park/wbw-ios-fontend
mkdir -p WBW/Resources/models
cp /Users/park/su-wbw-website/public/models/*.glb WBW/Resources/models/
cp /Users/park/su-wbw-website/public/models/CREDITS.md WBW/Resources/models/
ls -la WBW/Resources/models/
```

Expected: eight `.glb` files (`grass`, `mountain-ridge`, `mountain-snow`, `rock-large`, `rock-small`, `signpost`, `snowy-hills`, `tree`) totalling about 100 KB, plus `CREDITS.md`.

- [ ] **Step C: Confirm Blender runs headless**

```bash
/Applications/Blender.app/Contents/MacOS/Blender --version
```

Expected: `Blender 5.1.2`.

- [ ] **Step D: Start SUS and confirm it answers**

```bash
cd /Users/park/Student-Union-Server && docker compose up -d
until curl -sf http://localhost:8080/wbw/notifications/public >/dev/null; do sleep 1; done
echo up
```

Expected: `up`.

- [ ] **Step E: Get a participant token and give that participant some check-ins**

```bash
TOKEN=$(curl -s -X POST http://localhost:8080/wbw/auth/login \
  -H 'content-type: application/json' \
  -d '{"username":"6931900011","password":"chatv2test"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
echo "${TOKEN:0:20}…"

UID=$(docker exec postgres-db psql -U admin -d sudb -tAc \
  "SELECT user_id FROM app_user WHERE username='6931900011'")
echo "$UID"

docker exec postgres-db psql -U admin -d sudb -c \
  "INSERT INTO check_in (client_id, participant_id, checkpoint_id, device_time)
   VALUES (gen_random_uuid(), '$UID', 1, now()),
          (gen_random_uuid(), '$UID', 2, now()),
          (gen_random_uuid(), '$UID', 3, now())
   ON CONFLICT (participant_id, checkpoint_id) DO NOTHING"
```

Expected: a token prefix prints, a UUID prints, and the insert reports `INSERT 0 3` (or `INSERT 0 0` if rerun). Keep `$TOKEN` and `$UID` for Task 2.

If the login fails, register a fresh participant with the `curl` recipe in `docs/sus-test-backend.md` and use that account instead.

---

## Task 1: Bake the forest to USDZ

This task writes no Swift. It ends at a hard gate: the exported file must look right in Quick Look and be under 25 MB. Everything downstream assumes that gate passed.

**Files:**
- Create: `scripts/bake-forest.py`
- Create (generated, committed): `WBW/Resources/forest.usdz`, `WBW/Resources/tree.usdz`

**Interfaces:**
- Consumes: the eight GLBs at `WBW/Resources/models/*.glb` from Environment Step B.
- Produces:
  - `forest.usdz` — a scene whose root is a single `Xform` named `Forest`. Objects are grouped into materials named `<sourceMaterial>__band<N>`, where `N` is in `0…7`, band 0 is nearest the camera and band 7 is furthest. Task 5 looks materials up by that `__band<N>` suffix.

    **Not every band will be populated, and that is correct.** Band 2 spans y ∈ [4, 8); at that distance the frustum (fov 55°, a 9∶19.5 screen, ×1.25 gyro margin) is only ±1.2 to ±2.4 units wide, which lies entirely inside the radius-3.2 clearing reserved for the growing tree. There is nowhere left to place anything. Task 5 must therefore iterate the materials that exist and read `N` off each name — never loop `0…7` and assume each is present.
  - `tree.usdz` — one normalised tree, **exactly 1.0 units tall**, base at the origin, centred on X and Y. Task 6 scales it by the stage height directly.
  - A clearing of radius 3.2 centred at `(0, 6)` in Blender XY, so nothing occludes the growing tree.

**Coordinate system:** Blender is Z-up. The camera sits at `(0, 0, 1.7)` looking toward **+Y**. X is lateral, Y is distance from the camera, Z is height. The website's Y-up coordinates are deliberately not reproduced — this spec matches proportions, not numbers.

- [ ] **Step 1: Write the bake script**

Create `scripts/bake-forest.py`:

```python
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
    """ก็อป material ของ object เป็นชุดของแถบนั้น ชื่อ <ชื่อเดิม>__band<N>"""
    for i, slot in enumerate(obj.material_slots):
        base = slot.material
        if base is None:
            continue
        key = (base.name, band)
        if key not in cache:
            copy = base.copy()
            copy.name = "%s__band%d" % (base.name, band)
            cache[key] = copy
        obj.material_slots[i].material = cache[key]


def place(src, x, y, scale, rot, band, cache, collection):
    """วาง linked duplicate (แชร์ mesh data) ที่พิกัดที่ขอ"""
    dup = src.copy()          # copy() ไม่ copy mesh data → instance จริง
    dup.data = src.data
    dup.animation_data_clear()
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
    noise = mat.node_tree.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 90.0
    ramp = mat.node_tree.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.13, 0.24, 0.16, 1.0)
    ramp.color_ramp.elements[1].color = (0.34, 0.44, 0.26, 1.0)
    mat.node_tree.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    mat.node_tree.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    g.data.materials.append(mat)
    if g.name not in coll.objects:
        coll.objects.link(g)
        bpy.context.scene.collection.objects.unlink(g)
    return g


def export(filepath):
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
    print("USD export kwargs:", sorted(kwargs.keys()))
    bpy.ops.wm.usd_export(**kwargs)


def bake_tree():
    """tree.usdz — ต้นเดียว สูง 1.0 พอดี ให้ Swift คูณ scale ตามขั้นได้ตรงๆ"""
    clear_scene()
    src = import_glb("tree")
    normalize(src, 1.0)
    src.name = "Tree"
    export(os.path.join(OUT, "tree.usdz"))


def bake_forest():
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
    export(os.path.join(OUT, "forest.usdz"))


if __name__ == "__main__":
    bake_tree()
    bake_forest()
    print("BAKE OK")
```

- [ ] **Step 2: Run the bake and read the counts**

```bash
cd /Users/park/wbw-ios-fontend
/Applications/Blender.app/Contents/MacOS/Blender --background --python scripts/bake-forest.py 2>&1 | tail -20
ls -la WBW/Resources/*.usdz
```

Expected: a line `SCATTER STATS: {...}` with non-zero counts for every key, a `MATERIAL BANDS:` count between 8 and 60, `USD export kwargs:` listing at least `export_materials` and `filepath`, and `BAKE OK`. Both `.usdz` files exist.

`MATERIAL BANDS` counts `(source material, band)` pairs, not distinct bands — a healthy scene has far more than 8. Do **not** read a distinct-band count off this line, and do not treat a missing band as a failure (see the Interfaces note above).

If any scatter count is `0`, the frustum or clearing test rejected everything — print `half_w` for a few `y` values and widen `x_spread` before continuing.

- [ ] **Step 3: Gate — file size**

```bash
cd /Users/park/wbw-ios-fontend
du -m WBW/Resources/forest.usdz WBW/Resources/tree.usdz
```

Expected: `forest.usdz` **under 25 MB**, `tree.usdz` well under 1 MB.

If `forest.usdz` is over 25 MB, `use_instancing` was probably not applied (check the `USD export kwargs:` line from Step 2). If it was applied and the file is still too big, halve `COUNTS["grass"]` and re-run Steps 2–3. Do not proceed past this step with an oversized file.

- [ ] **Step 4: Gate — Quick Look**

```bash
qlmanage -p WBW/Resources/forest.usdz >/dev/null 2>&1 &
sleep 3
```

Look at the window. It must show: ground with visible colour variation, trees standing **on** the ground rather than floating or sunk, mountains on the horizon, and an empty patch roughly 6 units ahead of centre.

If materials render flat grey, the exporter dropped them — re-run with `generate_preview_surface` confirmed present in the kwargs line, and check `export_textures`.

**Do not start Task 2 until this looks right.** Everything downstream is built on this file.

- [ ] **Step 5: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add scripts/bake-forest.py WBW/Resources/models WBW/Resources/forest.usdz WBW/Resources/tree.usdz
git commit -m "feat(scene): สคริปต์ bake ป่าเป็น USDZ + โมเดล CC BY 8 ไฟล์"
```

---

## Task 2: SUS endpoint `GET /wbw/me/progress`

**Files:**
- Modify: `/Users/park/Student-Union-Server/internal/model/wbw_model.go` (append types)
- Modify: `/Users/park/Student-Union-Server/internal/repository/wbw_checkpoint_repository.go` (append method)
- Create: `/Users/park/Student-Union-Server/internal/service/wbw_progress_service.go`
- Create: `/Users/park/Student-Union-Server/internal/handler/wbw_progress_handler.go`
- Modify: `/Users/park/Student-Union-Server/cmd/main.go` (construct + one route)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `GET /wbw/me/progress` returning
  `{"total": int, "checked_in": [{"checkpoint_id": int, "name": string, "sequence": int|null, "at": string}]}`,
  ordered by `sequence`. Task 3 decodes exactly these keys.

Spec 2 will later add `activity_name`, `answered`, `rating`, and `comment` to each entry. Leave room for that — do not build a second endpoint for it.

- [ ] **Step 1: Add the model types**

Append to `internal/model/wbw_model.go`:

```go
// CheckinProgressItem — ฐานหนึ่งที่ผู้เข้าร่วมเช็คอินไปแล้ว
type CheckinProgressItem struct {
	CheckpointID int    `json:"checkpoint_id"`
	Name         string `json:"name"`
	Sequence     *int   `json:"sequence"`
	At           string `json:"at"`
}

// CheckinProgress — ความคืบหน้าของผู้เข้าร่วมคนหนึ่ง
//
// Total นับจาก DB ทุกครั้ง ไม่ใช่ค่าคงที่ 8 — แอดมินเพิ่ม/ลบฐานได้ผ่าน
// /wbw/admin/checkpoints ถ้าฝังเลขไว้ ต้นไม้ในแอปจะเพี้ยนทันทีที่แก้ฐานวันงาน
type CheckinProgress struct {
	Total     int                   `json:"total"`
	CheckedIn []CheckinProgressItem `json:"checked_in"`
}
```

- [ ] **Step 2: Add the query**

Append to `internal/repository/wbw_checkpoint_repository.go`:

```go
// Progress — ฐานที่ผู้เข้าร่วมคนนี้เช็คอินแล้ว + จำนวนฐานทั้งหมดที่ต้องเช็คอิน
//
// นับ total แยกจากรายการ เพราะต้องได้เลขที่ถูกแม้ยังไม่เคยเช็คอินสักฐาน
// (COUNT บน join จะได้ 0 ทั้งคู่)
func (r *WBWCheckpointRepository) Progress(ctx context.Context, participantID string) (*model.CheckinProgress, error) {
	out := &model.CheckinProgress{CheckedIn: []model.CheckinProgressItem{}}

	if err := r.db.QueryRow(ctx,
		`SELECT count(*)::int FROM checkpoint WHERE requires_checkin`,
	).Scan(&out.Total); err != nil {
		return nil, err
	}

	rows, err := r.db.Query(ctx, `
		SELECT c.checkpoint_id, c.name, c.sequence, ci.server_received_at
		  FROM check_in ci
		  JOIN checkpoint c ON c.checkpoint_id = ci.checkpoint_id
		 WHERE ci.participant_id = $1::uuid AND c.requires_checkin
		 ORDER BY c.sequence NULLS LAST, c.checkpoint_id`, participantID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var it model.CheckinProgressItem
		var at time.Time
		if err := rows.Scan(&it.CheckpointID, &it.Name, &it.Sequence, &at); err != nil {
			return nil, err
		}
		it.At = at.UTC().Format(time.RFC3339)
		out.CheckedIn = append(out.CheckedIn, it)
	}
	return out, rows.Err()
}
```

Add `"time"` to that file's imports if it is not already there.

- [ ] **Step 3: Add the service**

Create `internal/service/wbw_progress_service.go`:

```go
package service

import (
	"context"

	"su-server/internal/model"
	"su-server/internal/repository"
)

// WBWProgressService — ความคืบหน้าเช็คอินของผู้เข้าร่วมที่เรียกเอง
type WBWProgressService struct {
	repo *repository.WBWCheckpointRepository
}

func NewWBWProgressService(repo *repository.WBWCheckpointRepository) *WBWProgressService {
	return &WBWProgressService{repo: repo}
}

func (s *WBWProgressService) MyProgress(ctx context.Context, participantID string) (*model.CheckinProgress, error) {
	return s.repo.Progress(ctx, participantID)
}
```

- [ ] **Step 4: Add the handler**

Create `internal/handler/wbw_progress_handler.go`:

```go
package handler

import (
	"log/slog"
	"net/http"

	"su-server/internal/middleware"
	"su-server/internal/service"
)

type WBWProgressHandler struct {
	service *service.WBWProgressService
}

func NewWBWProgressHandler(s *service.WBWProgressService) *WBWProgressHandler {
	return &WBWProgressHandler{service: s}
}

// MyProgress GET /wbw/me/progress — ฐานที่ตัวเองเช็คอินแล้ว + จำนวนฐานทั้งหมด
func (h *WBWProgressHandler) MyProgress(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFrom(r.Context())
	if claims == nil {
		middleware.WriteError(w, http.StatusUnauthorized, "ต้องล็อกอินก่อน")
		return
	}
	p, err := h.service.MyProgress(r.Context(), claims.Subject)
	if err != nil {
		slog.Error("load checkin progress failed", "err", err)
		middleware.WriteError(w, http.StatusInternalServerError, "โหลดความคืบหน้าไม่สำเร็จ")
		return
	}
	middleware.WriteJSON(w, http.StatusOK, p)
}
```

- [ ] **Step 5: Wire it up**

In `cmd/main.go`, next to where `wbwStaffHandler` is constructed (around line 143), add:

```go
	wbwProgressService := service.NewWBWProgressService(wbwCheckpointRepo)
	wbwProgressHandler := handler.NewWBWProgressHandler(wbwProgressService)
```

Use whatever variable already holds the `*repository.WBWCheckpointRepository`; if none exists in `main.go`, construct one with `repository.NewWBWCheckpointRepository(pool)` using the same pool variable the other WBW repositories are given.

Then beside the existing `r.With(requireAuth).Get("/me", wbwAdminHandler.Me)` line, add:

```go
		// ความคืบหน้าเช็คอินของตัวเอง — แอปใช้คุมขั้นต้นไม้ที่หน้า Home
		r.With(requireAuth).Get("/me/progress", wbwProgressHandler.MyProgress)
```

- [ ] **Step 6: Build and restart**

```bash
cd /Users/park/Student-Union-Server
go build ./... && docker compose up -d --build
until curl -sf http://localhost:8080/wbw/notifications/public >/dev/null; do sleep 1; done
echo up
```

Expected: `go build` prints nothing, and `up` prints.

- [ ] **Step 7: Verify against the running stack**

There is no DB test harness in SUS, so this is the verification — not a formality.

```bash
TOKEN=$(curl -s -X POST http://localhost:8080/wbw/auth/login \
  -H 'content-type: application/json' \
  -d '{"username":"6931900011","password":"chatv2test"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')

echo "--- with 3 check-ins ---"
curl -s http://localhost:8080/wbw/me/progress -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

echo "--- no auth ---"
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/wbw/me/progress
```

Expected: the first prints `"total": 8` and a `checked_in` array of **3** entries with `checkpoint_id` 1, 2, 3 in `sequence` order, each with a `name` and an RFC3339 `at`. The second prints `401`.

- [ ] **Step 8: Verify the zero case and the deleted-checkpoint case**

```bash
UID=$(docker exec postgres-db psql -U admin -d sudb -tAc "SELECT user_id FROM app_user WHERE username='6931900011'")

docker exec postgres-db psql -U admin -d sudb -c "DELETE FROM check_in WHERE participant_id='$UID'"
echo "--- zero check-ins ---"
curl -s http://localhost:8080/wbw/me/progress -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

docker exec postgres-db psql -U admin -d sudb -c \
  "INSERT INTO check_in (client_id, participant_id, checkpoint_id, device_time)
   VALUES (gen_random_uuid(), '$UID', 1, now()), (gen_random_uuid(), '$UID', 2, now()),
          (gen_random_uuid(), '$UID', 3, now()), (gen_random_uuid(), '$UID', 9, now())"
echo "--- service point 9 must NOT appear ---"
curl -s http://localhost:8080/wbw/me/progress -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

Expected: the zero case prints `"total": 8` with `"checked_in": []` (an empty array, **not** `null` — the iOS decoder relies on that). The second prints exactly 3 entries; checkpoint 9 is a restroom with `requires_checkin = false` and must be filtered out.

- [ ] **Step 9: Commit (SUS repo)**

```bash
cd /Users/park/Student-Union-Server
git add internal/model/wbw_model.go internal/repository/wbw_checkpoint_repository.go \
        internal/service/wbw_progress_service.go internal/handler/wbw_progress_handler.go cmd/main.go
git commit -m "feat(wbw): GET /wbw/me/progress — ฐานที่ผู้เข้าร่วมเช็คอินแล้ว + total จาก DB"
```

---

## Task 3: iOS progress model, API call, and cached store

**Files:**
- Modify: `WBW/Models.swift` (append)
- Modify: `WBW/APIClient.swift` (append one method)
- Create: `WBW/CheckinProgressStore.swift`
- Create: `WBWTests/CheckinProgressStoreTests.swift`

**Interfaces:**
- Consumes: `GET /wbw/me/progress` from Task 2.
- Produces:
  - `struct CheckinProgress: Codable, Equatable { let total: Int; let checkedIn: [CheckinProgressItem] }` with `var stage: Int { checkedIn.count }`
  - `struct CheckinProgressItem: Codable, Equatable { let checkpointId: Int; let name: String; let sequence: Int?; let at: String }`
  - `APIClient.progress(token:) async throws -> CheckinProgress`
  - `@MainActor final class CheckinProgressStore: ObservableObject` with `@Published private(set) var progress: CheckinProgress?`, `func load(token: String) async`, `func clear()`, and `static func cacheKey(for backend: Backend) -> String`
- Tasks 5, 6, 9, and 10 read `store.progress?.stage` and `store.progress?.total`.

- [ ] **Step 1: Write the failing tests**

Create `WBWTests/CheckinProgressStoreTests.swift`:

```swift
import XCTest
@testable import WBW

/// cache ของ progress ต้องแยกตาม backend — checkpoint_id คนละชุดต่อ backend
/// ถ้าใช้ key เดียวกัน สลับ backend แล้วต้นไม้ผิดขนาดแบบเงียบๆ ไม่มี error ไม่มี log
/// (กับดักเดียวกับ cursor แชท ดู docs/sus-test-backend.md)
final class CheckinProgressStoreTests: XCTestCase {

    func testCacheKeyDiffersPerBackend() {
        let keys = Set([
            CheckinProgressStore.cacheKey(for: .prodNode),
            CheckinProgressStore.cacheKey(for: .nodeLocal),
            CheckinProgressStore.cacheKey(for: .susLocal),
            CheckinProgressStore.cacheKey(for: .susProd),
            CheckinProgressStore.cacheKey(for: .susLan),
        ])
        XCTAssertEqual(keys.count, 5, "ทุก backend ต้องได้ key ไม่ซ้ำกัน")
    }

    func testDecodesServerPayload() throws {
        let json = """
        {"total": 8, "checked_in": [
          {"checkpoint_id": 1, "name": "วิหารพระเจ้าล้านทอง", "sequence": 1, "at": "2026-08-29T09:12:03Z"},
          {"checkpoint_id": 2, "name": "สวนกุหลาบ", "sequence": 2, "at": "2026-08-29T09:40:00Z"}
        ]}
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let p = try dec.decode(CheckinProgress.self, from: json)

        XCTAssertEqual(p.total, 8)
        XCTAssertEqual(p.stage, 2)
        XCTAssertEqual(p.checkedIn.first?.name, "วิหารพระเจ้าล้านทอง")
    }

    func testDecodesEmptyCheckedIn() throws {
        let json = #"{"total": 8, "checked_in": []}"#.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let p = try dec.decode(CheckinProgress.self, from: json)
        XCTAssertEqual(p.stage, 0)
        XCTAssertEqual(p.total, 8)
    }

    func testDecodesNullSequence() throws {
        let json = """
        {"total": 8, "checked_in": [
          {"checkpoint_id": 5, "name": "จุดปลูก", "sequence": null, "at": "2026-08-29T10:00:00Z"}
        ]}
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let p = try dec.decode(CheckinProgress.self, from: json)
        XCTAssertNil(p.checkedIn[0].sequence)
    }

    @MainActor
    func testCacheRoundTrip() throws {
        let key = CheckinProgressStore.cacheKey(for: .susLocal)
        UserDefaults.standard.removeObject(forKey: key)

        let store = CheckinProgressStore()
        let value = CheckinProgress(total: 8, checkedIn: [
            CheckinProgressItem(checkpointId: 1, name: "ฐาน 1", sequence: 1, at: "2026-08-29T09:00:00Z"),
        ])
        store.cache(value, backend: .susLocal)

        let fresh = CheckinProgressStore()
        fresh.restoreFromCache(backend: .susLocal)
        XCTAssertEqual(fresh.progress, value)

        UserDefaults.standard.removeObject(forKey: key)
    }

    @MainActor
    func testRestoreFromOtherBackendCacheIsIgnored() throws {
        let susKey = CheckinProgressStore.cacheKey(for: .susLocal)
        let nodeKey = CheckinProgressStore.cacheKey(for: .prodNode)
        UserDefaults.standard.removeObject(forKey: susKey)
        UserDefaults.standard.removeObject(forKey: nodeKey)

        let store = CheckinProgressStore()
        store.cache(CheckinProgress(total: 8, checkedIn: [
            CheckinProgressItem(checkpointId: 1, name: "ฐาน 1", sequence: 1, at: "2026-08-29T09:00:00Z"),
        ]), backend: .susLocal)

        let fresh = CheckinProgressStore()
        fresh.restoreFromCache(backend: .prodNode)
        XCTAssertNil(fresh.progress, "cache ของ backend อื่นต้องไม่ถูกหยิบมาใช้")

        UserDefaults.standard.removeObject(forKey: susKey)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WBWTests/CheckinProgressStoreTests 2>&1 | tail -30
```

Expected: compile failure — `cannot find 'CheckinProgressStore' in scope` and `cannot find type 'CheckinProgress' in scope`.

- [ ] **Step 3: Add the model types**

Append to `WBW/Models.swift`:

```swift
/// ฐานหนึ่งที่เช็คอินไปแล้ว (จาก GET /wbw/me/progress)
struct CheckinProgressItem: Codable, Equatable {
    let checkpointId: Int
    let name: String
    let sequence: Int?
    let at: String
}

/// ความคืบหน้าเช็คอินของตัวเอง
///
/// total มาจาก backend ทุกครั้ง ไม่ใช่ 8 ตายตัว — แอดมินเพิ่ม/ลบฐานได้
struct CheckinProgress: Codable, Equatable {
    let total: Int
    let checkedIn: [CheckinProgressItem]

    /// ขั้นของต้นไม้ = จำนวนฐานที่เช็คอินแล้ว
    var stage: Int { checkedIn.count }
}
```

- [ ] **Step 4: Add the API call**

Append inside `struct APIClient` in `WBW/APIClient.swift`, after `me(token:)`:

```swift
    /// ความคืบหน้าเช็คอินของตัวเอง — คุมขั้นต้นไม้กับเวลาของวันที่หน้า Home
    func progress(token: String) async throws -> CheckinProgress {
        try await getDecoded("/me/progress", token: token, CheckinProgress.self,
                             error: "โหลดความคืบหน้าไม่สำเร็จ")
    }
```

`getDecoded` is `private` and already sets `convertFromSnakeCase`, so nothing else is needed.

- [ ] **Step 5: Write the store**

Create `WBW/CheckinProgressStore.swift`:

```swift
import Foundation

/// ความคืบหน้าเช็คอินที่ใช้ร่วมกันทั้งแอป — ต้นไม้ที่ Home อ่านตัวนี้
///
/// cache ลง UserDefaults เพื่อให้เปิดแอปมาต้นไม้ขนาดถูกทันทีโดยไม่ต้องรอเน็ต
/// **key ผูกกับ backend** เพราะแต่ละ backend เดิน checkpoint_id คนละชุด ถ้าใช้ key
/// เดียวกัน สลับ backend แล้วจะได้ต้นไม้ผิดขนาดโดยไม่มี error และไม่มี log อะไรเลย
@MainActor
final class CheckinProgressStore: ObservableObject {
    @Published private(set) var progress: CheckinProgress?

    static func cacheKey(for backend: Backend) -> String {
        "wbw.progress.\(backend.cacheNamespace)"
    }

    /// โหลดจาก cache ก่อน (ทันที) แล้วค่อยยิงเน็ตทับ
    func load(token: String, backend: Backend = Config.backend) async {
        if progress == nil { restoreFromCache(backend: backend) }
        guard !token.isEmpty else { return }
        guard let fresh = try? await APIClient.shared.progress(token: token) else { return }
        progress = fresh
        cache(fresh, backend: backend)
    }

    func restoreFromCache(backend: Backend = Config.backend) {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey(for: backend)),
              let value = try? JSONDecoder().decode(CheckinProgress.self, from: data)
        else { return }
        progress = value
    }

    func cache(_ value: CheckinProgress, backend: Backend = Config.backend) {
        progress = value
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey(for: backend))
    }

    /// ล้างตอน logout — บัญชีถัดไปบนเครื่องเดียวกันต้องไม่สืบทอดต้นไม้ของคนก่อน
    func clear(backend: Backend = Config.backend) {
        progress = nil
        UserDefaults.standard.removeObject(forKey: Self.cacheKey(for: backend))
    }
}
```

- [ ] **Step 6: Add the backend namespace — in a new file, not `Config.swift`**

`WBW/Config.swift` carries an uncommitted `Config.backend = .susLan` marked `ห้าม commit`. Touching that file would force a partial stage, and `git add -p` is interactive, which this environment does not support. So the property goes in its own file and `Config.swift` is never opened.

Create `WBW/BackendCacheKey.swift`:

```swift
import Foundation

/// ชื่อสั้นๆ ของแต่ละ backend ไว้ทำ key ของ cache
///
/// อยู่แยกไฟล์จาก Config.swift ตั้งใจ — Config.swift มีบรรทัด Config.backend ที่
/// เปลี่ยนไปมาระหว่างทดสอบและห้าม commit การแยกไว้ทำให้แก้ไฟล์นี้แล้ว stage ได้เลย
///
/// cache ทุกตัวในแอปต้องแยกตาม backend: id ของ checkpoint/message เดินคนละชุดต่อ
/// backend ถ้าใช้ key เดียวกัน สลับ backend แล้วได้ข้อมูลผิดโดยไม่มี error ไม่มี log
/// (ดู docs/sus-test-backend.md)
extension Backend {
    var cacheNamespace: String {
        switch self {
        case .prodNode:  return "prodNode"
        case .nodeLocal: return "nodeLocal"
        case .susLocal:  return "susLocal"
        case .susProd:   return "susProd"
        case .susLan:    return "susLan"
        }
    }
}
```

**Do not stage `WBW/Config.swift` in this task or any later task.**

- [ ] **Step 7: Run the tests to verify they pass**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WBWTests/CheckinProgressStoreTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **` with 6 tests passing.

- [ ] **Step 8: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/Models.swift WBW/APIClient.swift WBW/CheckinProgressStore.swift \
        WBW/BackendCacheKey.swift WBWTests/CheckinProgressStoreTests.swift
git status --short    # WBW/Config.swift ต้องยังขึ้น " M" คือยังไม่ถูก stage
git commit -m "feat(progress): ดึงความคืบหน้าเช็คอิน + cache แยกตาม backend"
```

Expected: `git status --short` shows ` M WBW/Config.swift` (unstaged) alongside the staged additions.

---

## Task 4: Pure scene maths — sun cycle, tree height, day mapping

No RealityKit here. Everything in this task is a pure function, so it is fully unit-tested before any 3D code exists.

**Files:**
- Create: `WBW/Scene3D/SunCycle.swift`
- Create: `WBW/Scene3D/ForestMath.swift`
- Create: `WBWTests/ForestMathTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct SunState { var elevation, azimuth, sunIntensity, ambientIntensity, fogDensity, stars: Float; var sun, skyColor, groundColor, fog: SIMD3<Float> }`
  - `enum SunCycle { static func state(at p: Float) -> SunState; static func direction(_ s: SunState) -> SIMD3<Float> }`
  - `enum ForestMath { static func treeHeight(stage: Int, total: Int) -> Float; static func day(stage: Int, total: Int) -> Float; static let dayWelcome/dayStill: Float }`
- Task 5 calls `SunCycle.state(at:)` and `SunCycle.direction(_:)`. Task 6 calls `ForestMath.treeHeight`. Task 9 calls `ForestMath.day`.

- [ ] **Step 1: Write the failing tests**

Create `WBWTests/ForestMathTests.swift`:

```swift
import XCTest
import simd
@testable import WBW

/// ค่าอ้างอิงทั้งหมดอ่านจาก components/landing/trail.ts และ lib/dayCycle.ts ของเว็บ
/// (~/su-wbw-website) — ฉากในแอปต้องให้แสงชุดเดียวกับเว็บที่เวลาเดียวกัน
final class ForestMathTests: XCTestCase {

    // MARK: - ความสูงต้นไม้

    func testTreeHeightEndsMatchTheWebsiteTable() {
        // เว็บใช้ตาราง [0.7, 1.3, 2.2, 3.4, 5.0] · เราใช้สูตรที่ปลายทั้งสองตรงกัน
        XCTAssertEqual(ForestMath.treeHeight(stage: 0, total: 8), 0.7, accuracy: 0.001)
        XCTAssertEqual(ForestMath.treeHeight(stage: 8, total: 8), 5.0, accuracy: 0.001)
    }

    func testTreeHeightIsMonotonic() {
        var last = Float(0)
        for stage in 0...8 {
            let h = ForestMath.treeHeight(stage: stage, total: 8)
            XCTAssertGreaterThan(h, last, "ขั้น \(stage) ต้องสูงกว่าขั้นก่อน")
            last = h
        }
    }

    func testTreeHeightConstantRatio() {
        // อัตราส่วนคงที่ทุกขั้น = ต้นไม้โต "เท่าๆ กัน" ทุกฐาน ไม่กระโดดตอนท้าย
        let r1 = ForestMath.treeHeight(stage: 1, total: 8) / ForestMath.treeHeight(stage: 0, total: 8)
        let r7 = ForestMath.treeHeight(stage: 8, total: 8) / ForestMath.treeHeight(stage: 7, total: 8)
        XCTAssertEqual(r1, r7, accuracy: 0.001)
    }

    func testTreeHeightAdaptsToDifferentTotals() {
        // แอดมินลบฐานเหลือ 5 — ขั้นสุดท้ายยังต้องเป็นต้นโตเต็มที่
        XCTAssertEqual(ForestMath.treeHeight(stage: 5, total: 5), 5.0, accuracy: 0.001)
        XCTAssertEqual(ForestMath.treeHeight(stage: 12, total: 12), 5.0, accuracy: 0.001)
    }

    func testTreeHeightClampsOutOfRange() {
        XCTAssertEqual(ForestMath.treeHeight(stage: -3, total: 8), 0.7, accuracy: 0.001)
        XCTAssertEqual(ForestMath.treeHeight(stage: 99, total: 8), 5.0, accuracy: 0.001)
    }

    func testTreeHeightSurvivesZeroTotal() {
        // total = 0 เกิดได้ถ้าแอดมินลบฐานหมด — ห้ามหาร 0 แล้ว NaN ไปทั้งฉาก
        let h = ForestMath.treeHeight(stage: 0, total: 0)
        XCTAssertFalse(h.isNaN)
        XCTAssertEqual(h, 0.7, accuracy: 0.001)
    }

    // MARK: - เวลาของวัน

    func testDayRangeMatchesWebsiteBounds() {
        XCTAssertEqual(ForestMath.day(stage: 0, total: 8), 0.14, accuracy: 0.001)
        XCTAssertEqual(ForestMath.day(stage: 8, total: 8), 0.78, accuracy: 0.001)
        XCTAssertEqual(ForestMath.day(stage: 4, total: 8), 0.46, accuracy: 0.001)
    }

    func testDaySurvivesZeroTotal() {
        XCTAssertEqual(ForestMath.day(stage: 0, total: 0), 0.14, accuracy: 0.001)
    }

    // MARK: - สถานะดวงอาทิตย์

    func testSunStateAtKeyframesMatchesTheWebsite() {
        // p = 0.0 ก่อนฟ้าสาง
        let dawn = SunCycle.state(at: 0.0)
        XCTAssertEqual(dawn.elevation, -8, accuracy: 0.01)
        XCTAssertEqual(dawn.sunIntensity, 0.18, accuracy: 0.001)
        XCTAssertEqual(dawn.stars, 1.0, accuracy: 0.001)

        // p = 0.56 เที่ยง
        let noon = SunCycle.state(at: 0.56)
        XCTAssertEqual(noon.elevation, 58, accuracy: 0.01)
        XCTAssertEqual(noon.sunIntensity, 2.85, accuracy: 0.001)
        XCTAssertEqual(noon.stars, 0.0, accuracy: 0.001)
        XCTAssertEqual(noon.fog.x, 0.85, accuracy: 0.001)

        // p = 1.0 ตะวันลับดอย
        let dusk = SunCycle.state(at: 1.0)
        XCTAssertEqual(dusk.elevation, 2, accuracy: 0.01)
        XCTAssertEqual(dusk.sun.y, 0.46, accuracy: 0.001)
    }

    func testSunStateClampsOutsideZeroOne() {
        XCTAssertEqual(SunCycle.state(at: -5).elevation, SunCycle.state(at: 0).elevation, accuracy: 0.001)
        XCTAssertEqual(SunCycle.state(at: 7).elevation, SunCycle.state(at: 1).elevation, accuracy: 0.001)
    }

    func testSunStateInterpolatesBetweenKeys() {
        // กึ่งกลางระหว่าง p=0.36 (elev 24) และ p=0.56 (elev 58) ด้วย smoothstep(0.5) = 0.5
        let mid = SunCycle.state(at: 0.46)
        XCTAssertEqual(mid.elevation, 41, accuracy: 0.01)
    }

    func testSunDirectionIsUnitLengthAndRisesWithElevation() {
        let low = SunCycle.direction(SunCycle.state(at: 0.18))
        let high = SunCycle.direction(SunCycle.state(at: 0.56))
        XCTAssertEqual(simd_length(low), 1.0, accuracy: 0.001)
        XCTAssertEqual(simd_length(high), 1.0, accuracy: 0.001)
        XCTAssertGreaterThan(high.y, low.y, "ตอนเที่ยงดวงอาทิตย์ต้องสูงกว่าตอนเช้า")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WBWTests/ForestMathTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'ForestMath' in scope` and `cannot find 'SunCycle' in scope`.

- [ ] **Step 3: Write `SunCycle.swift`**

Create `WBW/Scene3D/SunCycle.swift`:

```swift
import simd

/// สถานะแสง/ฟ้าที่เวลาหนึ่งของวัน — พอร์ตจาก SunState ใน
/// ~/su-wbw-website/components/landing/trail.ts
struct SunState {
    var elevation: Float        // องศาเหนือขอบฟ้า (ติดลบ = ยังไม่ขึ้น)
    var azimuth: Float          // องศา
    var sun: SIMD3<Float>       // สีแสงตรง 0..1
    var sunIntensity: Float
    var skyColor: SIMD3<Float>  // hemiSky ของเว็บ
    var groundColor: SIMD3<Float>
    var ambientIntensity: Float // hemiIntensity ของเว็บ
    var fog: SIMD3<Float>
    var fogDensity: Float
    var stars: Float            // 0..1 ความชัดของดาว
}

/// วงจรแสงหนึ่งวัน — 6 keyframe เดียวกับ SUN_KEYS ของเว็บ ห้ามแก้ค่าโดยไม่แก้ที่เว็บด้วย
enum SunCycle {
    private struct Key { let p: Float; let s: SunState }

    private static let keys: [Key] = [
        Key(p: 0.00, s: SunState(elevation: -8, azimuth: 104,
            sun: [0.35, 0.45, 0.72], sunIntensity: 0.18,
            skyColor: [0.13, 0.18, 0.30], groundColor: [0.05, 0.09, 0.07],
            ambientIntensity: 0.40, fog: [0.07, 0.11, 0.15], fogDensity: 0.0090, stars: 1.00)),
        Key(p: 0.18, s: SunState(elevation: 3, azimuth: 100,
            sun: [1.00, 0.55, 0.26], sunIntensity: 2.20,
            skyColor: [0.56, 0.50, 0.50], groundColor: [0.15, 0.20, 0.15],
            ambientIntensity: 0.85, fog: [0.76, 0.60, 0.45], fogDensity: 0.0072, stars: 0.22)),
        Key(p: 0.36, s: SunState(elevation: 24, azimuth: 94,
            sun: [1.00, 0.86, 0.66], sunIntensity: 2.60,
            skyColor: [0.70, 0.80, 0.92], groundColor: [0.20, 0.30, 0.22],
            ambientIntensity: 1.15, fog: [0.80, 0.83, 0.79], fogDensity: 0.0055, stars: 0.00)),
        Key(p: 0.56, s: SunState(elevation: 58, azimuth: 78,
            sun: [1.00, 0.98, 0.93], sunIntensity: 2.85,
            skyColor: [0.76, 0.86, 1.00], groundColor: [0.25, 0.35, 0.25],
            ambientIntensity: 1.35, fog: [0.85, 0.88, 0.86], fogDensity: 0.0045, stars: 0.00)),
        Key(p: 0.79, s: SunState(elevation: 25, azimuth: 58,
            sun: [1.00, 0.86, 0.60], sunIntensity: 2.50,
            skyColor: [0.72, 0.78, 0.86], groundColor: [0.22, 0.30, 0.22],
            ambientIntensity: 1.05, fog: [0.86, 0.80, 0.70], fogDensity: 0.0055, stars: 0.00)),
        Key(p: 1.00, s: SunState(elevation: 2, azimuth: 48,
            sun: [1.00, 0.46, 0.20], sunIntensity: 2.00,
            skyColor: [0.50, 0.40, 0.43], groundColor: [0.14, 0.16, 0.14],
            ambientIntensity: 0.72, fog: [0.73, 0.50, 0.38], fogDensity: 0.00725, stars: 0.18)),
    ]

    /// interpolate ระหว่าง keyframe ด้วย smoothstep — เปลี่ยนช่วงนุ่ม ไม่หักมุม
    static func state(at p: Float) -> SunState {
        let q = min(max(p, 0), 1)
        var i = 0
        while i < keys.count - 2 && q > keys[i + 1].p { i += 1 }
        let a = keys[i], b = keys[i + 1]
        let span = b.p - a.p
        let t = min(max(span > 0 ? (q - a.p) / span : 0, 0), 1)
        let s = t * t * (3 - 2 * t)

        func f(_ x: Float, _ y: Float) -> Float { x + (y - x) * s }
        func v(_ x: SIMD3<Float>, _ y: SIMD3<Float>) -> SIMD3<Float> { x + (y - x) * s }

        return SunState(
            elevation: f(a.s.elevation, b.s.elevation),
            azimuth: f(a.s.azimuth, b.s.azimuth),
            sun: v(a.s.sun, b.s.sun),
            sunIntensity: f(a.s.sunIntensity, b.s.sunIntensity),
            skyColor: v(a.s.skyColor, b.s.skyColor),
            groundColor: v(a.s.groundColor, b.s.groundColor),
            ambientIntensity: f(a.s.ambientIntensity, b.s.ambientIntensity),
            fog: v(a.s.fog, b.s.fog),
            fogDensity: f(a.s.fogDensity, b.s.fogDensity),
            stars: f(a.s.stars, b.s.stars))
    }

    /// ทิศดวงอาทิตย์เป็นเวกเตอร์หนึ่งหน่วย (Y ขึ้น เหมือนเว็บ)
    static func direction(_ s: SunState) -> SIMD3<Float> {
        let e = s.elevation * .pi / 180
        let a = s.azimuth * .pi / 180
        return SIMD3<Float>(cos(e) * sin(a), sin(e), -cos(e) * cos(a))
    }
}
```

- [ ] **Step 4: Write `ForestMath.swift`**

Create `WBW/Scene3D/ForestMath.swift`:

```swift
import Foundation

/// สูตรที่แปลง "เช็คอินไปกี่ฐาน" เป็นขนาดต้นไม้กับเวลาของวัน
///
/// เว็บใช้ตารางความสูงตายตัว 5 ค่า [0.7, 1.3, 2.2, 3.4, 5.0] (อัตราส่วนคงที่ ~1.65)
/// ที่นี่ใช้สูตรแทน เพราะ total มาจาก DB — แอดมินเพิ่ม/ลบฐานได้ ตารางตายตัวจะพังทันที
enum ForestMath {
    static let minTreeHeight: Float = 0.7
    static let maxTreeHeight: Float = 5.0

    /// ช่วงเวลาของวันที่ใช้จริง — ปลายทั้งสองข้างของ 0..1 มืดเกินกว่าจะอ่าน UI ที่ลอยทับ
    /// (ค่าเดียวกับ DAY_FROM/DAY_TO ใน ~/su-wbw-website/lib/dayCycle.ts)
    static let dayFrom: Float = 0.14
    static let dayTo: Float = 0.78

    /// เวลากลางวันนิ่งๆ สำหรับหน้าที่ไม่มีความคืบหน้า (Login, QR)
    static let dayStill: Float = 0.46
    /// เช้าตรู่ — หน้า Welcome
    static let dayWelcome: Float = 0.20

    private static func fraction(_ stage: Int, _ total: Int) -> Float {
        guard total > 0 else { return 0 }
        return Float(min(max(stage, 0), total)) / Float(total)
    }

    static func treeHeight(stage: Int, total: Int) -> Float {
        minTreeHeight * pow(maxTreeHeight / minTreeHeight, fraction(stage, total))
    }

    static func day(stage: Int, total: Int) -> Float {
        dayFrom + (dayTo - dayFrom) * fraction(stage, total)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WBWTests/ForestMathTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **` with 12 tests passing.

- [ ] **Step 6: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/Scene3D/SunCycle.swift WBW/Scene3D/ForestMath.swift WBWTests/ForestMathTests.swift
git commit -m "feat(scene): พอร์ตวงจรแสงจากเว็บ + สูตรความสูงต้นไม้/เวลาของวัน"
```

---

## Task 5: The scene host, the RealityView, and the `.forestBackground` modifier

This is the first task that touches RealityKit. It ends with the forest visible behind Home at a fixed time of day, and a static-image fallback that survives a missing or broken USDZ.

**Files:**
- Create: `WBW/Scene3D/ForestSceneHost.swift`
- Create: `WBW/Scene3D/ForestSceneView.swift`
- Modify: `WBW/RootView.swift`
- Modify: `WBW/HomeView.swift`
- Modify: `WBW/WBWApp.swift` (inject the host into the environment)

**Interfaces:**
- Consumes: `forest.usdz` from Task 1, `SunCycle` from Task 4.
- Produces:
  - `@MainActor final class ForestSceneHost: ObservableObject` with `@Published var enabled: Bool`, `@Published var day: Float`, `@Published var plantStep: Int?`, `@Published var plantTotal: Int`, and `@Published private(set) var loadFailed: Bool`
  - `extension View { func forestBackground(day: Float, plantStep: Int? = nil, plantTotal: Int = 0) -> some View }`
- Task 6 adds the tree entity inside `ForestSceneView`. Task 7 adds gyro. Task 9 applies the modifier to the other four screens.

- [ ] **Step 1: Write the host**

Create `WBW/Scene3D/ForestSceneHost.swift`:

```swift
import SwiftUI

/// เจ้าของฉาก 3D ตัวเดียวของทั้งแอป
///
/// วางไว้ที่ RootView จึงไม่ถูกทำลายตอนสลับ welcome → login → home หรือสลับแท็บ
/// แต่ละหน้าไม่ได้เป็นเจ้าของฉาก แค่ "สั่งค่า" เข้ามาผ่าน .forestBackground()
/// (แนวคิดเดียวกับ SceneHost.tsx ของเว็บ ที่มี Canvas เดียวอยู่ใน layout)
@MainActor
final class ForestSceneHost: ObservableObject {
    /// false = ซ่อน + หยุด render (หน้าที่ไม่ใช้ฉาก, แอปอยู่หลัง, จอเจ้าหน้าที่)
    @Published var enabled = false
    /// ช่วงเวลาของวัน 0..1
    @Published var day: Float = ForestMath.dayStill
    /// ขั้นต้นไม้ · nil = ไม่มีต้นไม้ในฉาก (ตรงกับ plantStep?: number ของเว็บ)
    @Published var plantStep: Int?
    /// จำนวนฐานทั้งหมด — คู่กับ plantStep เพื่อคำนวณความสูง
    @Published var plantTotal = 0
    /// โหลด USDZ ไม่สำเร็จ → ทุกหน้าตกกลับไปใช้รูปนิ่งเดิม
    @Published private(set) var loadFailed = false

    func markLoadFailed() { loadFailed = true }
}

/// สั่งฉากจากหน้าใดก็ได้โดยไม่ต้องรู้จัก RealityKit
///
/// ตัวกลางนี้คือเหตุผลที่สลับ implement ข้างในได้ (3D ↔ รูปนิ่ง) โดยไม่แตะ 5 จอเลย
private struct ForestBackground: ViewModifier {
    @EnvironmentObject private var host: ForestSceneHost
    let day: Float
    let plantStep: Int?
    let plantTotal: Int

    func body(content: Content) -> some View {
        content
            .background {
                // โหลดฉากไม่ได้ → รูปเดิม · ห้ามลบ asset bg_forest ทิ้ง
                if host.loadFailed {
                    Image("bg_forest").resizable().scaledToFill().ignoresSafeArea()
                } else {
                    Color.clear   // ฉากจริงวาดอยู่ที่ RootView ใต้ทุกอย่าง
                }
            }
            .onAppear {
                host.day = day
                host.plantStep = plantStep
                host.plantTotal = plantTotal
                host.enabled = true
            }
            .onDisappear { host.enabled = false }
            .onChange(of: day) { _, v in host.day = v }
            .onChange(of: plantStep) { _, v in host.plantStep = v }
            .onChange(of: plantTotal) { _, v in host.plantTotal = v }
    }
}

extension View {
    /// ใช้ฉากป่า 3D เป็นพื้นหลังของหน้านี้
    /// - plantStep: nil = ไม่มีต้นไม้ · มีค่า = ต้นไม้โตตามขั้น (มีแค่ Home ที่ส่ง)
    func forestBackground(day: Float, plantStep: Int? = nil, plantTotal: Int = 0) -> some View {
        modifier(ForestBackground(day: day, plantStep: plantStep, plantTotal: plantTotal))
    }
}
```

- [ ] **Step 2: Write the RealityView**

Create `WBW/Scene3D/ForestSceneView.swift`:

```swift
import RealityKit
import SwiftUI
import simd

/// ฉากป่าจริง — RealityView ตัวเดียวของแอป
///
/// กล้องนิ่งที่ (0, 1.7, 0) มองไปทาง +Z ของฉาก (ในไฟล์ USDZ ที่ bake ไว้ แกน "ลึก"
/// คือ +Y ของ Blender ซึ่ง USD แปลงเป็น -Z ของ RealityKit ตอน import)
///
/// หมอก: RealityKit ไม่มี exponential fog · สคริปต์ bake แบ่ง material เป็น 8 แถบ
/// ตามระยะ (ชื่อลงท้าย __band0..__band7) ที่นี่ไล่สี tint ของแต่ละแถบตามเวลาของวัน
struct ForestSceneView: View {
    @EnvironmentObject var host: ForestSceneHost

    var body: some View {
        RealityView { content in
            let root = Entity()
            content.add(root)

            guard let forest = try? await Entity(named: "forest") else {
                await MainActor.run { host.markLoadFailed() }
                return
            }
            forest.name = "Forest"
            root.addChild(forest)

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 55
            camera.camera.near = 0.1
            camera.camera.far = 900
            camera.name = "Camera"
            camera.position = SIMD3<Float>(0, 1.7, 0)
            camera.look(at: SIMD3<Float>(0, 1.4, -16), from: camera.position, relativeTo: nil)
            root.addChild(camera)

            let sun = DirectionalLight()
            sun.name = "Sun"
            sun.light.isRealWorldProxy = false
            root.addChild(sun)

            // ไฟเติมจากตรงข้ามดวงอาทิตย์ — แทน hemisphere light ของ three.js
            // ที่ RealityKit ไม่มี · ทำให้ด้านเงาไม่ดำสนิท
            let fill = DirectionalLight()
            fill.name = "Fill"
            root.addChild(fill)

            applySun(to: root, day: host.day)
        } update: { content in
            guard let root = content.entities.first else { return }
            applySun(to: root, day: host.day)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)   // พื้นหลังล้วน ห้ามกินทัชของ UI ข้างหน้า
    }

    /// ตั้งสี/ทิศ/ความแรงของแสง + สีหมอกของทั้ง 8 แถบ ตามเวลาของวัน
    private func applySun(to root: Entity, day: Float) {
        let s = SunCycle.state(at: day)
        let dir = SunCycle.direction(s)

        if let sun = root.findEntity(named: "Sun") as? DirectionalLight {
            sun.light.color = uiColor(s.sun)
            sun.light.intensity = s.sunIntensity * 1_500
            sun.look(at: .zero, from: dir * 40, relativeTo: nil)
        }
        if let fill = root.findEntity(named: "Fill") as? DirectionalLight {
            fill.light.color = uiColor(s.skyColor)
            fill.light.intensity = s.ambientIntensity * 700
            fill.look(at: .zero, from: SIMD3<Float>(-dir.x, 0.6, -dir.z) * 40, relativeTo: nil)
        }

        guard let forest = root.findEntity(named: "Forest") else { return }
        applyFog(to: forest, fog: s.fog, density: s.fogDensity)
    }

    /// ผสมสีวัสดุเข้าหาสีหมอกตามแถบระยะ — แถบไกลผสมมาก แถบใกล้แทบไม่ผสม
    private func applyFog(to entity: Entity, fog: SIMD3<Float>, density: Float) {
        entity.forEachDescendant { node in
            guard var model = node.components[ModelComponent.self] as ModelComponent? else { return }
            var changed = false
            for i in model.materials.indices {
                guard var pbr = model.materials[i] as? PhysicallyBasedMaterial,
                      let band = Self.band(of: pbr.name) else { continue }
                // ระยะกลางของแถบ (แบ่งแบบ log ตอน bake) → ปริมาณหมอกแบบ exp2 เหมือน three.js
                let distance = powf(260, (Float(band) + 0.5) / 8)
                let amount = 1 - expf(-powf(density * distance, 2))
                pbr.baseColor.tint = mix(.white, uiColor(fog), amount)
                model.materials[i] = pbr
                changed = true
            }
            if changed { node.components.set(model) }
        }
    }

    /// อ่านเลขแถบจากชื่อวัสดุที่สคริปต์ bake ตั้งไว้ (`<ชื่อเดิม>__band3`)
    static func band(of name: String?) -> Int? {
        guard let name, let r = name.range(of: "__band", options: .backwards) else { return nil }
        return Int(name[r.upperBound...])
    }

    private func uiColor(_ v: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(v.x), green: CGFloat(v.y), blue: CGFloat(v.z), alpha: 1)
    }

    private func mix(_ a: UIColor, _ b: UIColor, _ t: Float) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let k = CGFloat(min(max(t, 0), 1))
        return UIColor(red: ar + (br - ar) * k, green: ag + (bg - ag) * k,
                       blue: ab + (bb - ab) * k, alpha: 1)
    }
}

extension Entity {
    /// เดินทุก descendant รวมตัวเอง
    func forEachDescendant(_ body: (Entity) -> Void) {
        body(self)
        for child in children { child.forEachDescendant(body) }
    }
}
```

**API verification:** `PhysicallyBasedMaterial.name`, `DirectionalLight.light.isRealWorldProxy`, and the `Entity(named:)` bundle lookup are the three places most likely to differ from this text on the installed SDK. Step 4 will surface any mismatch as a compile error; fix by consulting the SDK's generated interface (`⌃⌘J` on the symbol in Xcode) rather than by guessing. If `PhysicallyBasedMaterial` has no `name`, read the band from the **entity** name instead and have Task 1's script rename objects to carry `__band<N>` as well.

- [ ] **Step 3: Mount the scene and inject the host**

In `WBW/WBWApp.swift`, create the host as a `@StateObject` and inject it with `.environmentObject(...)` alongside the existing environment objects.

In `WBW/RootView.swift`, wrap the existing `ZStack` contents so the scene sits underneath everything.

**Mount on a one-way latch, never on `enabled`.** `enabled` is flipped by the modifier's `onAppear`/`onDisappear`, so gating the view on it means SwiftUI unmounts and rebuilds the whole scene — reloading the USDZ and all 571 objects — every time the user leaves and returns to the Home tab. This was measured: one toggle produced two make-closure calls. The website hit the same problem and solved it in `components/scene/SceneHost.tsx` with a separate `everEnabled` flag plus opacity; port that.

`ForestSceneHost` therefore also publishes `everEnabled`, set true the first time `enabled` becomes true and never reset.

```swift
    var body: some View {
        ZStack {
            // ฉากป่า 3D ใต้ทุกอย่าง — mount ครั้งเดียวตลอดอายุแอป ซ่อนด้วย opacity
            // ห้าม gate ด้วย host.enabled: มันถูกพลิกโดย onAppear/onDisappear ของ modifier
            // ซึ่งจะทำให้ SwiftUI ถอดแล้วสร้างฉากใหม่ทุกครั้งที่ออกจากแท็บ Home แล้วกลับมา
            if host.everEnabled && !host.loadFailed {
                ForestSceneView()
                    .opacity(host.enabled ? 1 : 0)
            }

            switch phase {
            // …เดิมทั้งหมด ไม่แก้…
            }
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
    }
```

Add `@EnvironmentObject private var host: ForestSceneHost` to `RootView`.

- [ ] **Step 4: Point Home at the scene**

In `WBW/HomeView.swift`, replace the `.background { Image("bg_forest") … }` block with:

```swift
        .forestBackground(day: ForestMath.dayStill)
```

Leave the DinDin mascot and everything else alone for now — Task 9 removes it. This step is only about seeing the forest render.

- [ ] **Step 5: Build**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild -scheme WBW -configuration Debug -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -25
```

Expected: `** BUILD SUCCEEDED **`. Fix any RealityKit API mismatch here, per the note in Step 2.

- [ ] **Step 6: Look at it**

```bash
cd /Users/park/wbw-ios-fontend
xcrun simctl boot "iPhone 17" 2>/dev/null || true
xcodebuild -scheme WBW -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build
xcrun simctl install booted "$(xcodebuild -scheme WBW -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -showBuildSettings 2>/dev/null | awk -F'= ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)/WBW.app"
xcrun simctl launch booted th.ac.mfu.wbwSwift -uitestToken "$TOKEN" -uitestUser 6931900011 -uitestRole participant -uitestTab 0
sleep 6
xcrun simctl io booted screenshot /tmp/forest-task5.png
open /tmp/forest-task5.png
```

Expected: the Home greeting and mascot over a 3D forest, not the old flat photograph. The horizon should sit near the middle of the screen with mountains behind it.

If the screen is black, the camera is probably inside geometry or facing the wrong way — print `forest.visualBounds(relativeTo: nil)` in the make closure and compare with the camera position.

- [ ] **Step 7: Verify the fallback**

```bash
cd /Users/park/wbw-ios-fontend
mv WBW/Resources/forest.usdz /tmp/forest-backup.usdz
xcodegen generate && xcodebuild -scheme WBW -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
# reinstall + relaunch as in Step 6, then:
xcrun simctl io booted screenshot /tmp/forest-fallback.png
mv /tmp/forest-backup.usdz WBW/Resources/forest.usdz
```

Expected: the app still runs and Home shows the old `bg_forest` photograph. **No crash, no blank screen.** Restore the file afterwards and rebuild.

- [ ] **Step 8: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/Scene3D/ForestSceneHost.swift WBW/Scene3D/ForestSceneView.swift \
        WBW/RootView.swift WBW/HomeView.swift WBW/WBWApp.swift
git commit -m "feat(scene): ฉากป่า 3D ตัวเดียวที่ RootView + ตกกลับไปรูปนิ่งเมื่อโหลดไม่ได้"
```

---

## Task 6: The growing tree

**Files:**
- Create: `WBW/Scene3D/GrowingTree.swift`
- Modify: `WBW/Scene3D/ForestSceneView.swift`

**Interfaces:**
- Consumes: `tree.usdz` from Task 1, `ForestMath.treeHeight` from Task 4, `host.plantStep` / `host.plantTotal` from Task 5.
- Produces: `final class GrowingTree` with `init?(target: Entity)`, `func setStage(_ stage: Int, total: Int)`, and `func tick(deltaTime: Float, elapsed: Float, reduceMotion: Bool)`.

- [ ] **Step 1: Write the tree**

Create `WBW/Scene3D/GrowingTree.swift`:

```swift
import RealityKit
import simd

/// ต้นไม้ประจำผู้เข้าร่วม — โตหนึ่งขั้นต่อหนึ่งฐานที่เช็คอิน
///
/// ใช้ tree.glb ต้นเดียวกับป่ารอบๆ แล้วไล่ขนาดเอา (เว็บเคยลองสลับเป็นโมเดลคนละตัว
/// ต่อระยะแล้ว สไตล์ไม่เข้ากับฉาก เลยกลับมาใช้วิธีนี้) · tree.usdz ถูก bake ให้สูง
/// 1.0 หน่วยพอดี จึงคูณ scale ด้วยความสูงเป้าหมายได้ตรงๆ
final class GrowingTree {
    /// ตำแหน่งที่ถางไว้ในสคริปต์ bake — กลางจอ ระยะ 6 หน่วยหน้ากล้อง
    static let position = SIMD3<Float>(0, 0, -6)

    private let node: Entity
    private var height: Float = ForestMath.minTreeHeight
    private var target: Float = ForestMath.minTreeHeight

    init?(target parent: Entity) {
        guard let tree = try? Entity.load(named: "tree") else { return nil }
        let holder = Entity()
        holder.name = "GrowingTree"
        holder.position = Self.position
        holder.addChild(tree)
        parent.addChild(holder)
        node = holder
        node.scale = .init(repeating: height)
    }

    func setStage(_ stage: Int, total: Int) {
        target = ForestMath.treeHeight(stage: stage, total: total)
    }

    /// เรียกทุกเฟรม — ค่อยๆ โตเข้าหาเป้าหมาย ไม่กระโดดทันทีที่ข้อมูลมาถึง
    func tick(deltaTime: Float, elapsed: Float, reduceMotion: Bool) {
        if reduceMotion {
            height = target
        } else {
            height += (target - height) * min(1, deltaTime * 1.7)   // อัตราเดียวกับเว็บ
        }
        node.scale = .init(repeating: height)

        guard !reduceMotion else {
            node.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            return
        }
        // ไหวตามลม — ต้นเล็กไหวมาก ต้นใหญ่แทบไม่ไหว (สูตรเดียวกับ GrowingPlant.tsx)
        let amp = 0.05 / (1 + height * 0.8)
        let z = sin(elapsed * 0.90) * amp
        let x = sin(elapsed * 0.72 + 1.3) * amp * 0.6
        node.orientation = simd_quatf(angle: z, axis: [0, 0, 1]) * simd_quatf(angle: x, axis: [1, 0, 0])
    }

    func removeFromScene() { node.removeFromParent() }
}
```

- [ ] **Step 2: Drive it from the scene**

In `ForestSceneView`, add state and a render tick. Add these properties:

```swift
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tree: GrowingTree?
    @State private var lastTick: TimeInterval = 0
    @State private var elapsed: Float = 0
```

In the `make` closure, after adding the forest, create the tree only when a step is set:

```swift
            if host.plantStep != nil {
                let grown = GrowingTree(target: root)
                grown?.setStage(host.plantStep ?? 0, total: max(host.plantTotal, 1))
                await MainActor.run { tree = grown }
            }
```

Then attach a per-frame driver to the view using `TimelineView` so growth and wind animate without a `SceneEvents` subscription:

```swift
        TimelineView(.animation(paused: !host.enabled)) { timeline in
            RealityView { content in
                // …make closure as above…
            } update: { content in
                guard let root = content.entities.first else { return }
                applySun(to: root, day: host.day)

                let now = timeline.date.timeIntervalSinceReferenceDate
                let dt = lastTick == 0 ? 1.0 / 60 : min(0.05, now - lastTick)
                lastTick = now
                elapsed += Float(dt)

                if let step = host.plantStep {
                    tree?.setStage(step, total: max(host.plantTotal, 1))
                    tree?.tick(deltaTime: Float(dt), elapsed: elapsed, reduceMotion: reduceMotion)
                }
            }
        }
```

Mutating `@State` from `update:` is safe here because the values are frame-local scalars, not view identity. If Xcode warns about publishing changes from within view updates, move `lastTick` and `elapsed` into a small `final class TickClock` held by `@StateObject` instead.

- [ ] **Step 3: Build**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild -scheme WBW -configuration Debug -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -25
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: See the tree at two different stages**

Temporarily pass a fixed step from Home to prove the size changes — in `HomeView`, change the modifier to `.forestBackground(day: ForestMath.dayStill, plantStep: 0, plantTotal: 8)`, build, install, launch, screenshot; then change to `plantStep: 8`, repeat.

```bash
xcrun simctl io booted screenshot /tmp/tree-stage0.png
# …edit, rebuild, reinstall, relaunch…
xcrun simctl io booted screenshot /tmp/tree-stage8.png
open /tmp/tree-stage0.png /tmp/tree-stage8.png
```

Expected: stage 0 is a small sapling in the clearing; stage 8 is a tree filling much of the screen height. Both stand on the ground with no gap or sinking. Revert `HomeView` to `plantStep: nil` after this check — Task 9 wires the real value.

- [ ] **Step 5: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/Scene3D/GrowingTree.swift WBW/Scene3D/ForestSceneView.swift WBW/HomeView.swift
git commit -m "feat(scene): ต้นไม้โตตามขั้น + ไหวตามลม เคารพ Reduce Motion"
```

---

## Task 7: Gyroscope parallax

**Files:**
- Create: `WBW/Scene3D/GyroParallax.swift`
- Create: `WBWTests/GyroParallaxTests.swift`
- Modify: `WBW/Scene3D/ForestSceneView.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `@MainActor final class GyroParallax: ObservableObject` with `@Published private(set) var offset: SIMD2<Float>`, `func start()`, `func stop()`, and the pure `static func mapAttitude(roll: Double, pitch: Double) -> SIMD2<Float>`.

- [ ] **Step 1: Write the failing tests**

Create `WBWTests/GyroParallaxTests.swift`:

```swift
import XCTest
import simd
@testable import WBW

/// การ map การเอียงเครื่องเป็นการเลื่อนกล้อง — เทสเฉพาะส่วนที่เป็นคณิตศาสตร์ล้วน
/// (ตัวเซนเซอร์เทสไม่ได้ในซิม ต้องเครื่องจริง)
final class GyroParallaxTests: XCTestCase {

    func testLevelDeviceIsCentred() {
        let o = GyroParallax.mapAttitude(roll: 0, pitch: 0)
        XCTAssertEqual(o.x, 0, accuracy: 0.0001)
        XCTAssertEqual(o.y, 0, accuracy: 0.0001)
    }

    func testTiltingRightMovesCameraRight() {
        let o = GyroParallax.mapAttitude(roll: 0.3, pitch: 0)
        XCTAssertGreaterThan(o.x, 0)
    }

    func testTiltingLeftMovesCameraLeft() {
        let o = GyroParallax.mapAttitude(roll: -0.3, pitch: 0)
        XCTAssertLessThan(o.x, 0)
    }

    func testOffsetIsClampedToTheBakedMargin() {
        // สคริปต์ bake เผื่อขอบไว้ 25% ของกรวยกล้อง = ±1.1 หน่วย
        // ถ้าปล่อยให้เกินนี้ เอียงแรงๆ จะเห็นขอบฉากว่างเปล่า
        for roll in stride(from: -3.0, through: 3.0, by: 0.25) {
            let o = GyroParallax.mapAttitude(roll: roll, pitch: 0)
            XCTAssertLessThanOrEqual(abs(o.x), GyroParallax.maxOffsetX + 0.0001,
                                     "roll \(roll) ให้ offset เกินขอบที่ bake ไว้")
        }
    }

    func testPitchOffsetIsClamped() {
        for pitch in stride(from: -3.0, through: 3.0, by: 0.25) {
            let o = GyroParallax.mapAttitude(roll: 0, pitch: pitch)
            XCTAssertLessThanOrEqual(abs(o.y), GyroParallax.maxOffsetY + 0.0001)
        }
    }

    func testResponseIsMonotonicWithinRange() {
        let a = GyroParallax.mapAttitude(roll: 0.1, pitch: 0).x
        let b = GyroParallax.mapAttitude(roll: 0.2, pitch: 0).x
        XCTAssertGreaterThan(b, a)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WBWTests/GyroParallaxTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'GyroParallax' in scope`.

- [ ] **Step 3: Write the parallax source**

Create `WBW/Scene3D/GyroParallax.swift`:

```swift
import CoreMotion
import SwiftUI
import simd

/// เอียงเครื่องแล้วฉากขยับ — เวอร์ชันมือถือของ pointer parallax ที่เว็บทำใน CameraRig
///
/// เลื่อน "ตำแหน่ง" กล้องแล้ว lookAt จุดเดิม ไม่ใช่หมุนกล้อง — ของใกล้กับของไกลจึง
/// ขยับไม่เท่ากัน ได้ความรู้สึกเป็นหน้าต่างจริง ถ้าหมุนกล้องเฉยๆ ทุกอย่างจะเลื่อนพร้อมกัน
@MainActor
final class GyroParallax: ObservableObject {
    /// ขอบที่สคริปต์ bake เผื่อไว้ (GYRO_MARGIN = 1.25) — เกินกว่านี้เห็นขอบฉาก
    static let maxOffsetX: Float = 1.1
    static let maxOffsetY: Float = 0.4

    @Published private(set) var offset = SIMD2<Float>(0, 0)

    private let motion = CMMotionManager()
    private var running = false

    /// map มุมเอียงเป็นระยะเลื่อน · ล้วนๆ ไม่มี side effect เทสได้
    static func mapAttitude(roll: Double, pitch: Double) -> SIMD2<Float> {
        // tanh ให้เอียงน้อยๆ ตอบไว เอียงมากอิ่มตัว ไม่กระชากตอนพลิกเครื่อง
        let x = Float(tanh(roll * 1.6)) * maxOffsetX
        let y = Float(tanh(pitch * 1.2)) * maxOffsetY
        return SIMD2<Float>(min(max(x, -maxOffsetX), maxOffsetX),
                            min(max(y, -maxOffsetY), maxOffsetY))
    }

    func start() {
        guard !running, motion.isDeviceMotionAvailable else { return }
        running = true
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.attitude else { return }
            let raw = Self.mapAttitude(roll: a.roll, pitch: a.pitch)
            // low-pass — เซนเซอร์ดิบสั่นตลอด ถ้าไม่กรองฉากจะสั่นตาม
            self.offset += (raw - self.offset) * 0.12
        }
    }

    /// หยุดตอนฉากถูกซ่อนหรือแอปลงหลัง — เซนเซอร์ที่วิ่งอยู่เฉยๆ กินแบต
    func stop() {
        guard running else { return }
        running = false
        motion.stopDeviceMotionUpdates()
        offset = .zero
    }
}
```

- [ ] **Step 4: Apply it to the camera**

In `ForestSceneView`, add `@StateObject private var gyro = GyroParallax()`, and in the `update:` closure move the camera before applying the sun:

```swift
                if let camera = root.findEntity(named: "Camera") {
                    let o = reduceMotion ? SIMD2<Float>(0, 0) : gyro.offset
                    let eye = SIMD3<Float>(o.x, 1.7 - o.y, 0)
                    camera.position = eye
                    camera.look(at: SIMD3<Float>(0, 1.4, -16), from: eye, relativeTo: nil)
                }
```

Start and stop it with the scene:

```swift
        .onAppear { if !reduceMotion { gyro.start() } }
        .onDisappear { gyro.stop() }
        .onChange(of: host.enabled) { _, on in on && !reduceMotion ? gyro.start() : gyro.stop() }
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WBWTests/GyroParallaxTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **` with 6 tests passing.

- [ ] **Step 6: Note what is not proven**

The simulator has no motion sensors, so `start()` returns immediately there and nothing moves. The parallax itself is only observable on a physical device — see `docs/sus-test-backend.md` for pointing a device at a LAN backend. Record in the commit message that the sensor path is unverified rather than implying it was tested.

- [ ] **Step 7: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/Scene3D/GyroParallax.swift WBWTests/GyroParallaxTests.swift WBW/Scene3D/ForestSceneView.swift
git commit -m "feat(scene): ไจโรเลื่อนกล้อง (คณิตศาสตร์ผ่านเทส · เซนเซอร์ยังไม่ได้ลองบนเครื่องจริง)"
```

---

## Task 8: Overlay — scrim, grain, and the model credit

The models are CC BY. The credit is a licence obligation, not decoration.

**Files:**
- Create: `WBW/Scene3D/ForestOverlay.swift`
- Modify: `WBW/RootView.swift`

**Interfaces:**
- Consumes: `SunCycle` from Task 4, `host` from Task 5.
- Produces: `struct ForestOverlay: View` — draws above the scene and below all app UI.

- [ ] **Step 1: Write the overlay**

Create `WBW/Scene3D/ForestOverlay.swift`:

```swift
import SwiftUI

/// ชั้นทับฉาก — ไล่เฉดให้ UI ที่ลอยอยู่อ่านออกทุกช่วงเวลา + เกรน + เครดิตโมเดล
///
/// พอร์ตจาก overlay ใน ~/su-wbw-website/components/ForestScene.tsx
/// เครดิตเป็นข้อบังคับของ CC BY ไม่ใช่ของประดับ ห้ามถอด
struct ForestOverlay: View {
    let day: Float

    private var scrim: LinearGradient {
        // เข้มหัวจอกับท้ายจอ กลางจอโปร่ง — ตรงกลางคือที่ต้นไม้อยู่
        LinearGradient(
            stops: [
                .init(color: Color(red: 10/255, green: 22/255, blue: 16/255).opacity(0.72), location: 0.00),
                .init(color: Color(red: 10/255, green: 22/255, blue: 16/255).opacity(0.15), location: 0.22),
                .init(color: Color(red: 10/255, green: 22/255, blue: 16/255).opacity(0.20), location: 0.62),
                .init(color: Color(red: 10/255, green: 22/255, blue: 16/255).opacity(0.75), location: 1.00),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            scrim.ignoresSafeArea()

            // เกรนฟิล์มบางๆ — กันไล่เฉดเป็นแถบ (banding) บนฟ้าเรียบๆ
            Rectangle()
                .fill(.white)
                .opacity(0.025)
                .blendMode(.overlay)
                .ignoresSafeArea()

            Text("โมเดล 3 มิติ: ดู WBW/Resources/models/CREDITS.md · CC BY")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.40))
                .padding(.leading, 16)
                .padding(.bottom, 3)
        }
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 2: Put it above the scene**

In `RootView`, immediately after `ForestSceneView()`:

```swift
                ForestOverlay(day: host.day)
                    .transition(.opacity)
```

Both are inside the same `if host.enabled && !host.loadFailed` block, so the overlay never appears over the static-image fallback (which is already dark enough to read against).

- [ ] **Step 3: Build and look**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild -scheme WBW -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -10
# reinstall + relaunch as in Task 5 Step 6
xcrun simctl io booted screenshot /tmp/forest-overlay.png && open /tmp/forest-overlay.png
```

Expected: the "Hey! <name>" greeting and the bell are clearly readable against the sky, the credit line sits at the bottom left, and the middle of the screen is still bright enough to see the forest.

- [ ] **Step 4: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/Scene3D/ForestOverlay.swift WBW/RootView.swift
git commit -m "feat(scene): scrim + เกรน + เครดิตโมเดล CC BY ทับฉาก"
```

---

## Task 9: Wire all five screens, remove DinDin, gate the render loop

**Files:**
- Modify: `WBW/HomeView.swift`
- Modify: `WBW/WelcomeView.swift`
- Modify: `WBW/LoginView.swift`
- Modify: `WBW/MyQRCodeView.swift`
- Modify: `WBW/MainTabView.swift`
- Modify: `WBW/RootView.swift`
- Modify: `WBW/Session.swift` (clear the progress cache on logout)

**Interfaces:**
- Consumes: everything from Tasks 3–8.
- Produces: the finished feature. No new API.

- [ ] **Step 1: Home — real progress, real day, no mascot**

In `HomeView`, add `@EnvironmentObject var progress: CheckinProgressStore`, delete the `Image("dindin")` block together with the `Spacer()` that positioned it, and set the modifier to:

```swift
        .forestBackground(
            day: ForestMath.day(stage: progress.progress?.stage ?? 0,
                                total: progress.progress?.total ?? 0),
            plantStep: progress.progress?.stage ?? 0,
            plantTotal: progress.progress?.total ?? 0)
```

`Image("dindin")` is used nowhere else — confirm with `grep -rn 'dindin' WBW/` before deleting. Leave the asset in `Assets.xcassets`; the mascot may return on another screen.

- [ ] **Step 2: The other four screens**

- `WelcomeView`: replace the `Image("bg_welcome")` background with `.forestBackground(day: ForestMath.dayWelcome)`
- `LoginView`: replace the `Image("bg_login")` background block — including its `.background(Color.wbwInk)` — with `.forestBackground(day: ForestMath.dayStill)`
- `MyQRCodeView`: delete the `Image("bg_forest")` line from the `ZStack` and add `.forestBackground(day: ForestMath.dayStill)` to the `ZStack`
- `MainTabView`'s `ForestBlank`: same substitution

- [ ] **Step 3: Load progress alongside the profile**

In `MainTabView`, add `@EnvironmentObject var progress: CheckinProgressStore` and, inside the existing `.task`, after `await profile.load(...)`:

```swift
                await progress.load(token: session.token ?? "")
```

And in the existing `.onChange(of: scenePhase)` handler, in the `.active` branch:

```swift
                if phase == .active {
                    chat.start()
                    Task { await progress.load(token: session.token ?? "") }
                }
```

Create the store as a `@StateObject` in `WBWApp` and inject it with `.environmentObject(...)` next to `ProfileStore`.

- [ ] **Step 4: Gate the render loop**

In `MainTabView`, add `@EnvironmentObject var host: ForestSceneHost` and turn the scene off for the tabs and overlays that hide it:

```swift
            .onChange(of: tab) { _, t in
                // แท็บ Map รัน MapLibre บน GPU อยู่แล้ว · SU RUN กับ Group ทับเต็มจอ
                // ปล่อยให้ฉากวิ่งอยู่ข้างหลังคือเผาแบตให้สิ่งที่ไม่มีใครเห็น
                host.enabled = (t == 0 || t == 4) && !chatOpen
            }
            .onChange(of: chatOpen) { _, open in
                host.enabled = (tab == 0 || tab == 4) && !open
            }
```

In `RootView`, turn it off for staff and when the app leaves the foreground. Add `@Environment(\.scenePhase) private var scenePhase` and:

```swift
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { host.enabled = false }
        }
        .onChange(of: isStaff) { _, staff in
            // StaffScanView ทับด้วยสีทึบ + กล้อง · เจ้าหน้าที่เปิดจอสแกนค้างเป็นชั่วโมง
            // ในวันงาน ฉากที่วิ่งอยู่ข้างหลังกินแบตทั้งวันโดยไม่มีใครเห็น
            if staff { host.enabled = false }
        }
```

- [ ] **Step 5: Clear the cache on logout**

`Session` holds no reference to any store (`Session.swift:46-53` only clears its own `UserDefaults` keys and calls `PushManager.shared.unregister()`), so it clears the cached bytes directly. Add to the end of `logout()`:

```swift
        // ต้นไม้ของบัญชีก่อนหน้าต้องไม่ตกทอดไปให้บัญชีถัดไปบนเครื่องเดียวกัน
        // Session ไม่ได้ถือ store ไว้ จึงลบ cache ตรงๆ · ตัว store ในหน่วยความจำ
        // ถูกล้างที่ MainTabView.onDisappear (ทางเดียวกับ chat.purgeForLogout)
        UserDefaults.standard.removeObject(
            forKey: CheckinProgressStore.cacheKey(for: Config.backend))
```

And in `MainTabView`, extend the existing `.onDisappear { chat.purgeForLogout() }` — which fires only on logout, per its own comment — to:

```swift
        .onDisappear {
            chat.purgeForLogout()
            progress.clear()
        }
```

- [ ] **Step 6: Build and run the full test suite**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -25
```

Expected: `** TEST SUCCEEDED **`. The pre-existing chat, QR, and `PendingPush` suites must still pass — this task touches `MainTabView` and `Session`, which they exercise.

- [ ] **Step 7: Walk every screen**

```bash
# ยังไม่ล็อกอิน — Welcome แล้ว Login
xcrun simctl launch booted th.ac.mfu.wbwSwift -uitestLogin YES
sleep 5 && xcrun simctl io booted screenshot /tmp/s-login.png

# ล็อกอินแล้ว — Home
xcrun simctl launch booted th.ac.mfu.wbwSwift -uitestToken "$TOKEN" -uitestUser 6931900011 -uitestRole participant -uitestTab 0
sleep 6 && xcrun simctl io booted screenshot /tmp/s-home.png

# แท็บ QR
xcrun simctl launch booted th.ac.mfu.wbwSwift -uitestToken "$TOKEN" -uitestUser 6931900011 -uitestRole participant -uitestTab 4
sleep 6 && xcrun simctl io booted screenshot /tmp/s-qr.png

open /tmp/s-login.png /tmp/s-home.png /tmp/s-qr.png
```

Expected: all three sit on the 3D forest, Login is brighter (day 0.46) than Welcome (0.20), Home has no DinDin and shows a tree sized to the three seeded check-ins, and the QR card is readable against the scene.

- [ ] **Step 8: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/HomeView.swift WBW/WelcomeView.swift WBW/LoginView.swift WBW/MyQRCodeView.swift \
        WBW/MainTabView.swift WBW/RootView.swift WBW/Session.swift WBW/WBWApp.swift
git commit -m "feat(scene): ทั้ง 5 จอใช้ฉากป่าเดียวกัน · ถอด DinDin · หยุด render ตอนไม่ได้ใช้"
```

---

## Task 10: Stage screenshots and the debug launch hook

**Files:**
- Modify: `WBW/HomeView.swift` (DEBUG override for the stage)
- Create: `docs/forest-3d-verification.md`

**Interfaces:**
- Consumes: everything.
- Produces: `-uitestProgress <n>` launch argument forcing the tree to stage `n` out of 8, matching the existing `-uitestTab` / `-uitestChat` pattern.

- [ ] **Step 1: Add the override**

In `HomeView`, compute the stage through a DEBUG hook:

```swift
    private var stage: Int {
        #if DEBUG
        // บังคับขั้นต้นไม้เพื่อถ่ายภาพยืนยัน — ทรงเดียวกับ uitestTab/uitestChat
        if UserDefaults.standard.object(forKey: "uitestProgress") != nil {
            return UserDefaults.standard.integer(forKey: "uitestProgress")
        }
        #endif
        return progress.progress?.stage ?? 0
    }

    private var total: Int {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "uitestProgress") != nil { return 8 }
        #endif
        return progress.progress?.total ?? 0
    }
```

and use `stage` / `total` in the `.forestBackground(...)` call.

- [ ] **Step 2: Capture the three stages**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild -scheme WBW -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
# reinstall as in Task 5 Step 6, then:
for n in 0 4 8; do
  xcrun simctl terminate booted th.ac.mfu.wbwSwift 2>/dev/null
  xcrun simctl launch booted th.ac.mfu.wbwSwift -uitestToken "$TOKEN" -uitestUser 6931900011 \
    -uitestRole participant -uitestTab 0 -uitestProgress $n
  sleep 6
  xcrun simctl io booted screenshot /tmp/tree-$n.png
done
open /tmp/tree-0.png /tmp/tree-4.png /tmp/tree-8.png
```

Expected: three images showing a sapling, a mid-sized tree, and a full tree — and three visibly different times of day (dawn, midday, golden afternoon), because the day advances with the stage.

- [ ] **Step 3: Write down what was and was not verified**

Create `docs/forest-3d-verification.md` recording, with dates: the baked file sizes, the scatter counts printed by the script, which screens were screenshotted, the three stage screenshots, and explicitly that **gyro parallax was never exercised** (no motion sensors in the simulator) and that the scene's appearance against the website was judged by eye, not measured.

- [ ] **Step 4: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/HomeView.swift docs/forest-3d-verification.md
git commit -m "test(scene): launch arg -uitestProgress + บันทึกสิ่งที่ยืนยันแล้วและยังไม่ได้ยืนยัน"
```

---

## Self-review notes

Checked against the spec section by section:

- **One persistent scene across five screens** — Tasks 5 and 9.
- **Tree grows a stage per base; day advances with it** — Tasks 4, 6, 9.
- **Gyro parallax** — Task 7, with the untestable part named rather than hidden.
- **Bake pipeline with a Quick Look gate** — Task 1, Steps 3 and 4, which block Task 2.
- **`total` from the database, never hardcoded** — Task 2 Step 2, tested in Task 4 (`testTreeHeightAdaptsToDifferentTotals`) and checked by `curl` in Task 2 Step 8.
- **Cache namespaced per backend** — Task 3, Steps 1 and 6, with two dedicated tests.
- **Fallback to `Image("bg_forest")`** — Task 5, Steps 1 and 7.
- **Render gating, including the staff case** — Task 9 Step 4.
- **CC BY credit on screen** — Task 8.
- **XcodeGen resource classification** — Environment Step B plus the `xcodegen generate` in every build step; if `.usdz` files fail to appear in the bundle, that surfaces in Task 5 Step 6 as a load failure into the fallback path.

Two things the spec asks for that this plan deliberately does **not** deliver, and why:

- The spec's testing section lists Go unit tests for the progress query. SUS has no database-backed test harness and adding one is out of scope for this feature, so Task 2 verifies with `curl` against the local stack and says so plainly.
- The spec mentions baking ponds. Task 1 does not place any — the six-mountain backdrop and the ground already close the horizon, and adding water would need a second material path. If ponds are wanted, they are a follow-up change to `bake-forest.py` alone; nothing in Swift depends on their absence.
