# บันทึกการตรวจ — รอบแก้ App Review 1.0 (8)

วันที่ 2026-08-19 · ทุกข้อด้านล่างรันจริงบนเครื่องนี้ ไม่ได้อ่านโค้ดแล้วสรุปเอา

## 1. ต้นตอของ Guideline 2.1 — ยิงจริงยืนยันแล้ว

| ยิงอะไร | ผล |
|---|---|
| `POST https://api.studentunion.social/wbw/auth/login` `{"username":"6939999999","password":"WbwReview2026!"}` | **401** `{"error":"username หรือ password ไม่ถูกต้อง"}` |
| `GET /wbw/admin/schools` · `GET /wbw/notifications/public` | 200 — backend prod ไม่ล่ม |
| `GET /wbw/capacity` | `{"max":2000,"taken":2000,"seats_left":0,"full":true}` |
| `POST /wbw/auth/register` (ลองสมัคร `6939999999` ใหม่) | **409** `ที่นั่งเต็มแล้ว — ปิดรับสมัคร` |
| `git log -p -- WBW/Config.swift` | `.susProd` ตั้งแต่ `8500875` (2026-08-04) ไม่มีอะไรแตะอีก |

สรุป: บัญชีไม่มีอยู่จริง (หรือรหัสไม่ตรง) และ **สมัครใหม่ทดแทนไม่ได้** เพราะงานเต็ม 2000/2000
ที่นั่ง (CHECK constraint `taken_within_max`, migration `000021_wbw_capacity`) — ไม่ใช่ปัญหา
backend ล่ม ไม่ใช่ build ชี้ผิด ไม่ใช่ OTP ไม่ใช่ ATS ไม่ใช่ validation ฝั่ง client

### แก้แล้ว 2026-08-19 — เพิ่มที่นั่งเป็น 2001 แล้วสมัครบัญชีรีวิวใหม่

แถว `6939999999` ถูกลบไปแล้วจริง (ค้นในแดชบอร์ดไม่เจอ) ที่นั่งทั้ง 2000 เป็นนักศึกษาจริงล้วน
จึงเปิดที่นั่งเพิ่มหนึ่งที่แทนการไปยุ่งกับแถวของใคร

**กลไกที่ตรวจก่อนแตะอะไร** (`ssh park@100.109.2.36`, container `postgres-db`):

- `wbw_capacity` มีแถวเดียว (`id boolean PRIMARY KEY DEFAULT true`) คอลัมน์ `max_participants`,
  `taken`, `updated_at` · CHECK `taken_within_max` คือ `taken <= max_participants`
- ตัวนับมาจาก trigger `trg_participant_count` บน `wbw_user`
  (`AFTER INSERT OR DELETE OR UPDATE OF role`) → `sync_participant_count()` ซึ่งเป็น `+1/-1`
  ตรงไปตรงมา · **เพิ่ม `max_participants` จึงแค่ผ่อน CHECK ไม่แตะแถวผู้ใช้เลยสักแถว**

**ลำดับที่ทำจริง**

| ขั้น | ผล |
|---|---|
| สำรอง `pg_dump` ก่อนเขียน | `/home/park/sudb-before-cap2001-20260819-050348.sql` · 22.8 MB · นับในไฟล์ได้ `participant_profile` 2000 แถว, `wbw_user` 2015 แถว (2000 participant + 12 staff + 3 admin) ตรงกับ DB เป๊ะ |
| `UPDATE wbw_capacity SET max_participants = 2001, updated_at = now() WHERE id;` | `UPDATE 1` → `max 2001 / taken 2000` · participant ยัง 2000 ทั้ง `wbw_user` และ `participant_profile` |
| `POST /wbw/auth/register` | **201** `user_id 196a9af8-787b-414f-a627-f77e6e91ed54` |
| `POST /wbw/auth/login` `6939999999` / `WbwReview2026!` | **200** + token |
| `GET /wbw/me` ด้วย token นั้น | **200** · BIB 2006 · มี `qr_token` · `group_id` = null · เช็คอิน 0 ฐาน |
| นับซ้ำหลังเสร็จ | `max 2001 / taken 2001` · participant 2001 · **`WHERE username <> '6939999999'` = 2000 พอดี** → ไม่มีนักศึกษาจริงหายหรือเปลี่ยนแม้แต่คนเดียว |

**ไม่มี DELETE ถูกรันเลยตลอดกระบวนการ** คำสั่งเขียนมีคำสั่งเดียวคือ UPDATE ข้างบน

**ข้อจำกัดของบัญชีนี้:** เป็นแถวใหม่เอี่ยม ยังไม่ได้เข้ากลุ่มและยังไม่เคยเช็คอิน แท็บกลุ่มจึงเป็นจอ
"เข้ากลุ่ม" ไม่ใช่แชท และไม่มีฟอร์มให้คะแนนฐาน — **Demo Mode คือทางที่โชว์ได้ครบกว่า** จดหมาย
ตอบ Apple จึงชี้ไปที่ Demo Mode เป็นหลักและบอกข้อจำกัดนี้ตรง ๆ

**ตรวจเรื่องข้อมูลส่วนบุคคลแล้ว:** ยิง `GET /wbw/groups/members/index` ด้วย token ของบัญชีรีวิว
คืน **0 รายชื่อ** เพราะยังไม่มีผู้เข้าร่วมคนไหนเข้ากลุ่มเลย (คอลัมน์ Group ในแดชบอร์ดเป็น `—` ทั้งหมด)
reviewer จึงไม่เห็นชื่อนักศึกษาจริงสักคน · **ห้ามเอาบัญชีรีวิวเข้ากลุ่ม** เพราะจะเปลี่ยนข้อเท็จจริงข้อนี้

