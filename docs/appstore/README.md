# ชุดส่ง App Store — 1.0 (10)

รอบ 1.0 (7) โดนตีกลับ 2 ข้อเมื่อ 2026-08-09 (submission `30d177e2-a7d0-4be5-9050-5f47f2ba69f3`)
โฟลเดอร์นี้เก็บของที่ใช้ตอบกลับและอัปโหลดใหม่

- `connect-checklist.md` — **เริ่มที่นี่ก่อนส่ง** รายการติ๊กของทุกอย่างที่ ASC ต้องการ
  แต่โค้ดทำแทนไม่ได้ (ทรงเดียวกับที่โปรเจกต์ Club Fair ใช้) พร้อมลำดับการอัปโหลดที่
  สลับแล้วโดนตีกลับซ้ำ
- `review-reply-1.0-10.md` — ข้อความที่จะตอบใน App Store Connect รอบปัจจุบัน
  (`review-reply-1.0-8.md` = รอบก่อน เก็บไว้อ้างอิง)
- `screenshots/6.5/` — 1242×2688 (iPhone 11 Pro Max) 10 ใบ
- `screenshots/6.9/` — 1320×2868 (iPhone 17 Pro Max) 10 ใบ

**เพดานของ App Store คือ 10 ใบต่อขนาด** — ตอนนี้เต็มพอดี เพิ่มใบใหม่ต้องถอดใบเก่าออกก่อน

**อัปโหลดต้องทำมือ** — เมนู Previews and Screenshots → "View All Sizes in Media Manager"
สคริปต์ในเครื่องอัปให้ไม่ได้

## ถ่ายใหม่ยังไง

ทุกใบถ่ายจาก **โหมดเดโม่** ข้อมูลจึงซ้ำได้เป๊ะทุกครั้งและไม่มีข้อมูลของผู้เข้าร่วมจริงหลุดออกมา
ไม่มีใบไหนเป็นหน้า splash หรือหน้าล็อกอิน — Apple เขียนไว้ตรง ๆ ในใบตีกลับว่าสองอย่างนั้นไม่นับว่า
"app in use" ซึ่งเป็นเหตุผลของ 2.3.3 รอบที่แล้ว

```bash
# 1. simulator ที่ต้องมี (สร้างครั้งเดียว)
xcrun simctl create "iPhone 11 Pro Max" com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-26-5
xcrun simctl create "iPhone 17 Pro Max" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-26-5

# 2. ล้างเครื่องก่อนเสมอ (เหตุผลด้านล่าง)
xcrun simctl erase <device-id>

# 3. build Debug แล้วยิง launch args ทีละจอ (ตารางเต็มอยู่ที่ .claude/skills/wbw-ios/build-and-run.md)
xcrun simctl launch <device-id> th.ac.mfu.wbwSwift -uitestDemo 1 -uitestTab 0
xcrun simctl io <device-id> screenshot --type=png 01-home.png
```

**`simctl erase` ก่อนถ่ายทุกครั้ง ห้ามข้าม** — dialog ขอสิทธิ์ที่ไม่มีใครกดตอบจะค้างอยู่ใน SpringBoard
ข้ามการ uninstall/install ของแอปไปเรื่อย ๆ แล้วบังทุกใบที่ถ่ายหลังจากนั้น · รอบนี้เสียเวลาไล่หา
สาเหตุในโค้ดไปหลายรอบทั้งที่โค้ดไม่ได้ผิด

