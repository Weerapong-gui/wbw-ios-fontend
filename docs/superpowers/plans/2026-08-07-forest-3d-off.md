# ปิดฉากป่า 3D ชั่วคราว — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ปิดฉากป่า 3D ทั้งสายด้วยค่าเดียวใน `Config.swift` แล้วให้ 5 จอที่ใช้ฉากได้พื้นทึบ `#0A1610` แทน โดยไม่ลบโค้ดหรือ asset ของฉากทิ้ง

**Architecture:** `ForestBackground` modifier (`WBW/Scene3D/ForestSceneHost.swift`) เป็นตัวกลางที่ 5 จอเรียกอยู่แล้ว สวิตช์ลงที่นั่นจุดเดียว — `claimScene()` ไม่ตั้ง `wantsScene` ทำให้ `enabled`/`everEnabled` ค้าง false และ `RootView.swift:40` ไม่ mount `ForestSceneView`/`ForestOverlay` เลย (ไม่มี RealityKit, CoreMotion, TimelineView) ส่วน `.background{}` ของ modifier วาดสีทึบแทน ไม่มีไฟล์จอไหนถูกแก้เพราะเรื่องพื้นหลัง

**Tech Stack:** Swift 5, SwiftUI, XCTest, XcodeGen (`project.yml` ผูก sources เป็นโฟลเดอร์ ไฟล์ใหม่เข้า target เองหลัง `xcodegen generate`)

**Spec:** `docs/superpowers/specs/2026-08-07-forest-3d-off-design.md`

## Global Constraints

- **ห้ามลบ** `WBW/Scene3D/` ทั้งโฟลเดอร์, `WBW/Resources/forest.usdz`, `WBW/Resources/tree.usdz`, `WBW/Resources/models/*.glb`, `scripts/bake-forest.py` และเทสของฉาก (`ForestMathTests`, `GyroParallaxTests`)
- **ห้ามลบ asset `bg_forest`** — path `loadFailed → Image("bg_forest")` ต้องอยู่ต่อสำหรับตอนเปิดฉากกลับ
- ไม่แตะ backend รีโปไหนเลย งานนี้อยู่ใน `wbw-ios-fontend` อย่างเดียว
- ไม่แตะแท็บ Map (`2026-07-31-map3d-glb-design.md` พักไว้)
- **ห้าม `git add -A` หรือ `git commit -a`** — repo นี้มีงานที่ยังไม่ commit ของคนอื่นวางอยู่ (เช่น `claude-code-server-side-swift-skills/`) ทุก commit ต้อง `git add <ไฟล์ที่ระบุ>` ตามที่เขียนไว้ในแต่ละ Task เท่านั้น
- คำสั่งเทสมาตรฐานของรีโป: `xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17'`
- app target เป็น test host ของ `WBWTests` ทุก `xcodebuild test` จึง boot แอปทั้งตัว — นี่คือเหตุผลที่ `isRunningUnderXCTest` มีอยู่ ห้ามถอด
- deployment target iOS 18.0, `SWIFT_VERSION: "5.0"`
- คอมเมนต์และข้อความในแอปเป็นภาษาไทย ตามของเดิมทั้งไฟล์

## File Structure

| ไฟล์ | สถานะ | หน้าที่ |
|---|---|---|
| `WBW/Config.swift` | แก้ | เพิ่ม `Config.forest3D` และสี `Color.wbwForestVoid` |
| `WBW/Scene3D/ForestSceneHost.swift` | แก้ | เพิ่ม `shouldClaim` · `claimScene()` เรียกใช้ · `ForestBackground.body` แตกสองทาง |
| `WBWTests/ForestSceneHostTests.swift` | สร้าง | เทส `shouldClaim` |
| `WBW/HomeView.swift` | แก้ | ตัวอักษรหัวจอเป็นขาว + ตัวเลขความคืบหน้า |
| `WBW/CheckinProgressLabel.swift` | สร้าง | ฟังก์ชันบริสุทธิ์ประกอบข้อความ "เช็คอินแล้ว x/y ฐาน" |
| `WBWTests/CheckinProgressLabelTests.swift` | สร้าง | เทสฟังก์ชันนั้น |
| `docs/superpowers/specs/2026-08-06-group-join-glass-design.md` | แก้ | เปลี่ยนพื้นหลังเป็นพื้นทึบ ตัดความเสี่ยงที่หายไป |
| `docs/superpowers/plans/2026-08-06-group-join-glass.md` | แก้ | ตามสเปกข้างบน |
| `docs/superpowers/specs/2026-08-02-forest-3d-background-design.md` | แก้ | เติมสถานะหัวไฟล์ว่าปิดใช้งานแล้ว |
| `docs/forest-3d-off-verification.md` | สร้าง | บันทึกผลยืนยันจริง (Task 5) |

---

### Task 1: สวิตช์ปิดฉาก + พื้นทึบ

**Files:**
- Modify: `WBW/Config.swift:44-47` (เพิ่มใน `enum Config`), `WBW/Config.swift:51-56` (เพิ่มใน `extension Color`)
- Modify: `WBW/Scene3D/ForestSceneHost.swift:91-99` (`claimScene()`), `WBW/Scene3D/ForestSceneHost.swift:153-166` (`ForestBackground.body`)
- Test: `WBWTests/ForestSceneHostTests.swift` (สร้างใหม่)

**Interfaces:**
- Consumes: ไม่มี (งานแรก)
- Produces:
  - `Config.forest3D: Bool` (static let, ค่า `false`)
  - `Color.wbwForestVoid: Color` (static let)
  - `ForestSceneHost.shouldClaim(forest3D: Bool, underTest: Bool) -> Bool` (nonisolated static)

