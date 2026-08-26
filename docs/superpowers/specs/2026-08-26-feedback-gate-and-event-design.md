# Feedback gate + event feedback — ยกจาก Android

**สถานะ:** อนุมัติแล้ว 2026-08-26 · ลงมือครบตามแผน `docs/superpowers/plans/2026-08-26-feedback-gate-and-event.md` (จบที่ commit `255c588`)

## ทำไม

Android (0.3.0) เปลี่ยนการให้คะแนนจาก "คำเชิญ" เป็น "เงื่อนไข": ถึงฐานแล้วฟอร์มยึดจอทันที
เดินผ่านไม่ได้ (`FeedbackGate.kt`) และจบเส้นทางแล้วถามความเห็นทั้งงานหนึ่งครั้ง
(`POST /wbw/me/event-feedback`) — เหตุผลที่ต้นทางเขียนไว้: โอกาสเดียวที่ผู้จัดจะได้ยินว่าฐาน
เป็นยังไงคือตอนคนยังยืนอยู่ตรงนั้น การ์ดชวนบน Home คือการ์ดที่ถูกเลื่อนผ่าน ตกเย็นคำตอบ
กลายเป็นความทรงจำของความทรงจำ · iOS ตอนนี้มีแค่ toast ชวน + sheet ที่ปัดทิ้งได้
ข้อมูลสองแพลตฟอร์มจึงได้ไม่เท่ากัน

## พฤติกรรมที่ยกมา (สัญญาจาก Android — ไม่ประดิษฐ์เพิ่ม)

1. **Gate ต่อฐาน** — `pending` = ฐานแรกใน `checked_in` ที่ `answered == false` (ทีละฐาน
   เรียงตามลำดับ โดนสแกนสามฐานตอนมือถืออยู่ในกระเป๋า = เจอสามฟอร์มเรียงกัน ไม่ใช่ฟอร์มเดียว
   สามหัวข้อ) · ฟอร์มแทนที่ scaffold ทั้งใบ: ไม่มีแถบแท็บ ไม่มีปุ่มปิด back ถูกกลืน
2. **ข้อยกเว้นเดียวคือ SOS** — ปุ่ม SOS มีแถวของตัวเองใต้ฟอร์ม (ไม่ลอยทับ — เคยชนปุ่มส่ง
   ซึ่งบนจอนี้กดผิดปุ่มเดียวคือแจ้งเหตุปลอมหรือไม่ได้แจ้งเหตุจริง) · เคส SOS เปิดอยู่ =
   จอ SOS ทับ gate ได้
3. **Event feedback** — เด้งเมื่อ `complete && pending == nil && !event_feedback_answered
   && !dismissedEvent` · `complete` คำนวณฝั่งเครื่อง: `total > 0 && count >= total` (งานที่
   ไม่มีฐาน = ไม่ complete ไม่ใช่ complete ตั้งแต่เกิด) · ฟอร์มถาม: ภาพรวมทั้งเดิน (บังคับ) +
   กิจกรรมตลอดเส้นทาง (ไม่บังคับ — คำถามที่ย้ายมาจากต่อฐาน) + comment
4. **`event_feedback_answered` มาจาก server** (decode จาก `me/progress` ไม่มี = `false`) —
   หลักเดียวกับ `answered` ต่อฐาน: เครื่องไม่จำเอง กัน "ลบแอป/เครื่องที่สอง แล้วถามคนที่
   ตอบแล้วซ้ำ"
5. **ปุ่มข้ามของ event form โผล่เฉพาะหลังส่งล้มเหลวจริง** — ไม่ใช่การอ่อนข้อของ gate แต่
   เพราะ `POST /wbw/me/event-feedback` **ยังไม่มีใน SUS** ไม่มีปุ่มนี้ = จบเส้นทางแล้วเจอ
   ฟอร์มที่ส่งไม่ได้ตลอดกาล ไม่มีแถบ ไม่มี back แอปจบสำหรับคนนั้น · การข้ามจำแค่ในรัน
   (in-memory) ไม่บันทึกลงดิสก์ — server ยังไม่เคยได้คำตอบ เปิดแอปใหม่ถามซ้ำคือถูกแล้ว
