# ธรรมเนียม UI

ไฟล์นี้ตอบว่าสีธีมมีอะไรบ้าง, Liquid Glass ใช้ยังไง, ไฟล์จอใหม่วางตรงไหน, และคอมเมนต์ในโค้ดควรเขียนแบบ
ไหน — เรื่อง backend/`Config` ดูที่ `.claude/skills/wbw-ios/backend-and-config.md`, เรื่อง build/รัน ดูที่
`.claude/skills/wbw-ios/build-and-run.md` แทน ไม่ซ้ำที่นี่

## สีธีม

ประกาศเป็น `extension Color` ใน `WBW/Config.swift` (บรรทัด 63 เป็นต้นไป) ครบ 5 ตัว:

| ชื่อ | hex | ใช้ทำอะไร |
|---|---|---|
| `Color.wbwCream` | `#DEC684` | สีครีมหลักของธีม DOI-APP |
| `Color.wbwInk` | `#2B2B2B` | สีตัวอักษร/เส้นเข้ม |
| `Color.wbwGold` | `#C99A1F` | สีทอง |
| `Color.wbwGreen` | `#40916C` | เขียวป่า ใช้ตอน toggle เปิด |
| `Color.wbwForestVoid` | `#0A1610` | พื้นหลังทึบแทนฉากป่าตอน `Config.forest3D` ปิด (สีเดียวกับ scrim เดิมของ `ForestOverlay`) — รายละเอียด flag ดู `backend-and-config.md` |

กติกา: **ใช้ของที่มี ห้ามหว่าน hex ใหม่ในจอเดียว** — เจอสีที่ยังไม่มีใน 5 ตัวนี้ ให้เพิ่มเป็น `static let`
ใหม่ใน `WBW/Config.swift` ก่อน อย่าฝัง `Color(red:green:blue:)` แยกไว้กลางไฟล์จอ

## Liquid Glass

`func glassSurface<S: Shape>(_ shape: S, interactive: Bool = false)` ใน `WBW/GlassSurface.swift` คือตัว
กลางที่ใช้ซ้ำได้ — เรียกผ่าน `extension View` เช่น `.glassSurface(Capsule())` เวลาจะเอาพื้นผิวกระจกใช้
ตัวนี้ ไม่ต้องเขียนเอง

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

## จอที่ยังเป็น mock

SU RUN (`WBW/SURunView.swift`) กับ SU RUN Ranking (`WBW/SURunRankingView.swift`) กินข้อมูลจาก
`WBW/SURunMock.swift` ทั้งหมด (ชื่อ, เลขก้าว, ตารางอันดับ) — ยังไม่มี backend จริงรองรับ อย่าเผลออ่านโค้ด
สองจอนี้แล้วสรุปว่าเป็นของเสร็จแล้วต่อ backend จริง ต่อ endpoint จริงเมื่อไหร่ค่อยเอา `SURunMock` ออก

## คอมเมนต์

เขียนภาษาไทย บอก **"ทำไม"** ไม่ใช่ **"ทำอะไร"** — โค้ดอ่านเองได้อยู่แล้วว่าทำอะไร สิ่งที่โค้ดบอกไม่ได้คือ
อาการที่จะเจอถ้าทำผิดทาง

ตัวอย่างของจริง: คอมเมนต์หัวไฟล์ `WBW/BackendCacheKey.swift` อธิบายว่าทำไมไฟล์นี้ถึงแยกออกจาก
`Config.swift` — เพราะ `Config.swift` มีบรรทัด `Config.backend` ที่สลับไปมาระหว่างทดสอบและห้าม commit
แยกไฟล์ไว้ทำให้แก้ `cacheNamespace` แล้ว `git add` ได้เลยโดยไม่ดึงบรรทัดที่สลับค้างอยู่ติดไปด้วย — ดีเพราะ
บอกอาการ (จะ commit `Config.backend` หลุดไปโดยไม่ตั้งใจ) ไม่ใช่แค่บอกว่า "แยกไฟล์ไว้เก็บ cache key"

## ต้นทาง UI

ดีไซน์อ้างอิง Figma DOI-APP ไฟล์ `EKkcnLzTFz8zGjtO8ay70U`
