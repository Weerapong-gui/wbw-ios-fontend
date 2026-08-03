# Check-in feedback — verification notes

**Date:** 2026-08-03
**Branches:** `feature/checkin-feedback` (iOS), `feat/wbw-feedback` (SUS)
**Scope:** the whole 12-task check-in feedback feature (plan at
`docs/superpowers/plans/2026-08-03-checkin-feedback.md`), written at Task 12 — the task whose
only job is to look at the finished thing, exercise the offline path against a real network
failure, and then say plainly what was and was not established. Per-task detail lives in
`.superpowers/sdd/2026-08-03-checkin-feedback/` (`task-N-report.md`, `progress.md`); this
document pulls forward what someone preparing for event day needs without making them read all
of it.

**This is a status report, not a guarantee.** Several claims below are explicitly "never
exercised" or "proven under a simulated payload, not a real one". That wording is deliberate.
The section "What you are carrying into event day" is the one to read if you read nothing else.

Everything in this document was run against the local SUS stack (`http://localhost:8080/wbw`,
`Config.backend == .susLocal`) as test participant `6931900011`, on the booted `iPhone 17`
simulator (`17458066-33DC-464C-A008-9C9C05165247`), iOS 26.5.

---

## The short version

The feature works, end to end, for the path a participant will actually take **if the push
arrives** — and the push is the part that has never been delivered by Firebase.

| Layer | State |
|---|---|
| Database, endpoints, business rules | Verified live, all five submit cases by `curl` |
| Offline outbox (queue → flush → row lands) | **Verified against a real stopped backend** (§2) |
| Terminal is now an explicit list (400/401/405/410/413/414/415/422); `403`/`409` are terminal only when the body is the origin's; everything else — including 404/408/425 — is retryable and stays queued | `409` **verified live**; the classification, the round-2 inversion, and the origin-body gate are verified by unit tests, an integration test over the real transport, and one **live 500** — no live reproduction of a real 408, 425, or edge 403/409 exists (§3) |
| 60 s poll → toast → form → row | Verified live, no hooks, twice, by two agents; the diff logic behind it, including a since-fixed out-of-order-response race, now has automated coverage too (§7) |
| Push arriving while the app is open | Verified under a **simulated** APNs payload, one manual run (§5) |
| Push **tap** (background and cold launch) | **Never exercised.** Reasoning only |
| Real FCM delivery | **Never exercised.** No Firebase service account here |
| Physical hardware | **Never exercised** for this feature |

---

## What you are carrying into event day

Ranked, worst first.

### 1. Merging this branch as-is repoints the app at localhost. Release-blocking.

`WBW/Config.swift` currently reads:

```swift
static let backend: Backend = .susLocal
```

which resolves to `http://localhost:8080/wbw`. `main` carries `.prodNode`
(`https://wbw.sumfu.store`). **Merging this branch to `main` as-is repoints the app at
localhost, and any build cut from this branch reaches no server** — not a degraded feature,
a non-functional app: login, chat, the map, every network call, because `Config.backend`
switches the whole app at once.

This predates the check-in feedback feature — it came in with commit `fba1ebc`, before this
plan started, and this plan never touched the line. It is not new, and it is not this document's
bug, but nothing anywhere flagged it as a release blocker until the final whole-branch review.

**Before this branch (or `main` after merging it) ships:**

- [ ] Change `Config.backend` to `.prodNode` or `.susProd`. **This is the maintainer's decision**
      — it depends on whether SUS is meant to serve the event or whether the app should keep
      talking to the existing Node backend — not something this plan or this document can settle.
- [ ] Re-verify against whichever backend is chosen. Nothing in this document was run against
      `.prodNode` or `.susProd`; all of it, every curl call and every screenshot, was run against
      `.susLocal`.

### 2. FCM push has never been delivered. This is the feature's primary realtime path.

There is no Firebase service account in this environment. `WBWPushService.SendUserPush`
opens with:

```go
if s.tokens == nil {
    return
}
```

so it returns **before contacting FCM**, every time, on every run of every task in this plan.
Nothing downstream of that line has ever run against a real notification:

- the FCM → APNs payload translation (whether the `data` map really lands as top-level keys in
  `userInfo`, which is what `AppDelegate` reads),
- `UserPushTargets` returning real device tokens for the right user,
- the dead-token reaping in `sendOne`,
- APNs delivery, the banner, the badge,
- **`didReceive` — the tap.** Every one of the four entry points that begins with a push tap
  rests on `PendingPush.hold(...)` being called with the right arguments, which was driven by a
  test hook making that exact call, never by a real tap on a real banner.

What *was* proven on the backend side is the notification **row**: a first check-in creates
exactly one `notification` row of type `checkin_feedback` with `ref_id` set to the checkpoint,
guarded by `already_checked_in` and verified by counting rows after two scans (Task 4). The row
is what the bell badge and the notification list read, and that path is solid. The push is the
part that is supposed to make it *immediate*.

One more thing on this path changed since this document was first written, and it is a fix
rather than a gap: `notifyFeedback` — the function that writes that row and calls
`SendUserPush` — now runs inside `goSafe`, added in the final whole-branch review. Before that,
the detached goroutine had no `recover()`, and chi's `middleware.Recoverer` only covers the
request goroutine, not ones spawned from inside it. A panic anywhere in `notifyFeedback` — a nil
map, a bad type assertion, anything — would have taken down **the entire backend process for
every user**, not just the participant who triggered it, and this exact code path fires once per
first check-in: roughly 16,000 times over the event. `TestGoSafeRecoversPanicAndRunsDeferredCleanup`
proves the fix the direct way: remove the `recover()` in a scratch copy and the whole test binary
dies with `panic: ระเบิด` instead of a clean `FAIL`. The wrap was applied to all five detached
goroutines on this path (`notifyFeedback` plus four inside `wbw_push_service.go`), not just the
one this document exercises. One bare goroutine elsewhere in the same server, `go
e.listenLoop(ctx)` at `internal/service/wbw_chat_events.go:54`, is still unwrapped — it is off
this feature's path (chat, not check-in feedback) and was left exactly as found.

**Practical consequence for event day:** if push is misconfigured in production, the feature
does not fail — it degrades to the 60 s poll and the notification list, both of which are
verified. Participants would see the toast within a minute of being scanned instead of
instantly. Plan for someone to confirm a real push end to end on a real device, with a real
service account, before the event. That test has never been run and nothing in this plan
substitutes for it.

### 3. The push **tap** routing is reasoned, not observed.

`didReceive` decides which screen to open and, for `checkin_feedback`, carries
`checkpoint_id` through `PendingPush` so a cold launch can replay it after the splash screen.
Task 11 exercised everything *downstream* of `PendingPush.hold` — the `consume()` in
`MainTabView.task`, the `NotificationCenter` post, the `.onReceive` parse, the sheet, the
deferred `markRead` retry — by calling `hold` from a temporary launch hook. The line that
actually builds the payload from a `UNNotificationResponse` has never executed.

Concretely untested: the `info["checkpoint_id"] as? String ?? ""` coercion. If FCM delivers
that value as a number rather than a string, the coercion yields `""`, `Int("")` is nil, and
`.onReceive` **drops the push silently** — the participant taps the banner and lands on Home
with nothing open. The backend does send it as a string (`"checkpoint_id": ref` where `ref` is
`strconv.Itoa(checkpointID)`), so this is expected to be fine; it is expectation, not evidence.