6. **ส่งเสร็จ gate ปิดด้วยข้อมูล ไม่ใช่ navigation** — submit แล้ว refresh progress ทันที
   gate อ่านค่าใหม่แล้วถอยเอง (ห้ามรอ poll รอบถัดไป — คือคนยืนจ้องฟอร์มที่ตอบเสร็จแล้ว
   โดยไม่มีอะไรให้กด)

## ออกแบบฝั่ง iOS

### ข้อมูล

- `CheckinProgress` (Models.swift): เพิ่ม `eventFeedbackAnswered: Bool` (decode
  `event_feedback_answered`, ขาด = `false`) + computed `complete` — สูตรเดียวกับ Android
- `APIClient.submitEventFeedback(token:draft:)` — `POST /me/event-feedback` body
  `{client_id, rating, rating_activity?, comment?, device_time}` · จำแนกผลแบบเดียวกับ
  `submitFeedback` (201/200-ซ้ำ = สำเร็จ) · **404 = ล้มเหลวแบบ terminal** (endpoint ยัง
  ไม่เกิด) — เป็นทางที่พาให้ปุ่มข้ามโผล่
- ไม่มี outbox สำหรับ event feedback — Android ก็ไม่คิว: ฟอร์มอยู่บนจอจนส่งสำเร็จหรือข้าม
  (ต่างจากต่อฐานที่คนเดินออกจากฐานไปแล้ว) `client_id` เดิมใช้ retry ตอนกดส่งซ้ำในฟอร์ม

### Logic (บริสุทธิ์ เทสตรงได้ — ตาม workflow.md)

`FeedbackGateState` enum + static func:
```swift
static func decide(progress: CheckinProgress?, eventDismissed: Bool) -> Gate?
// .base(CheckinProgressItem) | .event | nil
```
กติกาข้อ 1/3 ทั้งหมดอยู่ในฟังก์ชันนี้ — เทสไล่ทุกกิ่งโดยไม่ต้อง mount จอ

### จอ

- **Gate mount ที่ `MainTabView`** ด้วย `.fullScreenCover(item:)` +
  `.interactiveDismissDisabled()` — คุมทุกแท็บจากจุดเดียว (ที่เดียวกับที่ toast/sheet
  feedback เดิมอยู่แล้ว) · fullScreenCover ไม่มีปุ่มระบบให้หนีเอง ตรงกับ "back ถูกกลืน"
- **`FeedbackView` เดิมใช้ต่อทั้งสองแบบ** เพิ่มโหมด:
  - `blocking: Bool` — ซ่อนปุ่มปิด (toolbar "action_close" หายไปทั้งแถบ)
  - `kind: .base(checkpointId) / .event` — `.event` เปลี่ยนชุดคำถามเป็น ภาพรวม+กิจกรรม
    (คีย์ `feedback_q_overall_event*`, `feedback_q_activity_event_hint` — คำตรง Android)
    หัวจอเป็น `feedback_event_name` และ submit ยิง endpoint event
  - `.event` ส่งล้มเหลว → โชว์ error + ปุ่ม "ข้ามไปก่อน" (`feedback_give_up`
    — สเปกเดิมพิมพ์ผิดเป็น `feedback_event_give_up` แก้ให้ตรงของจริงตอน final review) —
    โผล่เฉพาะหลัง fail ตามข้อ 5
- **SOS บน gate** — แถวปุ่ม SOS ใต้ฟอร์ม (reuse `SOSButton` + เส้นทางเปิด `SOSStatusView`
  ที่มีอยู่) ตามข้อ 2 · รายละเอียดการ mount ไปเคาะตอน plan (จอ SOS ฝั่ง iOS เป็น
  fullScreenCover ของตัวเองอยู่แล้ว)
