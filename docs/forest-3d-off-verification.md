# ผลยืนยันการปิดฉากป่า 3D

- **วันที่:** 2026-08-07
- **Branch:** `feature/forest-3d-off`
- **แผน:** `docs/superpowers/plans/2026-08-07-forest-3d-off.md` (Task 5)
- **สเปก:** `docs/superpowers/specs/2026-08-07-forest-3d-off-design.md`

เอกสารนี้บันทึกสิ่งที่ **พิสูจน์แล้วด้วยของจริง** กับสิ่งที่ **ยังไม่ได้พิสูจน์** แยกกันให้ชัด
เทสยูนิตพิสูจน์ได้แค่ตรรกะของสวิตช์ ไม่ได้พิสูจน์ว่าจอออกมาหน้าตายังไงหรือเครื่องเบาลงจริงไหม

---

## 1. วิธีที่ใช้

Build ใหม่หมดลง DerivedData เปล่า (กันกับดักที่ `docs/forest-3d-verification.md` เคยเจอ —
สกรีนช็อตจาก DerivedData เก่าเคยยืนยันบั๊กที่แก้ไปแล้ว):

```bash
xcodegen generate
xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/wbw-forest-off clean build
xcrun simctl install booted /tmp/wbw-forest-off/Build/Products/Debug-iphonesimulator/WBW.app
```

จอที่ต้องมี session ใช้ `-uitestToken` กับ JWT จริงจาก production (`Config.backend = .susProd`):

```bash
curl -s -X POST "https://api.studentunion.social/wbw/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"6931900013","password":"<รหัส>"}'
```

**รหัสของบัญชีนี้ไม่ถูกบันทึกในรีโป** — เป็นบัญชีบน production ถามจาก Park

**บัญชี `6931900013` ถูกสมัครใหม่ลง production DB ตอน 2026-08-07 เพื่องานนี้โดยเฉพาะ**
(`user_id 2e462184-32b7-4a26-9a68-e15d3ac37e94`, role `participant`, ชื่อ Test ForestOff)
Park อนุมัติให้เขียนลง prod ก่อนยิง · บัญชีทดสอบเดิมทั้งสี่ใบใน `docs/sus-test-backend.md`
(`6931900001`, `6931900002`, `6931900011`, `6931900012`) **ไม่มีบน prod** — ถูกสร้างไว้บน SUS local
คนละฐานกัน ยิง login บน prod ได้ `{"error":"username หรือ password ไม่ถูกต้อง"}` ทุกใบ
ตารางในเอกสารนั้นควรถูกแก้ให้บอกว่าเป็นบัญชีของ local เท่านั้น

---

## 2. สิ่งที่แผนเขียนไว้ไม่ตรงกับของจริง

สามข้อนี้เจอตอนลงมือทำ Task 5 ไม่ใช่ข้อผิดพลาดของโค้ด แต่ทำให้คำสั่งในแผนใช้ตรงๆ ไม่ได้

1. **แผนบอกให้ถ่าย 5 จอ โดยจอที่ห้าคือ "แท็บ Event (ForestBlank)" ที่ `-uitestTab 1`**
   ของจริง `-uitestTab 1` คือแท็บ Map (MapLibre) และ `ForestBlank` (`MainTabView.swift:401`)
   **ไม่ถูกเรียกใช้จากที่ไหนแล้ว** — แท็บปัจจุบันคือ Home(0) · Map(1) · SU RUN(2) · Group(3) · QR(4)
   จอที่เรียก `.forestBackground()` จริงเหลือสี่: `WelcomeView`, `LoginView`, `HomeView`, `MyQRCodeView`
   (บวก `ForestBlank` ที่เป็นโค้ดตายอยู่)
2. **แผนบอกให้ถ่าย Welcome ที่ ~8 วินาที** ถ่ายตอนนั้นได้ Login แทน เพราะถ้ามี session ค้างอยู่
   `WelcomeView.task` จะ `onContinue()` เองหลัง 1.5 วินาที แล้ว prod ตอบ 401 ตกกลับมา Login
   ต้องถ่ายที่ ~2 วินาที · `xcrun simctl keychain booted reset` ไม่ได้ล้าง session ให้
3. **`-uitestToken` ต้องเป็น JWT จริง** ลองใส่ token ปลอมแล้วแอปเตะออกกลับหน้า Login
   ก่อน `HomeView` จะ mount ทุกครั้ง ถ่ายเร็วแค่ไหนก็ไม่ทัน

