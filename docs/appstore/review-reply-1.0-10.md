# ข้อความตอบ App Review — 1.0 (10)

ต่อจาก `review-reply-1.0-8.md` · รอบนี้ต่างจากรอบนั้นตรงที่ **ฟีเจอร์ SOS เข้ามาด้วย**
ซึ่งจดหมายฉบับก่อนไม่ได้พูดถึงเลย (ตอนนั้นวางแผนกันไว้เป็น 1.1)

> **ก่อนส่ง — สองอย่างที่ต้องเสร็จก่อน ไม่ใช่งานโค้ด**
>
> 1. **Privacy Policy URL ต้องเปิดได้จริง** — `docs/privacy-policy-draft.md` ยังมีเครื่องหมาย
>    `⟨ตัดสิน⟩` ค้างอยู่ 4 จุด (ผู้ควบคุมข้อมูล · ระยะเวลาเก็บ · การจัดการผู้เยาว์ · วันที่เผยแพร่)
>    แอปนี้เก็บ**ข้อมูลสุขภาพ** ซึ่งผู้ตรวจจะเปิดนโยบายอ่านจริง
> 2. **Privacy Nutrition Label ใน ASC ต้องตรงกับ `WBW/PrivacyInfo.xcprivacy`** — ตอนนี้ manifest
>    ประกาศ 5 ประเภท: UserID · Name · OtherUserContent · DeviceID · PreciseLocation
>    (`PhotosorVideos` ถูกถอดออกแล้วเพราะแอปไม่มีตัวเลือกรูปเลย) · **ข้อมูลสุขภาพแอปแค่แสดง
>    ไม่ได้เก็บเอง** — ผู้ใช้กรอกบนเว็บลงทะเบียน ไม่มี endpoint ไหนในแอปเขียนข้อมูลสุขภาพ

---

Hello,

Thank you for the previous review. This build (1.0 (10)) carries the fixes from the last round
plus one new feature, described below.

**Demonstration mode — unchanged and still the fastest way to review the app**

The sign-in screen has a button labelled "ดูตัวอย่างแอป (Demo)" / "Try the app (Demo)" directly
below "Sign in". It opens the full app with representative sample data — no account, no network
connection, and no server dependency. It is present in this shipping build, not only in
development builds.

The demo account in the Demo Account fields also works:

- User name: `6939999999`
- Password: `WbwReview2026!`

That account is a brand-new participant record, so it has not joined a walking group and has not
checked in anywhere; the group chat and the checkpoint feedback form have nothing to display on
it. Demonstration mode is populated and shows those screens in full.

**New in this build: an emergency help (SOS) button**

This app is the participant companion for a one-day university hiking event on a mountain trail.
Participants walk 8.36 km through twelve staffed checkpoints, and the organisers asked for a way
for a walker who is hurt to alert the event's own staff.

Please note explicitly: **this button alerts the event's staff team. It is not a call to
emergency services and the app does not present itself as one.** The status screen says so in
plain words, and the app tells the user to call 1669 (Thailand's ambulance number) in a real
emergency. The app makes no medical claims and gives no medical advice.

How it behaves for a reviewer:

- The button is on the participant pass screen. It requires a deliberate three-second press —
  a single tap does nothing — so it cannot be triggered by accident.
- **In demonstration mode nothing leaves the device.** The case is created in memory only; no
  network request is made, no staff are contacted, and no location is read or requested.
- The status screen that opens can be dismissed at any time with "Minimize · back to the app".
  The case stays open and the SOS button changes to "In progress · tap for status" so you can
  return to it.

**Location**

The app requests location only as "While Using the App" and never in the background. Before the
system prompt appears, the app shows its own screen explaining the three things location is used
for: placing you on the event map, measuring distance while walking, and sending your position to
staff when you press the emergency button. You can decline and still use every feature, including
SOS — staff then see only the last checkpoint you checked in at.

**Account creation and deletion (Guideline 5.1.1(v))**

The app does not offer account creation. Registration for this event is closed at its 2,000-person
capacity and happens on the organiser's website, not in the app; there is no sign-up link, no
sign-up screen, and no registration endpoint reachable from the app. Account deletion is handled
through the contact channel published in our privacy policy.

**No purchases**

The app contains no in-app purchases, no subscriptions, and no payments of any kind. It links to
no external purchase mechanism.

Thank you again for the review.
