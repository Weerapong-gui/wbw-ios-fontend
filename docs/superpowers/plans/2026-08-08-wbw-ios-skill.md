# skill ประจำ repo `wbw-ios` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** สร้าง skill `.claude/skills/wbw-ios/` (SKILL.md + ไฟล์อ้างอิง 4 ไฟล์) กับ `CLAUDE.md` ที่ราก เพื่อให้ session ใหม่อ่านกติกาของ repo นี้ได้ก่อนออกแบบหรือเขียนโค้ด

**Architecture:** เขียนไฟล์อ้างอิงทั้ง 4 ก่อน (แต่ละไฟล์จบในตัว ตรวจข้อเท็จจริงจาก repo ก่อนเขียนทุกไฟล์) แล้วค่อยเขียน `SKILL.md` เป็นประตูเดียวที่ชี้ไปหาไฟล์เหล่านั้น ปิดท้ายด้วย `CLAUDE.md` ที่ชี้มาที่ `SKILL.md` และการยืนยันด้วยการรันจริง

**Tech Stack:** markdown ล้วน · ไม่มีโค้ด Swift เปลี่ยน · เครื่องมือยืนยัน: `grep`, `ls`, `xcodegen`, `xcodebuild`, `xcrun simctl`

**สเปก:** `docs/superpowers/specs/2026-08-08-wbw-ios-skill-design.md`

## Global Constraints

- **ห้ามแตะโค้ดแอปหรือเทส** — งานนี้สร้างเฉพาะ `.claude/skills/wbw-ios/*` และ `CLAUDE.md` ห้ามแก้ไฟล์ใน `WBW/`, `WBWTests/`, `project.yml` หรือ `docs/*.md` ที่มีอยู่แล้ว
- **ทุกข้อความต้องยืนยันได้จาก repo ตอนเขียน** — path มีจริง, symbol `grep` เจอ, คำสั่งรันผ่านจริง ข้อไหนพิสูจน์ไม่ได้ให้ตัดออก ห้ามเขียนกำกวม
- **ข้อยกเว้นเดียว:** หัวข้อ "รันบนเครื่องจริง" ใน `build-and-run.md` มาจากบันทึกการรัน ต้องกำกับข้อความ `รันจริงล่าสุด 2026-08-03 (iPhone 13 ต่อ SUS local)` ไว้ที่หัวหัวข้อ
- **ไม่ก๊อปเนื้อ `docs/*.md` มาซ้ำ** — ชี้ path แทน
- **เพดานความยาว:** `SKILL.md` ≤ 180 บรรทัด · `build-and-run.md` ≤ 160 · `backend-and-config.md` ≤ 140 · `ui-conventions.md` ≤ 110 · `workflow.md` ≤ 120 · `CLAUDE.md` ≤ 12
- **ภาษาไทย** ทั้งหมด ยกเว้นคำสั่ง/ชื่อ symbol/ชื่อไฟล์
- **`git add` ทีละไฟล์เสมอ ห้าม `git add -A`** — repo มีของที่ยังไม่ commit ของงานอื่นวางอยู่ (`claude-code-server-side-swift-skills/` untracked อยู่ตอนนี้ ห้าม stage)
- commit message: conventional prefix + สรุปไทย

---

### Task 1: `backend-and-config.md`

**Files:**
- Create: `.claude/skills/wbw-ios/backend-and-config.md`

**Interfaces:**
- Consumes: ไม่มี (ทาสก์แรก)
- Produces: หัวข้อ `## Backend มีอะไรบ้าง`, `## กับดักที่เคยเสียเวลาจริง`, `## flag ปิด/เปิดฉาก` — Task 5 จะลิงก์ถึงชื่อไฟล์นี้ในสารบัญ

- [ ] **Step 1: ตรวจข้อเท็จจริงก่อนเขียน**

```bash
sed -n '1,60p' WBW/Config.swift
sed -n '1,25p' WBW/BackendCacheKey.swift
grep -n "auth/login" WBW/APIClient.swift
grep -rn "shouldClaim\|shouldRender" WBW --include='*.swift' | grep "static func"
ls docs/backend-contract.md docs/sus-test-backend.md
```