- [ ] **Step 1: เขียนเทสที่ยังไม่ผ่าน**

สร้าง `WBWTests/ForestSceneHostTests.swift`:

```swift
import XCTest
@testable import WBW

/// สวิตช์ปิดฉากป่า 3D — ตรรกะเดียวที่ตัดสินว่าจอที่ขอฉากจะได้ฉากจริงไหม
/// (ดู docs/superpowers/specs/2026-08-07-forest-3d-off-design.md)
final class ForestSceneHostTests: XCTestCase {

    func testClaimsOnlyWhenForest3DOnAndNotUnderTest() {
        XCTAssertTrue(ForestSceneHost.shouldClaim(forest3D: true, underTest: false),
                      "ฉากเปิดและไม่ได้รันเทส — จอต้องได้ฉากจริง")
    }

    func testDoesNotClaimWhenForest3DOff() {
        XCTAssertFalse(ForestSceneHost.shouldClaim(forest3D: false, underTest: false),
                       "ฉากถูกปิดที่ Config.forest3D — ห้าม claim ไม่ว่ากรณีไหน")
    }

    func testDoesNotClaimUnderTestEvenWhenForest3DOn() {
        XCTAssertFalse(ForestSceneHost.shouldClaim(forest3D: true, underTest: true),
                       "เทสยูนิตรันในโปรเซสเดียวกับแอป โหลด usdz แล้ว exit() ทันทีจะ segfault")
    }

    func testDoesNotClaimWhenBothOff() {
        XCTAssertFalse(ForestSceneHost.shouldClaim(forest3D: false, underTest: true))
    }
}
```

- [ ] **Step 2: รันเทสให้เห็นว่าพัง**

Run: `xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WBWTests/ForestSceneHostTests`

Expected: FAIL — compile error `type 'ForestSceneHost' has no member 'shouldClaim'`

- [ ] **Step 3: เพิ่มค่าใน `Config.swift`**

ใน `enum Config` ต่อจาก `static var mePath` (บรรทัด 46):

```swift
    /// ฉากป่า 3D — ปิดชั่วคราว (เครื่องทำงานหนัก) เปิดกลับได้ที่ค่านี้ค่าเดียว
    ///
    /// ปิด = ทุกจอที่เรียก .forestBackground() ได้พื้นทึบ Color.wbwForestVoid แทน และ
    /// ForestSceneView/ForestOverlay ไม่ถูก mount เลยสักครั้ง (ดู ForestSceneHost.shouldClaim)
    /// โค้ดและ asset ของฉากยังอยู่ครบ ไม่ได้ถูกลบ
    static let forest3D = false
```

ใน `extension Color` ต่อจาก `wbwGreen` (บรรทัด 55):

```swift
    /// พื้นหลังทึบแทนฉากป่าตอน Config.forest3D ปิด — สีเดียวกับ scrim เดิมของ ForestOverlay
    static let wbwForestVoid = Color(red: 10 / 255, green: 22 / 255, blue: 16 / 255) // #0A1610
```

- [ ] **Step 4: เพิ่ม `shouldClaim` แล้วให้ `claimScene()` เรียกใช้**

ใน `WBW/Scene3D/ForestSceneHost.swift` แทรกเหนือ `claimScene()` (บรรทัด 91):

```swift
    /// จอขอฉากแล้วต้องให้จริงไหม — false = claimScene() ปล่อย token คืนเฉยๆ ไม่แตะ wantsScene
    ///
    /// `nonisolated` ไม่ใช่ของประดับ: คลาสนี้เป็น @MainActor ทั้งก้อน static member จึงเป็น
    /// main-actor isolated ตามไปด้วย เทสยูนิตจะเรียกไม่ได้ถ้าไม่ประกาศ (ฟังก์ชันนี้ไม่แตะ state ใดเลย)
    nonisolated static func shouldClaim(forest3D: Bool, underTest: Bool) -> Bool {
        forest3D && !underTest
    }
```

แล้วเปลี่ยน guard ใน `claimScene()` จาก:

```swift
        // เทสยูนิต (XCTest host) ไม่ต้องการฉากเลย — ดูคอมเมนต์ที่ isRunningUnderXCTest ด้านบนว่าทำไม
        // ปล่อยให้ wantsScene เป็น true ตอนนี้ถึงพังยังไง
        guard !Self.isRunningUnderXCTest else { return token }
```

เป็น:

```swift
        // สองเหตุผลที่จอขอฉากแล้วไม่ได้: Config.forest3D ปิดอยู่ (ฉากกินเครื่อง ดู spec
        // 2026-08-07-forest-3d-off-design.md) หรือกำลังรันเทสยูนิต (ดูคอมเมนต์ที่
        // isRunningUnderXCTest ด้านบนว่าปล่อยให้ wantsScene เป็น true ตอนนั้นถึงพังยังไง)
        guard Self.shouldClaim(forest3D: Config.forest3D,
                               underTest: Self.isRunningUnderXCTest) else { return token }
```

- [ ] **Step 5: รันเทสให้ผ่าน**

Run: `xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WBWTests/ForestSceneHostTests`

Expected: PASS — 4 tests, 0 failures

- [ ] **Step 6: ให้ `ForestBackground` วาดพื้นทึบตอนฉากปิด**

ใน `WBW/Scene3D/ForestSceneHost.swift` แทนที่ `.background { ... }` ทั้งก้อน (บรรทัด 155-166) ด้วย:

