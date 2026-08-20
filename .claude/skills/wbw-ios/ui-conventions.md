# ธรรมเนียม UI

ไฟล์นี้ตอบว่าสีธีมมีอะไรบ้าง, Liquid Glass ใช้ยังไง, ไฟล์จอใหม่วางตรงไหน, และคอมเมนต์ในโค้ดควรเขียนแบบ
ไหน — เรื่อง backend/`Config` ดูที่ `.claude/skills/wbw-ios/backend-and-config.md`, เรื่อง build/รัน ดูที่
`.claude/skills/wbw-ios/build-and-run.md` แทน ไม่ซ้ำที่นี่

## สีธีม

ประกาศเป็น `extension Color` ใน `WBW/Config.swift` (บรรทัด 66 เป็นต้นไป) แบ่งเป็นสองกลุ่ม

**สีแบรนด์/สีฉาก — คงที่ทั้งสองธีม** (พลิกตามโหมดมืดเมื่อไหร่แอปจะดูเป็นคนละงาน):

| ชื่อ | hex | ใช้ทำอะไร |
|---|---|---|
| `Color.wbwCream` | `#DEC684` | สีครีมหลักของธีม DOI-APP |
| `Color.wbwGold` | `#C99A1F` | สีทอง |
| `Color.wbwGreen` | `#40916C` | เขียวป่า ใช้ตอน toggle เปิด |
| `Color.wbwForestVoid` | `#0A1610` | พื้นหลังทึบแทนฉากป่าตอน `Config.forest3D` ปิด (สีเดียวกับ scrim เดิมของ `ForestOverlay`) — รายละเอียด flag ดู `backend-and-config.md` |
| `Color.wbwTicketBG` | `#1A1A1A` | พื้นจอตั๋วประจำตัว — **ที่พักไว้ก่อน ของจริงจะเป็นรูปภาพ** เปลี่ยนที่ `TicketView.background` ที่เดียว |
| `Color.wbwMedical` | `#421717` | แดงเลือดหมูของปุ่ม Medical ID ใช้เป็น tint ของกระจก |

**สีพื้นผิว — ปรับตามโหมดมืด** ผ่าน `UIColor(dynamicProvider:)` ตัวขับคือ `.preferredColorScheme`
ที่ `WBW/WBWApp.swift` ตั้งจาก `AppSettings.isDark`:

| ชื่อ | light | dark | ใช้ทำอะไร |
|---|---|---|---|
| `Color.wbwBg` | `#FAF7F0` | `#14120F` | พื้นหลังจอ |
| `Color.wbwSurface` | ขาว | `#211F1B` | การ์ด/ฟองแชท/ช่องพิมพ์ |
| `Color.wbwInk` | `#2B2B2B` | `#EFEBE3` | ตัวอักษร/เส้นเข้ม |
| `Color.wbwMuted` | `#8F8A80` | `#A8A196` | ข้อความรอง |
| `Color.wbwLine` | `#ECE6DA` | `#332F29` | เส้นคั่น |

กติกา: **ใช้ของที่มี ห้ามหว่าน hex ใหม่ในจอเดียว** — เจอสีที่ยังไม่มีในตารางพวกนี้ ให้เพิ่มเป็น
`static let` ใหม่ใน `WBW/Config.swift` ก่อน อย่าฝัง `Color(red:green:blue:)` แยกไว้กลางไฟล์จอ
(เคยมี `private let bg = Color(red: 250/255, ...)` ก๊อปกันอยู่ 6 จอ พอเพิ่มโหมดมืดเลยต้องไล่แก้ทีละที่)

**จอที่ตั้งใจไม่ให้ปรับตามธีม** อย่าเผลอไปเปลี่ยน: `TicketView` (บัตรจำลองกระดาษ ต้องขาวเสมอ),
`HomeView` (ใช้ `.forestBackground()` ซึ่งมืดอยู่แล้ว), `StaffScanView` (จอสแกนพื้นมืด), `Scene3D/*`

## Liquid Glass

`func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false)` ใน
`WBW/GlassSurface.swift` คือตัวกลางที่ใช้ซ้ำได้ — เรียกผ่าน `extension View` เช่น
`.glassSurface(Capsule())` เวลาจะเอาพื้นผิวกระจกใช้ตัวนี้ ไม่ต้องเขียนเอง