### 4. Physical hardware has never run this feature.

No physical device was used at any point in this plan, and none was used in the forest-3D plan
this branch forks from either. Two consequences carry forward unchanged:

- **Gyroscope parallax — half closed on 2026-08-03, after this plan finished.** `CMMotionManager`
  reports `isDeviceMotionAvailable == false` on the simulator, so the parallax path was dead code
  in every run made *during* this plan. It has since been run on an iPhone 13: the sensor path is
  live, real samples flow through `mapAttitude` and the low-pass filter, and the forest scene
  renders on device. Still unseen is the scene actually *moving* when the phone tilts — the
  device sat flat for the whole run. Detail, including a delivered sample rate of 33.6 Hz against
  a requested 60 Hz, is in `docs/forest-3d-verification.md`.
- **The 3D scene's appearance was judged by eye, not measured** — sky colour, fog blend, canopy
  size per stage. See `docs/forest-3d-verification.md` for the detail.

A working physical-device recipe does exist (`~/.claude` memory `device-testing-recipe.md`,
iPhone 13, last exercised 2026-08-02 for chat sync), and `WBW/Config.swift` now carries a
committed `case susLan` for it. It has **never been run against this feature**, and the plan's
ledger records that later attempts did not complete — the app is installed on the iPhone 13, but
the device was locked on each attempt and no session got past installation. Two environment
problems also block picking it up immediately: the ad-hoc `sus-lan-forward` container is dead
and the app on a phone cannot reach the Mac's loopback-only SUS port without it, and
`cloudflared` is in a restart loop. Neither was touched by this task; both are pre-existing and
neither is caused by anything in this feature.

### 5. `NotiStore` has no injectable seam, so one fix is reasoned rather than tested.

Task 11 fix round 2 changed `NotiStore.load` so that a notification marked read locally (the
push path marks it read without opening the list) is not resurrected as unread when the list
reloads from the server. `FeedbackStore` in the same diff shows the closure-injection pattern
that would make this testable; `NotiStore` has not adopted it, so there is no test. The failure
mode if the reasoning is wrong is cosmetic and self-healing: the bell badge briefly shows a
number for something the participant already dealt with, until `markAllRead` sweeps it.

### 6. Known, deferred, cosmetic

- **`CheckinToast`'s title has no `.lineLimit`**, unlike its subtitle. A long server-supplied
  base name wraps to two lines and leaves the leading `checkmark.seal.fill` icon vertically
  off-centre. It mirrors `ChatToast`'s pre-existing unbounded `senderName`, so it is latent
  rather than a regression. Base names in the database today are all short enough that this has
  never been seen on screen — an admin adding a long name on event day would surface it.
- **The service-point `403` and the not-checked-in `403` return the same message**
  (`"ยังไม่ได้เช็คอินฐานนี้"`). A participant *is* checked into a service point; the message is
  inaccurate for that case. It is only reachable if the UI opens a form for a service point,
  which it does not do, so nobody should ever see it.
- **The admin checkpoint-create path omits `requires_checkin`**, which defaults `TRUE`, and no
  admin endpoint can set it. An admin adding a restroom on event day silently raises `total`,
  which affects the tree and now also the pending-feedback list. Inherited from the previous
  plan, unchanged here, and worth an issue rather than a hotfix.
- **`pending`'s sort assumes lexicographic order on the `at` string equals chronological order.**
  It holds only because SUS formats it `at.UTC().Format(time.RFC3339)` on the other side — fixed
  width, no fractional seconds, a literal `Z`. Nothing pins that pairing on either side; a future
  change to either the iOS sort or the Go formatter, made without knowing about the other, would
  silently reorder the pending list. Flagged at Task 5 review, deferred rather than fixed there.
- **`case susLan` now carries a real, committed LAN IP** (`172.25.32.8`), with a comment telling
  whoever next does physical-device testing to edit it in place. Before commit `0f52be4` this
  whole case lived only in an uncommitted local `Config.swift`, so a wrong IP could never reach
  git; now that the file is committed (see item 1), it can. The standing risk is the same shape
  as item 1: someone changes the IP for their own network, tests, and forgets to revert it before
  committing something unrelated in the same diff.
- **The `403`/`409` origin check trusts body shape, not source, and one gap in that could not be
  tested.** Any edge or gateway that happened to answer with JSON shaped like `{"error":"..."}` —
  not just Cloudflare — would be misread as the backend's own response and would drop that base's
  whole queue. Cloudflare's actual block page is HTML, not JSON, so this is believed remote, but
  nobody here has access to the real edge in front of `api.studentunion.social` to check it —
  reasoned, not observed. See §3.