คาดว่าเห็น: `Backend` 5 case (`prodNode`, `nodeLocal`, `susLocal`, `susProd`, `susLan`), `mePath` แยก `/auth/me` กับ `/me`, `cacheNamespace` ใน `BackendCacheKey.swift`, `APIClient.swift:21` ยิง `\(Config.apiBase)/auth/login` โดยส่งคีย์ `"username"`, `ForestSceneHost.shouldClaim` กับ `Map3DScreen.shouldRender` เป็น `nonisolated static func`, และ docs สองไฟล์มีอยู่จริง

ถ้าอันไหนไม่ตรง **หยุดแล้วรายงาน** อย่าเขียนตามแผนทับของจริง

- [ ] **Step 2: เขียนไฟล์**

โครงที่ต้องมี (เขียนเป็นภาษาไทย ≤ 140 บรรทัด):

1. `# backend กับ Config — WBW iOS` + ประโยคเดียวว่าไฟล์นี้ตอบอะไร
2. `## Backend มีอะไรบ้าง` — ตาราง 3 คอลัมน์ `case | apiBase | mePath` ครบ 5 แถวตามค่าที่อ่านได้จริงใน Step 1 พร้อมหมายเหตุว่า `susLan` คือ IP ของ Mac ในวง LAN ที่เปลี่ยนทุกครั้งที่ย้ายเน็ต (`ipconfig getifaddr en0`)
3. `## กับดักที่เคยเสียเวลาจริง` — 4 ข้อ ข้อละ 2–4 บรรทัด:
   - **ห้ามลบ `case susLan`** — `BackendCacheKey.cacheNamespace` กับเทสอีกสองไฟล์ `switch` ครบทุก case ลบแล้ว clone ใหม่ build ไม่ผ่าน สิ่งที่แก้เฉพาะเครื่องคือ **เลข IP** ไม่ใช่ตัว case
   - **`Config.backend` เป็นบรรทัดที่ห้าม commit ตอนสลับไปทดสอบ** — ค่าที่อยู่ใน repo คือค่าที่จะส่งขึ้น store `git add` ทีละไฟล์เสมอ (นี่คือเหตุผลที่ `cacheNamespace` ถูกแยกออกมาไว้คนละไฟล์)
   - **สลับ backend แล้วต้องล้างข้อมูลแอป** — cursor แชท/cache ไม่ผูกกับ backend ที่มันมาจาก แต่ละ backend เดิน id แยกกัน อาการคือได้ 200 พร้อมลิสต์ว่างตลอด ไม่มี error ไม่มี log · รายละเอียด `docs/sus-test-backend.md`
   - **login ใช้คีย์ `username`** ไม่ใช่ `student_id` (`WBW/APIClient.swift`) ต่อให้ค่าที่ใส่เป็นรหัสนักศึกษาก็ตาม
4. `## flag ปิด/เปิดฉาก` — `Config.forest3D = false` (ทุกจอที่เรียก `.forestBackground()` ได้พื้นทึบ `Color.wbwForestVoid`, `ForestSceneView`/`ForestOverlay` ไม่ถูก mount — ดู `ForestSceneHost.shouldClaim`) และ `Config.map3D = true` (ปิดแล้วแท็บ Map เป็นการ์ดข้อความ ไม่โหลด `map.usdz` — ดู `Map3DScreen.shouldRender`) + ประโยคว่าทำไมตั้งต่างกัน: ฉากป่าถูกปิดจากอาการที่ยังไม่ได้วัด ส่วนแผนที่ยังไม่ถูกวัดจึงเปิดไว้ก่อน
5. `## จะแก้ฝั่ง backend` — SUS อยู่ที่ `/Users/park/Student-Union-Server` Park ร่วมเป็นเจ้าของ **แก้ได้ ไม่ใช่ของต้องห้าม** สองทางเลือกคือแก้ SUS ตรง ๆ หรือเขียนความต้องการลง `docs/backend-contract.md` ให้ Yion — **ถามก่อน อย่าเดาเอง**

- [ ] **Step 3: ตรวจว่าไฟล์ไม่มีข้ออ้างที่พิสูจน์ไม่ได้**

```bash
wc -l .claude/skills/wbw-ios/backend-and-config.md
for s in cacheNamespace shouldClaim shouldRender wbwForestVoid forestBackground; do
  printf '%s: ' "$s"; grep -rl "$s" WBW --include='*.swift' | head -1
done
grep -o 'docs/[a-z0-9./-]*\.md' .claude/skills/wbw-ios/backend-and-config.md | sort -u | xargs ls
```

