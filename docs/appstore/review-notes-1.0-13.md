# App Review Notes — 1.0 (13)

ช่องนี้อยู่ในหน้าเวอร์ชันของ ASC (App Review Information → Notes) · **เพดาน 4,000 ตัวอักษร**
· ชุดที่วางอยู่ตอนนี้ตัดมาจาก `review-reply-1.0-11.md` เมื่อ 2026-08-23 ซึ่ง **เล่าถึงปุ่ม
"ดูตัวอย่างแอป (Demo)" ที่ถอดออกไปแล้ว 2026-08-25** — ต้องแทนด้วยข้อความข้างล่างตอนอัป 1.0 (13)
ไม่งั้นผู้ตรวจหาปุ่มตามโน้ตแล้วไม่เจอ = โดนตีกลับเหมือนของหาย

> **ก่อนวาง — ตรวจสองอย่างนี้ด้วยตาตัวเอง**
>
> 1. **ล็อกอิน `6939999999` แล้วเปิดแท็บแชท** — โน้ตนี้บอกผู้ตรวจว่าปุ่มบล็อก/รายงานอยู่ในแชท
>    ถ้าบัญชีนี้ไม่มีกลุ่ม หรือกลุ่มไม่มีข้อความของคนอื่นเลย ผู้ตรวจจะกดตามไม่ได้ =
>    **Guideline 1.2** (ของมีแต่ผู้ตรวจหาไม่เจอ) · เดิมย่อหน้านี้ให้กดผ่านโหมดเดโม่ซึ่งมี
>    ข้อมูลครบ แต่ปุ่มนั้นถูกถอดแล้ว · ยังไม่มีข้อความในกลุ่ม ให้ให้เจ้าหน้าที่โพสต์ทิ้งไว้
>    หนึ่งข้อความก่อนส่ง
> 2. **ยิง `POST /wbw/auth/login` ซ้ำก่อนกด Submit** — บัญชีนี้เป็นทางเข้าแอปทางเดียวแล้ว

---

This app is the participant companion for a one-day university hiking event: 6 km on a mountain
trail through twelve staffed checkpoints.

**Signing in**

Use the account in the Demo Account fields:

- User name: `6939999999`
- Password: `WbwReview2026!`

The app has no demonstration mode button on the sign-in screen; this account is the way in. It
signed in against production on 2026-08-25 (HTTP 200). If it fails for you, please tell us in
Resolution Center — we can restore a no-account demonstration mode within one build.

**What changed in this build (Guideline 5.1.1(iv))**

The explanatory screen shown before the system location prompt now has a single button,
"Continue", which always brings up the system prompt. The "Not now" button is gone, and the screen
can no longer be swiped away on iPhone or dismissed by tapping outside it on iPad. It appears at
most once per install, only while the permission is still undetermined.

**Location**

Location is requested as "While Using the App" only, never in the background. The app explains,
before the prompt, the three things it is used for: placing you on the event map, measuring
walking distance when you start a walk, and attaching your position to an emergency alert. You may
decline and still use every feature, including the emergency button — staff then see only the last
checkpoint you checked in at. The purpose string, that screen, and our published privacy policy
describe the same three uses.

**Emergency help (SOS) button**

The button is on the participant pass screen and needs a deliberate three-second press. **It
alerts the event's own staff team. It is not a call to emergency services and the app never
presents itself as one.** The status screen says so plainly and points the user to 1669
(Thailand's ambulance number) for a real emergency. The app makes no medical claims.

**Group chat and user-generated content (Guideline 1.2)**

Chat is limited to the members of one walking group. Every participant is a registered student
whose identity was verified at registration: no anonymous posting, no public posting, no images,
no discovery of strangers.

- **Block** — open the group chat, tap the group name at the top, tap a member, then "Block this
  person". The same action is on a long press of any message. Blocked people's messages are hidden
  immediately.
- **Unblock** — Settings → "Blocked people", with an Unblock button per person.
- **Report** — long press a message, choose "Report this message". It opens a pre-filled email to
  student-union@lamduan.mfu.ac.th (the address published in our privacy policy and support page)
  with the message id, sender and timestamp.

**Account creation and deletion (Guideline 5.1.1(v))**

The app does not offer account creation. Registration closed at its 2,000-person capacity and
happens on the organiser's website; there is no sign-up link, screen, or endpoint in the app.
Account deletion is handled through the contact channel published in our privacy policy.

**No purchases**

No in-app purchases, no subscriptions, no payments, and no link to an external purchase mechanism.