- **A latent trap for whoever touches this route next.** `POST /wbw/me/feedback` currently runs
  behind `requireAuth` only. If `middleware.RequireRole` is ever added to it, that `403` goes
  through the same `WriteError` as the feedback handler's own "not checked in" response — same
  envelope, same `error` key — so the app would read it as the origin's and show its fixed
  not-checked-in copy (§4) for what is actually a permissions problem. The *action* would still
  be right (a role mismatch isn't fixed by retrying); only the message would be wrong. See §3.

---

## Method gaps — things a green build does not tell you

These are about *how* this feature was verified, and they matter more than any single bug.

### A green `xcodebuild` on the dev machine says nothing about whether the committed tree is complete.

Until commit `0f52be4`, **this branch did not compile from a clean checkout**, and had not since
`33f58b8` in the previous plan. `WBW/BackendCacheKey.swift` (production code) plus
`WBWTests/CheckinProgressStoreTests.swift` and `WBWTests/FeedbackOutboxTests.swift` all switched
exhaustively over `Backend` and named `.susLan` — while `case susLan` existed **only in an
uncommitted `WBW/Config.swift`** on this machine. Eleven consecutive tasks built and tested
green because every one of them built on the machine that held the uncommitted case.

It surfaced only when a reviewer built in an isolated `git worktree`, could not compile at all,
and hand-copied the local `Config.swift` in to proceed — mentioning it in passing.

Record this as a **method** gap, not just a fixed bug. `xcodebuild` compiles the *working tree*,
not the commit. Any verification loop that never builds from a fresh clone or worktree cannot
detect a missing file, a missing case, or a missing resource. If you take one process change
from this plan, take this one: build at least once from `git clone` or `git worktree add` before
declaring a branch done.

`main` was never affected (`33f58b8` is unmerged). `feature/forest-3d` still carries the break;
`feature/checkin-feedback` contains the fix, so merging this branch repairs both.

### `xcodebuild build` without `clean` can serve stale bundled resources while reporting success.

Recorded in the previous plan and re-confirmed as still true. An incremental `build` will
happily reuse an old copy of a bundled resource (this bit the forest `.usdz`) and print
`** BUILD SUCCEEDED **`. Every build behind every screenshot in this document was
`xcodebuild clean build`. If you are about to trust a screenshot, check that the build behind it
was clean.

### There is no UI tap tooling in this environment.

No `cliclick`; Simulator.app exposes zero accessible windows to System Events. Four separate
agents independently confirmed this. **Every screen transition in every task of this plan was
driven by a launch argument or a programmatic state change, never by a tap.** The permanently
committed hooks (`-uitestTab`, `-uitestChat`, `-uitestProgress`, `-uitestFeedback`,
`-uitestTabSequence`, `-uitestNotifications`) exist for exactly this reason.

What this costs, specifically, is that no `Button`, `TextEditor` binding, or `.disabled(...)`
gate in this feature has ever been operated by a real touch. The send button's disabled state,
the three face buttons' `rating = value`, and the comment field's binding are all read-verified
and driven from code, not pressed.

### A test hook can invalidate its own result. Mine did.

Worth recording because it nearly produced a false finding in this task. The first attempt to
verify `.id(target.id)` (§6) used a hook in `FeedbackView.onAppear` that filled in a rating and
comment. When `.id()` did its job and forced a **new view identity**, `onAppear` ran again — and
the hook refilled the *new* form with the *old* form's values. The screenshot looked exactly
like the state bleed the guard is supposed to prevent. The hook had to be scoped to a single
checkpoint id before the test meant anything. Any hook that fires on a lifecycle event is a
candidate for this.

### The database is shared, mutable, and moves under you.

The test account's progress changes as tasks scan, submit, and clean up after themselves. Two
separate tasks in this plan recorded "the next task's baseline has moved". Do not write a check
that assumes a fixed number of answered bases; read the current state first (§8 has the queries).

---

## 1. The endpoints, curl-verified

Run 2026-08-03 against the live local stack as `6931900011`. Exact output:

```
POST /wbw/me/feedback  cp5, NEW client_id (base already answered)
  -> 409  {"id":38,"checkpoint_id":5,"rating":1,"comment":"รอบแรก ส่งตอนเน็ตหลุด","created_at":"2026-08-03 04:16:49.906193+00"}

POST /wbw/me/feedback  cp5, SAME client_id as the stored row (a retry)
  -> 200  {"id":38,"checkpoint_id":5,"rating":1,"comment":"รอบแรก ส่งตอนเน็ตหลุด","created_at":"2026-08-03 04:16:49.906193+00"}

POST /wbw/me/feedback  cp10, never checked in
  -> 403  {"error":"ยังไม่ได้เช็คอินฐานนี้"}

POST /wbw/me/feedback  cp9, service point (requires_checkin = false)
  -> 403  {"error":"ยังไม่ได้เช็คอินฐานนี้"}

POST /wbw/me/feedback  cp7, rating 5 (out of range)
  -> 400  {"error":"rating must be 1..3"}

GET  /wbw/me/progress
  -> 200  total 8, checked_in[8], each entry carrying answered / rating / comment
```

The `409` returning the **stored** answer rather than a bare error is what lets the form show
the real answer when a second client wins the race — see §3.

`409` vs `200` is the distinction Task 3 had to fix: the table carries *two* unique constraints,
and the original handler assumed every `23505` was the `(participant, checkpoint)` one, so a
plain retry with the same `client_id` was misreported as a conflict. Both branches above are
regression evidence for that fix.

`GET /wbw/admin/feedback` was verified in Task 3 and **not** re-verified here — the only
privileged account on this machine is `admin`, whose password is not recorded.

---

## 2. Step 1 — the outbox against a real stopped backend

The brief's own step, run exactly as written (with one correction: the compose **service** is
`backend`; `su-server` is the container name, so `docker compose stop su-server` fails with
`no such service`).

**Setup.** `docker compose stop backend`, confirmed dead by `curl` returning exit 7 /
`http=000`. The app had a warm progress cache from a launch a minute earlier, which is the
realistic shape: a participant who used the app before losing signal.

**Submit.** Launched into the feedback form for checkpoint 4 with a temporary hook that sets a
rating and a comment on the real `@State` and calls `FeedbackView.send()` — the same private
function the send button calls, so the whole path from `send()` through `FeedbackStore.submit`,
`APIClient.submitFeedback`, the `catch { throw AppError.offline }`, and back into the view's
outcome switch is production code.

**On screen** (`step1-offline-sent.png`, read directly): the card titled **ลานสวนสน** with the
subtitle **ส่งแป้งข้ามหัว** (both from the offline cache), **ชอบ** selected and green-tinted,
the comment **"ทดสอบส่งตอนเซิร์ฟเวอร์ดับ"** in the box, and below it a green
`checkmark.circle.fill` with **"ส่งความเห็นแล้ว ขอบคุณ"**. No error. The participant is not told
anything failed — which is the requirement.

> **Correction to the brief:** it says "the form must close and report success". The form does
> **not** close. It switches into the answered state and stays open until the participant taps
> ปิด. That is the shipped behaviour and it is fine; the brief's wording is wrong, not the code.

**Queued, not saved:**

```
docker exec postgres-db psql -U admin -d sudb -c \
  "SELECT count(*) FROM checkin_feedback WHERE checkpoint_id = 4"
 count
-------
     0
```

and the draft sitting in the app's own `UserDefaults`, read straight out of the container plist
(`xcrun simctl get_app_container … data` → `Library/Preferences/th.ac.mfu.wbwSwift.plist`, key
`wbw.feedback.outbox.susLocal`):

```json
[{"clientId":"1ba3079a-304d-412e-bb31-1d0c750d6d0b","checkpointId":4,"rating":3,
  "deviceTime":"2026-08-03T04:13:44Z","comment":"ทดสอบส่งตอนเซิร์ฟเวอร์ดับ"}]
```

**Flush.** `docker compose start backend`, waited for it to answer, then confirmed the row count
was *still* 0 and the draft *still* queued — the app in the foreground does not spontaneously
retry. Then backgrounded the app (`simctl launch com.apple.Preferences`) and foregrounded it
again (`simctl launch th.ac.mfu.wbwSwift`, which returned **PID 7750, the same PID**, proving
this was a genuine `scenePhase == .active` transition and not a cold launch whose `.task` would
have flushed anyway):

```
 checkpoint_id | rating |       comment        |              client_id               |          created_at
---------------+--------+----------------------+--------------------------------------+-------------------------------
             4 |      3 | ทดสอบส่งตอนเซิร์ฟเวอร์ดับ | 1ba3079a-304d-412e-bb31-1d0c750d6d0b | 2026-08-03 04:15:33.825069+00
```

Outbox afterwards: `[]`.

The `client_id` in the database is byte-identical to the one that was queued. That is the whole
safety argument for the optimistic UI — the same id is reused on every retry, so the backend's
`uniq(client_id)` turns a resend into the same row rather than a duplicate.

**One behaviour worth knowing:** while the form for checkpoint 4 is still open,
`FeedbackStore.editingCheckpoint` deliberately makes `flush` **skip that base**. So a queued
draft does not flush until the form is closed. That is intentional (it stops the queue
overwriting what someone is currently typing), and it means the sequence above only works after
the form closes. On event day this is invisible; in a test it will look like the flush silently
did nothing.

---

## 3. Step 2 — terminal errors are dropped, retryable errors are kept and retried

