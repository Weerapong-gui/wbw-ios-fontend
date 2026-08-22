# backend กับ Config — WBW iOS

ไฟล์นี้ตอบว่าแอปคุยกับ backend ตัวไหนได้บ้าง สลับยังไง และกับดักที่เคยกินเวลาจริงตอนสลับ/เทส มีอะไรบ้าง

## Backend มีอะไรบ้าง

ประกาศเป็น `enum Backend` ใน `WBW/Config.swift` สลับทั้งแอปด้วยค่าเดียวคือ `Config.backend`

| case | apiBase | mePath |
|---|---|---|
| `prodNode` | `https://wbw.sumfu.store` | `/auth/me` |
| `nodeLocal` | `http://localhost:4000` | `/auth/me` |
| `susLocal` | `http://localhost:8080/wbw` | `/me` |
| `susProd` | `https://api.studentunion.social/wbw` | `/me` |
| `susLan` | `http://172.25.32.8:8081/wbw` | `/me` |

`susLan` คือ IP ของ Mac ในวง LAN — ใช้ตอนรันแอปบนเครื่องจริงเท่านั้น (localhost บนมือถือคือตัวมือถือเอง)
เลข IP ข้างบนเปลี่ยนทุกครั้งที่ย้ายเน็ต หาเลขปัจจุบันด้วย `ipconfig getifaddr en0` แล้วแก้ที่ `apiBase` ของ
`case susLan` ใน `WBW/Config.swift` — สิ่งที่แก้คือเลข IP เท่านั้น ห้ามลบ/แก้ตัว case (ดูข้อถัดไป) นอกจากเลข
IP แล้ว container ของ SUS publish พอร์ตแค่ที่ `127.0.0.1` เท่านั้น ต้อง forward ออกวง LAN ก่อนถึงจะยิงจาก
มือถือเข้าได้ — วิธี forward ดู `docs/sus-test-backend.md`

## กับดักที่เคยเสียเวลาจริง

**ห้ามลบ `case susLan`** — `Backend.cacheNamespace` (`WBW/BackendCacheKey.swift`) `switch` ครบทุก case
ของ `Backend` อยู่ ส่วน `WBWTests/FeedbackOutboxTests.swift` กับ `WBWTests/CheckinProgressStoreTests.swift`
อ้าง `.susLan` ตรง ๆ ใน array literal (ไม่ใช่ `switch`) แล้ว assert ว่านับได้ 5 ตัวไม่ซ้ำกัน ถ้าลบ
`case susLan` ออก repo จะ build ไม่ผ่านเลยตอน clone ใหม่บนเครื่องอื่น สิ่งที่ต้องแก้เฉพาะเครื่องคือ **เลข
IP** ใน `apiBase` เท่านั้น ไม่ใช่ตัว case

**`Config.backend` เป็นบรรทัดที่ห้าม commit ตอนสลับไปทดสอบ** — ค่าที่อยู่ใน `WBW/Config.swift` ตอน push
คือค่าที่จะส่งขึ้น store จริง ระหว่างสลับ backend ไปมาเพื่อเทส ให้ `git add` ทีละไฟล์เสมอ อย่า `git add -A`
(นี่คือเหตุผลที่ `cacheNamespace` ถูกแยกออกไปไว้คนละไฟล์ `BackendCacheKey.swift` — แก้ไฟล์นั้นแล้ว stage
ได้โดยไม่ดึง `Config.backend` ที่ยังสลับค้างอยู่ติดไปด้วย)

**สลับ backend แล้วต้องล้างข้อมูลแอปทุกครั้ง** — cache แชท (SwiftData) กับ cursor ใน UserDefaults ไม่ได้
ผูกกับ backend ที่มันมาจาก แต่ละ backend เดิน id ของข้อความแยกกันคนละชุด สลับแล้วไม่ล้างจะได้ 200 พร้อม
ลิสต์ว่างตลอด ไม่มี error ไม่มี log ให้เห็นเลย · รายละเอียดเพิ่มดู `docs/sus-test-backend.md`