อยากได้กระจก **มีสี** ส่ง `tint:` ไป มันใช้ `Glass.tint(_:)` ของระบบให้ — **อย่าเอาสีไปแปะเป็นพื้น
ใต้กระจกเอง** เพราะกระจกจะไปซ้อนอยู่หลังสีทึบจนไม่เห็นการหักเหอะไรเลย ได้แค่รูปทรงสีเดียว
ตัวอย่างของจริง: ปุ่ม Medical ID ที่ `WBW/TicketView.swift` ใช้ `tint: Color.wbwMedical`

## ทรงที่เจาะรู — ห้ามแปะสีพื้นทับ

`WBW/TicketShape.swift` คือทรงตั๋วที่เจาะรอยเว้าจริง (บนกลางสำหรับ avatar, ซ้าย/ขวาที่แนวฉีก)
ของเดิมใช้ `Circle().fill(สีพื้น)` แปะทับ ซึ่งเนียนเฉพาะตอนพื้นหลังเป็นสีเรียบสีเดียว — พื้นจอตั๋ว
กำลังจะเปลี่ยนเป็นรูปภาพ วงกลมสีทึบจะโผล่กลางรูปทันที

วาดเป็นเส้นรอบรูปเส้นเดียวที่ไม่ตัดตัวเองด้วย `addArc` โค้งกลับเข้าใน **ไม่ใช่** วาดสี่เหลี่ยมแล้ว
`addEllipse` ทับหวังให้หักลบ — แบบหลังต้องพึ่ง `FillStyle(eoFill: true)` ซึ่ง `.clipShape` กับ
`.background(_:in:)` ไม่รับ ใช้ได้แค่ `.fill` พอจะเอาไปคลิปเนื้อหาหรือทำเงาตามทรงจะพังเงียบ ๆ

เส้นแนวฉีกใช้ `DashedLine` (ไฟล์เดียวกัน) เป็น `Shape` — `Path` ที่ลากยาวแล้วครอบ `.frame()`
วาดทะลุกรอบออกไปได้ `frame` คุมแค่พื้นที่ layout ไม่ได้คลิปการวาด (เคยพลาดมาแล้ว เส้นประพาด
ออกนอกการ์ดไปจนสุดขอบจอ)

ทุกที่ที่แตะกระจกจริงต้อง guard `#available(iOS 26.0, *)` แล้ว fallback เป็น `.ultraThinMaterial` เพราะ
deployment target ของโปรเจกต์คือ iOS 18 (`IPHONEOS_DEPLOYMENT_TARGET: "18.0"` ใน `project.yml`) — ตอนนี้มี
2 จุดที่ guard ไว้แบบนี้: `WBW/GlassSurface.swift:12`, `WBW/WelcomeView.swift:60`
(`GlassRing` ที่ `HomeView` ถูกลบไปพร้อม avatar บนหัวจอตอนยกเลย์เอาต์ Home มาจาก Android)
เพิ่มจุดใหม่ก็ต้อง guard แบบเดียวกันเสมอ

**ห้ามปลอมกระจกด้วย blur เอง** (เช่น `.blur()` + opacity ผสมมือ) — ผลลัพธ์ไม่เนียนเท่า `.glassEffect`
จริงของ iOS 26 และ fallback ที่ถูกต้องมีอยู่แล้วใน `glassSurface`

## ไฟล์ใหม่วางที่ไหน

จอเดี่ยว ๆ วางแบน ๆ ที่ราก `WBW/` (เช่น `WBW/HomeView.swift`, `WBW/WelcomeView.swift`) แตกเป็นโฟลเดอร์
ย่อยเมื่อฟีเจอร์เกิน ~3 ไฟล์ ของจริงที่มีอยู่ตอนนี้:

- `WBW/Map3D/` — 10 ไฟล์ (`Map3DCamera`, `Map3DConfig`, `Map3DFocus`, `Map3DGeo`, `Map3DIntro`, `Map3DLocation`, `Map3DPins`,
  `Map3DScreen`, `Map3DSky`, `MapModelLoader`)