This section originally covered only `409`. That was true but incomplete: `409` and `403` were
the only statuses ever exercised through the app, and — until the final whole-branch review —
the code did not distinguish "will never succeed on retry" (`400`/`401`/`403`/`409`) from
"hasn't succeeded **yet**" (`429` and every `5xx`) at all. Every status outside 2xx/409/403 was
treated as terminal and the queued draft was deleted. That is a real bug, not a hypothetical
one: a participant told **"ส่งความเห็นแล้ว ขอบคุณ"** whose answer was then silently discarded the
moment the origin returned `503`. The final review found it and it is now fixed; the fix and its
evidence are described in a new subsection after the original `409` run below, which is
unchanged and still the only live, on-screen proof for `409` specifically.

A second pass, after this section was first written, found that first fix was itself still
guessing: `408` and `425` — both plausible on congested event Wi-Fi — fell through the same
default-terminal trap the review had just closed for `429`/`5xx`, and the `403`/`409` outcomes
below trusted the status code alone, which a Cloudflare WAF block page can produce without the
request ever reaching origin. Both are now fixed. The subsection below, "The fix: retryable vs.
terminal, and how it was proven," describes the code as it stands after both passes, not just the
first; the `409` run immediately below is unaffected by either pass and is still the only live,
on-screen evidence for that specific status.

Same base, two answers, two different `client_id`s, from two different launches — all in the
app, no `curl` in the setup.

1. **Backend down.** Launched into the form for checkpoint 5 and sent rating 1, comment
   `"รอบแรก ส่งตอนเน็ตหลุด"`. Queued as `client_id 558d04e2-…`. `checkin_feedback` count for
   checkpoint 5: `0`. Terminated the app with the draft still in the queue.
2. **Backend up.** Cold launch. `MainTabView.task` runs `progress.load` (checkpoint 5 still
   unanswered) and then `feedback.flush`, which POSTs the queued draft → `201`, the row lands
   with rating 1. The form for checkpoint 5 then opens — still editable, because `progress` has
   not been reloaded since — and sends **a second answer, rating 3, with a brand-new
   `client_id`**.

**Result:** `409`. `FeedbackStore.submit` returns `.alreadyAnswered`, calls
`outbox.remove(checkpointId:)`, the view sets `sent = false`, and the trailing `progress.load()`
drives `syncFromServerIfNeeded` through `.onChange(of: item)`.

**On screen** (`step2-409.png`): the card titled **จุดปลูก / ปลูกป่า** showing **ไม่ชอบ**
(rating 1) and the comment **"รอบแรก ส่งตอนเน็ตหลุด"** — the *server's* answer, read-only, with
the green success label. Not the rating 3 / "รอบสอง" that was just typed. The server wins, which
is what the design says must happen.

```
 checkpoint_id | rating |      comment       |              client_id
---------------+--------+--------------------+--------------------------------------
             5 |      1 | รอบแรก ส่งตอนเน็ตหลุด | 558d04e2-66d2-4869-915e-2151b3a257a7
```

Exactly one row. Outbox afterwards: `[]`. The `409` was not retained, and it did not overwrite.

**`403` is terminal too**, and that was checked on screen as well — see §4.

### The fix: retryable vs. terminal, and how it was proven

Two passes. The first (`1a18fea`) added `AppError.retryable`, mapped `429` and `500...599` to it,
and left every other non-2xx/409/403 status terminal by default — the shape described when this
subsection was first written. The second (`12e7cbc`) found that default was still the wrong way
round, in a way that kept losing answers, and inverted it: **terminal is now an explicit list,
and everything else retries.**

| | statuses |
|---|---|
| success | 200, 201 |
| terminal — only if the body is the origin's¹ | 403, 409 |
| terminal — request-shaped, retry cannot change the outcome | 400, 401, 405, 410, 413, 414, 415, 422 |
| **retryable — everything else** | 404, 408, 425, 429, all 5xx, and any status nobody has thought of yet |

Every status on the terminal list fails on something a retry cannot change: the same body (`400`
bad rating, `413` too long, `422` semantically wrong), the same headers (`401` expired token,
`415` content-type), the same method/URL (`405`, `414`), or permanent removal (`410`). `404` is
deliberately **not** terminal — in front of a live origin it is far more likely a transient edge
or routing problem than a permanently wrong URL. `408` and `425` are the two that actually reached
a participant under the old default: Cloudflare answers `408` when a client does not finish
sending its request body in time, which is exactly what two thousand people on congested event
Wi-Fi produces, and `425` ("Too Early") comes from the TLS early-data replay protection Cloudflare
enables by default. Both used to fall through to `default: throw AppError.message(...)` and
delete the draft.

**Why invert the default, rather than just add `408`/`425` to the old retryable list?** Because a
hand-picked retryable list only ever covers what someone thought of — the next status nobody
listed still falls to terminal and quietly deletes an answer. The two ways to be wrong here do not
cost the same. Guessing *retryable* when a status is genuinely terminal costs at most one wasted
`POST` per flush round for that base, against a queue `FeedbackOutbox` already hard-bounds to
about 8 items (one per base — `add` replaces rather than accumulates). Guessing *terminal* when a
status was retryable costs a participant's answer, silently: no error, no toast, no badge. A
default that always fails toward "keep it" turns an unanticipated status into something merely
wasteful instead of something destructive.

¹ **`403`/`409` are terminal only when the body actually came from the backend.** A Cloudflare WAF
or firewall rule can answer `403` on its own, as HTML, without the request ever reaching origin —
which the app used to read as "not checked in here" and act on by calling
`outbox.remove(checkpointId:)`, wiping **the whole base's queue**, not just the draft that failed.
The discriminator (`APIClient.OriginBody`) looks at the shape of the body, not the status: a `403`
is terminal only if it decodes to a non-empty `error` string, the shape `middleware.WriteError`
always sends; a `409` is terminal if the body carries `checkpoint_id` **or** a non-empty `error`.
It has to accept both shapes for `409` because of a sharp detail: a genuine `409` does **not**
carry an error envelope at all — `WriteJSON` sends the **existing feedback row**
(`{"id":…,"checkpoint_id":…,"rating":…,…}`) so the form can show the participant what is already
on file (§4). Gating `409` on "is this an error envelope" would have read every real conflict as
an edge response and left that base's queue retrying a submission that can never succeed —
permanently stuck, the opposite failure from the one being fixed. `APIErrorBody` could not be
reused as the discriminator: its `error` field is optional, so it decodes successfully against
*any* JSON object, including `{}` and including the `409` row itself.

The submit/flush behaviour per class is unchanged by either pass — only which statuses map to
which class changed:

| Path | offline | retryable (see table above) | terminal (see table above) | success / 409 / 403² |
|---|---|---|---|---|
| `submit` | queue, return `.saved` | queue, return `.saved` | no queue change, return `.failed` | drop queue entry for that base |
| `flush` | stop the round, keep everything | keep the draft, **continue to the next one** | drop, continue | drop, continue |

² `403`/`409` end the *retry* question — the row already exists (`409`) or never can (`403`, not
checked in) — but neither is thrown as an error; both come back as **outcomes**
(`.alreadyAnswered` / `.notCheckedIn`), which is what lets the form show the stored answer. See §4.

