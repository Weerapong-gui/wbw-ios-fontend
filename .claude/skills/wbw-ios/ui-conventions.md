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

`GlassRing` เป็น `private struct` (`ViewModifier`) อยู่ใน `WBW/HomeView.swift` (บรรทัด 108) — **ไม่ใช่ API
กลาง** ใช้ได้เฉพาะภายในไฟล์นั้น (เรียกอยู่ 2 จุดในไฟล์เดียวกัน) จะเอาไปใช้ที่จออื่นต้องยกออกมาเป็นไฟล์
กลางก่อน (ตามแพทเทิร์นเดียวกับที่ `glassSurface` ทำไปแล้ว) อย่าสมมติว่า import แล้วเรียกจากจอไหนก็ได้

ทุกที่ที่แตะกระจกจริงต้อง guard `#available(iOS 26.0, *)` แล้ว fallback เป็น `.ultraThinMaterial` เพราะ
deployment target ของโปรเจกต์คือ iOS 18 (`IPHONEOS_DEPLOYMENT_TARGET: "18.0"` ใน `project.yml`) — ตอนนี้มี
3 จุดที่ guard ไว้แบบนี้: `WBW/HomeView.swift:110`, `WBW/GlassSurface.swift:8`, `WBW/WelcomeView.swift:60`
เพิ่มจุดใหม่ก็ต้อง guard แบบเดียวกันเสมอ

**ห้ามปลอมกระจกด้วย blur เอง** (เช่น `.blur()` + opacity ผสมมือ) — ผลลัพธ์ไม่เนียนเท่า `.glassEffect`
จริงของ iOS 26 และ fallback ที่ถูกต้องมีอยู่แล้วใน `glassSurface`

## ไฟล์ใหม่วางที่ไหน

จอเดี่ยว ๆ วางแบน ๆ ที่ราก `WBW/` (เช่น `WBW/HomeView.swift`, `WBW/WelcomeView.swift`) แตกเป็นโฟลเดอร์
ย่อยเมื่อฟีเจอร์เกิน ~3 ไฟล์ ของจริงที่มีอยู่ตอนนี้:

- `WBW/Map3D/` — 5 ไฟล์ (`Map3DCamera`, `Map3DGeo`, `Map3DLocation`, `Map3DPins`, `Map3DScreen`)
- `WBW/Chat/` — 5 ไฟล์ (`ChatBubble`, `ChatDTOs`, `ChatRow`, `ChatSession`, `ChatToast`)
- `WBW/Feedback/` — 4 ไฟล์ (`CheckinToast`, `FeedbackOutbox`, `FeedbackStore`, `FeedbackView`)
- `WBW/Scene3D/` — 7 ไฟล์ (ฉากป่า — **ปิดอยู่ตอนนี้แต่ไม่ได้ลบ** ดู `Config.forest3D` ใน
  `backend-and-config.md`)
- `WBW/Resources/` — asset สามมิติ (`.usdz`, `.glb` ใต้ `models/`) ไม่ใช่โค้ด Swift

## จอที่ยังไม่มีของจริง

SU RUN (`WBW/SURunView.swift`) เป็น **จอว่างสนิท** มีแต่พื้นหลัง ไม่มีตัวหนังสือสักตัว

เดิมเป็นแดชบอร์ดที่ทุกตัวเลขมาจาก `SURunMock` (ก้าว/ระยะทาง/เวลา/แคลอรี/อันดับ) พร้อมบล็อก MAP
ปลอมกับปุ่ม "Start now!" ที่ไม่ทำอะไร — ล้างออกหมดแล้วเพราะยังไม่มี endpoint รองรับทั้งฝั่ง Go และ
Node ปล่อยตัวเลขปลอมไว้เสี่ยงให้คนเข้าใจว่าระบบนับก้าวให้จริง (`SURunRankingView.swift` กับ
`SURunMock.swift` ถูกลบไปแล้ว ดึงคืนจาก git ได้ถ้าจะรื้อฟื้น)

**ว่างสนิทตรงนี้เป็นข้อยกเว้นที่เจ้าของงานสั่ง ไม่ใช่ค่าปริยาย** — จอที่ปิดฟีเจอร์ชั่วคราวที่เหลือใช้
แบบของ `WBW/Map3D/Map3DScreen.swift` คือเหลือไอคอน + ข้อความสั้น ๆ ("แผนที่ 3D ปิดชั่วคราว")
เพื่อไม่ให้ดูเหมือนแอปพัง · จอใหม่ที่ยังไม่เสร็จให้ทำตามแบบหลัง ไม่ใช่แบบ SU RUN

## คอมเมนต์

เขียนภาษาไทย บอก **"ทำไม"** ไม่ใช่ **"ทำอะไร"** — โค้ดอ่านเองได้อยู่แล้วว่าทำอะไร สิ่งที่โค้ดบอกไม่ได้คือ
อาการที่จะเจอถ้าทำผิดทาง

ตัวอย่างของจริง: คอมเมนต์หัวไฟล์ `WBW/BackendCacheKey.swift` อธิบายว่าทำไมไฟล์นี้ถึงแยกออกจาก
`Config.swift` — เพราะ `Config.swift` มีบรรทัด `Config.backend` ที่สลับไปมาระหว่างทดสอบและห้าม commit
แยกไฟล์ไว้ทำให้แก้ `cacheNamespace` แล้ว `git add` ได้เลยโดยไม่ดึงบรรทัดที่สลับค้างอยู่ติดไปด้วย — ดีเพราะ
บอกอาการ (จะ commit `Config.backend` หลุดไปโดยไม่ตั้งใจ) ไม่ใช่แค่บอกว่า "แยกไฟล์ไว้เก็บ cache key"

## ต้นทาง UI

ดีไซน์อ้างอิง Figma DOI-APP ไฟล์ `EKkcnLzTFz8zGjtO8ay70U`