จอ SOS (`10-sos`) ต้องใส่ `-uitestPassBottom 1` — ปุ่มอยู่ใต้การ์ดซึ่งสูงกว่าจอ ไม่มีแฟลกนี้ถ่ายไม่เห็น
· **ตั้งเครื่องเป็นภาษาไทยก่อนถ่าย** (`defaults write -g AppleLanguages -array th` แล้ว reboot ซิม)
ไม่งั้นจะได้อังกฤษทั้งชุด · แถบสถานะให้ตรงกันด้วย `xcrun simctl status_bar <dev> override
--time "09:41" --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4
--batteryState charged --batteryLevel 100`
· **แบนเนอร์แจ้งเตือนของ iOS เองบังหัวจอได้** (เจอจริงตอนถ่ายใบ 6.9 — "พร้อมแล้วสำหรับ Apple
Intelligence" ทับแถบบนทั้งแถบ) ถ่ายแล้วต้องเปิดรูปดูทุกใบ ไม่ใช่เชื่อว่าคำสั่งไม่ error แปลว่ารูปใช้ได้

**โหมดเดโม่ต้องไม่ขอสิทธิ์อะไรเลย ไม่งั้นกล่องค้างบังทุกใบที่เหลือ** — เจอจริงรอบนี้:
`Map3DLocation.start()` ไม่มีประตูกันโหมดเดโม่ กล่องขอตำแหน่งจึงเด้งที่ใบที่สอง (แท็บแผนที่)
แล้วบัง 9 ใบจาก 10 เพราะไม่มีใครกดตอบ · `WBWTests/DemoPermissionTests.swift` กันไว้แล้ว

*(จอ SU RUN ถูกลบออกจากโปรเจกต์แล้ว 2026-08-22 — ขั้นตอนถ่ายจอนั้นระหว่างเดินจริงจึงหายไปด้วย)*

## 10 จอที่ถ่าย

ชุดนี้ถ่ายใหม่ทั้งหมด 2026-08-22 — **ชุดเดิม (2026-08-19) ใช้ไม่ได้แล้ว** แอปถูกออกแบบใหม่
ทั้งหน้า Home (ภาพวาดสว่าง 5 แท็บมีไอคอนคนวิ่ง → ภาพถ่ายมืด แท็บคนละชุด) และหน้าบัตร
(ป้ายห้อยขาว + บาร์โค้ด → การ์ดกระจก + QR) · Guideline 2.3.3 คือหนึ่งในสองข้อที่โดนตีกลับ
รอบ 1.0 (7) การส่งรูปที่ไม่ตรงกับแอปคือการเดินเข้าไปเจอข้อเดิมซ้ำ

**สองจอในชุดเดิมหายไป** — จอ SU RUN (จับระยะเดิน/นับก้าว) ถูก**ลบออกจากโปรเจกต์**
2026-08-22 เพราะงานจะไม่มีกิจกรรมนี้ · ส่วน `MyQRCodeView` (QR เต็มจอ) ยังอยู่ในโค้ดแต่
ไม่มีอะไรอ้างถึงเลยทั้งแอป ผู้ใช้กดเข้าไม่ได้ · ที่ว่างสองใบแทนด้วย `05-activities`
กับ `09-medical` ซึ่งเข้าถึงได้จริง

| ไฟล์ | จอ | launch args (ต่อจาก `-uitestDemo 1`) |
|---|---|---|
| `01-home` | หน้าหลัก — ดอกไม้ Bloom + อุณหภูมิ/AQI + เช็คอินแล้ว 5/12 ฐาน | `-uitestTab 0` |
| `02-map` | แผนที่ 3D + การ์ดฐานเปิดอยู่ | `-uitestTab 1 -uitestMapPin 5` |
| `03-chat` | แชทกลุ่ม | `-uitestChat 1` |
| `04-groupjoin` | เข้ากลุ่ม — ที่นั่งเหลือ/เต็ม | `-uitestDemoNoGroup 1 -uitestTab 2` |
| `05-activities` | แท็บกิจกรรม | `-uitestTab 3` |
| `06-pass` | บัตรผู้เข้าร่วม — ชื่อ/สำนักวิชา/บิบ/QR | `-uitestTab 4` |
| `07-notif` | ประกาศ คละระดับ | `-uitestNotifications 1` |
| `08-feedback` | ให้คะแนนฐาน | `-uitestFeedback 5` |
| `09-medical` | ข้อมูลการแพทย์ | `-uitestProfile 1 -uitestMedical 1` |
| `10-sos` | บัตรเลื่อนลงสุด — ปุ่มขอความช่วยเหลือฉุกเฉิน | `-uitestTab 4 -uitestPassBottom 1` |

**`02-map` ต้องรอนานกว่าใบอื่นมาก** — `map.usdz` หนัก 9.4 MB (entity 2,201 ก้อน) 13 วิได้
ตัวหมุน "กำลังโหลดแผนที่" แทนโมเดล · 6.5 ใช้ 40 วิพอ ส่วน 6.9 ต้องถึง 90 วิ