`flush` keeps going past a retryable failure rather than stopping, which is what actually
prevents head-of-line blocking (Task 6's original concern) — once flush continues past a stuck
draft, nothing is gained by deleting it, so retryable drafts no longer need to be deleted to
protect the queue. There is deliberately no bounded attempt counter: its only benefit is
garbage-collecting a draft that 5xxs forever, at the cost of one wasted POST per flush round per
stuck item (bounded by ~8, one per base) — cheaper than the alternative, which is a real answer
dropped with no signal once the bound is exhausted during a long outage: the original bug back in
a rarer but equally silent form. `401` stays terminal; in practice it is moot, because a `401`
triggers `.wbwUnauthorized`, which logs the participant out, and `Session.logout()` already
clears the outbox.

**Proof, in four parts (first pass — the 429/5xx split):**

1. **Unit tests** (`FeedbackStoreTests`) — a `503` on the first send queues the draft and reports
   `.saved`; a `503` during `flush` keeps that draft and still sends the next one; a kept draft
   is delivered on the next `flush` once the server recovers.
2. **Integration test across the real seam** (`WBWTests/FeedbackTransportTests.swift`, new) — a
   `URLProtocol` stub sits under the **real** `APIClient.submitFeedback`, the **real**
   `FeedbackStore`, and the **real** `FeedbackOutbox` on `UserDefaults`. This is the joint where
   the original bug actually lived — which status becomes which error — and a test that injects
   `AppError.retryable` directly at the store level, as the unit tests above do, cannot reach it.
   A guard test (`testStubActuallyInterceptsAPIClient`) asserts the stub really intercepts the
   request, so the suite cannot pass for the wrong reason. `429/500/502/503/504/524` all map to
   `.retryable`; `400/401/422` all stay terminal; `409`/`403` still come back as outcomes.
3. **End to end against the live backend** — SUS running at `localhost:8080`
   (`Config.backend == .susLocal`). A `device_time` Postgres cannot cast makes the repository
   return a non-`23505` error, which the handler's `default:` arm turns into a genuine `500` —
   the exact arm the review named. Verified first with `curl` (`500` back), then through the real
   iOS stack in a temporary test: the real `500` became `AppError.retryable`; `FeedbackStore.submit`
   returned `.saved` with the draft still in the outbox (pre-fix: `.failed`, outbox empty — the
   answer gone); and a queued draft flushed against the healthy server landed as `201`, the outbox
   emptied, and the row was confirmed present in Postgres, then deleted. The temporary test file
   was removed before committing; neither `grep` over the tree nor `git show HEAD` finds a trace
   of it.
4. **Negative control** — the three iOS fixes were reverted and the suite rerun. Every new test
   failed, with exactly the expected messages (`"failed" is not equal to "saved"`, `[] is not
   equal to ["a"]`, `status 503 ต้องเป็น AppError.retryable ได้ message(...)`). Then restored.

**Proof for the second pass (the inversion and the origin-body gate), same standard — written
test-first, run red against the pre-fix code, then green:**

- `testEverythingNotOnTheTerminalListIsRetryable` drives 402/404/406/407/408/418/423/425/426/
  428/429/431/451 plus every 5xx through the **real** `APIClient.submitFeedback`. Against the
  pre-fix code it failed on every one of them except 429 and the 5xx range — which the first pass
  had already fixed — including 408 and 425, the two with a plausible real-world cause on event
  Wi-Fi (Cloudflare's own request-timeout and early-data responses).
- `testForbiddenFromEdgeIsRetryable` and `testConflictFromEdgeIsRetryable` send the real
  Cloudflare block-page HTML under `403` and `409` respectively and assert `.retryable`;
  `testForbiddenWithBodyThatIsNotOursIsRetryable` does the same under `403` for an empty body,
  `{}`, and a body with an unrelated key (`{"message":"Forbidden"}`).
- The actual harm is measured, not just the error type: `testEdgeForbiddenDoesNotWipeTheWholeBaseQueue`
  queues a draft, then submits a second one for the same base against a stubbed Cloudflare `403`.
  Against the pre-fix code the outcome came back `.notCheckedIn` instead of `.saved` and the
  outbox was wiped to `[]` instead of holding the new draft — the whole-base wipe described above,
  reproduced and then closed. `testEdgeForbiddenDuringFlushKeepsTheDraft` is the same measurement
  during `flush`.
- The opposite direction was proved failable too, which matters more than usual here, because
  misreading a genuine backend response as an edge response reintroduces a permanently stuck
  queue: with `isOriginErrorEnvelope` / `isOriginFeedbackRow` forced to return `false`,
  `testForbiddenWithOriginEnvelopeIsTerminal`, `testConflictWithOriginRowIsTerminal`,
  `testConflictWithOriginEnvelopeIsTerminal`, and `testOriginForbiddenStillClearsTheBaseQueue`
  all fail.
- Two Go tests (`TestSubmitFeedbackForbiddenBodyIsErrorEnvelope`,
  `TestSubmitFeedbackConflictBodyIsFeedbackRow`) pin the body shapes the iOS discriminator now
  depends on. They are guardrails on a cross-repo contract rather than regression tests for a bug
  — they pass against unmodified handler code and fail only if the handler's response shape
  changes (verified by rewriting the handler to plain `w.WriteHeader(403)` and `WriteError(409,
  …)`, then restoring it).

Tests went `115 → 126` in the second pass; a further test for the `CheckinProgressStore` fix
below took the total to `127` — see §7.

**What this does not prove.** The live `500` from the first pass is **payload-induced, not
load-induced**: a garbage `device_time` reaches the same `default:` arm a genuinely overloaded
origin would hit, but a real `503` under real concurrent load could not be produced on this
machine, and the app was not pointed at a fake origin to manufacture one — `Config.backend` is
not this review's to set (see item 1). The integration test is what covers the actual status
codes an overloaded origin or a Cloudflare edge would return (`502`/`503`/`504`/`524`) uniformly,
by stubbing them directly rather than by reproducing the load that would normally cause them. The
second pass carries the same limit forward and adds two of its own:

- **No live reproduction of a real `408`, `425`, or edge `403`/`409` exists.** Every case above is
  proven through the unit suite and the `URLProtocol`-stubbed integration test, never against an
  actual Cloudflare response or an actual congested connection. The live evidence in this document
  is still limited to the `409` run above and the one live `500` from the first pass.
- **A residual risk that could not be tested.** The discriminator accepts any body with a
  non-empty `error` key as "from our origin" — it does not, and cannot from here, verify the
  response actually came from `api.studentunion.social`. An edge or gateway other than Cloudflare
  that answered with JSON shaped like `{"error":"..."}` would be misread as the origin and would
  drop that base's queue, the same failure this fix closes for Cloudflare's HTML block page.
  Cloudflare's own block page is HTML, so this is believed remote — but nobody here has access to
  the real edge in front of `api.studentunion.social`, so "remote" is reasoned, not observed.

There is also a latent trap for whoever adds authorization to this route: `POST /wbw/me/feedback`
runs behind `requireAuth` only today, and if `middleware.RequireRole` is ever added to it, that
`403` goes through the same `WriteError` as the feedback handler's own "not checked in" response
— same envelope, same `error` key — so the discriminator would read it as the origin's, and the
participant would see the fixed not-checked-in copy (§4) for what is actually a permissions
problem. The action is still correct (retrying will never fix a role mismatch); only the message
would be wrong.

One UI consequence worth knowing: a retryable failure shows the same **"ส่งความเห็นแล้ว ขอบคุณ"**
as the offline case — the existing optimistic stance, now genuinely true for this path too, since
the outbox retries it. Nothing on screen distinguishes "queued because offline" from "queued
because the server said try again".

---

## 4. Form states, on screen

Two states the earlier tasks had only code-reviewed are now screenshotted.

**`.alreadyAnswered`** — §3 above. The stored answer replaces the local draft, read-only, under
the green success label.

**`.notCheckedIn`** (`step2b-notcheckedin.png`) — driven by opening the form for checkpoint 10,
which the test account has never checked into, and sending. The `403` comes back, `sent` is
cleared, and the card shows a red `exclamationmark.triangle.fill` with
**"ระบบแจ้งว่ายังไม่ได้เช็คอินฐานนี้ (ไม่ควรเกิดขึ้น) ลองปิดแล้วเปิดฟอร์มใหม่"**. The rating
(**เฉยๆ**) and the typed comment are both **preserved**, and the gold send button is enabled
again — genuinely recoverable, not a dead end. No row was created and nothing was queued.

The base name falls back to **ฐานกิจกรรม** because checkpoint 10 is not in the participant's
progress, which is the correct behaviour for a base the app has no data for.

**`.failed`** was proven on screen in Task 8 through `FeedbackStore`'s injectable `submitCall`
seam. **`.saved`** is §2.

Still not screenshotted: the toast's `remaining > 0` branch (only one base has ever been newly
pending in a single tick), the toast suppression rules (`canShowCheckinToast`), and the logout
paths.

---

## 5. The foreground push path — closed, under a simulated payload

`AppDelegate.willPresent`'s `.checkinFeedbackArrived` post was, until this task, **the one line
of the foreground-push path with no coverage of any kind**. It has now executed.

**Method.** `xcrun simctl push` delivers an APNs-shaped payload through the simulator's real
notification pipeline, so `UNUserNotificationCenterDelegate` runs for real. The payload used
mirrors what FCM produces from `notifyFeedback`'s `SendUserPush` call (title, body, and the
`data` map hoisted to top-level keys, which is how FCM delivers `data` to APNs):

