# skill ประจำ repo — `wbw-ios`

- **Date:** 2026-08-08
- **Status:** Approved (design), pending implementation plan
- **Branch:** `feature/map3d-usdz` (งานนี้ไม่แตะโค้ดแอป จะแยก branch ตอนทำแผนหรือไม่ก็ได้)
- **ต้นแบบฟอร์แมต:** `claude-code-server-side-swift-skills/` (clone วางไว้ในโฟลเดอร์นี้ ไม่ใช่ของ repo)

## 1. ปัญหาที่แก้

ความรู้ที่ต้องใช้ทุกครั้งก่อนแตะ repo นี้ยังกระจายอยู่ 3 ที่ที่ session ใหม่มองไม่เห็น
พร้อมกัน: คอมเมนต์ในโค้ด (`Config.swift`, `project.yml`, `BackendCacheKey.swift`),
`docs/*.md`, และ memory ของ Claude ที่ผูกกับเครื่อง Park เครื่องเดียว repo **ไม่มี
`CLAUDE.md`** และ **ไม่มี `.claude/skills/`** เลย

ผลคือของที่เคยพังแล้วพังซ้ำได้: ลืม `xcodegen generate` หลังเพิ่มไฟล์, ลบ `case susLan`
แล้ว build ไม่ผ่าน, สลับ backend แล้วแชทเงียบเพราะ cursor ค้าง, ปลอม Liquid Glass ด้วย blur

เป้าหมาย: รวมของพวกนี้เป็น **skill เดียวที่ commit ไปกับ repo** และมี `CLAUDE.md` ชี้มา
เพื่อให้ session ต่อไปอ่านก่อนออกแบบและก่อนเขียนโค้ด

## 2. ขอบเขต

**ทำ** — skill ครอบ 4 เรื่อง: build/รัน/สกรีนช็อต · backend + `Config` กับดัก ·
ธรรมเนียม UI · วิธีทำงาน (spec→plan→TDD→commit)

**ไม่ทำ (YAGNI)**

- ไม่เขียน skill ของ backend SUS (คนละ repo — ถ้าอยากได้ทำแยกทีหลัง)
- ไม่ก๊อป `server-side-swift` / `xcode-cloud` จาก repo ตัวอย่างเข้ามา — backend จริงเป็น
  Go ไม่ใช่ Swift และโปรเจกต์นี้ยังไม่ได้ใช้ Xcode Cloud ทั้งสองอันจะเป็นคำแนะนำที่ไม่ตรงงาน
- ไม่ตั้ง hook ใน `settings.json` (ยังมี hook caveman อยู่ ไม่เพิ่มของซ้อน)
- ไม่ย้าย/ไม่แก้ `docs/*.md` ที่มีอยู่ — skill **ชี้ไปหา** ไม่ก๊อปเนื้อมาซ้ำ
- ไม่แตะโค้ดแอปสักไฟล์

## 3. โครงไฟล์

```
.claude/skills/wbw-ios/
├── SKILL.md               ประตูเดียว ~180 บรรทัด
├── build-and-run.md       ~150
├── backend-and-config.md  ~130
├── ui-conventions.md      ~100
└── workflow.md            ~110
CLAUDE.md                  ใหม่ ที่รากโปรเจกต์ 5–8 บรรทัด
```

frontmatter ของ `SKILL.md`:

```yaml
---
name: wbw-ios
description: WBW iOS app (SwiftUI, XcodeGen, backend SUS). ใช้ตอนแก้โค้ด build รัน หรือออกแบบฟีเจอร์ใน repo wbw-ios-fontend
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion]
---
```

ไฟล์อ้างอิงเป็น markdown ธรรมดา ไม่มี frontmatter (ทรงเดียวกับ repo ตัวอย่าง)

## 4. `SKILL.md` — 5 บล็อก

### 4.1 ตอนไหนใช้

แตะไฟล์ใน `WBW/` หรือ `WBWTests/` · เพิ่มจอ/ฟีเจอร์ · build/รัน/เก็บสกรีนช็อต ·
แตะอะไรที่คุยกับ backend · จะออกแบบฟีเจอร์ใหม่ในโปรเจกต์นี้

### 4.2 แผนที่โปรเจกต์

- SwiftUI, deployment target iOS 18.0, Swift 5, bundle `th.ac.mfu.wbwSwift`,
  team `NJL4K64JX5`, dependency เดียวคือ FirebaseMessaging