Expected: จำนวนบรรทัด ≤ 140 · ทุก symbol เจอไฟล์ · ทุก path ที่อ้างมีอยู่จริง (`ls` ไม่ error)

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/wbw-ios/backend-and-config.md
git commit -m "docs(skill): backend กับ Config — ตาราง 5 case และกับดักที่เคยเสียเวลาจริง"
```

---

### Task 2: `build-and-run.md`

**Files:**
- Create: `.claude/skills/wbw-ios/build-and-run.md`

**Interfaces:**
- Consumes: ไม่มี
- Produces: หัวข้อ `## build`, `## รันบน simulator`, `## launch args`, `## รันบนเครื่องจริง` — Task 5 ยกคำสั่ง build/test/launch จากไฟล์นี้ไปไว้ในบล็อก "คำสั่งเร็ว" ของ `SKILL.md` แบบย่อ (ต้องเป็นคำสั่งเดียวกันเป๊ะ)

- [ ] **Step 1: ตรวจข้อเท็จจริงก่อนเขียน**

```bash
grep -n "xcodeproj" .gitignore
git ls-files WBW.xcodeproj | wc -l
grep -rn "uitest" WBW --include='*.swift' | grep -o 'forKey: "[a-zA-Z]*"' | sort -u
grep -n "uitestToken\|uitestUser\|uitestRole" WBW/Session.swift
sed -n '33,44p' project.yml
xcrun simctl list devices available | grep "iPhone 17 ("
```

Expected: `WBW.xcodeproj/` ถูก ignore และ `git ls-files` ได้ 0 · คีย์ `uitest*` ที่โค้ดอ่านจริง (`uitestTab`, `uitestChat`, `uitestChatCloseAfter`, `uitestNotifications`, `uitestFeedback`, `uitestTabSequence` และใน `Session.swift` มี `uitestToken`/`uitestUser`/`uitestRole`) · `project.yml` แยก Debug/Release ที่ `INFOPLIST_FILE` + `CODE_SIGN_ENTITLEMENTS` · มี sim ชื่อ `iPhone 17`

**เขียนเฉพาะคีย์ที่ `grep` เจอ** ถ้าคีย์ไหนในแผนนี้ไม่โผล่ ตัดทิ้งแล้วบอกไว้ในรายงาน

- [ ] **Step 2: เขียนไฟล์**

โครงที่ต้องมี (≤ 160 บรรทัด):

1. `# build / รัน / เก็บสกรีนช็อต` + ประโยคเดียวว่าไฟล์นี้ตอบอะไร
2. `## XcodeGen มาก่อนเสมอ` — `WBW.xcodeproj/` อยู่ใน `.gitignore` (`git ls-files` ได้ 0 ไฟล์) `project.yml` คือของจริง เพิ่ม/ลบ/ย้ายไฟล์ใน `WBW/` แล้วต้อง `xcodegen generate` ก่อน build ห้ามแก้ xcodeproj ด้วยมือ
3. `## build` — สามคำสั่งพร้อมบอกว่าใช้ตอนไหน:

```bash
xcodegen generate
xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme WBW -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build      # แค่เช็คว่า compile ผ่าน ไม่ต้องมี sim
xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

4. `## รันบน simulator` — ลำดับ: หา `BUILT_PRODUCTS_DIR` → `simctl install booted` → `simctl launch booted th.ac.mfu.wbwSwift` → `simctl io booted screenshot <path>` (เขียนเป็นคำสั่งจริงที่ก๊อปไปวางได้)
5. `## launch args` — ตารางคีย์ที่โค้ดรองรับจริง (จาก Step 1) พร้อมค่าที่รับ: `-uitestToken <jwt>`, `-uitestUser <username>`, `-uitestRole participant`, `-uitestTab 0-4`, `-uitestChat`, `-uitestChatCloseAfter <วินาที>`, `-uitestNotifications`, `-uitestFeedback <checkpointId>`, `-uitestTabSequence` + ตาราง index แท็บ `0 Home / 1 Map / 2 SU RUN / 3 Group / 4 QR` + ประโยคว่า **ไม่มี tooling กดจอ (ไม่มี idb)** args พวกนี้จึงเป็นทางเดียวที่จะเห็นจอชั้นในแบบไม่ต้องกดมือ
6. `## รันบนเครื่องจริง (รันจริงล่าสุด 2026-08-03 — iPhone 13 ต่อ SUS local)` — 4 ข้อ ข้อละ 1–3 บรรทัด: ต้องปลดล็อกเครื่องแล้วกด Trust ก่อน ไม่งั้นไม่มีอะไรทำงาน · `devicectl device process launch --device <id> --console <bundle> -- -uitestToken <jwt>` — **ไม่มี `--` อาร์กิวเมนต์โดน `-t` (timeout) กิน** และ `--console` คือสิ่งที่ทำให้เห็น log · container SUS publish แค่ `127.0.0.1` ต้อง forward ออก LAN ก่อน (ดู `docs/sus-test-backend.md`) · `-uitestToken` ชนะเฉพาะตอนติดตั้งใหม่ ถ้าแอปมี session เก็บไว้แล้วมันจะใช้ของเดิมโดยไม่เตือน
7. `## ทำไม Debug/Release แยก plist กับ entitlements` — `aps-environment` ผิดฝั่ง = push ไม่มาสักอันโดยไม่มี error ให้เห็น และ `Info-Debug.plist` มีคีย์วง LAN ที่ห้ามหลุดขึ้น store (อ้างคอมเมนต์ใน `project.yml`)

