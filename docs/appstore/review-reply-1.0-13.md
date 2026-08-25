# ข้อความตอบ App Review — 1.0 (13)

ต่อจาก `review-reply-1.0-12.md` · รอบนี้โดนตีกลับ **ข้อเดิมซ้ำ: Guideline 5.1.1(iv)** เมื่อ
2026-08-25 (submission `30d177e2-a7d0-4be5-9050-5f47f2ba69f3`, ตรวจบน iPad Air 11-inch (M3)
กับ iPhone 17 Pro Max) · รอบที่แล้วโดนเรื่อง *คำ* บนปุ่ม รอบนี้โดนเรื่อง *ปุ่มที่สอง*:
ผู้ใช้ปิดจออธิบายแล้วเลื่อนกล่องขอสิทธิ์ออกไปได้ด้วยปุ่ม "Not now"

> **ก่อนส่ง — สามอย่างที่ยังไม่ใช่งานโค้ด**
>
> 1. **เอา `GoogleService-Info.plist` ของ `th.ac.mfu.wbwSwift` กลับมาวางบนเครื่อง** — ไฟล์ที่
>    อยู่ตอนนี้เป็นของ bundle Club Fair (อยู่ใน `.gitignore` git ไม่ย้อนให้) BUNDLE_ID ไม่ตรง
>    แล้ว push ตายเงียบ · โปรเจกต์กลับมาเป็น `th.ac.mfu.wbwSwift` 1.0 (13) แล้ว
> 2. **อัป build ใหม่ให้เสร็จก่อนตอบข้อความนี้** — รอบ 1.0 (7) โดนตีกลับซ้ำเพราะตอบตอนที่ ASC
>    ยังมีแต่ build เก่า
> 3. **ยิงบัญชีรีวิว `6939999999` ซ้ำก่อนกด Submit**

---

Hello,

Thank you for the follow-up on 1.0 (12), and for pointing at the button rather than the wording
this time — that was our misreading of the previous message, not yours.

**Guideline 5.1.1(iv) — the explanatory screen now always leads to the permission request**

The screen that appears before the system location prompt had two buttons: "Continue", which
brought up the system prompt, and a secondary "Not now", which closed the screen and postponed
the prompt. In 1.0 (13) the "Not now" button is gone. The screen now has a single button,
"Continue", and pressing it always brings up the system location prompt, exactly as your message
requires.

We also closed the other ways that screen could be dismissed without reaching the prompt, since
they amounted to the same thing:

- It can no longer be swiped down on iPhone.
- On iPad it can no longer be dismissed by tapping outside the sheet.
- The drag indicator at the top, which invited a swipe, has been removed.

The user is not trapped by this. The single button dismisses the screen itself, and the screen is
shown at most once per install: it appears only while the location permission is still
undetermined, and never again after the user has been taken to the system prompt — including the
case where Location Services are turned off device-wide, where the system shows its "Turn On
Location Services?" alert instead and the permission state does not change.

Nothing else on the screen changed. It still explains, before the prompt appears, that the app
uses location only while the app is open, for three purposes — drawing the participant's own dot
on the event map, measuring walking distance when they start a walk, and attaching their position
to an emergency alert if they press the SOS button — and it still says plainly that declining
leaves SOS usable, with staff seeing the participant's last checked-in checkpoint instead of a
live position.

The removal of the "Not now" button and the removal of the swipe-to-dismiss gesture are both
covered by automated tests in our test suite, so neither can return in a later build without the
build failing.

**To reach the screen you reviewed**

The screen appears for a signed-in participant on a device that has not yet answered the location
prompt. Signing in with the review account below on a fresh install shows it a second after the
home screen appears:

- User name: `6939999999`
- Password: `WbwReview2026!`

One change since 1.0 (12) that is not about this guideline: the "Try the app (Demo)" button on the
sign-in screen has been removed, so the review account above is now the way into the app. We
verified on 2026-08-25 that it signs in against production. Please tell us if it fails for you and
we will restore the demonstration mode button immediately.

Thank you again for the review.