```swift
            .background {
                if Config.forest3D {
                    ZStack {
                        // ดูคอมเมนต์ที่ struct ด้านล่าง — ไม่มีนี่ ฉากป่าที่ RootView โดนบังทึบขาวเสมอ
                        TabRootOpaqueBackgroundRemover().frame(width: 1, height: 1).allowsHitTesting(false)
                        // โหลดฉากไม่ได้ → รูปเดิม · ห้ามลบ asset bg_forest ทิ้ง
                        if host.loadFailed {
                            Image("bg_forest").resizable().scaledToFill().ignoresSafeArea()
                        } else {
                            Color.clear   // ฉากจริงวาดอยู่ที่ RootView ใต้ทุกอย่าง
                        }
                    }
                } else {
                    // ฉาก 3D ปิดอยู่ — พื้นทึบสีเดียว รอรูปพื้นหลังที่จะเอามาทับทีหลัง
                    // ไม่ต้องมี TabRootOpaqueBackgroundRemover ตรงนี้: มันมีไว้เจาะพื้นทึบขาวของ per-tab
                    // UIHostingController ให้ฉากที่ RootView (คนละต้นไม้) โผล่ขึ้นมาได้ ปิดฉากแล้วไม่มีอะไร
                    // อยู่หลังต้องโผล่ เพราะสีนี้ถูกวาดในกรอบของจอนั้นเอง ซึ่งอยู่ต้นไม้เดียวกับจอ
                    Color.wbwForestVoid.ignoresSafeArea()
                }
            }
```

`.onAppear`/`.onDisappear`/`.onChange` ที่ตามมาไม่ต้องแก้เลยสักบรรทัด

- [ ] **Step 7: รันเทสทั้งชุดให้ผ่าน**

Run: `xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: PASS ทั้งหมด 0 failures · จำนวนเทสต้องเป็น "จำนวนก่อนเริ่ม Task 1 + 4" พอดี
(รันชุดเต็มก่อนแก้อะไรแล้วจดเลขไว้เทียบ) โดยเฉพาะ `ForestMathTests` และ `GyroParallaxTests`
ต้องยังผ่าน — โค้ดฉากยังคอมไพล์อยู่ครบ

- [ ] **Step 8: Commit**

```bash
git add WBW/Config.swift WBW/Scene3D/ForestSceneHost.swift WBWTests/ForestSceneHostTests.swift
git commit -m "feat(scene): สวิตช์ปิดฉากป่า 3D — พื้นทึบแทน ไม่ลบโค้ด

Config.forest3D = false ทำให้ claimScene() ไม่ตั้ง wantsScene → everEnabled
ค้าง false → RootView ไม่ mount ForestSceneView/ForestOverlay เลย ทั้ง RealityKit,
CoreMotion และ TimelineView จึงไม่ถูกสร้าง และไม่มีการโหลด forest.usdz

5 จอที่เรียก .forestBackground() ได้ Color.wbwForestVoid (#0A1610) แทน
โดยไม่ต้องแก้ไฟล์จอไหนเลย · เปิดฉากกลับได้ด้วยการกลับค่าเดียวนั้น"
```

---

### Task 2: ตัวอักษรหัวจอ Home เป็นสีขาว

**Files:**
- Modify: `WBW/HomeView.swift:43`, `WBW/HomeView.swift:46`, `WBW/HomeView.swift:55`

**Interfaces:**
- Consumes: `Color.wbwForestVoid` จาก Task 1 (แค่เป็นเหตุผล ไม่ได้เรียกใช้ในโค้ดนี้)
- Produces: ไม่มี symbol ใหม่

**ทำไมไม่มีเทส:** เป็นค่าสีในตัว view ล้วนๆ ไม่มีตรรกะให้เทส — ยืนยันด้วยสกรีนช็อตใน Task 5 ข้อ 1

- [ ] **Step 1: เปลี่ยนสามจุด**

`WBW/HomeView.swift:43` และ `:46` (ใน `VStack` คำทักทาย) เปลี่ยนทั้งสองบรรทัดจาก
`.foregroundStyle(Color.wbwInk)` เป็น `.foregroundStyle(.white)` ผลที่ได้:

```swift
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hey!")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white)
                    Text(name)
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(.white)
                }