- [ ] **Step 3: รันคำสั่ง build จริงหนึ่งรอบ**

```bash
xcodegen generate && xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **` — ถ้าไม่ผ่าน **หยุด** แล้วรายงาน อย่าแก้โค้ดแอปเพื่อให้ผ่าน (นอกขอบเขตงานนี้)

- [ ] **Step 4: รันคำสั่ง test จริงหนึ่งรอบ**

```bash
xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: ลง+รันบน sim แล้วเก็บสกรีนช็อต**

```bash
APP=$(xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' -showBuildSettings 2>/dev/null \
  | awk -F'= ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)/WBW.app
xcrun simctl install booted "$APP"
xcrun simctl launch booted th.ac.mfu.wbwSwift -uitestTab 1
xcrun simctl io booted screenshot /private/tmp/wbw-skill-verify.png   # หรือ scratchpad ของ session
```

Expected: `install` เงียบ · `launch` คืน pid · ไฟล์ png เกิดขึ้น (ไม่ต้องมี JWT — เห็นจอ login ก็พอพิสูจน์ว่าเส้นทาง install/launch ใช้ได้) ถ้าไม่มี sim booted ให้ `xcrun simctl boot 'iPhone 17'` ก่อน

- [ ] **Step 6: แก้ไฟล์ให้ตรงกับสิ่งที่รันจริง**

ถ้าคำสั่งไหนใน Step 3–5 ต้องปรับถึงจะผ่าน ให้แก้คำสั่งในไฟล์ให้ตรงกับตัวที่ผ่านจริง แล้ว `wc -l` ต้อง ≤ 160

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/wbw-ios/build-and-run.md
git commit -m "docs(skill): build/รัน/สกรีนช็อต — คำสั่งที่รันผ่านจริงและ launch args ที่โค้ดรองรับ"
```

---

### Task 3: `ui-conventions.md`

**Files:**
- Create: `.claude/skills/wbw-ios/ui-conventions.md`

**Interfaces:**
- Consumes: ไม่มี
- Produces: หัวข้อ `## สีธีม`, `## Liquid Glass`, `## ไฟล์ใหม่วางที่ไหน`, `## คอมเมนต์`

- [ ] **Step 1: ตรวจข้อเท็จจริงก่อนเขียน**

```bash
sed -n '63,73p' WBW/Config.swift
sed -n '1,20p' WBW/GlassSurface.swift
grep -rn "GlassRing" WBW --include='*.swift' | head -5
grep -rn "available(iOS 26" WBW --include='*.swift'
ls WBW/Map3D WBW/Chat WBW/Feedback WBW/Scene3D WBW/Resources
grep -rn "MOCK\|Mock" WBW/SURunMock.swift | head -3
```

Expected: สี 5 ตัว (`wbwCream`, `wbwInk`, `wbwGold`, `wbwGreen`, `wbwForestVoid`) · `func glassSurface<S: Shape>(_ shape: S, interactive: Bool = false)` ใน `GlassSurface.swift` · `GlassRing` เป็น `private struct` อยู่ใน `HomeView.swift` (ไม่ใช่ API กลาง — เขียนให้ตรงตามนี้) · `#available(iOS 26.0, *)` โผล่ 3 ที่ · จำนวนไฟล์ต่อโฟลเดอร์ตามที่เห็นจริง

- [ ] **Step 2: เขียนไฟล์**

โครง (≤ 110 บรรทัด):

