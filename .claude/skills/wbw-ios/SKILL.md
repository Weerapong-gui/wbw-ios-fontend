---
name: wbw-ios
description: WBW iOS app (SwiftUI, XcodeGen, backend SUS). ใช้ตอนแก้โค้ด build รัน หรือออกแบบฟีเจอร์ใน repo wbw-ios-fontend
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion]
---

# WBW iOS — ประตูเข้า skill

ไฟล์นี้เป็นสารบัญ อ่านก่อนเสมอ รายละเอียดจริงอยู่ในไฟล์อ้างอิง 4 ไฟล์ในโฟลเดอร์เดียวกัน (ดู `## อ่านต่อ`)

## ตอนไหนใช้ skill นี้

- แตะไฟล์ใน `WBW/` หรือ `WBWTests/`
- เพิ่มจอ/ฟีเจอร์ใหม่
- build/รัน/เก็บสกรีนช็อต
- แตะอะไรที่คุยกับ backend
- จะออกแบบฟีเจอร์ใหม่ (ก่อนเขียนโค้ด)

## แผนที่โปรเจกต์

SwiftUI · deployment target iOS 18.0 · Swift 5 · bundle `th.ac.mfu.wbwSwift` · team `NJL4K64JX5` ·
dependency เดียวคือ `FirebaseMessaging` (package Firebase ใน `project.yml`)

- `WBW/` — จอเดี่ยว ๆ วางแบนที่ราก (46 ไฟล์ `.swift`) + โฟลเดอร์ฟีเจอร์เมื่อเกิน ~3 ไฟล์: `SOS/` (11
  ไฟล์ — ปุ่มขอความช่วยเหลือฉุกเฉิน จอสถานะ จอเจ้าหน้าที่ และ `LocationPrimer` ที่คั่นก่อนกล่อง
  ขอสิทธิ์ตำแหน่ง), `Map3D/` (10
  ไฟล์), `Chat/` (5 ไฟล์), `Conditions/` (4 ไฟล์ — อุณหภูมิ/AQI จาก Open-Meteo), `Feedback/` (4 ไฟล์),
  `Bloom/` (3 ไฟล์ — ดอกไม้ halftone หน้า Home), `SURun/` (3 ไฟล์ — จับระยะเดิน/นับก้าว),
  `Demo/` (3 ไฟล์ — โหมดเดโม่สำหรับ App Review), `Scene3D/` (7 ไฟล์ — ฉากป่า ปิดอยู่ตอนนี้แต่ไม่ได้ลบ),
  `Resources/` (asset 3D `.usdz`/`.glb` + `route_wbw.json` เส้นทางเดินที่ bake มาจาก repo Android +
  `Fonts/` ไฟล์ `.ttf` ของ Sarabun/Kanit ที่ยกมาจาก repo Android)
- `WBW/en.lproj/`, `WBW/th.lproj/` — `Localizable.strings` ชุดคีย์ชื่อเดียวกับ `strings.xml` ของ Android
  ทั้งสองฝั่ง · `Font.wbw*` ใน `Typography.swift` คือสเกลตัวอักษรของแอป (ยกจาก `Type.kt`)
  · **ข้อความนอก View ใช้ `Loc.t("key")` ไม่ใช่ `String(localized:)`** (ดูกติกาข้อ 10)
- `WBWTests/` — XCTest ล้วน 63 ไฟล์ วางแบนที่ราก
- `docs/` — เอกสารเสริม (spec/plan อยู่ `docs/superpowers/`)
- `scripts/` — สคริปต์ Blender ทำ asset (`.usdz`) ไม่ใช่ขั้นตอน build ของแอป · กับ
  `check-skill-refs.sh` ที่ตรวจว่าไฟล์ skill 5 ใบนี้ยังตรงกับ repo ไหม (ดู `workflow.md`)

## กติกาห้ามพลาด

1. **`xcodegen generate` หลังเพิ่ม/ลบ/ย้ายไฟล์ใน `WBW/`** — ไม่งั้น Xcode มองไม่เห็นไฟล์ใหม่ หรือยังอ้าง
   ไฟล์ที่ลบไปแล้ว build ไม่ผ่าน
2. **ห้ามลบ `case susLan` จาก `enum Backend`** — `Backend.cacheNamespace` `switch` ครบทุก case อยู่ อีก
   สองไฟล์เทสก็อ้าง `.susLan` ตรง ๆ (ไม่ใช่ `switch`) ลบ case ออกแล้ว repo build ไม่ผ่านเลยตอน clone ใหม่
   บนเครื่องอื่น (รายชื่อไฟล์/รายละเอียดดู `backend-and-config.md`)
3. **`Config.backend` ห้าม commit ตอนสลับไปทดสอบ** — ค่าที่ค้างอยู่ตอน push คือค่าที่ขึ้น store จริง
   `git add` ทีละไฟล์เสมอ อย่าดึงบรรทัดที่สลับค้างไปด้วย
4. **สลับ backend แล้วต้องล้างข้อมูลแอปทุกครั้ง** — cache แชทกับ cursor ไม่ผูกกับ backend ที่มา สลับแล้ว
   ไม่ล้างจะได้ 200 พร้อมลิสต์ว่างตลอด ไม่มี error ให้เห็นเลย