- `WBW/` 57 ไฟล์ Swift — จอหลักวางแบน ๆ ที่ราก, ฟีเจอร์ที่โตแล้วแยกโฟลเดอร์:
  `Map3D/` (5), `Chat/` (5), `Feedback/` (4), `Scene3D/` (7, ปิดอยู่แต่ไม่ได้ลบ),
  `Resources/` (`map.usdz`, `forest.usdz`, `tree.usdz`)
- `WBWTests/` 20 ไฟล์ XCTest
- `docs/` — spec/plan อยู่ `docs/superpowers/`, เอกสารยืนยันผลและ contract อยู่ราก `docs/`
- `scripts/` — สคริปต์ Blender สำหรับ asset ไม่ใช่ขั้นตอน build: `bake-forest.py`
  (ประกอบฉากป่าจาก GLB → USDZ), `render-check.py` (เรนเดอร์ตรวจด้วยตาแบบ headless)

### 4.3 กติกาห้ามพลาด

ทุกข้อมาจากของที่เคยพังจริงในโปรเจกต์นี้:

1. เพิ่ม/ลบ/ย้ายไฟล์ใน `WBW/` แล้ว **ต้อง `xcodegen generate`** — `WBW.xcodeproj/`
   อยู่ใน `.gitignore`, `project.yml` คือของจริง ห้ามแก้ xcodeproj ด้วยมือ
2. **ห้ามลบ `case susLan`** ใน `Config.swift` — `BackendCacheKey` กับเทสอีกสองไฟล์
   `switch` ครบทุก case ลบแล้ว clone ใหม่ build ไม่ผ่าน; ของที่แก้เฉพาะเครื่องคือเลข IP
3. **`Config.backend` เป็นบรรทัดที่ห้าม commit ตอนสลับไปทดสอบ** — ค่าที่อยู่ใน repo คือ
   ค่าที่จะส่งขึ้น store (`.susProd`) `git add` ทีละไฟล์เสมอ
4. สลับ `Config.backend` แล้ว **ต้องล้างข้อมูลแอป** — cursor แชท/cache ไม่ผูกกับ backend
   ที่มันมาจาก อาการคือได้ 200 พร้อมลิสต์ว่างตลอด ไม่มี error ไม่มี log
5. **Liquid Glass ของ native เท่านั้น** — `glassSurface(_:)` / `GlassRing` ที่ guard
   `#available(iOS 26.0, *)` แล้ว fallback `.ultraThinMaterial` ห้ามปลอมด้วย blur
6. **ห้าม `git add -A`** — repo มักมีงานที่ยังไม่ commit ของงานอื่นวางอยู่
7. **ห้ามอ้างว่าเสร็จโดยยังไม่ได้รัน** — build/test ต้องมีผลจริงก่อนพูด
8. เขียนเทสก่อน (TDD) และคอมเมนต์/commit เป็นภาษาไทย

### 4.4 คำสั่งเร็ว

build, test, ลง+รันบน sim พร้อม launch args อย่างละบรรทัด รายละเอียดอยู่ใน
`build-and-run.md`

### 4.5 สารบัญ

ชี้ไฟล์อ้างอิงทั้ง 4 + เอกสารที่มีอยู่แล้ว: `docs/backend-contract.md`,
`docs/sus-test-backend.md`, `docs/superpowers/specs/`, `docs/superpowers/plans/`

## 5. ไฟล์อ้างอิง

### 5.1 `build-and-run.md`

- วงจร XcodeGen: แก้ `project.yml` หรือเพิ่มไฟล์ → `xcodegen generate` → build
- คำสั่ง build/test ที่ใช้จริงในโปรเจกต์นี้ (destination `platform=iOS Simulator,name=iPhone 17`
  และตัว `generic/platform=iOS Simulator` สำหรับเช็คว่า compile ผ่านเฉย ๆ)
- ลง+รันบน sim: อ่าน `BUILT_PRODUCTS_DIR` จาก build settings → `simctl install booted`
  → `simctl launch booted th.ac.mfu.wbwSwift`
- **launch args ที่โค้ดรองรับจริง** (ตรวจแล้วใน `Session.swift` + `MainTabView.swift`):
  `-uitestToken`, `-uitestUser`, `-uitestRole`, `-uitestTab` (0 Home / 1 Map / 2 SU RUN /
  3 Group / 4 QR), `-uitestChat`, `-uitestChatCloseAfter`, `-uitestNotifications`,
  `-uitestFeedback <checkpointId>`, `-uitestTabSequence`
  — ไม่มี tooling กดจอ (ไม่มี idb) นี่คือทางเดียวที่จะเห็นจอชั้นในแบบไม่ต้องกดมือ
