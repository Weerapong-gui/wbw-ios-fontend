# build / รัน / เก็บสกรีนช็อต

ไฟล์นี้ตอบว่า build/test ยังไงให้ผ่านจริง, ลงรันบน simulator ยังไง, args ที่โค้ดรองรับสำหรับข้าม UI มี
อะไรบ้าง, และ (บันทึกไว้) เคยรันบนเครื่องจริงยังไง — เรื่อง backend/`Config.backend` ดูที่
`.claude/skills/wbw-ios/backend-and-config.md` แทน ไม่ซ้ำที่นี่

## XcodeGen มาก่อนเสมอ

`WBW.xcodeproj/` อยู่ใน `.gitignore` (`git ls-files WBW.xcodeproj | wc -l` → `0`) — ไฟล์ที่ commit จริง
และเป็นของจริงคือ `project.yml` เพิ่ม/ลบ/ย้ายไฟล์ใน `WBW/` แล้วต้อง `xcodegen generate` ก่อน build เสมอ
ไม่งั้น Xcode มองไม่เห็นไฟล์ใหม่/ยังอ้างไฟล์ที่ลบไปแล้ว ห้ามแก้ `.xcodeproj` ด้วยมือ — แก้แล้วหายเมื่อรัน
`xcodegen generate` รอบถัดไปอยู่ดี

## build

```bash
xcodegen generate
```

รันก่อนเสมอหลังแก้ `project.yml` หรือเพิ่ม/ลบ/ย้ายไฟล์ใน `WBW/` — สร้าง `WBW.xcodeproj/` ใหม่ (ที่ไม่ถูก
commit)

```bash
xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

เช็คว่า build ผ่านจริงบน sim ตัวที่จะรันจริงต่อ (ต้องมี sim ชื่อนี้อยู่ในเครื่อง)

```bash
xcodebuild -scheme WBW -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
```

เช็คไวว่า compile ผ่านเฉยๆ ไม่ต้องมี sim ตัวไหน booted อยู่จริง — ใช้ก่อน commit ตอนไม่อยากรอ boot

```bash
xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

รัน `WBWTests` ทั้งชุด (165 เทสตอนที่เขียนไฟล์นี้) ก่อน push/PR — รอบแรกที่รันเพื่อยืนยันไฟล์นี้เจอเทสตัว
หนึ่ง (`CheckinProgressStoreTests.testClearResetsPendingDiffState`) ที่ทำให้โฮสต์เทสแครช/timeout จน
xcodebuild ต้อง restart runner กลางคัน (ปรากฏเป็น `** TEST FAILED **`) — รันซ้ำอีกรอบผ่านสะอาด
(`** TEST SUCCEEDED **`, 165/165) ไม่มี error/log อื่นระหว่างนั้น สรุปว่าเป็นอาการแครชของตัว test host
เอง ไม่ใช่ assertion พังจากโค้ดแอป ถ้าเจอ `** TEST FAILED **` ครั้งเดียวแบบไม่มี assertion message ให้ลอง
รันซ้ำก่อนตีความว่าโค้ดพัง

## รันบน simulator

```bash
xcrun simctl boot 'iPhone 17'   # ข้ามได้ถ้า boot อยู่แล้ว — เช็คด้วย `xcrun simctl list devices | grep Booted`
APP=$(xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' -showBuildSettings 2>/dev/null \
  | awk -F'= ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)/WBW.app
xcrun simctl install booted "$APP"
xcrun simctl launch booted th.ac.mfu.wbwSwift
xcrun simctl io booted screenshot /tmp/wbw.png
```

`install` เงียบถ้าไม่มี error · `launch` คืน pid ทันที (ไม่ใช่สัญญาณว่าจอขึ้นแล้ว รอสักครู่ก่อน screenshot)
· ไม่ต้องมี JWT ก็ verify เส้นทาง install/launch ได้ — เห็นจอ login ก็พอ ต่อ `-uitestTab`/`-uitestToken`
ท้าย `launch` เพื่อข้ามไปหน้าที่ต้องการตรงๆ (ดู `## launch args`)

## launch args

ไม่มี tooling กดจอในสภาพแวดล้อมนี้ (ไม่มี idb) — args พวกนี้จึงเป็นทางเดียวที่จะเห็นจอชั้นในของแอปแบบ
ไม่ต้องกดมือ ทุกคีย์ตรวจด้วย `grep -rn "uitest" WBW --include='*.swift'` แล้วอ่านจุดที่โค้ดใช้จริง เป็น
`#if DEBUG` ทั้งหมด (build Release อ่านคีย์พวกนี้ไม่ได้)

