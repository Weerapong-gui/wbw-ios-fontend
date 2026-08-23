# ข้อความตอบ App Review — 1.0 (12)

ต่อจาก `review-reply-1.0-11.md` · รอบนี้โดนตีกลับข้อเดียว: **Guideline 5.1.1(iv)** เมื่อ
2026-08-24 (submission `30d177e2-a7d0-4be5-9050-5f47f2ba69f3`, ตรวจบน iPhone 17 Pro Max)
ใจความคือปุ่มบนจออธิบายก่อนกล่องขอสิทธิ์เขียนว่า "Allow Location" ซึ่งเป็นการชี้นำ
ใบตีกลับยกคำที่ใช้ได้มาเองว่า *"Use words like 'Continue' or 'Next' on the button instead."*

> **ก่อนส่ง — สองอย่างที่ยังไม่ใช่งานโค้ด**
>
> 1. **ถ่ายสกรีนช็อต `02-map` ใหม่ทั้งสองขนาด** — ค่าเริ่มต้นของแท็บแผนที่เปลี่ยนเป็นแผนที่ 2 มิติ
>    แล้ว ใบที่อัปไว้ยังเป็นจอ 3 มิติ (รายละเอียดใน `connect-checklist.md` ลำดับข้อ 3)
> 2. **ยิงบัญชีรีวิว `6939999999` ซ้ำก่อนกด Submit** — รอบ 1.0 (7) โดนตีกลับเพราะบัญชีหายไป
>    จาก production ระหว่างรอรีวิว

---

Hello,

Thank you for the detailed note on 1.0 (11). The wording issue is fixed in 1.0 (12).

**Guideline 5.1.1(iv) — the button before the location prompt**

The explanatory screen that appears before the system location prompt had a primary button
labelled "Allow location" ("อนุญาตตำแหน่ง" in Thai). That button is now labelled **"Continue"**
("ถัดไป" in Thai), exactly as your message suggested. The secondary button is unchanged and still
reads "Not now".

Nothing else on that screen changed: it still explains, before the prompt appears, that the app
uses location only while the app is open, for two purposes — drawing the participant's own dot on
the event map, and attaching their position to an emergency alert if they press the SOS button —
and it states plainly that declining still leaves SOS usable, with staff seeing the participant's
last checked-in checkpoint instead of a live position.

We also found and changed a second button with the same wording that your review did not reach:
inside the SOS status screen, a banner shown when location has not been decided yet offered the
same "Allow location" button. It now reads "Continue" as well, so no button anywhere in the app
asks the user to grant a permission.

Both strings are covered by an automated test in our test suite, so the wording cannot regress
into a later build without the build failing.

**To reach the screen you reviewed**

The screen appears for a signed-in participant on a device that has not yet answered the location
prompt. Signing in with the review account below on a fresh install shows it a second after the
home screen appears:

- User name: `6939999999`
- Password: `WbwReview2026!`

The demo button on the sign-in screen ("ดูตัวอย่างแอป (Demo)" / "Try the app (Demo)") still opens
the whole app with sample data. Demonstration mode deliberately never asks for location at all, so
this particular screen does not appear there.

Thank you again for the review.
