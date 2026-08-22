# SOS — what was built, what was proven, what was not

Written 2026-08-07, at the end of the implementation run for
`docs/superpowers/specs/2026-08-06-sos-design.md` and
`docs/superpowers/plans/2026-08-06-sos.md`.

This file records what is actually true, in the same spirit as
`docs/checkin-feedback-verification.md`. Where something was verified, it says by what
means. Where it was not, it says so plainly.

## Where the code is

- **Go backend** — `~/Student-Union-Server`, branch `feat/wbw-sos`, `d9bcb10..f094fed`
  (18 commits). Branched from `origin/main`, **not** local `main`, which is stale at
  migration 000010 and would have put migration 000015 on a tree missing 11-14.
- **iOS app** — branch `feat/wbw-sos`, `9a68e43..a402f98` (37 commits), currently checked out
  in the worktree `/Users/park/wbw-ios-sos-build`. The main checkout was returned to
  `feature/redesign-group-chat` for the other session working there.

Neither branch is pushed. Neither is merged.

## What is proven

- **Go**: `go build ./...` and `go vet ./...` clean. Every SOS-scoped package passes —
  `handler`, `repository`, `service`, `model`.
- **iOS**: **214 tests, 0 failures**, run in the foreground against a real simulator after the
  final commit. The baseline before this work was 133.
- **Migration 000015 applies cleanly from an empty database through the whole 1→15 chain**, and
  the down migration round-trips. Verified against a throwaway Postgres container built from
  scratch, not against a developer machine.

## What is NOT proven, and must be before event day

1. **Nothing has run on real hardware.** No two-phone rehearsal, no push delivered to a real
   device for this feature, no on-device login. The spec makes that rehearsal a precondition for
   "done" and it has not happened. Four of the defects listed below would have surfaced in ten
   minutes of it.
2. **Migration 000015 has not been applied to production.** Only to the throwaway database.
3. **The camera-stop when staff switch to the SOS tab is unverified.** It depends on
   `ScannerVC.viewWillDisappear` firing through a `UIViewControllerRepresentable` inside a
   SwiftUI `TabView` — a different mechanism from the `ForestSceneHost` lifecycle proof cited for
   it, and unverifiable on the simulator. If it does not fire, `AVCaptureSession` runs all day
   behind the SOS tab on the devices that most need their battery.
4. **The location permission dialog has never been seen.** No automated test exercises
   `Session.save(_:)` end to end. Confirm it on a fresh login *and* on an already-authenticated
   upgrade — those are different paths and only the second was a bug.
5. **`ack` / `resolve` error handling is verified by inspection only.** They call
   `APIClient.shared` with no injection seam.
6. **The sheet-dismiss ordering in `SOSFriendView`** was reasoned through, not observed.

## Operational prerequisites — none of these are code

1. **`checkpoint_staff` must be populated on production.** Without it every case falls through
   the everyone-sees-it net and all twelve bases are paged for every incident.
2. **`WBW_EMERGENCY_PHONE` must be set to a real number.** `.env.example` ships it empty.
3. **`staff_role` must be `medical` / `security`** on the nurse and security accounts, or
   `seesEverything` returns false for them and the central team is `admin` only.
4. **App Store**: a new build, the location privacy answers, and the rewritten privacy policy.
5. One full rehearsal.

## The defects that were found and fixed

Twenty-six real defects were found during implementation, **all of them in code the plan told
the implementers to write** — the plan was written from the schema and the existing code without
running any of it. They are recorded here because the shapes recur.

### The ones that made the feature silently useless

- **`noti_level` has no member `"urgent"`.** The group notification row failed to insert on every
  SOS, and `slog.Error` swallowed it. Two more independently fatal defects sat on the same call:
  `AudienceID` was never set (so `ListForUser`'s `audience_id = p.group_id::text` could never
  match), and `createdBy` was `""` into a UUID column. A group member with the app open saw
  nothing at all, and every piece of iOS surface built for it was unreachable.
- **The staff feed cursor did not survive the wire.** `updated_at::text` emits `+00`;
  `.urlQueryAllowed` does not escape `+`; Go decodes it as a space; Postgres rejects it; the
  handler 500s; `try?` hides it; and because the cursor is only reassigned on success, the
  poisoned value is re-sent forever. From the first real case of the day onward the staff screen
  was frozen while still looking healthy.