1. `# ธรรมเนียม UI`
2. `## สีธีม` — ตาราง ชื่อ/hex/ใช้ทำอะไร ครบ 5 ตัวจาก `WBW/Config.swift` + กติกา "ใช้ของที่มี ห้ามหว่าน hex ใหม่ในจอเดียว"
3. `## Liquid Glass` — `glassSurface(_:interactive:)` ใน `WBW/GlassSurface.swift` คือตัวกลางที่ใช้ซ้ำได้ · `GlassRing` เป็น `private` อยู่ใน `HomeView.swift` จะใช้ที่อื่นต้องยกออกมาก่อน · ทุกที่ guard `#available(iOS 26.0, *)` แล้ว fallback `.ultraThinMaterial` เพราะ deployment target คือ iOS 18 · **ห้ามปลอมกระจกด้วย blur เอง**
4. `## ไฟล์ใหม่วางที่ไหน` — จอเดี่ยววางแบน ๆ ที่ราก `WBW/` แตกโฟลเดอร์เมื่อฟีเจอร์เกิน ~3 ไฟล์ พร้อมของจริงที่มีอยู่: `Map3D/`, `Chat/`, `Feedback/`, `Scene3D/` (ปิดอยู่แต่ไม่ได้ลบ), `Resources/` (usdz)
5. `## จอที่ยังเป็น mock` — SU RUN / SU RUN Ranking กินข้อมูลจาก `WBW/SURunMock.swift` ยังไม่มี backend จริง อย่าเผลออ่านว่าเป็นของเสร็จแล้ว
6. `## คอมเมนต์` — ภาษาไทย เขียน "ทำไม" ไม่ใช่ "ทำอะไร" + ยกตัวอย่างของจริง 1 อัน (บล็อกคอมเมนต์ `configs:` ใน `project.yml` หรือหัว `BackendCacheKey.swift`) พร้อมบอกว่าทำไมมันดี: บอกอาการที่จะเกิดถ้าทำผิด
7. `## ต้นทาง UI` — Figma DOI-APP (ไฟล์ `EKkcnLzTFz8zGjtO8ay70U`)

- [ ] **Step 3: ตรวจ**

```bash
wc -l .claude/skills/wbw-ios/ui-conventions.md
grep -o '`WBW/[A-Za-z0-9/+._-]*`' .claude/skills/wbw-ios/ui-conventions.md | tr -d '`' | sort -u | xargs ls -d
grep -c "glassSurface" .claude/skills/wbw-ios/ui-conventions.md
```

Expected: ≤ 110 บรรทัด · ทุก path ที่อ้างมีจริง · พูดถึง `glassSurface` อย่างน้อย 1 ครั้ง

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/wbw-ios/ui-conventions.md
git commit -m "docs(skill): ธรรมเนียม UI — สีธีม Liquid Glass และที่วางไฟล์จอใหม่"
```

---

### Task 4: `workflow.md`

**Files:**
- Create: `.claude/skills/wbw-ios/workflow.md`

**Interfaces:**
- Consumes: ไม่มี
- Produces: หัวข้อ `## วงจรงาน`, `## เทส`, `## commit`, `## ก่อนบอกว่าเสร็จ`, `## skill เน่าเมื่อไหร่`

- [ ] **Step 1: ตรวจข้อเท็จจริงก่อนเขียน**

```bash
ls docs/superpowers/specs docs/superpowers/plans
grep -rl "import XCTest" WBWTests | wc -l
grep -rl "import Testing" WBWTests | wc -l
git log --oneline -12 | cat
head -12 docs/superpowers/specs/2026-08-07-map3d-usdz-design.md
```

Expected: spec 10+ ไฟล์ / plan 10+ ไฟล์ ชื่อขึ้นต้นด้วยวันที่ · XCTest 20 ไฟล์ / Swift Testing 0 ไฟล์ · commit เป็น conventional prefix + สรุปไทย · หัวสเปกมีบรรทัด `Status:` และมีการอ้างสเปกที่ถูกแทนที่

- [ ] **Step 2: เขียนไฟล์**

โครง (≤ 120 บรรทัด):