- `WBW/Chat/` — 5 ไฟล์ (`ChatBubble`, `ChatDTOs`, `ChatRow`, `ChatSession`, `ChatToast`)
- `WBW/Feedback/` — 4 ไฟล์ (`CheckinToast`, `FeedbackOutbox`, `FeedbackStore`, `FeedbackView`)
- `WBW/SURun/` — 3 ไฟล์ (`SURunMath`, `SURunTracker`, `TrailRoute`) · ตัวจอคือ `WBW/SURunView.swift`
  ที่ราก
- `WBW/Conditions/` — 4 ไฟล์ (`ConditionsModels`, `ConditionsStore`, `OpenMeteoClient`,
  `TrailConditionsRow`)
- `WBW/Bloom/` — 3 ไฟล์ (`BloomStages`, `BloomGeometry`, `BloomView`)
- `WBW/Demo/` — 2 ไฟล์ (`DemoMode`, `DemoData`)
- `WBW/Scene3D/` — 7 ไฟล์ (ฉากป่า — **ปิดอยู่ตอนนี้แต่ไม่ได้ลบ** ดู `Config.forest3D` ใน
  `backend-and-config.md`)
- `WBW/Resources/` — asset สามมิติ (`.usdz`, `.glb` ใต้ `models/`) ไม่ใช่โค้ด Swift

## ฉาก RealityKit ต้องมีโดมฟ้าเสมอ

`RealityView` วาด **ดำล้วน** ตรงที่ไม่มีเรขาคณิต ไม่ใช่โปร่งใส — ฉากไหนที่กล้องหมุน/ซูมได้จะเห็นพื้นดำ
รอบโมเดลทันทีที่หันไปทางที่ไม่มีอะไร ทั้งสองฉากจึงล้อมด้วยทรงกลมใหญ่:

- ฉากป่า — `WBW/Scene3D/ForestSceneView.swift`
- แท็บแผนที่ — `WBW/Map3D/Map3DSky.swift` (โดม + ม่านปิดสันตัดของแผ่นภูมิประเทศ + ก้อนเมฆของ intro)

กติกาที่พังซ้ำได้ง่าย:

- `faceCulling = .none` **บังคับ** — กล้องอยู่ข้างในทรงกลม ถ้า cull back-face ตามค่าปริยายจะโดน cull
  ทิ้งทั้งใบ กลับไปดำเหมือนเดิมโดยไม่มี error
- texture ที่มี alpha ต้องเขียน buffer เอง **ห้ามวาดผ่าน `UIGraphicsImageRenderer`/`CGContext`** —
  ผลลัพธ์เป็น premultiplied เสมอ RealityKit อ่านเป็น straight alpha แล้วได้สีเทาแทนสีที่ตั้งไว้
- ผิวที่มีบริเวณไล่เฉดกว้าง ๆ **ห้ามตั้ง `opacityThreshold`** — มันสั่งใช้ alpha test แทน alpha blend
  ขอบจะไล่เป็นขั้น เห็นเป็นวงซ้อนหลายชั้น
- ระนาบแบนที่กล้องอาจมองเฉียง ให้ใส่ `BillboardComponent` ไม่งั้นเห็นขอบสี่เหลี่ยมของแผ่น

## แผนที่ 3D ปรับผ่าน JSON ไม่ใช่แก้โค้ด

ค่าทุกตัวที่ผูกกับไฟล์ `map.usdz` อยู่ที่ `WBW/Resources/map_config.json` ตัวเดียว (อ่านผ่าน
`WBW/Map3D/Map3DConfig.swift`) — ชื่อไฟล์โมเดล, ชื่อ prim ของแท่งแดงแต่ละฐาน, กรอบ lat/lng,
มุมหันพื้นที่งาน, ขอบเขตกล้อง (pitch/distance/ท่าโฟกัส/ความเร็วหมุนวน), รัศมีโดมกับชายพื้น

**เหตุผล:** โมเดลจะถูกเปลี่ยนใบ ก่อนหน้านี้ค่าพวกนี้กระจายอยู่ 4 ไฟล์แล้วลืมที่ใดที่หนึ่งได้ง่ายมาก
โดยไม่มีอะไรฟ้อง — อาการที่ได้คือหมุดกดไม่ติดหรือจุด GPS ไปโผล่ผิดที่ ซึ่งอ่านเหมือนบั๊กคนละเรื่อง