- **`req.httpBody` was deleted by a fix** and replaced with `req.timeoutInterval` on the same
  line. Every raise returned 400 and no case was ever created — while the never-drop guarantee
  and the 20-second call fallback kept the UI looking alive. 211 tests stayed green because every
  `SOSStore` test injects `raiseCall` and `APIClient.raiseSOS` had no test at all. That gap is
  now closed.

### The ones that only appeared across a task boundary

- Migration 000015 referenced `app_user`, renamed to `wbw_user` back in migration 000012. The
  whole chain refused to run. The plan was written from `000005_wbw.up.sql`, which predates the
  rename — and the task-scoped reviewer verified the FK targets against that same pre-rename file.
- `SOSStaffCase` was used in Task 10 and declared in Task 15; `Config.cacheEmergencyPhone` was
  used in Task 12 and defined in Task 13. Neither target would have compiled.
- `sosNoti.Create` was declared returning `(int64, error)` while the real service returns
  `(*model.Notification, error)`.

### The ones only a real run could find

- `go test -run SOS` matched **no test in this feature** — every name starts with `TestRaise`,
  `TestCancel`, `TestResolve`, `TestStaffFeed` — and printed `ok … [no tests to run]`, which reads
  like a pass.
- `oneShot` built on `withTaskGroup` hung forever when the GPS fix never arrived, which is the
  one case the function exists to guard. The runtime said so directly:
  `SWIFT TASK CONTINUATION MISUSE`, with xcodebuild parked at 0% CPU for 6:44.
- `activeSOS` compared the response body to the literal `"null"`, but Go's encoder always appends
  a newline, so the comparison missed and it threw a raw `DecodingError` — on the response every
  participant gets on every poll while they have no open case.
- `accuracy_m > 200` yields SQL NULL, not FALSE, when `accuracy_m` is NULL, so `CanStaffSee`'s
  scan into `*bool` crashed. Found only because a review demanded the missing coverage.
- The listener's `backoff = time.Second` reset was unreachable: it runs only when `listenOnce`
  returns nil, and `listenOnce` has no such path. One blip after deploy pinned reconnects at the
  30-second cap for the life of the process. **The identical bug is still live in
  `internal/service/wbw_chat_events.go`**, which is shipped code outside this branch — worth its
  own change.

### The concurrency ones

- `Raise` returned a raw 23505 when two presses raced on a participant's first-ever case —
  `FOR UPDATE` cannot lock a row that does not exist yet.
- `Cancel` did check-then-act across two round trips with a bare `WHERE id = $1`, so a staff
  `Ack` landing in the gap was silently overwritten with `resolve_reason = 'canceled_by_user'` —
  corrupting the record of why a safety-critical case closed.
- A `cancel` or `logout` racing an in-flight send could resurrect the cancelled case, or leak it
  into the next account's session. Closed with a generation counter.
- Leaving the outbox intact across an automatic logout then let a *different* account adopt the
  previous person's draft and POST it under their own token — which, when the original raise had
  not yet reached the server, made the server INSERT a **real, dispatchable case attributed to
  the wrong person with someone else's coordinates**. Closed with `SOSDraft.ownerId`.
- Adding `ownerId` with no default then made every pre-existing draft undecodable, silently
  dropping an in-flight case on upgrade. Closed with a tolerant decoder.

### The "looks tappable, does nothing" ones

This project was already rejected once by App Review for a dead affordance on the login screen.
Three more shipped into this branch before review caught them:

- The staff full-screen alert never fired for the **first real case of the day**, because
  `isBaseline` was keyed on `seenIDs.isEmpty` and an emergency feed is empty most of the time.
- The note field could never be submitted — `TextField(axis: .vertical)` with `.onSubmit` as its
  only trigger, and the Return key inserts a newline.
- "เปิดแชทกลุ่ม" posted its notification without dismissing its own sheet, so the chat opened
  invisibly behind it.

## What holds up

The never-drop guarantee is real and defended in depth: `sosIsTerminal` returns a constant with a
test walking every status 100-599 behind it, `decodeSOS` closes the raw-`DecodingError` escape,
and no `catch` in `SOSStore` clears the outbox. The health-data gate lives in SQL over three
conditions with a negative test for each, and the peer-facing type has no phone field at all, so
that prohibition is structural rather than disciplinary. `Raise`'s single retry on 23505 and
`Cancel`'s guarded single UPDATE are the right shapes for the races they close.
