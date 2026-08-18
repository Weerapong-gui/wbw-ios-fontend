# ชุดส่ง App Store — 1.0 (8)

รอบ 1.0 (7) โดนตีกลับ 2 ข้อเมื่อ 2026-08-09 (submission `30d177e2-a7d0-4be5-9050-5f47f2ba69f3`)
โฟลเดอร์นี้เก็บของที่ใช้ตอบกลับและอัปโหลดใหม่

- `review-reply-1.0-8.md` — ข้อความที่จะตอบใน App Store Connect
- `screenshots/6.5/` — 1242×2688 (iPhone 11 Pro Max) 9 ใบ
- `screenshots/6.9/` — 1320×2868 (iPhone 17 Pro Max) 9 ใบ

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

จอ SU RUN ถ่ายตอน "กำลังเดินอยู่จริง": ป้อนพิกัดตามเส้นทางจริงเข้าเครื่องด้วย
`xcrun simctl location <dev> start --speed=6 --interval=1 <lat,lng ...>` แล้วส่ง `-uitestRunStart 1`
ตัวเลขบน HUD จึงมาจากการคำนวณของแอปจริงทั้งหมด ไม่ใช่ค่าที่ยัดไว้ (ช่อง "ก้าว" ขึ้น `—` เพราะ
simulator ไม่มีตัวนับก้าว ซึ่งเป็นพฤติกรรมที่ตั้งใจ)

## 9 จอที่ถ่าย

| ไฟล์ | จอ | โชว์อะไร |
|---|---|---|
| `01-home` | หน้าหลัก | ดอกไม้ Bloom ขั้น "บานครึ่ง" + อุณหภูมิ/AQI + เช็คอินแล้ว 5/12 ฐาน |
| `02-surun` | SU RUN | แผนที่ + เส้นทาง 8.36 กม. + HUD ระยะ/pace/เวลา ระหว่างเดินจริง |
| `03-map` | แผนที่ 3D | โมเดลพื้นที่งาน + หมุดฐาน + การ์ดฐานเปิดอยู่ |
| `04-chat` | แชทกลุ่ม | บทสนทนาหลายคน + สถานะอ่านแล้ว |
| `05-groupjoin` | เข้ากลุ่ม | รายชื่อกลุ่ม + ที่นั่งเหลือ + สถานะเต็ม |
| `06-ticket` | บัตรผู้เข้าร่วม | ชื่อ/สำนักวิชา/บาร์โค้ด + ปุ่ม Medical ID |
| `07-notif` | ประกาศ | คละระดับ info/warning/emergency |
| `08-feedback` | ให้คะแนนฐาน | ฟอร์ม 3 ระดับ + ช่องความเห็น |
| `09-qr` | QR ของฉัน | QR สำหรับให้เจ้าหน้าที่สแกนเช็คอิน |