ป๊อปอัพ "เดินรอบดอย Would Like to Send You Notifications" ยังโผล่ทุกครั้งที่ติดตั้งใหม่
ตามข้อจำกัดเดิมที่ `docs/forest-3d-verification.md:61` บันทึกไว้ (สภาพแวดล้อมนี้ไม่มี tap tooling
`xcrun simctl privacy booted grant notifications` ตอบ `Operation not permitted` ส่วน osascript
โดน macOS บล็อก `osascript is not allowed to send keystrokes`) — รอบที่ใช้เป็นหลักฐานข้างล่าง
ถ่ายหลังป๊อปอัพหายไปแล้ว ทั้งสี่รูปสะอาด ไม่มีป๊อปอัพบัง

---

## 3. บั๊กที่การถ่ายรูปจับได้ และแก้ไปแล้ว

**อาการ:** แท็บ QR มีแถบขาวพาดเต็มความสูงที่ขอบซ้ายและขอบขวาจอ (พื้นทึบครอบแค่ ~74% กลางจอ)
และแท็บบาร์กระจกกลายเป็นสีขาวอมเทาแทนโทนเข้ม อยู่คงที่ ถ่ายซ้ำที่ 20 วินาทีก็ยังเหมือนเดิม
ไม่ใช่เฟรมค้างระหว่าง transition

**สาเหตุ:** Task 1 ตัด `TabRootOpaqueBackgroundRemover` ออกจากทางที่ฉากปิด พร้อมคอมเมนต์ที่ให้เหตุผลว่า
"ปิดฉากแล้วไม่มีอะไรอยู่หลังต้องโผล่ เพราะสีนี้ถูกวาดในกรอบของจอนั้นเอง" เหตุผลนั้นผิด —
แท็บ QR เป็น `Tab(value: 4, role: .search)` ของ iOS 26 ซึ่งวาง content ไว้ใน container ที่แคบกว่าจอ
พื้นทึบขาวของ per-tab `UIHostingController` (ที่คอมเมนต์ยาวใน `ForestSceneHost.swift:225` อธิบายไว้)
จึงยังโผล่ตรงส่วนที่พื้นทึบของจอเอื้อมไม่ถึง และ material ของแท็บบาร์ก็ไปสุ่มสีขาวนั้นมาใช้

**ทางแก้ (commit `89d971d`):** สองจุด

- `ForestSceneHost.swift` — คืน `TabRootOpaqueBackgroundRemover` ให้ทางที่ฉากปิดด้วย เหมือนทางฉากเปิด
- `RootView.swift` — วาด `Color.wbwForestVoid` ใต้ทุกอย่างตอน `!Config.forest3D` เป็นชั้นที่โผล่ขึ้นมา
  แทนรูที่ remover เจาะ (ชั้นเดียวกับที่ฉาก 3D เคยอยู่) ไม่มีชั้นนี้จะเห็นพื้นดำของหน้าต่างแทนขาว

**หลังแก้:** พื้นทึบเต็มจอ กรอบสแกนสี่มุมของ QR ที่เดิมถูกแถบขาวกลืนไปโผล่ครบ แท็บบาร์กลับเป็นโทนเข้ม

---

## 4. สกรีนช็อตทั้งสี่จอ (build หลังแก้)

ทุกจอถ่ายจาก build เดียวกันที่ `/tmp/wbw-forest-off` หลัง commit `89d971d`
พื้นทุกจอเป็นเขียวเกือบดำ `#0A1610` (`Color.wbwForestVoid`) เต็มจอ **ไม่มีจอไหนขาว ดำล้วน หรือโปร่งทะลุ**
และ **ไม่มีบรรทัดเครดิต "โมเดล 3 มิติ: …" ที่มุมล่างซ้ายจอไหนเลย** (`ForestOverlay` ไม่ถูก mount)

| จอ | launch args | สิ่งที่เห็น |
|---|---|---|
| Welcome | ไม่ส่ง arg (ถ่ายที่ ~2 วิ) | "Welcome to" + wordmark "Walk Beyond the Wild / ดันรอบดอย สานต่อรอยปณิธาน 69" ตัวขาวบนพื้นทึบ อ่านออกครบ |
| Login | ไม่ส่ง arg (ถ่ายที่ ~6 วิ) | "Hey, Welcome back" ตัวขาว · ช่องรหัสนักศึกษา/Password เป็นแคปซูลเทาโปร่ง placeholder อ่านออก · ปุ่ม Sign In สีทอง |
| Home | `-uitestToken <jwt> -uitestUser 6931900013 -uitestProgress 3` | "Hey!" + "Test" **ตัวขาว** · บรรทัด **"เช็คอินแล้ว 3/8 ฐาน"** อยู่ใต้ชื่อ · ไอคอนกระดิ่งขาวในวงแหวนกระจก · แท็บบาร์ลอยโทนเข้ม ไอคอน Home สีทอง |
| QR | `-uitestToken <jwt> -uitestTab 4` | "My QR Code" ตัวขาว · การ์ด QR ขาวกลางจอ · กรอบสแกนสี่มุมสีขาวครบทั้งสี่มุม · พื้นเต็มจอไม่มีแถบขาว |

