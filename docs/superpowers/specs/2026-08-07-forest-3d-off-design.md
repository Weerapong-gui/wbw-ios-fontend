# ปิดฉากป่า 3D ชั่วคราว — แทนด้วยพื้นทึบสีเดียว

- **วันที่:** 2026-08-07
- **สถานะ:** อนุมัติดีไซน์แล้ว รอเขียนแผน implementation
- **ขอบเขต:** 5 จอที่ใช้ `.forestBackground()` + ตัวแสดงความคืบหน้าเช็คอินบน Home
- **รีโป:** `wbw-ios-fontend` เท่านั้น ไม่แตะ backend
- **แทนที่ชั่วคราว:** `2026-08-02-forest-3d-background-design.md` (โค้ดยังอยู่ครบ ปิดด้วยสวิตช์)

## เหตุผล

เครื่องทำงานหนักขึ้นหลังฉากป่า 3D เข้ามาเป็นพื้นหลัง ต้องการเอาฉากออกก่อน
ใช้พื้นทึบว่างๆ ไปพลาง แล้วค่อยเอารูปมาทับทีหลัง

ข้อสังเกตที่ต้องพูดตรงๆ: "หนักขึ้น" ตอนนี้เป็นความรู้สึกจากการใช้จริง ยังไม่มีตัวเลข
วัดเทียบ สเปกนี้จึงออกแบบให้ **เปิดกลับได้ด้วยการแก้ค่าเดียว** และบังคับให้มีขั้นตอน
วัดผลบนเครื่องจริงตอนยืนยัน (หมวด "การยืนยัน" ข้อ 3) ถ้าวัดแล้วไม่ต่าง แปลว่าตัวการ
อยู่ที่อื่น เปิดฉากกลับได้ทันทีโดยไม่เสียงานที่ทำไปเลย

## สภาพปัจจุบัน

| ของ | ที่อยู่ | หมายเหตุ |
|---|---|---|
| ฉากจริง (RealityKit) | `WBW/Scene3D/ForestSceneView.swift` | 399 บรรทัด · โหลด `forest.usdz` |
| เจ้าของฉาก + modifier | `WBW/Scene3D/ForestSceneHost.swift` | 235 บรรทัด · `claimScene()`/`releaseScene()` |
| ชั้นทับ (สครีม เกรน เครดิต) | `WBW/Scene3D/ForestOverlay.swift` | เครดิต CC BY อยู่ในนี้ |
| ไจโรพารัลแลกซ์ | `WBW/Scene3D/GyroParallax.swift` | CoreMotion |
| ต้นไม้โตตามขั้น | `WBW/Scene3D/GrowingTree.swift` | ผูกกับ `plantStep` |
| จุด mount ตัวเดียว | `WBW/RootView.swift:40` | `if host.everEnabled && !host.loadFailed` |
| asset | `WBW/Resources/forest.usdz` (636K), `tree.usdz` (12K), `models/*.glb` 8 ตัว | รวม 772K |

5 จอที่เรียก `.forestBackground()`: `WelcomeView:46`, `LoginView:85`, `HomeView:79`,
`MyQRCodeView:36`, `ForestBlank` ใน `MainTabView:404` (แท็บ Event/Voucher)

`ForestBackground` modifier มีอยู่แล้วเพื่อการนี้โดยเฉพาะ — คอมเมนต์ที่
`ForestSceneHost.swift:142` เขียนไว้ตั้งแต่แรกว่า "ตัวกลางนี้คือเหตุผลที่สลับ implement
ข้างในได้ (3D ↔ รูปนิ่ง) โดยไม่แตะ 5 จอเลย" สเปกนี้คือการใช้ช่องนั้นตามที่ออกแบบไว้

## เป้าหมาย

1. ปิดฉาก 3D ทั้งสาย — ไม่โหลด `forest.usdz`, ไม่มี RealityKit, ไม่มี CoreMotion,
   ไม่มี `TimelineView` tick — ด้วยการแก้ค่าเดียวใน `Config.swift`
2. 5 จอเดิมได้พื้นทึบสีเดียว `#0A1610` แทน โดยไม่ต้องแก้ไฟล์จอเลยสักไฟล์
3. Home ยังบอกความคืบหน้าเช็คอินได้ ด้วยตัวเลขชั่วคราวแทนต้นไม้
4. เปิดฉากกลับได้ด้วยการกลับค่าเดียวนั้น