`Map3DConfig.fallback` คือค่าเดียวกันที่ compile ไว้ ใช้ตอนไฟล์หาย/พัง · `decode` ปฏิเสธ config
ที่ decode ผ่านแต่ใช้จริงไม่ได้ (หมุดว่าง, กรอบกลับด้าน, โดมเล็กกว่าระยะกล้องสูงสุด) —
`WBWTests/Map3DConfigFileTests.swift` คุมไว้ว่าไฟล์จริงกับ fallback ต้องตรงกันเป๊ะ

## แท็บ SU RUN มีของจริงแล้ว

`WBW/SURunView.swift` เคยเป็น **จอว่างสนิท** (ก่อนหน้านั้นเป็นแดชบอร์ดที่ทุกตัวเลขมาจาก `SURunMock`)
— **เปลี่ยนแล้วตั้งแต่ 2026-08-19 ห้ามถอยกลับ** ตอนนี้เป็นแผนที่ MapKit + เส้นทางจริง 8.36 กม.
จาก `WBW/Resources/route_wbw.json` + HUD ระยะ/ก้าว/pace/เวลา ที่คำนวณจาก CoreLocation กับ
CMPedometer จริง ไม่มี mock เหลืออยู่เลย

เหตุผลที่ห้ามถอย: build 1.0 (7) โดน App Review ตีกลับด้วย Guideline 2.1 กับ 2.3.3 · reviewer กด
ครบทุกแท็บเสมอ แท็บที่เปิดมาแล้วไม่มีอะไรคือใบตีกลับใบต่อไป (4.2 minimum functionality) ·
ข้อความบนจอถูกตรึงด้วย `WBWTests/SURunCopyTests.swift`

## แท็บถูกสร้างล่วงหน้าทุกใบ — ของที่ขอสิทธิ์ต้องหน่วงเอง

`TabView` แบบ `Tab(value:)` ของ iOS 18+ **สร้างเนื้อของทุกแท็บตั้งแต่ตอน mount** ไม่ใช่ตอนกดแท็บ
ยืนยันจากการถ่ายจริง: launch ด้วย `-uitestTab 4` แล้ว dialog ขอสิทธิ์ตำแหน่งยังเด้งทับจอ QR
เพราะ `MapKit.Map` ของแท็บ SU RUN ขอสิทธิ์เองทันทีที่ถูกสร้าง (ไม่ใช่โค้ดเราเรียก — ใส่ NSLog ที่ทุกจุด
ที่เรียก `requestWhenInUseAuthorization` แล้ว log ว่างเปล่า แต่ dialog ยังเด้ง)

จอไหนที่แตะกล้อง/ตำแหน่ง/ไมค์ ต้องรับ `isActive` เข้ามาแล้วหน่วงการสร้างของจริงไว้จนกว่าแท็บนั้น
จะถูกเลือกจริง — ของจริงที่ทำแบบนี้อยู่แล้วสองที่: `Map3DScreen(isActive:)` กับ `SURunView(isActive:)`
(ทั้งคู่ถูกส่งค่ามาจาก `WBW/MainTabView.swift:51` และ `:52`)

## คอมเมนต์

เขียนภาษาไทย บอก **"ทำไม"** ไม่ใช่ **"ทำอะไร"** — โค้ดอ่านเองได้อยู่แล้วว่าทำอะไร สิ่งที่โค้ดบอกไม่ได้คือ
อาการที่จะเจอถ้าทำผิดทาง

ตัวอย่างของจริง: คอมเมนต์หัวไฟล์ `WBW/BackendCacheKey.swift` อธิบายว่าทำไมไฟล์นี้ถึงแยกออกจาก
`Config.swift` — เพราะ `Config.swift` มีบรรทัด `Config.backend` ที่สลับไปมาระหว่างทดสอบและห้าม commit
แยกไฟล์ไว้ทำให้แก้ `cacheNamespace` แล้ว `git add` ได้เลยโดยไม่ดึงบรรทัดที่สลับค้างอยู่ติดไปด้วย — ดีเพราะ
บอกอาการ (จะ commit `Config.backend` หลุดไปโดยไม่ตั้งใจ) ไม่ใช่แค่บอกว่า "แยกไฟล์ไว้เก็บ cache key"

## ต้นทาง UI

ดีไซน์อ้างอิง Figma DOI-APP ไฟล์ `EKkcnLzTFz8zGjtO8ay70U`