| คีย์ | ค่า | ผล |
|---|---|---|
| `-uitestToken <jwt>` | JWT string | ล็อกอินทันทีด้วย token นี้ (`Session.swift`) — ข้าม splash ด้วย |
| `-uitestUser <username>` | string, default `tester` | คู่กับ `-uitestToken` เป็นชื่อผู้ใช้ |
| `-uitestRole participant` | string, default `participant` | คู่กับ `-uitestToken` เป็น role |
| `-uitestLogin` | flag | ข้ามสแปลชตรงไปหน้า Login โดยไม่ต้องมี token |
| `-uitestTab 0-4` | int | แท็บเริ่มต้นตอน launch เท่านั้น (ดูตาราง index ด้านล่าง) |
| `-uitestTabSequence "<วิ>:<แท็บ>,..."` | string | สลับแท็บสดระหว่างแอปรันอยู่ เช่น `"6:4,12:0"` |
| `-uitestChat` | flag | เปิดหน้าแชทกลุ่มตรงๆ |
| `-uitestChatCloseAfter <วินาที>` | double | ปิดแชทเองหลัง N วิ (แอปยัง foreground) |
| `-uitestNotifications` | flag | เปิดหน้าแจ้งเตือนตรงๆ |
| `-uitestFeedback <checkpointId>` | int > 0 | เปิดฟอร์มให้ความเห็นของฐานนั้นตรงๆ (id จริงเริ่มที่ 1) |
| `-uitestProgress <n>` | int | บังคับขั้นต้นไม้หน้า Home เป็น n/8 |
| `-uitestProfile` | flag | เปิดหน้าโปรไฟล์ตรงๆ (จาก Home) |
| `-uitestMedical` | flag | เปิดหน้าข้อมูลการแพทย์ตรงๆ (จาก Ticket) |
| `-uitestSettings` | flag | เปิดหน้าตั้งค่าตรงๆ (จาก Ticket) |
| `-uitestMapHeading <องศา>` | int | ทับมุมกล้อง yaw ของแผนที่ 3D ชั่วคราว |
| `-uitestMapPitch <องศา>` | int | ทับมุมเงยกล้องของแผนที่ 3D ชั่วคราว |
| `-uitestMapPin <n>` | int > 0 | บังคับให้การ์ดฐานที่ n เปิดตรงๆ บนแผนที่ |

index แท็บ (สำหรับ `-uitestTab`/`-uitestTabSequence`):

| index | แท็บ |
|---|---|
| 0 | Home |
| 1 | Map |
| 2 | SU RUN |
| 3 | Group |
| 4 | QR |

## รันบนเครื่องจริง (รันจริงล่าสุด 2026-08-03 — iPhone 13 ต่อ SUS local)

บันทึกจากการรันจริงครั้งก่อน ไม่ได้ verify ซ้ำรอบเขียนไฟล์นี้:

1. เครื่องต้องปลดล็อกแล้วกด Trust คอมพิวเตอร์นี้ก่อนเสมอ — ไม่งั้น `devicectl` ต่อเข้าไม่ติดเลยสักคำสั่ง
2. `xcrun devicectl device process launch --device <id> --console <bundle> -- -uitestToken <jwt>` —
   ต้องมี `--` คั่นก่อนอาร์กิวเมนต์ของแอป ไม่งั้น `-uitestToken` โดน `devicectl` ตีความเป็นแฟล็กของตัวเอง
   (ชน `-t`/timeout) แทน · `--console` คือสิ่งที่ทำให้เห็น log ของแอปสด ๆ ไม่มีมันจะไม่เห็นอะไรเลย
3. container ของ SUS publish พอร์ตแค่ `127.0.0.1` ต้อง forward ออกวง LAN ก่อนถึงจะยิงจากเครื่องจริงเข้าได้
   — วิธี forward ดู `docs/sus-test-backend.md` และเคส `.susLan` ใน
   `.claude/skills/wbw-ios/backend-and-config.md`
4. `-uitestToken` ชนะเฉพาะตอนติดตั้งแอปใหม่ (ไม่มี session เก่า) ถ้าแอปมี session เก็บไว้อยู่แล้วมันจะใช้
   ของเดิมทันทีโดยไม่เตือนว่ามี token ใหม่ส่งมา — ต้องลบแอปออกจากเครื่องก่อนถ้าจะบังคับ token ใหม่

## ทำไม Debug/Release แยก plist กับ entitlements

`aps-environment` ใน `WBW/WBW-Debug.entitlements` เป็น `development` ส่วน `WBW/WBW-Release.entitlements`
เป็น `production` — ผิดฝั่ง (เช่น build ที่จะขึ้น store ดันเซ็น development) แล้ว push จะไม่มาสักอันโดยไม่มี
error ให้เห็นเลย

`WBW/Info-Debug.plist` มี `NSAllowsLocalNetworking`/`NSLocalNetworkUsageDescription` ไว้ให้แอปยิงเข้า
`http://localhost`/`.susLan` ตอนเทสบนเครื่องจริงได้ — สองคีย์นี้ห้ามหลุดขึ้น store (`WBW/Info.plist` ของ
Release ไม่มี) commit `8dfa5d4` เคยลืมเติม `NSLocalNetworkUsageDescription` ตอนใช้วิธี "ลบแล้วค่อยเติม
กลับ" มาแล้ว จึงแยกเป็นคนละไฟล์ถาวรแทน (ดูคอมเมนต์หัวไฟล์ `WBW/Info-Debug.plist` และ `configs:` ใน
`project.yml`) — เพิ่มคีย์อะไรต้องเพิ่มทั้งสองไฟล์ ไม่งั้น `AppStoreConfigTests` fail (โดยเฉพาะ
`testDebugPlistDiffersFromReleaseOnlyByTheAllowedKeys` และ `testApsEnvironmentMatchesItsConfiguration`)