## ไม่ทำ (YAGNI)

- ไม่ลบ `WBW/Scene3D/`, `forest.usdz`, `tree.usdz`, `models/*.glb` หรือเทสของมัน
- ไม่แตะ `scripts/bake-forest.py`
- ไม่ทำ UI ให้ผู้ใช้สลับเองในแอป — เป็นค่าคงที่ตอน compile
- ไม่เอามาสคอต DinDin กลับมา
- ไม่ใส่รูปพื้นหลังใหม่ (คนละงาน จะทำทีหลัง)
- ไม่ optimize ฉาก 3D ให้เบาลง (ถ้าจะกลับมาทำ เป็นงานแยกอีกใบ)
- ไม่แตะแท็บ Map (มีสเปกของตัวเองที่พักไว้ `2026-07-31-map3d-glb-design.md`)

## วิธีที่เลือก

**สวิตช์ที่ `ForestBackground` modifier จุดเดียว**

ปิด `claimScene()` ไม่ให้ตั้ง `wantsScene` ทรงเดียวกับ guard `isRunningUnderXCTest` ที่มี
อยู่แล้วที่ `ForestSceneHost.swift:96` ผลลูกโซ่: `wantsScene` ไม่เคยเป็น true →
`recompute()` ให้ `enabled` เป็น false ตลอด → `everEnabled` ไม่เคยเป็น true →
`RootView:40` ไม่ mount `ForestSceneView`/`ForestOverlay` เลยสักครั้ง → ไม่มีอะไรใน
สาย RealityKit/CoreMotion/TimelineView ถูกสร้าง

สองทางที่ไม่เอา:

- **gate ที่ `RootView`** (`if Config.forest3D && host.everEnabled`) — ยังต้องแก้
  `.background{}` ของ modifier ให้วาดสีทึบอยู่ดี ไม่งั้นจอโปร่ง และ host ยัง claim/
  recompute เปล่าๆ ต่อไปทุกจอ ไม่ได้ดีกว่าเลย
- **ถอด `.forestBackground()` ออกจาก 5 จอ ใส่ `.background(สี)` ตรงๆ** — คนอ่านโค้ด
  เข้าใจง่ายสุด แต่แตะ 5 ไฟล์ และตอนเปิดฉากกลับต้องแก้ 5 ไฟล์อีกรอบ ขัดกับที่ต้องการว่า
  สวิตช์เดียว

## รายละเอียด

### 1. สวิตช์

`WBW/Config.swift` เพิ่มใน `enum Config`:

```swift
/// ฉากป่า 3D — ปิดชั่วคราว (เครื่องทำงานหนัก) เปิดกลับได้ที่ค่านี้ค่าเดียว
///
/// ปิด = ทุกจอที่เรียก .forestBackground() ได้พื้นทึบ Color.wbwForestVoid แทน และ
/// ForestSceneView/ForestOverlay ไม่ถูก mount เลย (ดู ForestSceneHost.shouldClaim)
static let forest3D = false
```

และเพิ่มสีข้างสีธีมอื่นในไฟล์เดียวกัน:

```swift
/// พื้นหลังทึบแทนฉากป่า — สีเดียวกับ scrim เดิมของ ForestOverlay
static let wbwForestVoid = Color(red: 10 / 255, green: 22 / 255, blue: 16 / 255) // #0A1610
```

### 2. `ForestSceneHost`

เพิ่ม static ที่เทสได้ (เดิมเงื่อนไข XCTest เขียน inline อยู่ใน `claimScene()`):

```swift
/// จอขอฉากแล้วต้องให้จริงไหม — false = ปล่อย token คืนเฉยๆ ไม่แตะ wantsScene
nonisolated static func shouldClaim(forest3D: Bool, underTest: Bool) -> Bool {
    forest3D && !underTest
}
```

`nonisolated` ไม่ใช่ของประดับ — `ForestSceneHost` เป็น `@MainActor` ทั้งคลาส static
member จึงเป็น main-actor isolated ตามไปด้วย เทสยูนิตจะเรียกไม่ได้ถ้าไม่ประกาศตรงนี้
(ฟังก์ชันนี้ไม่แตะ state อะไรเลย เป็น pure function ล้วน)