```json
{"Simulator Target Bundle":"th.ac.mfu.wbwSwift",
 "aps":{"alert":{"title":"เช็คอิน ฐาน SDGs แล้ว","body":"แตะเพื่อให้คะแนนฐานนี้"},
        "sound":"default","badge":0},
 "type":"checkin_feedback","checkpoint_id":"8","gcm.message_id":"0:…"}
```

Notification authorization was obtained with `.provisional` (granted immediately, no dialog)
through a temporary `#if DEBUG` hook, because there is no way to press **Allow**.

**The experiment.** Deleted the `check_in` row for checkpoint 8 so the app would load a progress
state without it, launched (T0), restored the row at T0+19 s, pushed at T0+22 s, and
screenshotted at T0+25 s and T0+29 s.

At **T0+25 s**, `push-t25.png` shows the app's own `CheckinToast`: a green
`checkmark.seal.fill`, **"เช็คอิน ฐาน SDGs แล้ว"**, **"แตะเพื่อให้คะแนนฐานนี้"**. By T0+29 s the
tree had grown from stage 7 to stage 8.

**Why that is proof and not a coincidence.** For `CheckinToast` to appear, `progress.newlyPending`
must become non-empty, which requires `progress.load()` to run. There are exactly five callers:

| Caller | Ruled out because |
|---|---|
| `MainTabView.task` (mount) | ran at T0, 22 s before the database changed |
| the 60 s poll | first tick at T0+60, 35 s after the toast appeared |
| `scenePhase == .active` | the app never left the foreground |
| `FeedbackView.send()` | no form was open |
| **`.onReceive(.checkinFeedbackArrived)`** | the only one left |

and `.checkinFeedbackArrived` is posted from exactly one line in the entire codebase —
`AppDelegate.swift:128`, inside `willPresent`'s `checkin_feedback` branch.

**Negative control.** The identical push, sent again with no database change, produced **no
toast and no system banner** (`push-control-t3.png`). The absent system banner is the second
half of the claim: `willPresent` returned `[]` and suppressed iOS's own banner, which is exactly
what the `checkin_feedback` branch is supposed to do.

**What this does *not* prove.** The payload was hand-written to match what FCM should produce;
it was not produced by FCM. So the FCM→APNs translation, the token targeting, and the delivery
itself remain unverified — see §"What you are carrying", item 2. What is now certain is that
**given** a correctly-shaped payload, the app suppresses the system banner, posts the refresh
event, reloads, and shows its own toast within about 3 seconds.

`didReceive` still requires a tap and remains unexercised.

---

## 6. `.id(target.id)` on the feedback sheet — verified, and redundant on this OS

The guard exists so that setting `feedbackCheckpoint` to a **new** base while the sheet is
already open forces SwiftUI to build fresh `@State`, instead of leaving base A's rating and
comment sitting in base B's form.

Driven by a temporary hook that fills the form for checkpoint 7 with rating 3 and
`"ร่างของฐานที่ 7 ยังไม่ได้กดส่ง"`, then swaps `feedbackCheckpoint` to checkpoint 8 twelve
seconds later. (The trigger is a hook rather than two live pushes, but the SwiftUI mechanism
under test — assigning a new `Identifiable` item to a presented `.sheet(item:)` — is identical
regardless of who assigns it.)

- **With `.id(target.id)`** (`id2-a-form7.png`, `id2-b-form8.png`): form A shows ฐานผ้าใบ with
  ชอบ selected and the draft text; after the swap, form B shows **ฐาน SDGs** with **all three
  faces unselected**, the comment box back to its placeholder **"เล่าให้ฟังหน่อย… (ไม่บังคับ)"**,
  and the send button greyed out. No bleed.
- **Negative control, `.id(target.id)` removed and rebuilt** (`id4-negctrl-A/B.png`): form A is
  identical, and after the swap form B is **also fully reset**.

So on **iOS 26.5 the guard is not load-bearing** — `.sheet(item:)` already tears down and
rebuilds when the item's id changes. The line is harmless insurance, and its own code comment
already says the behaviour it guards is "undocumented and varies by version", which is exactly
the reason to keep it. Recorded so nobody later reads the comment as describing a bug that was
observed here; it was not.

---

## 7. Which entry points were exercised, and how

The spec names four ways into the feedback form. All four converge on the single
`feedbackCheckpoint` state in `MainTabView` — there is no other route to `FeedbackView`.

| Entry point | Exercised? | By what means |
|---|---|---|
| 1. Tap a push while the app is **closed** (cold launch) | Downstream only | Temporary hook calling `PendingPush.hold(.openCheckinFeedback, info: ["checkpoint_id": "6"])` — the exact call `didReceive` makes. Everything after that is production code, including the deferred `markRead` retry, confirmed by the `notification.read_at` timestamp changing without the list ever being opened. **The tap itself and `didReceive` have never run.** |
| 2. Push arrives while the app is **open** | **Yes — §5** | `xcrun simctl push` with a simulated FCM-shaped payload. Real `willPresent`, real suppression, real refresh event, real toast. |
| 3. Toast from the 60 s poll | **Yes, fully live** | No hooks, no taps. Run end to end twice by two different agents on two different checkpoints; toast at T+62–65 s naming the base, tree growing in the same frame, plus a 361-frame continuous sweep over a further full tick proving the toast does not repeat. The diff logic behind it now also has dedicated automated coverage — see below. |
| 4. Tap a card in the notification list | Downstream only | Temporary hook calling `onOpenFeedback(6)` — the same closure the card's `Button` calls. The sheet-to-sheet handoff (notifications closes, form opens) is real and was the reason `.sheet(onDismiss:)` replaced a 350 ms timer. **The tap itself has never run.** |