**วิธีย้อนกลับหลังรีวิวผ่าน** (ตามลำดับนี้เท่านั้น — สลับลำดับจะชน CHECK เพราะตอนนี้ `taken = max`):

```sql
-- 1) ลบบัญชีรีวิว (trigger ลด taken เป็น 2000 ให้เอง)
DELETE FROM wbw_user WHERE username = '6939999999';
-- 2) ค่อยลดเพดานกลับ
UPDATE wbw_capacity SET max_participants = 2000, updated_at = now() WHERE id;
```

## 2. build / test

| คำสั่ง | ผล |
|---|---|
| `xcodegen generate` | ผ่าน |
| `xcodebuild -configuration Debug -destination 'generic/platform=iOS Simulator' build` | `** BUILD SUCCEEDED **` |
| `xcodebuild -configuration Release -destination 'generic/platform=iOS Simulator' build` | `** BUILD SUCCEEDED **` |
| `xcodebuild -destination 'platform=iOS Simulator,name=iPhone 17' test` | `** TEST SUCCEEDED **` · **260 เทส 0 fail** (ฐานเดิม 249 ก่อนเพิ่มเทสโหมดเดโม่) |
| `./scripts/check-skill-refs.sh` | `skill ยังตรงกับ repo` |

## 3. ตรวจ binary ที่จะส่งขึ้น store

รันบน `Release-iphonesimulator/WBW.app`:

- `ดูตัวอย่างแอป` (ปุ่ม Demo) — **พบใน binary** → โหมดเดโม่ติดไปกับ build ที่ส่งจริง ไม่ได้อยู่ใน `#if DEBUG`
- `uitestDemo` / `uitestToken` — **ไม่พบ** → launch args ทั้งชุดถูกตัดออกจาก Release ตามเดิม
- `route_wbw.json` — อยู่ใน bundle
- `CFBundleVersion` = **8** (ของเดิมค้างที่ 2 ทั้งที่ส่งไปแล้วถึง build 7 — ไม่บั๊มก่อน archive
  App Store Connect จะปฏิเสธไฟล์ตั้งแต่ตอนอัป)
- `NSMotionUsageDescription` — มีทั้ง `Info.plist` และ `Info-Debug.plist` (`InfoPlistParityTests` คุมอยู่)

## 4. สกรีนช็อต (Guideline 2.3.3)

9 ใบ × 2 ขนาด ถ่ายจากโหมดเดโม่บน simulator จริง — `docs/appstore/screenshots/6.5/` (1242×2688)
และ `/6.9/` (1320×2868) · ไม่มีใบไหนเป็น splash หรือหน้าล็อกอิน · รายละเอียดวิธีถ่ายอยู่ที่
`docs/appstore/README.md`

จอ SU RUN ถ่ายตอนกำลังเดินจริง (ป้อนพิกัดตามเส้นทางเข้าเครื่องด้วย `simctl location start`)
HUD อ่านได้ **117 ม. · — ก้าว · 2:47 นาที/กม. · 0:20** — ทุกตัวเลขมาจากการคำนวณของแอปเอง
ช่อง "ก้าว" ขึ้น `—` เพราะ simulator ไม่มีตัวนับก้าว ซึ่งเป็นพฤติกรรมที่ตั้งใจ (ไม่ใช่ `0`)

## 5. บั๊กที่เจอระหว่างถ่ายรูป และแก้ไปแล้ว

**แอปขอสิทธิ์ตำแหน่งทันทีที่ล็อกอินเสร็จ ทั้งที่ยังอยู่หน้า Home** — `TabView` แบบ `Tab(value:)`
ของ iOS 18+ สร้างเนื้อของทุกแท็บตั้งแต่ตอน mount และ `MapKit.Map` ของแท็บ SU RUN ขอสิทธิ์เอง
ทันทีที่ถูกสร้าง · ยืนยันว่าไม่ใช่โค้ดเราเรียกด้วยการใส่ `NSLog` ที่ทุกจุดที่เรียก
`requestWhenInUseAuthorization` แล้ว log ว่างเปล่าแต่ dialog ยังเด้ง จากนั้น bisect ด้วยการปิด
`Map` ชั่วคราวแล้ว dialog หายไป

แก้ด้วยการส่ง `isActive` เข้าไปทั้ง `Map3DScreen` และ `SURunView` แล้วหน่วงการสร้างของจริง
ไว้จนกว่าแท็บนั้นจะถูกเลือก

**dialog ค้างใน SpringBoard หลอกให้ไล่หาสาเหตุผิด** — dialog ขอสิทธิ์ที่ไม่มีใครกดตอบค้างข้าม
การ uninstall/install ของแอปไปเรื่อย ๆ แล้วบังทุกใบที่ถ่ายหลังจากนั้น · ต้อง `xcrun simctl erase`
ก่อนถ่ายเสมอ (จดไว้ที่ `build-and-run.md` แล้ว)

## 6. ที่ยังไม่ได้ทำ

- **ยังไม่ได้รันบนเครื่องจริง** — ตัวนับก้าว (`CMPedometer`) กับความแม่นของ GPS ตรวจบน simulator
  ไม่ได้จริง ต้องเดินจริงสักรอบก่อนส่ง
- **ยังไม่ได้ commit** — เจ้าของงานยังไม่ได้สั่ง
- **SOS** ยังไม่เอาเข้า (ตัดสินใจไว้ตอนวางแผน — ทำเป็น 1.1 หลังผ่านรีวิว)