- **จังหวะรู้ว่าโดนสแกน** — iOS มีสองทางอยู่แล้ว: push `.checkinFeedbackArrived` (เร็วกว่า
  Android ที่มีแต่ poll) + poll ของ `CheckinProgressStore` · **ลด poll 60 → 20 วิ ให้เท่า
  Android** — เหตุผลต้นทาง: คนยืนอยู่หน้าฐานกับ staff ตรงหน้า เงียบเป็นนาทีอ่านว่าสแกน
  ไม่ติด · โหลดเท่าที่ SUS รับจากฝูง Android อยู่แล้ว (ยกเลิกข้อนี้ได้ถ้าเจ้าของงานห่วง
  โหลด — gate ยังทำงาน แค่ fallback ช้าลง)
- **เส้นทางเดิมที่เปลี่ยน**: toast "แตะเพื่อให้คะแนนฐานนี้" ถูก gate แทนสำหรับฐานที่ยัง
  ไม่ตอบ (gate ขึ้นเองทันที ไม่ต้องชวน) · sheet แบบปัดได้ยังอยู่สำหรับดูคำตอบเก่า
  (read-only จากแจ้งเตือน) · `dismissedEvent` เก็บใน store ระดับแอป ไม่เขียนดิสก์

### Localization

คีย์ใหม่ (th/en คำตรง Android): `feedback_event_name`, `feedback_q_overall_event`,
`feedback_q_overall_event_hint`, `feedback_q_activity_event_hint`, `feedback_give_up`
(สเปกเดิมพิมพ์ผิดเป็น `feedback_event_give_up` แก้ให้ตรงของจริงตอน final review),
ข้อความ error ส่ง event ไม่สำเร็จ · รัน `check-localization.sh`

### เอกสาร/สัญญา

- `docs/backend-contract.md`: เพิ่มแถว `POST /wbw/me/event-feedback` + ฟิลด์
  `event_feedback_answered` ใน `GET /wbw/me/progress` เป็นของที่ SUS ต้องเพิ่ม
  (ตอนนี้แอปสองฝั่งส่ง/อ่านล่วงหน้าแบบเดียวกัน)
- อัพเดต skill ถ้าจำนวนไฟล์/บรรทัดที่ถูกอ้างขยับ (`check-skill-refs.sh` ก่อน commit)

## App Store (กติกาข้อ 12)

- จอใหม่สองจอ (gate ต่อฐาน / event form) — **ไม่อยู่ในชุดสกรีนช็อต ASC** ไม่บังคับเพิ่ม
  แต่ `08-feedback` ค้างถ่ายใหม่อยู่แล้ว ถ่ายรอบเดียวกัน
- App description ยังจริง (ฟีเจอร์ให้คะแนนมีอยู่แล้ว แค่บังคับขึ้น) · ไม่มีสิทธิ์/
  background mode ใหม่ · Nutrition Label ไม่ขยับ (feedback เป็น data ที่ประกาศแล้ว)
- ข้อระวังรีวิว: gate บังคับตอบก่อนใช้แอปต่อ — Android ผ่านด้วยดีไซน์เดียวกันแล้ว และ
  ผู้ตรวจ iOS ใช้บัญชีรีวิวซึ่งไม่ถูกสแกนเข้าฐานจริง จึงไม่มีวันเจอ gate

## Verification

- เทสบริสุทธิ์ `FeedbackGateState.decide` ทุกกิ่ง (pending เรียงลำดับ · complete ขอบ
  total 0 · dismissedEvent · event_feedback_answered) — RED ก่อนตามเดิม
- เทส decode `event_feedback_answered` ขาด/มี · เทส `submitEventFeedback` ผ่าน
  URLProtocol stub (201/200/404/เน็ตล่ม)
- จอจริง: `-uitestDemo` + flag ใหม่บังคับ gate ขึ้น (ท่าเดียวกับ `-uitestFeedback`)
  สกรีนช็อตทั้งฟอร์มต่อฐานแบบ blocking และ event form + ปุ่ม SOS ในจอ
- เทสทั้งชุดผ่าน + `check-localization.sh` + `check-skill-refs.sh`
