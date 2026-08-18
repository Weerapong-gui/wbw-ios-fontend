# ข้อความตอบ App Review — 1.0 (8)

ตอบใน App Store Connect ที่เธรดของ submission `30d177e2-a7d0-4be5-9050-5f47f2ba69f3`

> **ช่อง Demo Account ใน App Store Connect ไม่ต้องแก้** — รหัสคู่เดิมที่ Apple ถืออยู่
> (`6939999999` / `WbwReview2026!`) ใช้ล็อกอินได้จริงแล้วตั้งแต่ 2026-08-19 ยืนยันด้วย
> `POST /wbw/auth/login` → 200 และ `GET /wbw/me` → 200 (ดู `docs/appstore-1.0-8-verification.md`)
>
> **ก่อนส่ง:** ต้องอัปโหลด build 1.0 (8) ให้ขึ้นใน ASC และเลือกให้ submission ก่อนตอบข้อความนี้ —
> ตอบไปตอนที่ยังมีแต่ build 7 reviewer จะกดทดสอบตัวที่ไม่มีปุ่ม Demo แล้วตีกลับ 2.1 ซ้ำ

---

Hello,

Thank you for the detailed feedback. Both issues are addressed in build 1.0 (8).

**Guideline 2.1 — Information Needed (demo account)**

You were right that the credentials could not sign in. The account we had supplied was a
temporary test record that no longer existed on our production server, so the sign-in genuinely
failed. We are sorry for the wasted review time.

Two things have changed:

1. **The app now has a built-in demonstration mode.** On the sign-in screen there is a button
   labelled "ดูตัวอย่างแอป (Demo)" ("View app demo") directly below "Sign In". Tapping it opens
   the full app with representative sample data — no account, no network connection, and no
   server dependency of any kind. Every tab and every screen listed below is reachable from it.
   This is available in the shipping build, not only in development builds.
2. The account in the Demo Account fields now works. We re-created it on our production server
   on 19 August 2026 and verified sign-in end to end:
   - User name: `6939999999`
   - Password: `WbwReview2026!`

   Please note that this is a brand-new participant record, so it has not yet joined a walking
   group and has not checked in at any checkpoint. The group chat and the checkpoint feedback
   form therefore have nothing to display on it. The demonstration mode above is populated with
   sample data and shows those two screens in full — we would suggest using it for the review.

Some background that may help: this app is the participant companion for a one-day university
hiking event, and registration for that event is now closed at its 2,000-person capacity, so new
accounts can no longer be created. The demonstration mode exists so that reviewing the app never
depends on our event database.

What you can see in demo mode:

- **Home** — event progress shown as a flower that opens as checkpoints are collected, plus the
  current temperature and air-quality index for the trail.
- **Trail (SU RUN)** — the 8.36 km event route on a map, with live distance, step count, pace and
  elapsed time while walking. Location is used only while the app is open; there is no background
  location use.
- **Area map** — a 3D model of the event grounds with the checkpoint markers.
- **Group** — the participant's group chat, and the group directory with remaining seats.
- **Participant pass** — name, school, bib number, barcode, and a medical-information sheet for
  first-aid staff.
- **Announcements** and **checkpoint feedback** — the organiser's notices and the short rating
  form shown after each checkpoint.

**Guideline 2.3.3 — Accurate Metadata (screenshots)**

All iPhone screenshots have been replaced. Every image is now a capture of a real screen inside
the running app, taken from the demonstration mode described above. No splash screen and no
sign-in screen is included, and there are no marketing compositions — the nine images are Home,
the trail tracker mid-walk, the 3D area map, group chat, the group directory, the participant
pass, announcements, the checkpoint feedback form, and the participant's QR code.

Thank you again for the review.