**A concurrency bug behind entry point 3, found by the final review and now fixed.**
`CheckinProgressStore.load()` has five callers — the poll, `scenePhase == .active`,
`.checkinFeedbackArrived` (the push path above), `FeedbackView.send()`, and mount — none of which
coordinate with each other. On bad network, two overlapping `GET /me/progress` calls can resolve
out of order, and the older response landing *after* the newer one used to roll `progress`, the
cache, and the pending-diff comparison set all backwards at once: the tree on Home could visibly
shrink by a stage, and a base that had already toasted could toast again on the next poll. The
fix is a generation counter (`loadGeneration`), not a guard that drops overlapping calls outright
— a drop-style guard would have quietly defeated the push path itself
(`.checkinFeedbackArrived` arriving while a poll is in flight would then wait for the *next*
poll, up to 60 s, which is the exact delay the push exists to avoid). Every call still runs to
completion; only a stale result is discarded, and it is discarded as a whole payload, never
partially. `testStaleLoadResponseDoesNotRollBackState` proves both symptoms are gone: `stage`
does not regress, and the next load does not re-emit the same base as newly pending.

**A second, subtler bug in the same counter, found in the next pass (`12e7cbc`).**
`loadGeneration` by itself tracks "started later," not "answered later." Concretely: a refresh
fired by `FeedbackView.send()` (generation *N*) is still in flight when the 60 s poll starts a
fraction of a second later (generation *N+1*); that poll's `GET` then fails on bad network — a
routine event on this Wi-Fi. The failed *N+1* still advanced `loadGeneration`, so when *N*'s
response landed afterward it no longer satisfied `generation == loadGeneration` and was discarded
as "stale," even though nothing newer had actually arrived to replace it. The visible effect: the
form stayed editable for up to 60 s after a successful submit, as if nothing had been sent. The
fix adds `acceptedGeneration`, which only advances when a response **actually arrives and is
applied**; a load that throws leaves it untouched, so a genuinely successful older response still
wins. `testFailedNewerLoadDoesNotDiscardSuccessfulOlderOne` proves the fix;
`testSuccessfulNewerLoadStillWinsOverOlderOne` is the negative control, pinning that a newer
**successful** load still beats an older one exactly as before.

**A related gap, closed one commit later (`924babf`).** `clear()` — called on logout — reset
`progress`, the cache, and the pending-diff state, but not `acceptedGeneration`. A request still
in flight at the moment of logout is therefore not yet "accepted," so its response could still
satisfy `generation > acceptedGeneration` and land **after** the next account has already logged
in and started loading — repopulating the tree and the pending list from the previous account's
data, into a cache key namespaced by backend, not by person. This matters here specifically
because phones are genuinely shared at this event, between staff and participants. `clear()` now
also sets `acceptedGeneration = loadGeneration`, so anything still in flight at logout is
retroactively treated as stale no matter when it lands. `testResponseInFlightAtLogoutIsDiscarded`
drives exactly that sequence — a load left in flight, `clear()`, then the stale response landing —
and asserts `progress`, `newlyPending`, and the on-disk cache all stay empty afterward.

**Which of the four rests on what, plainly:**

- **Entry point 1** (push tap, cold launch) rests on **reading alone**. The hook call stops one
  layer short of the tap; `didReceive` itself has never executed, in a test or otherwise.
- **Entry point 2** (push while open) rests on a **single manual run**, captured in two
  screenshots (§5). It is real evidence — `willPresent` genuinely ran against a real payload —
  but it is one run, not a regression test; nothing re-executes it on the next build.
- **Entry point 3** (the 60 s poll) rests on **both**: the live screenshot evidence above, run
  twice, plus automated XCTest coverage of the state-transition logic underneath it
  (`CheckinProgressStoreTests` — `testStaleLoadResponseDoesNotRollBackState` from the first
  review, plus the `acceptedGeneration` and logout tests above from the two passes since), which
  runs on every `xcodebuild test` rather than only when someone remembers to drive it by hand.
- **Entry point 4** (notification card tap) rests on **reading alone**, the same shape as entry
  point 1 — a hook stands in for the `Button`'s closure, but no tap, real or simulated, has ever
  reached it.

---

## 8. Database state left behind

All writes were confined to test participant `6931900011`
(`edde9922-199e-41e6-a521-33ba35eca3d3`). No other participant's rows were read or written, and
no password was ever placed on a command line — `docker exec postgres-db psql -U admin -d sudb`
needs none.

**`checkin_feedback` — 6 rows, all for this account.** Task 12 added the last two:

| id | checkpoint | rating | comment | origin |
|---|---|---|---|---|
| 4 | 2 | 3 | ดีมาก | early task |
| 6 | 1 | 3 | ดีมาก | early task |
| 28 | 3 | 3 | live-verify task6 | Task 6 |
| 35 | 6 | 3 | ตอบจากการ์ดแจ้งเตือน | **hand-inserted** by a Task 11 reviewer to simulate answering from the card; did not go through the app |
| 37 | 4 | 3 | ทดสอบส่งตอนเซิร์ฟเวอร์ดับ | **Task 12 §2** — went through the app and the offline queue |
| 38 | 5 | 1 | รอบแรก ส่งตอนเน็ตหลุด | **Task 12 §3** — same |

The account is now **6 answered (1, 2, 3, 4, 5, 6) and 2 pending (7, 8)**. Earlier task reports
say "4 answered, 4 pending" — **that baseline has moved.** Read the current state before writing
any check that depends on it.

**`notification` — 4 rows, unchanged by Task 12.**

- ids 1, 2: plain announcements, from before this plan.
- id 4: `checkin_feedback`, `ref_id = 7`, created by a real scan in Task 4.
- **id 8: `checkin_feedback`, `ref_id = 6` — synthetic.** A Task 11 reviewer inserted it by hand,
  mirroring the shape the backend creates, because no unread `checkin_feedback` notification for
  checkpoint 6 existed to test the card against. It is now marked read. **Do not mistake it for
  something the backend produced.**

**`check_in` — 9 rows for this account, checkpoints 1–9.**

- Checkpoints 1, 2, 3, 9: original seed (2026-08-02 03:03).
- Checkpoints 4, 5, 7, 8: created by test scans during this plan, so their `client_id`s and
  timestamps are test artefacts, not seed data.
- **Checkpoint 6 was deleted and re-inserted three times** across Task 11's runs, so its
  `client_id` (`99379212-…`) and `at` (2026-08-03 03:26) are **not** what they originally were.