- เครื่องจริง — **ส่วนเดียวในทั้ง skill ที่มาจากบันทึกการรันเก่า ไม่ใช่จากไฟล์ใน repo**
  (รันจริงล่าสุด 2026-08-03 บน iPhone 13 ต่อ SUS local) ต้องเขียนกำกับวันที่ไว้ในไฟล์ และ
  ไม่ต้องรันซ้ำเพื่อยืนยันตอนทำงานนี้ (ต้องมีเครื่องจริงเสียบ + Park กด Trust) ดู §7: ต้อง Trust เครื่องก่อน ·
  `devicectl ... --console <bundle> -- -uitestToken <jwt>` — **ไม่มี `--` อาร์กิวเมนต์โดน
  `-t` กิน** · container SUS bind loopback ต้อง forward ออก LAN ก่อน ·
  `-uitestToken` แพ้ session ที่แอปเก็บไว้แล้ว (ชนะเฉพาะตอนติดตั้งใหม่)
- ทำไม Debug/Release แยก `INFOPLIST_FILE` + `CODE_SIGN_ENTITLEMENTS`: `aps-environment`
  ผิดฝั่ง = push ไม่มาสักอันโดยไม่มี error, และ Info-Debug มีคีย์วง LAN ที่ห้ามหลุดขึ้น store

### 5.2 `backend-and-config.md`

- ตาราง `Backend` 5 case → `apiBase` + `mePath` (`/auth/me` ฝั่ง Node, `/me` ฝั่ง SUS)
- กติกาข้อ 2/3/4 ของ §4.3 ขยายความพร้อมสาเหตุ
- login คือ `POST /wbw/auth/login` ด้วย **`username`** ไม่ใช่ `student_id`
- `cacheNamespace` — cache ทุกตัวต้องแยกตาม backend และทำไมมันอยู่คนละไฟล์กับ `Config.swift`
- flag `Config.forest3D = false` / `Config.map3D = true` — ปิดแล้วเกิดอะไร
  (`ForestSceneHost.shouldClaim`, `Map3DScreen.shouldRender`) และทำไมตั้งค่าต่างกัน
- ชี้ `docs/backend-contract.md` (ช่องทางบอกความต้องการฝั่ง backend ให้ Yion) และ
  `docs/sus-test-backend.md` — **SUS แก้เองได้ ไม่ใช่ของต้องห้าม** ถามก่อนว่าจะแก้ตรงหรือส่ง contract

### 5.3 `ui-conventions.md`

- สีธีมที่มี: `wbwCream`, `wbwInk`, `wbwGold`, `wbwGreen`, `wbwForestVoid` — ใช้ของที่มี
  ห้ามหว่าน hex ใหม่ในจอเดียว
- Liquid Glass: `glassSurface(_:)` ใน `WBW/GlassSurface.swift` + `GlassRing`, guard
  `#available(iOS 26.0, *)`, fallback `.ultraThinMaterial` — target คือ iOS 18 ห้ามปลอม
- Figma DOI-APP เป็นต้นทาง UI; จอ SU RUN / Ranking ยังเป็น mock (`SURunMock.swift`)
- คอมเมนต์ภาษาไทย เขียน "ทำไม" ไม่ใช่ "ทำอะไร" — ยกของจริงจาก `project.yml` §configs
  และหัว `BackendCacheKey.swift` เป็นตัวอย่างที่ดี
- จอใหม่วางที่ไหน: ไฟล์เดี่ยวที่ราก `WBW/`, แตกโฟลเดอร์เมื่อฟีเจอร์มีมากกว่า ~3 ไฟล์

### 5.4 `workflow.md`

- วงจร spec → plan → TDD: `docs/superpowers/specs/YYYY-MM-DD-<หัวข้อ>-design.md`
  แล้ว `docs/superpowers/plans/YYYY-MM-DD-<หัวข้อ>.md` (มีของจริง 10 คู่ให้ดูเป็นแบบ)
  · สเปกที่ถูกแทนแล้วต้องเติมสถานะไว้หัวไฟล์ ไม่ทิ้งสองใบสั่งขัดกัน
- เทส **XCTest ล้วน** (20/20 ไฟล์) ตั้งชื่อ `<Thing>Tests.swift`, assert มีข้อความไทย
  บอกเหตุผล — จะเอา Swift Testing เข้ามาต้องคุยก่อน
- commit: conventional prefix + สรุปไทย เช่น `feat(map): จุดตำแหน่งผู้ใช้บนแผนที่ 3D`
- `git add` ทีละไฟล์ · ตรวจ `git status` ก่อน commit เสมอ
- ก่อนบอกว่าเสร็จ: build ผ่าน + test ผ่าน + (ถ้าเป็นงาน UI) มีสกรีนช็อตจาก sim

