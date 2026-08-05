# โมเดล 3D ที่ใช้ในหน้า Landing (`/landing`)

รวมทุกไฟล์ประมาณ 93 KB — เลือกเฉพาะโมเดล low-poly ตัวเล็ก เพราะงานนี้คนเข้าพร้อมกัน
หลักพันและส่วนใหญ่อยู่บนมือถือ

> ⚠️ **หลายชิ้นเป็น CC BY 4.0 = ต้องแสดงเครดิต** เครดิตย่อแสดงอยู่มุมล่างซ้ายของหน้า
> (`t.landing.credit` ใน `lib/i18n/dictionaries.ts`) และรายละเอียดเต็มอยู่ในไฟล์นี้
> ถ้าเอาโมเดลไหนออก ให้ปรับเครดิตตามด้วย

## รายการ

| ไฟล์ | โมเดล | ผู้สร้าง | สัญญาอนุญาต | ที่มา |
| --- | --- | --- | --- | --- |
| `tree.glb` | Tree | Poly by Google | **CC BY 4.0** | [poly.pizza](https://poly.pizza/m/6pwiq7hSrHr) |
| `rock-small.glb` | Rock | Quaternius | CC0 | [poly.pizza](https://poly.pizza/m/4MUaQTcDdc) |
| `rock-large.glb` | Rock Large | Quaternius | CC0 | [poly.pizza](https://poly.pizza/m/54jZKTAt5p) |
| `mountain-snow.glb` | Mountain with Snow | Matthew Creighton | **CC BY 4.0** | [poly.pizza](https://poly.pizza/m/0VBAQNbpNcl) |
| `mountain-ridge.glb` | Mountain | jeremy | **CC BY 4.0** | [poly.pizza](https://poly.pizza/m/0Fl55ZzsVzT) |
| `snowy-hills.glb` | Snowy Hills | Nebel | **CC BY 4.0** | [poly.pizza](https://poly.pizza/m/1wt1DXCt-nQ) |
| `signpost.glb` | Signpost | Kenney | CC0 | [poly.pizza](https://poly.pizza/m/3U2lj1gpeH) |
| `grass.glb` | Grass Patch 01 | Jarlan Perez | **CC BY 4.0** | [poly.pizza](https://poly.pizza/m/6XEjsza95ys) |

### หน้าสมัคร (`/register`) — ต้นไม้ที่โตตาม step

ไม่มีไฟล์เพิ่ม · ใช้ `tree.glb` ต้นเดียวกับป่ารอบ ๆ แล้วไล่ขนาดตาม step ของฟอร์ม
(ดู `PHASE_HEIGHTS` ใน `components/register/GrowingPlant.tsx`)

> ⚠️ `tree.glb` เป็น **CC BY 4.0 = ต้องแสดงเครดิตบนหน้าที่ใช้** — `ForestScene.tsx`
> แสดง `t.landing.credit` ไว้มุมล่างซ้ายเหมือนหน้า landing ห้ามเอาออก

CC BY 4.0: https://creativecommons.org/licenses/by/4.0/
CC0 1.0: https://creativecommons.org/publicdomain/zero/1.0/

## ที่ไม่ได้โหลดมา

พื้นป่า, ทางเดินดิน, บ่อน้ำ, ดาว และละอองในอากาศ สร้างเป็น procedural geometry
ในโค้ด (`TrailScene.tsx`) ไม่มีข้อผูกมัดเรื่องสัญญาอนุญาต

ท้องฟ้าใช้ `<Sky>` ของ `@react-three/drei` (Rayleigh/Mie scattering ของ three.js
examples · MIT ติดมากับ dependency อยู่แล้ว) โดยเลื่อนตำแหน่งดวงอาทิตย์ตาม scroll
เป็นวงจรกลางวัน — ดู `sunAt()` ใน `trail.ts`

## เปลี่ยนโมเดล

`components/landing/models.tsx` normalize ขนาด + จัดกึ่งกลางแกน X/Z ด้วย `Box3`
ตอน runtime — วางไฟล์ `.glb` ใหม่ทับชื่อเดิมได้เลย ไม่ต้องจูน scale ในโค้ด

**แต่ต้องรัน `node scripts/glb-info.mjs` แล้วอัปเดตค่า `FOOTPRINT` ใน
`components/landing/trail.ts` ด้วย** — ค่านั้นคือตัวกำหนดว่าของจะวางห่างจากทางเดิน
เท่าไหร่ ถ้าไม่อัปเดตแล้วโมเดลใหม่อ้วนกว่าเดิม มันจะไปยืนคร่อมทางทันที

(อย่าลืมแก้ตารางเครดิตข้างบนด้วย)