1. `# วิธีทำงานใน repo นี้`
2. `## วงจรงาน` — brainstorm → spec `docs/superpowers/specs/YYYY-MM-DD-<หัวข้อ>-design.md` → plan `docs/superpowers/plans/YYYY-MM-DD-<หัวข้อ>.md` → ทำทีละ task แบบ TDD · สเปกที่ถูกแทนแล้วต้องเติมสถานะไว้หัวไฟล์ ไม่ทิ้งสองใบสั่งเรื่องเดียวกันคนละแบบ (ของจริง: `2026-07-31-map3d-glb-design.md` ถูกแทนด้วย `2026-08-07-map3d-usdz-design.md`)
3. `## เทส` — **XCTest ล้วน 20/20 ไฟล์** ตั้งชื่อ `<Thing>Tests.swift` วางใน `WBWTests/` · assert ควรมีข้อความไทยบอกเหตุผลว่าทำไมค่านั้นสำคัญ · จะเอา Swift Testing เข้ามาต้องคุยก่อน · logic ที่อยากเทสให้แยกเป็น `static func` บริสุทธิ์ (แบบ `Map3DCamera.clampPitch`, `ForestSceneHost.shouldClaim`) แทนที่จะฝังใน View
4. `## commit` — conventional prefix + สรุปไทย (ยกของจริง 2 บรรทัดจาก `git log`) · **`git add` ทีละไฟล์ ห้าม `git add -A`** เพราะ repo มักมีงานที่ยังไม่ commit ของงานอื่นวางอยู่ · ตรวจ `git status` ก่อน commit ทุกครั้ง · `Config.backend` ที่สลับไว้ทดสอบห้ามติดไปด้วย
5. `## ก่อนบอกว่าเสร็จ` — build ผ่าน + test ผ่าน + งาน UI ต้องมีสกรีนช็อตจาก sim · ห้ามเคลมจากการอ่านโค้ดอย่างเดียว
6. `## skill เน่าเมื่อไหร่` — ถ้างานไหนทำให้กติกาใน skill ผิด (เช่น ย้ายไฟล์ เปลี่ยนคำสั่ง build เพิ่ม/ลบ `Backend` case) **ให้แก้ไฟล์ skill ในคอมมิตเดียวกับงานนั้น** ไม่ปล่อยไว้ทีหลัง

- [ ] **Step 3: ตรวจ**

```bash
wc -l .claude/skills/wbw-ios/workflow.md
grep -o 'docs/superpowers/[a-z]*' .claude/skills/wbw-ios/workflow.md | sort -u | xargs ls -d
grep -c "git add -A" .claude/skills/wbw-ios/workflow.md
```

Expected: ≤ 120 บรรทัด · path มีจริง · มีข้อห้าม `git add -A` อย่างน้อย 1 ที่

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/wbw-ios/workflow.md
git commit -m "docs(skill): วิธีทำงาน — spec→plan→TDD, XCTest ล้วน, กติกา commit"
```

---

### Task 5: `SKILL.md` (ประตูเดียว)

**Files:**
- Create: `.claude/skills/wbw-ios/SKILL.md`

**Interfaces:**
- Consumes: ไฟล์อ้างอิงทั้ง 4 จาก Task 1–4 (ต้องมีอยู่แล้วตอนเขียนสารบัญ)
- Produces: `name: wbw-ios` ใน frontmatter — Task 6 อ้างชื่อและ path นี้ใน `CLAUDE.md`

- [ ] **Step 1: ตรวจว่าไฟล์อ้างอิงครบ**

```bash
ls .claude/skills/wbw-ios/
```

Expected: `backend-and-config.md`, `build-and-run.md`, `ui-conventions.md`, `workflow.md` ครบ 4 ไฟล์ (ยังไม่มี `SKILL.md`)

- [ ] **Step 2: เขียน frontmatter + เนื้อ**

frontmatter เป๊ะตามนี้:

```yaml
---
name: wbw-ios
description: WBW iOS app (SwiftUI, XcodeGen, backend SUS). ใช้ตอนแก้โค้ด build รัน หรือออกแบบฟีเจอร์ใน repo wbw-ios-fontend
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion]
---
```

เนื้อ 5 บล็อก (รวมทั้งไฟล์ ≤ 180 บรรทัด):

1. `## ตอนไหนใช้ skill นี้` — แตะไฟล์ใน `WBW/` หรือ `WBWTests/` · เพิ่มจอ/ฟีเจอร์ · build/รัน/เก็บสกรีนช็อต · แตะอะไรที่คุยกับ backend · จะออกแบบฟีเจอร์ใหม่
2. `## แผนที่โปรเจกต์` — SwiftUI, deployment target iOS 18.0, Swift 5, bundle `th.ac.mfu.wbwSwift`, team `NJL4K64JX5`, dependency เดียวคือ FirebaseMessaging · `WBW/` (จอหลักแบนที่ราก + โฟลเดอร์ฟีเจอร์ `Map3D/ Chat/ Feedback/ Scene3D/ Resources/`) · `WBWTests/` XCTest · `docs/` (spec/plan อยู่ `docs/superpowers/`) · `scripts/` สคริปต์ Blender ทำ asset ไม่ใช่ขั้น build
3. `## กติกาห้ามพลาด` — 8 ข้อ ข้อละ 1–2 บรรทัด ตามลำดับใน §4.3 ของสเปก: `xcodegen generate` หลังเพิ่ม/ลบไฟล์ · ห้ามลบ `case susLan` · `Config.backend` ห้าม commit ตอนสลับทดสอบ · สลับ backend ต้องล้างข้อมูลแอป · Liquid Glass ของ native เท่านั้น · ห้าม `git add -A` · ห้ามเคลมเสร็จโดยไม่ได้รัน · เทสก่อน + คอมเมนต์/commit ไทย
4. `## คำสั่งเร็ว` — build / test / install+launch อย่างละบรรทัด **ก๊อปคำสั่งจาก `build-and-run.md` มาแบบตรงตัว** (ต่างกันแม้ตัวอักษรเดียวถือว่าผิด) + บรรทัดชี้ว่ารายละเอียดอยู่ในไฟล์นั้น
5. `## อ่านต่อ` — สารบัญ 4 ไฟล์อ้างอิงพร้อมประโยคเดียวต่อไฟล์ + เอกสารที่มีอยู่แล้ว: `docs/backend-contract.md`, `docs/sus-test-backend.md`, `docs/superpowers/specs/`, `docs/superpowers/plans/`