**cache/ที่เก็บถาวรตัวใหม่ต้องแยกตาม backend เสมอ** — กติกาเดียวกับ `cacheNamespace` ด้านบนครอบ cache
ทุกตัวในแอป ไม่ใช่แค่ตัวนั้น ของจริงที่ทำตามแพทเทิร์นนี้อยู่แล้ว: `FeedbackOutbox.key(for:)`
(`WBW/Feedback/FeedbackOutbox.swift:27-29`) และ `CheckinProgressStore.cacheKey(for:)`
(`WBW/CheckinProgressStore.swift:66-68`) ต่อ string จบด้วย `backend.cacheNamespace` ทั้งคู่ — repo นี้กัน
ด้วยเทสจริง ไม่ใช่แค่ทำตามธรรมเนียม: `FeedbackOutboxTests.testKeyDiffersPerBackend`
(`WBWTests/FeedbackOutboxTests.swift:27-31`) และ `CheckinProgressStoreTests.testCacheKeyDiffersPerBackend`
(`WBWTests/CheckinProgressStoreTests.swift:9-18`) assert ว่าทั้ง 5 backend ได้ key ไม่ซ้ำกัน เพิ่ม cache
หรือ persisted key ใหม่ (UserDefaults, SwiftData ฯลฯ) แล้วไม่ต่อ `cacheNamespace` เข้าไปด้วย จะได้อาการ
เดียวกับกับดัก "สลับ backend แล้วต้องล้างข้อมูลแอป" ด้านบนซ้ำอีกรอบ: ข้อมูลจาก backend หนึ่งปนกับอีก
backend หนึ่งแบบเงียบ ๆ ไม่มี error ไม่มี log ให้เห็นเลย

**โหมดเดโม่ซ้อน namespace อีกชั้น** — `CacheScope.suffix` (`WBW/BackendCacheKey.swift`) ต่อ `.demo`
ท้ายคีย์ทุกตัวเมื่ออยู่ในโหมดเดโม่ · cache/persisted key ใหม่ต้องต่อ **ทั้งสอง** อย่าง ไม่ใช่แค่
`cacheNamespace` — ไม่งั้นข้อมูลจำลองจะค้างข้ามไปให้บัญชีจริงบนเครื่องเดียวกัน อาการเดียวกับกับดัก
"สลับ backend แล้วไม่ล้าง" เป๊ะ ๆ · `Session.clearDemoCaches()` ล้างด้วย suffix นี้ ตั้งชื่อไม่ตรง
แล้วจะล้างไม่เจอ

**โหมดเดโม่ไม่แตะ Firebase เลย** — `PushManager.configureFirebaseIfAvailable()` คืนทันทีเมื่อ
`enteringDemo()` เป็นจริง ไม่ใช่แค่ไม่ลงทะเบียน device token: ตัว Firebase Messaging เองเป็นคนทำให้
ระบบเด้ง dialog ขอสิทธิ์แจ้งเตือน (พิสูจน์แล้วว่า `requestAuthorization` ของเราไม่เคยถูกเรียก) ·
`registerCurrent()` จึงเรียก `configureFirebaseIfAvailable()` ให้เองก่อน เผื่อผู้ใช้ออกจากโหมดเดโม่
แล้วล็อกอินจริงในรอบเดียวกัน ไม่งั้นเครื่องนั้นจะไม่ได้รับ push ทั้งวันโดยไม่มีอะไรฟ้อง

**login ใช้คีย์ `username`** ไม่ใช่ `student_id` — `WBW/APIClient.swift` ส่ง
`["username": studentId, "password": password]` ต่อให้ค่าที่ผู้ใช้กรอกเป็นรหัสนักศึกษาก็ตาม ชื่อ field
ในโค้ดคือ `studentId` แต่คีย์ JSON ที่ยิงออกไปคือ `username`

## flag ปิด/เปิดฉาก

ทั้งสองอยู่ใน `enum Config` (`WBW/Config.swift`):

- **`Config.forest3D = false`** — ทุกจอที่เรียก `.forestBackground()` ได้พื้นทึบ `Color.wbwForestVoid`
  แทน `ForestSceneView`/`ForestOverlay` ไม่ถูก mount เลยสักครั้ง (ตรรกะอยู่ที่
  `ForestSceneHost.shouldClaim`) โค้ดและ asset ของฉากยังอยู่ครบ ไม่ได้ถูกลบ
- **`Config.map3D = true`** — ปิด (`false`) แล้วแท็บ Map จะโชว์การ์ดข้อความแทน ไม่โหลด `map.usdz` เลย
  สักครั้ง (ตรรกะอยู่ที่ `Map3DScreen.shouldRender`)

ตั้งค่าเริ่มต้นต่างกันโดยตั้งใจ: ฉากป่าถูกปิดจากอาการที่ยังไม่ได้วัดจริงบนเครื่อง (เครื่องทำงานหนัก)
ส่วนโมเดลแผนที่ยังไม่ถูกวัด จึงเปิดไว้ก่อนแล้วค่อยดูอาการทีหลัง

## จะแก้ฝั่ง backend

SUS (Student-Union-Server) อยู่ที่ `/Users/park/Projects/Student-Union-Server` — **แก้ได้ ไม่ใช่ของต้องห้าม** เวลา
แอปต้องการพฤติกรรม/endpoint ที่ SUS ยังไม่มี มีสองทางเลือก: แก้ SUS ตรง ๆ หรือเขียนความต้องการลง
`docs/backend-contract.md` — **ถามก่อนว่าจะเอาทางไหน อย่าเดาเอง**