**จอที่ไม่ได้อยู่ในงานนี้และยังเป็นพื้นครีมตามเดิม:** แท็บ Group (`GroupJoinView`) — หน้านั้นรอแผน
`2026-08-06-group-join-glass.md` ที่ยังไม่ implement ไม่ได้เรียก `.forestBackground()` จึงไม่เกี่ยวกับสวิตช์นี้

---

## 5. ไม่มีอะไรในสาย 3D ทำงานเลย

```bash
xcrun simctl spawn booted log stream --predicate 'process == "WBW"' > log.txt &
xcrun simctl launch booted th.ac.mfu.wbwSwift -uitestToken "$TOK" -uitestProgress 3
# รอ 18 วินาที
grep -ci "forest.usdz\|ForestSceneView\|realityio\|RealityKit" log.txt
```

ผล: **`0`** จาก log 473 บรรทัดของรอบที่เข้า Home
(รอบก่อนหน้าที่เข้าแค่ Welcome→Login ก็ได้ `0` จาก 398 บรรทัดเหมือนกัน)

ตรงกับที่สวิตช์ตั้งใจ: `claimScene()` ไม่ตั้ง `wantsScene` → `everEnabled` ค้าง `false` →
`RootView` ไม่ mount `ForestSceneView`/`ForestOverlay` → ไม่มี RealityKit, CoreMotion, TimelineView
และไม่มีการโหลด `forest.usdz`

---

## 6. เทสยูนิต

```
xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17'
** TEST SUCCEEDED **  Executed 141 tests, with 0 failures (0 unexpected)
```

รันสองรอบ: หลังจบ Task 4 และหลังแก้บั๊กข้อ 3 — ได้ 141 ผ่านทั้งคู่ ไม่มีเทสหาย
`ForestMathTests` กับ `GyroParallaxTests` ของฉากยังผ่าน แปลว่าโค้ดฉากยังคอมไพล์และทำงานได้ครบ
พร้อมเปิดกลับ

---

## 7. สิ่งที่ยังไม่ได้พิสูจน์ — และมันคือคำถามตั้งต้นของงานนี้

**ยังไม่มีตัวเลขจากเครื่องจริงสักตัว**

งานนี้เกิดขึ้นเพราะสมมติฐานว่า "เครื่องทำงานหนักเพราะฉากป่า 3D" ทุกอย่างข้างบนพิสูจน์ได้แค่ว่า
*ฉากถูกปิดสำเร็จและจอยังใช้งานได้* — ไม่มีข้อไหนพิสูจน์ว่าฉากคือตัวการของอาการหนักจริง
simulator วัดแทน iPhone ไม่ได้ (คนละสถาปัตยกรรม GPU ไม่มีเรื่องอุณหภูมิ/แบต)

สิ่งที่ต้องทำให้จบ (Park รับไปวัดเอง):

1. ติดตั้ง build ก่อนปิดฉาก (`git checkout 23ac258`) ลง iPhone จริง เปิดค้างที่ Home 5 นาที
   จด CPU จาก Xcode Debug Navigator + สังเกตอุณหภูมิเครื่อง
2. ติดตั้ง build ปัจจุบัน (`feature/forest-3d-off`) ทำแบบเดียวกัน 5 นาที จดค่าเดียวกัน
3. เติมตารางตัวเลขทั้งสองชุดลงหมวดนี้

| build | CPU เฉลี่ย 5 นาทีที่ Home | อุณหภูมิ/ความรู้สึก |
|---|---|---|
| ก่อนปิดฉาก (`23ac258`) | *ยังไม่วัด* | *ยังไม่วัด* |
| หลังปิดฉาก (`feature/forest-3d-off`) | *ยังไม่วัด* | *ยังไม่วัด* |

**ถ้าตัวเลขออกมาไม่ต่างอย่างมีนัย** แปลว่าฉากไม่ใช่ตัวการ และควรพิจารณาเปิดกลับด้วย
`Config.forest3D = true` แล้วไปหาสาเหตุจริงที่อื่น — ห้ามสรุปว่างานนี้แก้ปัญหาได้จนกว่าจะมีตัวเลขรองรับ

---

## 8. เปิดฉากกลับ

แก้ `Config.forest3D = true` ที่เดียว ทุกอย่างกลับมาเหมือนเดิม ยกเว้นสองอย่างที่เปลี่ยนถาวรโดยตั้งใจ:
หัวจอ Home เป็นตัวอักษรขาว (Task 2) และตัวเลขความคืบหน้าซ่อนตัวเองคืนหน้าที่ให้ต้นไม้ (Task 3)