- [ ] **Step 3: ตรวจ frontmatter กับความยาว**

```bash
head -6 .claude/skills/wbw-ios/SKILL.md
wc -l .claude/skills/wbw-ios/SKILL.md
```

Expected: บรรทัดแรกเป็น `---`, มี `name: wbw-ios` (ตรงกับชื่อโฟลเดอร์), `description:`, `allowed-tools:` แล้วปิดด้วย `---` · ทั้งไฟล์ ≤ 180 บรรทัด

- [ ] **Step 4: ตรวจว่าคำสั่งเร็วตรงกับ `build-and-run.md`**

```bash
grep -n "xcodebuild" .claude/skills/wbw-ios/SKILL.md
grep -n "xcodebuild" .claude/skills/wbw-ios/build-and-run.md
```

Expected: บรรทัด `xcodebuild` ที่โผล่ใน `SKILL.md` ต้องมีข้อความเหมือนกับใน `build-and-run.md` ทุกตัวอักษร ต่างเมื่อไหร่แก้ให้ตรงก่อนไปต่อ

- [ ] **Step 5: ตรวจว่าลิงก์ในสารบัญชี้ของที่มีจริง**

```bash
grep -o '[a-z0-9-]*\.md' .claude/skills/wbw-ios/SKILL.md | sort -u
ls .claude/skills/wbw-ios/
ls docs/backend-contract.md docs/sus-test-backend.md
```

Expected: ทุกชื่อไฟล์ที่ SKILL.md อ้าง มีอยู่จริงในโฟลเดอร์เดียวกันหรือใน `docs/`

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/wbw-ios/SKILL.md
git commit -m "docs(skill): SKILL.md ประตูเข้า — แผนที่โปรเจกต์ กติกาห้ามพลาด 8 ข้อ สารบัญ"
```

---

### Task 6: `CLAUDE.md` + ตรวจรวบทั้งชุด

**Files:**
- Create: `CLAUDE.md`

**Interfaces:**
- Consumes: `.claude/skills/wbw-ios/SKILL.md` จาก Task 5
- Produces: ของสุดท้ายของแผน

- [ ] **Step 1: เขียน `CLAUDE.md`**

เนื้อทั้งไฟล์ (≤ 12 บรรทัด) — เขียนแบบนี้ได้เลย:

```markdown
# wbw-ios-fontend

iOS frontend ของ WBW ("เดินรอบดอย") — SwiftUI, deployment target iOS 18,
โปรเจกต์ Xcode สร้างจาก `project.yml` ด้วย XcodeGen, backend คือ Student-Union-Server (SUS)