- **Checkpoint 8 was deleted and restored by Task 12 §5**, re-inserted with the *same* explicit
  `id` (30), `client_id`, `staff_id`, `device_time` and `server_received_at`, so that row is
  byte-identical to before. The `check_in_id_seq` was not advanced (the insert named an id below
  the current sequence value), so no future collision.

**Not modified by any task:** the `checkpoint` table, `app_user`, roles, group membership, and
every other participant's data.

### Re-running the checks

```bash
# current answers
docker exec postgres-db psql -U admin -d sudb -c \
  "SELECT id, checkpoint_id, rating, comment FROM checkin_feedback ORDER BY id"

# what the app will see
curl -s http://localhost:8080/wbw/me/progress -H "Authorization: Bearer <jwt>"

# what is queued on the device right now
CONT=$(xcrun simctl get_app_container booted th.ac.mfu.wbwSwift data)
python3 -c "import plistlib,json,sys; d=plistlib.load(open('$CONT/Library/Preferences/th.ac.mfu.wbwSwift.plist','rb')); print(json.loads(d['wbw.feedback.outbox.susLocal']))"
```

The outbox key is namespaced per backend (`wbw.feedback.outbox.<cacheNamespace>`), so switching
`Config.backend` hides the queue rather than sending it to the wrong server. That is deliberate;
see `docs/sus-test-backend.md` for the same trap in the chat cache.

---

## 9. Test suites

Both run on 2026-08-03, on the committed tree, with no temporary hooks present. Numbers below are
higher than when this document was first written: the final whole-branch review added tests for
what it found (§3, §7), and a second pass after that closed two more gaps the same review missed
(§3, §7 again) plus one on the Go side below; this is the count as of `924babf` / `c706b48`.

**SUS (Go)** — `go test ./... -count=1`, actual output:

```
?   	su-server/cmd	[no test files]
?   	su-server/cmd/createadmin	[no test files]
?   	su-server/config	[no test files]
ok  	su-server/internal/handler	1.299s
ok  	su-server/internal/middleware	0.790s
ok  	su-server/internal/model	1.777s
ok  	su-server/internal/repository	2.230s
ok  	su-server/internal/service	3.599s
```

**56 top-level tests, 75 including subtests, 0 failures — but only 51 of the 56 exercise real
behaviour by default.** The other 5 are still `internal/repository`'s: they need a real Postgres,
so they check `WBW_DB_TESTS=1` and call `t.Skip` before opening a connection if it is unset, which
is why the default run above shows a plain `ok` for that package with no hint that anything was
skipped (`go test` only reports skips under `-v`). What changed since this section was first
written is not the gate itself but what used to happen once it was open: `openTestDB` used to
`t.Skip` on a failed connection, a failed ping, or a missing test account too — so
`WBW_DB_TESTS=1` on a checkout with no reachable database, or no `.env`, printed a clean `ok`
having run nothing at all, which is exactly what happened once during the review itself. Every one
of those paths is now `t.Fatalf`; the only remaining `t.Skip` is the original one, before the
switch is even checked. With `WBW_DB_TESTS=1` set, all 56 run and pass, 0 skipped — verified in
the fix report (`.superpowers/sdd/2026-08-03-checkin-feedback/final-fix-report.md`), which also
confirmed the database was byte-for-byte back to its prior state afterward (writes are confined to
`checkin_feedback` rows for the test participant, wiped both before and after). That run was not
repeated for this pass, because it writes to the database; the figure above is the fix report's,
cited rather than reproduced.

**What a default `go test ./...` — the kind any CI runs unless someone opts in — does not cover:**
the two-unique-constraint `23505` disambiguation, `ErrNotCheckedIn`, and the `requires_checkin`
filter, the three behaviours that are pure SQL and cannot be honestly faked (see the doc comment
at the top of `wbw_feedback_repository_test.go`). Those three stay covered only by the live
`curl` run in §1 and by whoever remembers to set the flag. The `GET /wbw/me/progress` query has
the same shape of gap and nobody has closed it: it `LEFT JOIN`s `checkin_feedback` on
`(participant_id, checkpoint_id)` (Task 2) to report which bases are answered, that join is pure
SQL exactly like the three above, and it has no test of its own — under `WBW_DB_TESTS=1` or
otherwise. `internal/handler` is a different story: it had no test files at all when this
document was first written; it now has 11 — the spec's five POST status-code cases, 401,
malformed JSON, and 500, all through the real `middleware.RequireAuth`, plus two added in the
second pass (`TestSubmitFeedbackForbiddenBodyIsErrorEnvelope`,
`TestSubmitFeedbackConflictBodyIsFeedbackRow`) that pin the exact body shapes the iOS
discriminator now depends on — see §3.

**iOS** — `xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS
Simulator,name=iPhone 17'`, actual output:

```
Test Suite 'All tests' passed.
	 Executed 127 tests, with 0 failures (0 unexpected) in 0.669 (0.727) seconds
** TEST SUCCEEDED **
```

**127 tests, 0 failures.**

Related and worth knowing: the app target is the test host, so every `xcodebuild test` boots the
whole app. Task 5b had to gate the RealityKit scene off under XCTest
(`ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil`) because the unit
tests finished in ~0.2 s and `exit()` tore down `libusd_ms`'s globals while a `forest.usdz` load
was still in flight, segfaulting **after** the results were recorded. Tests still passed; the
crash was invisible unless you looked at the crash logs. If you ever see a `WBW` `.ips` dated to
a test run, that is the shape to check for.

---

## 10. Temporary hooks used by Task 12, and their removal

All were `#if DEBUG`, all tagged `TEMP-TASK12-VERIFY`, none committed.

| Hook | File | Purpose |
|---|---|---|
| `-uitestT12Send "<rating>:<comment>"` | `FeedbackView.onAppear` | fills the form and calls the real `send()` |
| `-uitestT12Type "<cp>:<rating>:<comment>"` | `FeedbackView.onAppear` | fills the form **without** sending; scoped to one checkpoint (see the method note above) |
| `-uitestT12CloseAfter <seconds>` | `FeedbackView.onAppear` | closes the form on its own, since there is no tap tooling |
| `-uitestT12SwapTo "<cp>:<seconds>"` | `MainTabView.task` | reassigns the sheet's item while it is open (§6) |
| `-uitestT12NoPushPrompt 1` | `AppDelegate.didFinishLaunching` | requests `.provisional` authorization instead of the modal prompt |
| (untagged) `.id(target.id)` removed | `MainTabView` | negative control for §6, restored immediately |

After removal, `git status --short` is empty in both repositories, and
`grep -rn "TEMP-TASK12\|uitestT12" WBW/ WBWTests/` returns nothing in the working tree and
nothing in the commit.

**A note on the notification permission dialog.** Task 10 reported that a `#if DEBUG` skip of
`requestAuthorization` "did not reliably suppress the prompt", and Task 11 worked around it by
installing a bundle with `GoogleService-Info.plist` deleted — which meant none of its screenshots
were taken on a Firebase-live build. That diagnosis was wrong. The dialog is a **SpringBoard**
alert that survives app termination *and* reinstallation; it was a stale alert from an earlier
launch, not a new request. `xcrun simctl shutdown` + `boot` clears it, after which the DEBUG
guard works exactly as expected. Every screenshot in this document was taken on a normal,
Firebase-configured Debug build.