5. **Liquid Glass ใช้ของ native เท่านั้น (`glassSurface`/`.glassEffect` + guard iOS 26)** — ห้ามปลอมด้วย
   `.blur()` เอง ผลลัพธ์ไม่เนียนเท่าของจริง ทั้งที่ fallback ที่ถูกต้องมีอยู่แล้ว
6. **โหมดเดโม่ต้องคอมไพล์ติดใน Release** — ปุ่ม "ดูตัวอย่างแอป (Demo)" ที่หน้าล็อกอินคือคำตอบของ
   Guideline 2.1 (บัญชีเดโม่เดิมล็อกอินไม่ผ่าน และงานปิดรับสมัครที่ 2000/2000 ที่นั่งแล้ว สมัครใหม่
   ไม่ได้อีก) ห้ามย้ายเข้า `#if DEBUG` เหมือน `-uitest*` · cache ของโหมดนี้ต้องต่อ `CacheScope.suffix`
   ท้ายคีย์เสมอ (ดู `backend-and-config.md`)
7. **ห้าม `git add -A` / `git add .`** — repo นี้มักมีงานอื่นที่ยัง untracked วางอยู่ข้าง ๆ ใช้ `-A` แล้วจะ
   ดึงเข้ามาด้วยโดยไม่ตั้งใจ
8. **ห้ามเคลมว่างานเสร็จ/จอถูกโดยไม่ได้รันจริง** — ต้อง build ผ่านจริง test ผ่านจริง งานที่แตะ UI ต้องมี
   สกรีนช็อตจาก simulator ประกอบเสมอ บั๊กที่โค้ดดูถูกแต่พังจริงตอนรันเคยหลุดผ่านมาแล้วจนมีคนรันจริงถึงจับได้
   (`docs/forest-3d-off-verification.md`, `docs/checkin-feedback-verification.md`)
9. **เขียนเทสที่ fail ก่อนค่อยเขียนโค้ดให้ผ่าน (TDD) + คอมเมนต์/commit เป็นภาษาไทยบอก "ทำไม"** — โค้ดบอก
   "ทำอะไร" เองอยู่แล้ว สิ่งที่ขาดคืออาการที่จะเจอถ้าทำผิดทาง
10. **ข้อความที่ผู้ใช้เห็นต้องผ่านชุดคีย์เสมอ · นอก View ใช้ `Loc.t("key")`** — `String(localized:)` อ่าน
   ภาษาจาก bundle (ภาษาของ *เครื่อง*) ไม่ใช่จากตัวเลือกในหน้าตั้งค่า ใช้มันแล้วคนที่เลือก "ไทย" บนเครื่อง
   ภาษาอังกฤษจะได้แอปครึ่งไทยครึ่งอังกฤษ · `Text("key")` ใน View ใช้ทางเดิมได้ (อ่าน `\.locale`)
   · รันตรวจด้วย `scripts/check-localization.sh` — คีย์ที่หายไม่ทำให้ build พัง ผู้ใช้จะเห็นชื่อคีย์บนปุ่มแทน
   และ `%@` ที่คู่กับ `Int` จะ **crash** ตอนวาดจอ (เคยพังจริงที่บัตรผู้เข้าร่วม)

## คำสั่งเร็ว

คัดมาจาก `build-and-run.md` แบบตรงตัว — รายละเอียด (launch args ข้าม UI, รันบนเครื่องจริง, ทำไม
Debug/Release แยก plist) อยู่ในไฟล์นั้น ไม่ซ้ำที่นี่

```bash
xcodegen generate
```

```bash
xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

```bash
xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

```bash
xcrun simctl boot 'iPhone 17'   # ข้ามได้ถ้า boot อยู่แล้ว — เช็คด้วย `xcrun simctl list devices | grep Booted`
APP=$(xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' -showBuildSettings 2>/dev/null \
  | awk -F'= ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)/WBW.app
xcrun simctl install booted "$APP"
xcrun simctl launch booted th.ac.mfu.wbwSwift
xcrun simctl io booted screenshot /tmp/wbw.png
```

## อ่านต่อ

- `backend-and-config.md` — backend มีตัวไหนบ้าง (`enum Backend` ใน `Config.swift`) สลับยังไง และ
  กับดักที่เคยเสียเวลาจริงตอนสลับ/เทส
- `build-and-run.md` — คำสั่ง build/test, รันบน simulator/เครื่องจริง, launch args ข้าม UI ทั้งตาราง,
  ทำไม Debug/Release ต้องแยก plist/entitlements
- `ui-conventions.md` — สีธีม 5 ตัว, วิธีใช้ Liquid Glass, ไฟล์ใหม่วางตรงไหน, สไตล์คอมเมนต์ในโค้ด
- `workflow.md` — วงจรงาน brainstorm → spec → plan → ทำแบบ TDD, กติกาเทส, กติกา commit, เช็คว่า skill
  เน่าไปแล้วหรือยัง

เอกสารที่มีอยู่แล้วนอกโฟลเดอร์ skill: `docs/backend-contract.md`, `docs/sus-test-backend.md`,
`docs/superpowers/specs/`, `docs/superpowers/plans/`
