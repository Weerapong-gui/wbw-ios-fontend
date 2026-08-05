"""
render-check.py — เรนเดอร์ฉากป่าจากตำแหน่งกล้องจริงก่อน export เพื่อตรวจด้วยตา

ใช้แทนขั้นตอน `qlmanage -p` แบบโต้ตอบใน task-1-brief.md Step 4 (สภาพแวดล้อมที่รันงานนี้
ไม่มีจอให้ดูหน้าต่างที่เปิดขึ้นมา) เรียก build_forest() จาก bake-forest.py ซ้ำ (โหลดเป็น
โมดูลด้วย importlib เพราะชื่อไฟล์มีขีดกลาง import ตรงๆ ไม่ได้) แล้ววางกล้อง+แสงเพิ่ม
เฉพาะสำหรับเรนเดอร์ตรวจสอบ — ไม่ยุ่งกับ export ไม่ปนกับ forest.usdz จริง

รัน: /Applications/Blender.app/Contents/MacOS/Blender --background --python \
     scripts/render-check.py -- /path/to/out.png
(argument หลัง -- เป็น path PNG ปลายทาง ไม่ใส่ก็ default ไปที่ /tmp/forest-render-check.png)
"""

import importlib.util
import math
import os
import sys

import bpy

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BAKE_SCRIPT = os.path.join(REPO, "scripts", "bake-forest.py")

spec = importlib.util.spec_from_file_location("bake_forest", BAKE_SCRIPT)
bake_forest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bake_forest)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_PNG = argv[0] if argv else "/tmp/forest-render-check.png"


def add_camera():
    """กล้องที่ (0,0,1.7) มองไปทาง +Y ตาม brief · FOV แนวตั้ง 55°
    (ยืนยันด้วยการทดสอบจริงใน Blender: rotation_euler X=90° ทำให้ -Z ของกล้อง
    (ทิศมอง) ชี้ไปทาง world +Y พอดี และ +Y ของกล้อง (ทิศขึ้น) ชี้ไปทาง world +Z)"""
    cam_data = bpy.data.cameras.new("CheckCam")
    cam_data.lens_unit = "FOV"
    cam_data.sensor_fit = "VERTICAL"          # angle ด้านล่าง = FOV แนวตั้งตรงๆ ไม่ต้องเดาแกนอื่น
    cam_data.angle = math.radians(bake_forest.CAM_FOV_DEG)
    cam = bpy.data.objects.new("CheckCam", cam_data)
    cam.location = (0.0, 0.0, bake_forest.CAM_HEIGHT)
    cam.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam


def add_light():
    """แสง+ท้องฟ้าไว้ตรวจตาอย่างเดียว — สร้างในฉากที่ render-check ใช้เอง ไม่ได้ export
    ไปกับ forest.usdz (build_forest() ไม่รู้จักอ็อบเจ็กต์พวกนี้เลย)"""
    sun_data = bpy.data.lights.new("CheckSun", type="SUN")
    sun_data.energy = 3.5
    sun = bpy.data.objects.new("CheckSun", sun_data)
    sun.rotation_euler = (math.radians(55.0), 0.0, math.radians(35.0))
    bpy.context.scene.collection.objects.link(sun)

    world = bpy.data.worlds.new("CheckWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.55, 0.65, 0.75, 1.0)
    bg.inputs["Strength"].default_value = 1.0
    bpy.context.scene.world = world


def main():
    stats, cache = bake_forest.build_forest()
    add_camera()
    add_light()

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"     # Blender 5.1.2: ชื่อ enum เดียวคือ BLENDER_EEVEE (ไม่มี _NEXT)
    scene.render.resolution_x = 540
    scene.render.resolution_y = 1170
    scene.render.resolution_percentage = 100
    scene.eevee.taa_render_samples = 32
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = OUT_PNG

    bpy.ops.render.render(write_still=True)
    print("RENDER CHECK WROTE:", OUT_PNG)


if __name__ == "__main__":
    main()