## 6. `CLAUDE.md`

สั้น ๆ ที่รากโปรเจกต์: repo นี้คืออะไร (iOS frontend ของ WBW, SwiftUI + XcodeGen,
backend คือ SUS) + บรรทัดบังคับ **"ก่อนออกแบบหรือเขียนโค้ดใน repo นี้ ให้อ่าน
`.claude/skills/wbw-ios/SKILL.md` ก่อน"** ไม่ใส่รายละเอียดอื่นเพื่อไม่ให้มีสองแหล่งที่ต้องแก้คู่กัน

## 7. กติกาความถูกต้องของเนื้อหา

- ทุกข้อความในทั้ง 5 ไฟล์ต้อง **ยืนยันได้จาก repo ตอนเขียน** — path มีจริง, ชื่อ symbol
  มีจริง, คำสั่งรันผ่านจริง ห้ามเดาและห้ามลอกจาก memory โดยไม่เช็คไฟล์
- ข้อไหนพิสูจน์ไม่ได้ ณ ตอนเขียน ให้ **ตัดออก** ไม่ใช่เขียนแบบกำกวม
- **ข้อยกเว้นเดียว: หัวข้อ "เครื่องจริง" ใน `build-and-run.md`** — พิสูจน์ซ้ำตอนนี้ไม่ได้
  เพราะต้องมีเครื่องเสียบ ให้เขียนพร้อมกำกับ "รันจริงล่าสุด 2026-08-03" ทุกย่อหน้า
  ผู้อ่านจะได้รู้ว่าเป็นบันทึก ไม่ใช่ของที่เช็คแล้ววันนี้
- ห้ามก๊อปเนื้อ `docs/*.md` มาซ้ำ — ชี้ path แทน (เอกสารเดิมจะได้ไม่แตกกับ skill)

## 8. วิธียืนยันว่าใช้ได้ (ต้องทำก่อนบอกว่าเสร็จ)

1. ทุก path ที่ skill อ้าง มีอยู่จริง (เช็คด้วย script/ls ทีละอัน)
2. ทุกชื่อ symbol ที่อ้าง (`glassSurface`, `cacheNamespace`, `shouldClaim`,
   `shouldRender`, args `-uitest*`) `grep` เจอในโค้ดจริง
3. คำสั่ง build และ test ใน `build-and-run.md` **รันจริงหนึ่งรอบ** และผ่าน
4. คำสั่งลง+รัน sim รันจริงหนึ่งรอบแล้วเก็บสกรีนช็อตเป็นหลักฐาน — ถ้าไม่มี JWT สด
   ก็ยิงแค่ `-uitestTab 1` ได้ (จะเห็นจอ login) พอพิสูจน์ว่าเส้นทาง install/launch ใช้ได้
   ไม่ต้องไปหา token ให้เสียเวลา
5. frontmatter ถูกฟอร์แมต (`name`, `description`, `allowed-tools`) และ `name` ตรงกับชื่อ
   โฟลเดอร์ — ส่วนที่ว่า Claude Code เห็น skill จริงมั้ย ยืนยันได้เฉพาะใน session ถัดไป
   ให้บอก Park ไว้ ไม่ใช่เคลมเอง

## 9. ความเสี่ยง

**skill เน่าตามโค้ด** — ความเสี่ยงหลัก ป้องกันสองชั้น: (ก) เนื้อหาเน้น "กติกา + ที่อยู่ของ
ของ" มากกว่าลอกโค้ดมาแปะ ของที่เปลี่ยนบ่อย (ตัวเลข IP, ค่า `Config.backend` ปัจจุบัน)
ไม่เขียนลงไป (ข) `workflow.md` มีบรรทัดสั่งว่า ถ้างานไหนทำให้กติกาใน skill ผิด
ให้แก้ skill ในคอมมิตเดียวกับงานนั้น

**ยาวไปจนไม่มีใครอ่าน** — คุมด้วยเพดานบรรทัดใน §3 SKILL.md ห้ามเกิน ~180 บรรทัด

## 10. ไม่รวมในงานนี้

- skill ของ SUS backend
- ก๊อป skill ตัวอย่าง (`server-side-swift`, `xcode-cloud`) เข้ามา
- hook, subagent, slash command
- แก้โค้ดแอปหรือ `docs/*.md` เดิม
- ตัดสินใจว่าจะเก็บ `claude-code-server-side-swift-skills/` ที่ clone วางไว้ต่อหรือลบ
  (เป็นของนอก repo ค่อยคุยแยก)
