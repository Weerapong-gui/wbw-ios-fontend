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

Participant companion for a one-day university hiking event: 6 km on a mountain trail with
twelve staffed checkpoints.

**Signing in**

Use the Demo Account fields: `6939999999` / `WbwReview2026!`

There is no demonstration-mode button on the sign-in screen; this account is the way in. It signed
in against production on 2026-08-27 (HTTP 200). If it fails, tell us in Resolution Center — we can
restore a no-account demonstration mode within one build.

**What changed (Guideline 5.1.1(iv))**

The screen shown before the system location prompt now has a single button, "Continue", which
always brings up that prompt. "Not now" is gone, and the screen can no longer be swiped away on
iPhone or dismissed by tapping outside on iPad. It appears at most once per install.

**Location**

"While Using the App" only, never in the background. Before the prompt we name its three uses:
placing you on the event map, measuring walking distance, and attaching your position to an
emergency alert. Declining leaves every feature usable, emergency button included — staff then
see only your last checkpoint. Purpose string, screen and privacy policy all say the same.

**Step and distance counting**

Starting a walk reads steps and distance from the motion coprocessor (`CMPedometer`), which
records on its own; the app queries the elapsed window on return to the foreground. **The app
declares no background modes at all** and never runs location updates outside the foreground.
The numbers stay on the device — our server has no endpoint for them.

**Emergency help (SOS) button**

On the participant pass screen, needing a deliberate three-second press. **It alerts the event's
own staff team, is not a call to emergency services, and never presents itself as one.** The status
screen says so and points to 1669 (Thailand's ambulance number). No medical claims.

**A form that appears right after a checkpoint scan**

After a staff member scans a participant in at a checkpoint, a short rating form for it appears.
**It takes the whole screen and has no close button by design** — the organisers get one chance to
hear what a checkpoint was like, while the participant is standing in it (same as our Android app).
It is never a dead end:

- **It closes as soon as the rating is sent** — tap 1-5 on the first question (the rest are
  optional), then "Send". With no network the answer queues on the device and the form still closes.
- **If our server refuses the answer, a "Skip for now" button appears** below Send.
- **It only appears for a check-in from the last 12 hours**; older ones are offered as a dismissible
  notification instead. You are unlikely to see this form at all with the review account.

The emergency button stays reachable throughout — its own row beneath the form, the screen edge
glowing red while a case is open.

**Group chat and user-generated content (Guideline 1.2)**

Chat is limited to one walking group. Every participant is a registered student verified at
registration: no anonymous or public posting, no images, no discovery of strangers.

- **Filtering** — offensive language is refused at send time in Thai and English; the sender sees
  why, above the composer, and can rewrite.
- **Block** — long press any message, or group name → member → "Block this person". Their messages
  hide immediately. **Unblock** in Settings → "Blocked people".
- **Report** — long press a message → "Report this message": a pre-filled email to
  student-union@lamduan.mfu.ac.th (published in our privacy policy and support page) carrying the
  message id, sender and timestamp.

**Account creation and deletion (Guideline 5.1.1(v))**

No account creation in the app — registration happens on the organiser's website and closed at its
2,000-person capacity; no sign-up link, screen or endpoint exists here. Deletion goes through the
contact channel published in our privacy policy.

**No purchases**

No in-app purchases, subscriptions, payments or external purchase links.