`claimScene()` เรียกตัวนี้แทน guard เดิม โดยส่ง `Config.forest3D` กับ
`Self.isRunningUnderXCTest` เข้าไป พฤติกรรมตอน `forest3D == true` เหมือนเดิมทุกประการ

`ForestBackground.body` แตกสองทางที่ `.background{}`:

- `Config.forest3D == true` → เหมือนเดิมทั้งก้อน (`TabRootOpaqueBackgroundRemover` +
  `loadFailed ? Image("bg_forest") : Color.clear`)
- `Config.forest3D == false` → `Color.wbwForestVoid.ignoresSafeArea()` ตัวเดียว

`TabRootOpaqueBackgroundRemover` อยู่ในทาง 3D เท่านั้น — มันมีไว้เจาะพื้นทึบขาวของ
per-tab `UIHostingController` ให้ฉากที่ `RootView` (ซึ่งอยู่คนละต้นไม้) โผล่ขึ้นมาได้
ปิดฉากแล้วไม่มีอะไรอยู่หลังต้องโผล่ เพราะสีถูกวาดใน `.background` ของจอนั้นเอง ซึ่งอยู่ใน
ต้นไม้เดียวกับจอ

ส่วนที่เหลือของ `ForestSceneHost` ไม่แตะ: `onAppear`/`onDisappear`/`onChange` ยังเขียน
`host.day`/`plantStep`/`plantTotal`/`bottomClearance` เหมือนเดิม (ไม่มีใครอ่าน แต่ก็ไม่มี
ต้นทุน และทำให้เปิดกลับแล้วทำงานทันที)

### 3. สีตัวอักษร Home

`WelcomeView`, `LoginView`, `MyQRCodeView` ใช้ตัวอักษรขาวล้วนอยู่แล้ว อ่านออกบนพื้น
`#0A1610` ทันที ไม่ต้องแก้