```

`WBW/HomeView.swift:55` (ไอคอนกระดิ่ง) เปลี่ยนจาก `.foregroundStyle(Color.wbwInk)` เป็น
`.foregroundStyle(.white)` ผลที่ได้:

```swift
                    Image(systemName: "bell.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .modifier(GlassRing())
```

หลังแก้ครบ `grep -n "wbwInk" WBW/HomeView.swift` ต้องไม่คืนอะไรเลย

- [ ] **Step 2: แก้คอมเมนต์หัวไฟล์ให้ตรงความจริง**

`WBW/HomeView.swift:3` ตอนนี้เขียนว่า `/// หน้าหลัก (DOI-APP) — พื้นป่า 3D + คำทักทาย "Hey! <ชื่อ>" มุมซ้ายบน + ต้นไม้โตตามความคืบหน้าเช็คอินจริง`
เปลี่ยนเป็น:

```swift
/// หน้าหลัก (DOI-APP) — คำทักทาย "Hey! <ชื่อ>" มุมซ้ายบน บนพื้นหลังที่ .forestBackground() จัดให้
///
/// ตัวอักษรเป็นสีขาวเพราะพื้นหลังเป็นโทนเข้มเสมอ (พื้นทึบ #0A1610 ตอน Config.forest3D ปิด
/// หรือฉากป่า 3D ตอนเปิด) — ไม่ผูกกับ flag เพราะขาวอ่านออกทั้งสองโหมด
struct HomeView: View {
```

- [ ] **Step 3: build ให้ผ่าน**

Run: `xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: PASS ทั้งหมด 0 failures · จำนวนเทสเท่ากับตอนจบ Task 1 เป๊ะ — งานนี้ไม่เพิ่มเทส

- [ ] **Step 4: Commit**

```bash
git add WBW/HomeView.swift
git commit -m "fix(home): หัวจอเป็นตัวอักษรขาว — wbwInk มองไม่เห็นบนพื้นเข้ม

wbwInk (#2B2B2B) เดิมอ่านออกเพราะข้างหลังเป็นท้องฟ้าสว่างของฉาก 3D พอฉากถูกปิด
พื้นเป็น #0A1610 ตัวอักษรเทาเข้มบนเขียวเกือบดำแทบมองไม่เห็น เปลี่ยนเป็นขาวถาวร
ไม่ผูกกับ Config.forest3D เพราะขาวอ่านออกทั้งสองโหมด และตรงกับอีก 4 จอที่ใช้พื้นเดียวกัน"
```

---

### Task 3: ตัวเลขความคืบหน้าเช็คอินบน Home

**Files:**
- Create: `WBW/CheckinProgressLabel.swift`
- Test: `WBWTests/CheckinProgressLabelTests.swift` (สร้างใหม่)
- Modify: `WBW/HomeView.swift` (`VStack` คำทักทาย บรรทัด 40-47 หลัง Task 2)

**Interfaces:**
- Consumes: `Config.forest3D` จาก Task 1 · `HomeView.stage` / `HomeView.total` (private computed vars ที่มีอยู่แล้วที่ `HomeView.swift:13-27`)
- Produces: `CheckinProgressLabel.text(stage: Int, total: Int) -> String?`

- [ ] **Step 1: เขียนเทสที่ยังไม่ผ่าน**

สร้าง `WBWTests/CheckinProgressLabelTests.swift`:

```swift
import XCTest
@testable import WBW

/// ตัวเลขความคืบหน้าชั่วคราวบน Home — ของแทนต้นไม้ในฉาก 3D ที่ถูกปิดไป
/// (ดู docs/superpowers/specs/2026-08-07-forest-3d-off-design.md ข้อ 4)
final class CheckinProgressLabelTests: XCTestCase {

    func testShowsStageOverTotal() {
        XCTAssertEqual(CheckinProgressLabel.text(stage: 3, total: 8), "เช็คอินแล้ว 3/8 ฐาน")
    }

    func testShowsZeroStageWhenNothingCheckedInYet() {
        XCTAssertEqual(CheckinProgressLabel.text(stage: 0, total: 8), "เช็คอินแล้ว 0/8 ฐาน")
    }

    func testHidesWhenTotalUnknown() {
        // total 0 = ยังโหลดความคืบหน้าไม่เสร็จ หรือไม่มีฐานเลย — "x/0 ฐาน" ไม่มีความหมาย
        XCTAssertNil(CheckinProgressLabel.text(stage: 3, total: 0))
    }

    func testHidesWhenBothZero() {
        XCTAssertNil(CheckinProgressLabel.text(stage: 0, total: 0))
    }
}
```

- [ ] **Step 2: รันเทสให้เห็นว่าพัง**

Run: `xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WBWTests/CheckinProgressLabelTests`

Expected: FAIL — compile error `cannot find 'CheckinProgressLabel' in scope`

- [ ] **Step 3: เขียน implementation เท่าที่พอให้ผ่าน**

สร้าง `WBW/CheckinProgressLabel.swift`:

```swift
import Foundation

/// ข้อความความคืบหน้าเช็คอินบน Home — ของแทนชั่วคราวของต้นไม้ในฉากป่า 3D ที่ถูกปิดไว้
/// (Config.forest3D) เปิดฉากกลับเมื่อไหร่ ต้นไม้ทำหน้าที่นี้แทน แล้วข้อความนี้ซ่อนตัวเอง
enum CheckinProgressLabel {
    /// nil = ยังไม่มีข้อมูล (total 0) → ไม่ต้องโชว์อะไรเลย
    static func text(stage: Int, total: Int) -> String? {
        guard total > 0 else { return nil }
        return "เช็คอินแล้ว \(stage)/\(total) ฐาน"
    }
}
```

- [ ] **Step 4: รันเทสให้ผ่าน**

Run: `xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WBWTests/CheckinProgressLabelTests`

Expected: PASS — 4 tests, 0 failures

- [ ] **Step 5: ต่อเข้า `HomeView`**

ใน `WBW/HomeView.swift` เพิ่ม `Text` ตัวที่สามเข้าไปใน `VStack` คำทักทาย ต่อจาก `Text(name)`
(หลัง Task 2 แล้ว ทั้งก้อนจะเป็นแบบนี้):

```swift
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hey!")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white)
                    Text(name)
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(.white)
                    // ของแทนต้นไม้ในฉาก 3D ที่ถูกปิดไว้ — ผูกกับ Config.forest3D ตั้งใจ (ต่างจากสี
                    // ตัวอักษรด้านบนที่เป็นสไตล์ ไม่ใช่ของแทน) เปิดฉากกลับเมื่อไหร่ ต้นไม้บอกเรื่อง
                    // เดียวกันนี้อยู่แล้ว ไม่ควรมีสองที่พูดซ้ำกัน · ไม่วางกลางจอเพราะกลางจอคือที่ที่
                    // รูปพื้นหลังจะมาลงทีหลัง
                    if !Config.forest3D, let progressText = CheckinProgressLabel.text(stage: stage, total: total) {
                        Text(progressText)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
```

- [ ] **Step 6: รันเทสทั้งชุดให้ผ่าน**

Run: `xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: PASS ทั้งหมด 0 failures · จำนวนเทส = ตอนจบ Task 1 + 4

- [ ] **Step 7: Commit**

```bash
git add WBW/CheckinProgressLabel.swift WBWTests/CheckinProgressLabelTests.swift WBW/HomeView.swift
git commit -m "feat(home): ตัวเลขความคืบหน้าเช็คอินแทนต้นไม้ที่หายไปกับฉาก 3D

\"เช็คอินแล้ว 3/8 ฐาน\" ใต้คำทักทาย อ่านจาก stage/total ที่ HomeView มีอยู่แล้ว
ไม่ต่อ backend เพิ่ม · total 0 (ยังโหลดไม่เสร็จ) ซ่อนตัวเอง

โชว์เฉพาะตอน Config.forest3D ปิด — เปิดฉากกลับเมื่อไหร่ต้นไม้ทำหน้าที่นี้เอง"
```

---

### Task 4: อัปเดตเอกสารที่พึ่งฉากป่า

**Files:**
- Modify: `docs/superpowers/specs/2026-08-06-group-join-glass-design.md`
- Modify: `docs/superpowers/plans/2026-08-06-group-join-glass.md`
- Modify: `docs/superpowers/specs/2026-08-02-forest-3d-background-design.md` (หัวไฟล์อย่างเดียว)

**Interfaces:**
- Consumes: `Config.forest3D`, `Color.wbwForestVoid` จาก Task 1 (อ้างชื่อในเอกสาร)
- Produces: ไม่มี symbol

**ทำไมไม่มีเทส:** เอกสารล้วน ไม่มีโค้ดให้รัน — ตรวจด้วย `grep` ตาม Step 4

**สิ่งที่ไม่เปลี่ยน และสำคัญมากที่จะไม่เผลอแก้:** ทั้งสองเอกสารยังสั่งให้เรียก
`.forestBackground(day: ForestMath.dayStill)` เหมือนเดิมทุกตัวอักษร — modifier ตัวเดิมนั่นแหละ
คือตัวที่วาดพื้นทึบให้ตอนฉากปิด (Task 1) สิ่งที่ต้องแก้คือ **คำบรรยายว่าผลลัพธ์หน้าตายังไง**
กับ **ความเสี่ยงที่หายไป** ไม่ใช่ตัวโค้ดที่แผนสั่งให้เขียน

`ForestSceneHost.tabBarClearance` (89) ที่ §2.5 ใช้เป็น `.padding(.bottom, …)` ของ `LazyVStack`
ก็ **ยังใช้ต่อเหมือนเดิม** — มันคือระยะพ้นแท็บบาร์ลอย ซึ่งยังอยู่ ไม่ได้หายไปกับฉาก
สิ่งที่เสียไปคือ *เหตุผลประกอบ* ที่อ้างว่า "ใช้ค่าเดียวกับที่ฉากป่าใช้กันเครดิตโมเดล" เท่านั้น

- [ ] **Step 1: แก้สเปกหน้าจับกลุ่ม**

ใน `docs/superpowers/specs/2026-08-06-group-join-glass-design.md`:

1. ชื่อเรื่องบรรทัด 1 → `# หน้าจับกลุ่ม — Liquid Glass บนพื้นทึบ`
2. เติมเป็นบรรทัดใหม่ถัดจากชื่อเรื่อง:
   ```markdown
   > **แก้ 2026-08-07:** สเปกนี้เขียนตอนพื้นหลังยังเป็นฉากป่า 3D ตอนนี้ฉากถูกปิดด้วย
   > `Config.forest3D` (ดู `2026-08-07-forest-3d-off-design.md`) `.forestBackground()` ยังเป็น
   > ตัวเดิมที่ต้องเรียก แต่มันวาดพื้นทึบ `Color.wbwForestVoid` (#0A1610) ให้แทนฉาก
   > การ์ด liquid glass และเนื้อหาอื่นคงเดิมทั้งหมด
   ```
3. บรรทัด 3 (เป้าหมาย) — `การ์ด Liquid Glass ลอยบนฉากป่า 3D` → `การ์ด Liquid Glass ลอยบนพื้นทึบ #0A1610`
4. แถวตารางบรรทัด 25 — คำอธิบายท้ายแถวเปลี่ยนจาก
   `ฉากป่า 3D ที่ HomeView, LoginView, MyQRCodeView ใช้ร่วมกัน` เป็น
   `พื้นหลังร่วมของ HomeView, LoginView, MyQRCodeView — วาดพื้นทึบตอน Config.forest3D ปิด`
5. §2.5 บรรทัด 99 — **ไม่แตะค่า** `.padding(.bottom, ForestSceneHost.tabBarClearance)`
   แก้เฉพาะประโยคเหตุผล `ใช้ค่าเดียวกับที่ฉากป่าใช้กันเครดิตโมเดล จะได้ไม่ต้องมีเลขวิเศษสองตัวที่หมายถึงระยะเดียวกัน`
   เป็น `ค่านี้คือระยะพ้นแท็บบาร์ลอยที่วัดจากเครื่องจริงสองรุ่น (ดูคอมเมนต์ที่ ForestSceneHost.tabBarClearance) ยังใช้ได้เหมือนเดิมแม้ฉากป่าจะถูกปิดไปแล้ว`
6. **แทนที่ทั้งหมวด 3.1** (บรรทัด 105 เป็นต้นไป จนจบหมวด) และย่อหน้า claim/release ที่ §3.2
   (รอบบรรทัด 136 รวมย่อหน้าที่ขึ้นต้นว่า `ต้องเห็นด้วยตาบนซิมูเลเตอร์…`) ด้วยหมวดเดียวนี้:
   ```markdown
   ### 3.1 ความเสี่ยงเดิมที่หายไปทั้งคู่

   ฉบับก่อนมีความเสี่ยงสองข้อ: `NavigationStack` ทับฉากป่าจนพื้นดำ และ `claimScene()`/
   `releaseScene()` ส่งไม้ต่อไม่ทันตอน push ไป `GroupMembersView` จนฉากหายกลางทาง
   ทั้งคู่ผูกกับฉาก 3D ที่ `RootView` ซึ่งอยู่คนละ hosting context กับจอ ตอนนี้ฉากไม่ถูก mount
   แล้ว พื้นหลังถูกวาดใน `.background` ของจอเอง — อยู่ต้นไม้เดียวกับจอ ไม่มีอะไรให้ทับหรือ
   หลุดมือได้อีก แผนถอย 3 ขั้นและการถอด `NavigationStack` จึงไม่ต้องใช้แล้ว
   ```
7. §3.3 บรรทัด 146 — `fallback ของ glassSurface เบลอสิ่งที่อยู่หลังมัน แต่ฉากป่าถูกวาดที่ RootView ซึ่งอยู่คนละ hosting context material อาจสุ่มสีป่าไม่ติดแล้วออกมาเป็นแผ่นเทาเปล่า`
   → `fallback ของ glassSurface เบลอสิ่งที่อยู่หลังมัน ซึ่งตอนนี้คือพื้นทึบสีเดียวในกรอบเดียวกับการ์ด material จะได้สีเดียวสม่ำเสมอ ไม่ใช่ลายป่า — ยังต้องดูด้วยตาว่ามันไม่กลายเป็นแผ่นเทาที่กลืนกับพื้นจนมองไม่เห็นขอบการ์ด`

- [ ] **Step 2: แก้แผนหน้าจับกลุ่ม**

ใน `docs/superpowers/plans/2026-08-06-group-join-glass.md` แก้ตามบรรทัดนี้ (เลขบรรทัดจากฉบับ
ปัจจุบัน ถ้าเลื่อนให้ยึดข้อความเป็นหลัก):

1. เติมหมายเหตุแบบเดียวกับ Step 1 ข้อ 2 ไว้ใต้บรรทัด `**For agentic workers:**`
2. `:5` Goal — `ลอยบนฉากป่า 3D ตัวเดียวกับที่ Home / Login / QR ใช้` →
   `ลอยบนพื้นหลังตัวเดียวกับที่ Home / Login / QR ใช้ (พื้นทึบ #0A1610 ตอนฉาก 3D ปิด)`
3. `:7` Architecture — คงชื่อ `.forestBackground(day:)` ไว้ แก้แค่วงเล็บอธิบายให้บอกว่ามันวาด
   พื้นทึบตอน `Config.forest3D` ปิด
4. `:106` แถวตาราง `ForestSceneHost.swift` — `ให้ .forestBackground(day:) และ ForestSceneHost.tabBarClearance (= 89)` คงเดิม เติมท้ายว่า `· วาดพื้นทึบตอน Config.forest3D ปิด`
5. `:111` หัวข้อ `## Task 1: พื้นหลังฉากป่า 3D` → `## Task 1: พื้นหลังจาก .forestBackground`
6. `:113` — ประโยค `นี่คือ task ที่มีความเสี่ยงจริงข้อเดียวของแผน ทำก่อนและทำลำพัง — ถ้าไม่ผ่าน แผนที่เหลือเปลี่ยนรูปหมด (ต้องถอด NavigationStack) จึงต้องรู้ผลก่อนจะไปแตะสีอะไร`
   → `ความเสี่ยงเดิมของ task นี้ (NavigationStack ทับฉาก) หายไปแล้วตั้งแต่ฉาก 3D ถูกปิด — พื้นหลังถูกวาดในกรอบของจอเอง ยังทำก่อนอยู่เพราะ task ที่เหลือวางสีทับพื้นนี้`
7. `:126` — `ไม่ส่ง bottomClearance → ค่าเริ่มต้น ForestSceneHost.tabBarClearance (89) ถูกแล้วเพราะหน้านี้อยู่ใต้แท็บบาร์ลอย` → เติมท้ายว่า `(ตอนฉากปิด ค่านี้ไม่มีใครอ่าน เพราะมันมีไว้กันเครดิตโมเดลที่ ForestOverlay ซึ่งไม่ถูก mount — ไม่ต้องแก้ call site)`
8. `:212` Expected — `เห็นฉากป่า 3D เป็นพื้นหลัง` → `เห็นพื้นทึบเขียวเกือบดำ (#0A1610) เป็นพื้นหลัง`
9. `:216` เป็นต้นไปจนจบ **แผนถอย 3 ขั้น** (รวม `:225`, `:227`) — ลบทั้งก้อน แทนด้วย
   `ความเสี่ยงนี้หายไปแล้ว ดูสเปก §3.1 — ไม่ต้องมีแผนถอย`
10. `:253` commit message — `feat(group): หน้าจับกลุ่มใช้ฉากป่า 3D เป็นพื้นหลังแทนพื้นครีมทึบ`
    → `feat(group): หน้าจับกลุ่มใช้พื้นหลังร่วมของแอปแทนพื้นครีมทึบ`
11. `:387` คอมเมนต์ `กระจกลอยบนฉากป่า` → `กระจกลอยบนพื้นทึบ`
12. `:546` คอมเมนต์ในโค้ด — แก้เหมือน Step 1 ข้อ 5
13. `:601`-`:613` ทั้ง Step — ลบทั้งก้อน (ยืนยันว่าฉากป่าไม่หายตอนเข้าหน้าสมาชิก) แทนด้วย
    `ความเสี่ยงนี้หายไปแล้ว ดูสเปก §3.1 — ไม่มีฉากให้หาย`
14. `:645` — `พิสูจน์ได้ว่า .ultraThinMaterial สุ่มสีฉากป่าติดหรือกลายเป็นแผ่นเทาเปล่า` →
    `พิสูจน์ได้ว่า .ultraThinMaterial บนพื้นทึบยังเห็นขอบการ์ดหรือกลืนไปกับพื้น`
15. `:687` แถวตาราง traceability `§2.1 พื้นหลังฉากป่า` → `§2.1 พื้นหลังจาก .forestBackground`
16. `:692` แถว `§3.1 NavigationStack ทับฉาก + แผนถอย 3 ขั้น | 1 Step 6` → ลบแถวนี้ทิ้ง

- [ ] **Step 3: เติมสถานะที่หัวสเปกฉากป่าเดิม**

ใน `docs/superpowers/specs/2026-08-02-forest-3d-background-design.md` เปลี่ยนบรรทัด
`- **Status:** Approved (design), pending implementation plan` เป็น:

```markdown
- **Status:** สร้างเสร็จและ merge แล้ว แต่ **ปิดใช้งานตั้งแต่ 2026-08-07** ด้วย
  `Config.forest3D = false` เพราะเครื่องทำงานหนัก — โค้ดและ asset ยังอยู่ครบ
  ดู `2026-08-07-forest-3d-off-design.md` เนื้อหาที่เหลือของไฟล์นี้ไม่แก้ เป็นบันทึกของตอนนั้น
```

ห้ามแก้เนื้อส่วนอื่นของไฟล์นี้

- [ ] **Step 4: ตรวจว่าไม่มีที่ไหนหลงเหลือ**

Run:
```bash
grep -n "ฉากป่า 3D\|ฉาก 3 มิติ" docs/superpowers/specs/2026-08-06-group-join-glass-design.md docs/superpowers/plans/2026-08-06-group-join-glass.md
```

Expected: เหลือเฉพาะบรรทัดที่พูดถึงฉากในเชิงประวัติ (หมายเหตุ "แก้ 2026-08-07" กับหมวด
"ความเสี่ยงเดิมที่หายไป") ไม่มีบรรทัดไหนสั่งให้ใช้ฉากเป็นพื้นหลัง

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-08-06-group-join-glass-design.md \
        docs/superpowers/plans/2026-08-06-group-join-glass.md \
        docs/superpowers/specs/2026-08-02-forest-3d-background-design.md
git commit -m "docs: แก้เอกสารที่พึ่งฉากป่า 3D หลังฉากถูกปิด

หน้าจับกลุ่ม (ยังไม่ implement) เปลี่ยนพื้นหลังเป็นพื้นทึบ ตัดความเสี่ยงเรื่อง
NavigationStack ทับฉาก และ claimScene/releaseScene ชนกันทิ้ง — ไม่มีฉากแล้วไม่มี
ความเสี่ยงนั้น การ์ด liquid glass คงเดิม · สเปกฉากป่าเดิมเติมสถานะว่าปิดใช้งานแล้ว"
```

---

### Task 5: ยืนยันของจริง

**Files:**
- Create: `docs/forest-3d-off-verification.md`

**Interfaces:**
- Consumes: ทุกอย่างจาก Task 1-3
- Produces: ไม่มี symbol

**ทำไมต้องมี:** เทสยูนิตพิสูจน์ข้อที่เป็นเหตุของงานนี้ไม่ได้เลย — มันเทสได้แค่ตรรกะ ไม่ได้เทสว่า
จอออกมาหน้าตายังไง หรือเครื่องเบาลงจริงไหม

- [ ] **Step 1: build ลง simulator**

```bash
xcodegen generate
xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/wbw-forest-off clean build
xcrun simctl install booted /tmp/wbw-forest-off/Build/Products/Debug-iphonesimulator/WBW.app
```

- [ ] **Step 2: ขอ JWT จริงมาใช้กับ `-uitestToken`**

สามจอจากห้า (Home, QR, Event) ต้องมี session จริง `-uitestToken` รับ JWT ดิบมาเขียนลง
UserDefaults ให้ (ดู `RootView.init()`)

```bash
curl -s -X POST "https://api.studentunion.social/wbw/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"<บัญชีทดสอบ>","password":"<รหัส>"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])'
```

บัญชีทดสอบอยู่ใน `docs/sus-test-backend.md` · URL ข้างบนตรงกับ `Config.backend = .susProd`
ที่ตั้งอยู่ตอนนี้ (`WBW/Config.swift:44`) ถ้าค่านั้นถูกเปลี่ยน ให้ใช้ `apiBase` ของ backend
ที่ตั้งไว้จริงแทน · เก็บผลไว้ในตัวแปร shell: `TOKEN=$(curl … )`

- [ ] **Step 3: สกรีนช็อต 5 จอ**

ทีละจอ: `xcrun simctl terminate booted th.ac.mfu.wbwSwift` ก่อนเสมอ แล้ว launch ใหม่
รอ ~8 วินาทีให้จอนิ่งก่อนถ่าย

```bash
# Welcome (ไม่ส่ง arg ใดเลย)
xcrun simctl launch booted th.ac.mfu.wbwSwift
xcrun simctl io booted screenshot /tmp/wbw-forest-off/01-welcome.png

# Login
xcrun simctl launch booted th.ac.mfu.wbwSwift -uitestLogin YES
xcrun simctl io booted screenshot /tmp/wbw-forest-off/02-login.png

# Home (มีความคืบหน้า 3/8)
xcrun simctl launch booted th.ac.mfu.wbwSwift -uitestToken "$TOKEN" -uitestProgress 3
xcrun simctl io booted screenshot /tmp/wbw-forest-off/03-home.png

# QR (แท็บที่ 4)
xcrun simctl launch booted th.ac.mfu.wbwSwift -uitestToken "$TOKEN" -uitestTab 4
xcrun simctl io booted screenshot /tmp/wbw-forest-off/04-qr.png

# แท็บ Event (ForestBlank)
xcrun simctl launch booted th.ac.mfu.wbwSwift -uitestToken "$TOKEN" -uitestTab 1
xcrun simctl io booted screenshot /tmp/wbw-forest-off/05-event.png
```

เปิดดูทั้ง 5 รูปด้วยตาจริง (Read tool) แล้วเช็คทีละข้อ:
- พื้นเต็มจอเป็นเขียวเกือบดำ ไม่มีจอขาว ไม่มีจอโปร่งเห็นอะไรทะลุ ไม่มีจอดำล้วน
- ตัวอักษรทุกตัวอ่านออก โดยเฉพาะ "Hey!/ชื่อ" และไอคอนกระดิ่งบน Home
- Home มีบรรทัด "เช็คอินแล้ว 3/8 ฐาน"
- **ไม่มีบรรทัดเครดิต** "โมเดล 3 มิติ: ..." ที่มุมล่างซ้ายจอไหนเลย

> ระวังกับดักที่รีโปนี้เคยเจอมาแล้ว (`docs/forest-3d-verification.md`): สกรีนช็อตจาก
> DerivedData เก่าเคยยืนยันบั๊กที่แก้ไปแล้ว — ใช้ `-derivedDataPath` ใหม่ + `clean build`
> ตาม Step 1 เสมอ และ launch แรกสุดหลังติดตั้งใหม่อาจได้เฟรมดำ ให้ทิ้ง launch นั้นแล้วถ่ายรอบสอง

- [ ] **Step 4: ยืนยันว่าไม่มีอะไรในสาย 3D ทำงาน**

```bash
xcrun simctl terminate booted th.ac.mfu.wbwSwift
xcrun simctl spawn booted log stream --predicate 'process == "WBW"' > /tmp/wbw-forest-off/log.txt &
xcrun simctl launch booted th.ac.mfu.wbwSwift -uitestToken "$TOKEN"
# รอ ~15 วินาที แล้วหยุด log stream
grep -ci "forest.usdz\|ForestSceneView\|realityio\|RealityKit" /tmp/wbw-forest-off/log.txt
```

Expected: `0`

- [ ] **Step 5: วัดบนเครื่องจริง**

ข้อนี้คือข้อเดียวที่ตอบคำถามตั้งต้นว่า "หนักเพราะฉากจริงไหม" ต้องใช้ iPhone จริง ไม่ใช่ simulator

1. ติดตั้ง build ก่อนหน้า (commit ก่อน Task 1) ลงเครื่อง เปิดค้างที่ Home 5 นาที
   จดค่า CPU จาก Xcode Debug Navigator และสังเกตอุณหภูมิเครื่อง
2. ติดตั้ง build ปัจจุบัน ทำแบบเดียวกัน 5 นาที จดค่าเดียวกัน
3. บันทึกตัวเลขทั้งสองชุดลง `docs/forest-3d-off-verification.md`

**ถ้าตัวเลขไม่ต่างอย่างมีนัย** ให้เขียนไว้ตรงๆ ในเอกสารว่าฉากไม่ใช่ตัวการ และเสนอให้พิจารณา
เปิดกลับด้วย `Config.forest3D = true` — ห้ามเขียนว่างานนี้แก้ปัญหาได้ถ้าไม่มีตัวเลขรองรับ

- [ ] **Step 6: เขียนเอกสารยืนยัน**

สร้าง `docs/forest-3d-off-verification.md` โครงเดียวกับ `docs/forest-3d-verification.md`:
วิธีที่ใช้ (คำสั่ง build/launch จริงที่รัน), สกรีนช็อตทั้ง 5 พร้อมสิ่งที่เห็นในแต่ละรูป,
ผล `grep` จาก Step 3, ตารางตัวเลขจาก Step 4 ทั้งก่อนและหลัง, และข้อสรุปที่ตรงกับตัวเลขจริง

- [ ] **Step 7: Commit**

```bash
git add docs/forest-3d-off-verification.md
git commit -m "docs: ผลยืนยันการปิดฉากป่า 3D — สกรีนช็อต 5 จอ, log, ตัวเลขบนเครื่องจริง"
```

---

## เปิดฉากกลับยังไง

แก้ `Config.forest3D = true` ที่เดียวแล้ว build ทุกอย่างกลับมาเหมือนเดิม ยกเว้นสองอย่างที่
เป็นการเปลี่ยนถาวรโดยตั้งใจ: หัวจอ Home เป็นตัวอักษรขาว (Task 2) และตัวเลขความคืบหน้า
ซ่อนตัวเองคืนหน้าที่ให้ต้นไม้ (Task 3)