**ก่อนออกแบบหรือเขียนโค้ดใน repo นี้ ให้อ่าน `.claude/skills/wbw-ios/SKILL.md` ก่อน**
ในนั้นมีกติกาที่เคยพังจริงมาแล้ว (XcodeGen, `case susLan`, การสลับ backend,
Liquid Glass, `git add -A`) พร้อมสารบัญไปไฟล์อ้างอิงที่ลงรายละเอียด
```

- [ ] **Step 2: ตรวจรวบทั้งชุด — path ทุกอันที่ skill อ้าง มีจริง**

```bash
cd /Users/park/wbw-ios-fontend
grep -rhoE '`(WBW|WBWTests|docs|scripts|\.claude)/[A-Za-z0-9/+._-]*`' .claude/skills/wbw-ios/ CLAUDE.md \
  | tr -d '`' | sed 's:/$::' | sort -u | while read -r p; do
      [ -e "$p" ] || echo "MISSING: $p"
    done
```

Expected: ไม่มีบรรทัด `MISSING:` สักอัน — มีเมื่อไหร่ต้องแก้ให้ตรงหรือลบข้ออ้างนั้นทิ้ง

- [ ] **Step 3: ตรวจรวบ — symbol ทุกตัวที่อ้าง `grep` เจอในโค้ด**

```bash
for s in glassSurface cacheNamespace shouldClaim shouldRender clampPitch \
         wbwCream wbwInk wbwGold wbwGreen wbwForestVoid uitestTab uitestToken; do
  grep -rq "$s" .claude/skills/wbw-ios/ || continue
  grep -rq "$s" WBW --include='*.swift' && echo "ok: $s" || echo "BAD: $s ไม่มีในโค้ด"
done
```

Expected: ไม่มีบรรทัด `BAD:`

- [ ] **Step 4: ตรวจเพดานความยาว**

```bash
wc -l CLAUDE.md .claude/skills/wbw-ios/*.md
```

Expected: `CLAUDE.md` ≤ 12 · `SKILL.md` ≤ 180 · `build-and-run.md` ≤ 160 · `backend-and-config.md` ≤ 140 · `ui-conventions.md` ≤ 110 · `workflow.md` ≤ 120

- [ ] **Step 5: ตรวจว่าไม่ได้แตะของนอกขอบเขต**

```bash
git status --short
git diff --stat f3475a3..HEAD -- WBW WBWTests project.yml   # f3475a3 = คอมมิตสเปกของงานนี้
```

Expected: `git status` เห็นแค่ `CLAUDE.md` (untracked) กับ `claude-code-server-side-swift-skills/` (untracked อยู่ก่อนแล้ว **ห้าม stage**) · `git diff --stat` ตั้งแต่คอมมิตสเปกถึงตอนนี้ **ไม่มีบรรทัดออกมาเลย** (แปลว่าไม่ได้แตะโค้ดแอปหรือ `project.yml`) — `WBW.xcodeproj/` ที่ `xcodegen generate` สร้างทับใน Task 2 ถูก `.gitignore` อยู่แล้ว จึงไม่โผล่

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: CLAUDE.md ชี้ให้อ่าน skill wbw-ios ก่อนออกแบบหรือเขียนโค้ด"
```

- [ ] **Step 7: รายงานสิ่งที่ยืนยันไม่ได้เอง**

บอก Park ตรง ๆ ว่า: skill จะถูก Claude Code มองเห็นจริงหรือไม่ **ยืนยันได้เฉพาะใน session ถัดไป** (session นี้โหลดรายการ skill ไปตั้งแต่ต้นแล้ว) และหัวข้อ "รันบนเครื่องจริง" ใน `build-and-run.md` เป็นบันทึกจาก 2026-08-03 ไม่ได้รันซ้ำในงานนี้

---

## หมายเหตุการทำงาน

- ทำ Task 1–4 ก่อนแล้วค่อย Task 5 เพราะ `SKILL.md` ต้องชี้ของที่มีอยู่จริง
- Task 1, 3, 4 ไม่พึ่งกัน ทำขนานได้ถ้าอยาก · Task 2 กินเวลานานสุด (build + test + sim)
- ถ้าคำสั่ง build/test ไม่ผ่านเพราะโค้ดแอปพัง **ห้ามแก้โค้ดแอป** — หยุดแล้วรายงาน แล้วบันทึกในไฟล์ว่าคำสั่งไหนยังไม่ได้ยืนยัน