`HomeView` ใช้ `Color.wbwInk` (#2B2B2B) กับ "Hey!" (`:42`), ชื่อผู้ใช้ (`:45`) และไอคอน
กระดิ่ง (`:54`) — เทาเข้มบนเขียวเกือบดำแทบมองไม่เห็น เดิมอ่านออกเพราะข้างหลังเป็นท้องฟ้า
สว่างของฉาก 3D

**เปลี่ยนทั้งสามจุดเป็น `.white` ถาวร ไม่ผูกกับ `Config.forest3D`** — สอดคล้องกับอีก 4 จอ
ไม่มี conditional ปนใน view และรูปที่จะเอามาทับทีหลังก็เป็นภาพโทนเข้มแบบเดียวกัน
ผลข้างเคียงที่รับได้: ถ้าเปิดฉาก 3D กลับ หัวจอ Home จะเป็นขาวแทนเทาเข้ม อ่านออกทั้งคู่

### 4. ตัวเลขความคืบหน้าบน Home

ฟังก์ชันบริสุทธิ์ ไฟล์ใหม่ `WBW/CheckinProgressLabel.swift` (`project.yml` ผูก sources
เป็นโฟลเดอร์ `WBW` ทั้งก้อน ไฟล์ใหม่เข้า target เองหลังรัน `xcodegen`):

```swift
enum CheckinProgressLabel {
    /// nil = ยังไม่มีข้อมูล (total 0) → ไม่ต้องโชว์อะไรเลย
    static func text(stage: Int, total: Int) -> String? {
        guard total > 0 else { return nil }
        return "เช็คอินแล้ว \(stage)/\(total) ฐาน"
    }
}
```

`HomeView` วางไว้ใต้ "Hey!/ชื่อ" ใน `VStack` เดิมของหัวจอ: `.font(.system(size: 13))`,
`.foregroundStyle(.white.opacity(0.75))` อ่านค่าจาก `stage`/`total` ที่ `HomeView` คำนวณ
อยู่แล้ว (ไม่ต่อ backend เพิ่ม)

ห่อด้วย `if !Config.forest3D` — ตัวนี้เป็นของแทนต้นไม้ตรงๆ เปิดฉากกลับเมื่อไหร่ต้นไม้ทำ
หน้าที่นี้เอง ไม่ควรมีสองที่บอกเรื่องเดียวกัน (ต่างจากสีตัวอักษรในข้อ 3 ที่เป็นสไตล์ ไม่ใช่
ของแทน จึงไม่ผูก flag)

ไม่วางกลางจอ — กลางจอคือที่ที่รูปพื้นหลังจะมาลงทีหลัง

## ผลข้างเคียงที่ตั้งใจ

- **เครดิต CC BY หายไปเอง** อยู่ใน `ForestOverlay` ที่ไม่ถูก mount — ถูกต้องตามใบอนุญาต
  เพราะไม่มีโมเดลถูกวาดแล้ว เปิดฉากกลับเมื่อไหร่เครดิตกลับมาพร้อมกันเอง
- **`loadFailed → Image("bg_forest")` กลายเป็นโค้ดที่ไปไม่ถึง** ตอนปิด แต่ต้องอยู่ต่อ
  สำหรับตอนเปิดกลับ ห้ามลบ asset `bg_forest`
- **`forest.usdz` + `models/` ยังติดไปกับ binary** (~772K) ยอมแลกกับการเปิดกลับได้ทันที
- **`Scene3D/` ยังคอมไพล์อยู่** เทส `ForestMathTests`/`GyroParallaxTests` ยังผ่านเหมือนเดิม

## เทส

เพิ่มใหม่ (เขียนเทสก่อน):

- `ForestSceneHost.shouldClaim(forest3D:underTest:)` ครบ 4 ช่อง — true เฉพาะ
  `(true, false)` เท่านั้น
- `CheckinProgressLabel.text` — `(3, 8)` → `"เช็คอินแล้ว 3/8 ฐาน"` · `(0, 8)` →
  `"เช็คอินแล้ว 0/8 ฐาน"` · `(3, 0)` → `nil` · `(0, 0)` → `nil`

ไม่แตะ: `ForestMathTests`, `GyroParallaxTests` และเทสอื่นทั้งหมด

## การยืนยัน

เทสยูนิตพิสูจน์เรื่องที่เป็นเหตุของงานนี้ไม่ได้ ต้องมีสามข้อนี้:

1. **สกรีนช็อต 5 จอบน simulator** (Welcome, Login, Home, QR, แท็บ Event) — พื้นทึบเต็มจอ
   ตัวอักษรอ่านออกครบ ไม่มีจอขาว ไม่มีจอโปร่ง ไม่มีเครดิตค้าง
2. **`log stream` ตอนเปิดแอป** — ต้องไม่มีร่องรอยโหลด `forest.usdz` และไม่มี
   `[ForestSceneView]` โผล่เลย
3. **วัดบนเครื่องจริง** — เปิดแอปค้างที่ Home แล้วเทียบ CPU/อุณหภูมิกับ build ก่อนหน้า
   นี่คือข้อเดียวที่ตอบคำถามตั้งต้นว่าหนักเพราะฉากจริงไหม ถ้าตัวเลขไม่ต่างอย่างมีนัย
   ให้บันทึกไว้และพิจารณาเปิดฉากกลับ เพราะตัวการอยู่ที่อื่น

## เอกสารที่ต้องแก้ไปพร้อมกัน

- `specs/2026-08-06-group-join-glass-design.md` และ `plans/2026-08-06-group-join-glass.md`
  (ยังไม่ implement) — เปลี่ยนพื้นหลังจากฉากป่า 3D เป็นพื้นทึบ `Color.wbwForestVoid` ·
  ตัดหมวดความเสี่ยง `NavigationStack` ทับฉากป่า และเรื่อง `claimScene()`/`releaseScene()`
  ชนกันทิ้ง (ไม่มีฉากแล้วไม่มีความเสี่ยงนั้น) · ตัด `bottomClearance` ที่มีไว้กันเครดิต
  โมเดลออก · การ์ด liquid glass และเนื้อหาอื่นคงเดิมทั้งหมด
- `specs/2026-08-02-forest-3d-background-design.md` — เติมสถานะที่หัวไฟล์ว่าปิดใช้งาน
  ตั้งแต่ 2026-08-07 ชี้มาสเปกนี้ ไม่แก้เนื้อใน (เป็นบันทึกของตอนนั้น)

## เปิดฉากกลับยังไง

แก้ `Config.forest3D = true` ที่เดียว แล้ว build ทุกอย่างกลับมาเหมือนเดิม ยกเว้นสองอย่าง
ที่เป็นการเปลี่ยนถาวร: หัวจอ Home เป็นตัวอักษรขาว (ข้อ 3) และตัวเลขความคืบหน้าซ่อนตัวเอง
คืนหน้าที่ให้ต้นไม้ (ข้อ 4)
