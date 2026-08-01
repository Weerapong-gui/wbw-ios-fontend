# Check-in Feedback — Notify After Scan, Collect Per-Base Feedback

- **Date:** 2026-08-02
- **Status:** Approved (design), pending implementation plan
- **Scope:** what happens after a staff member scans a participant — a personal
  notification, and a per-base feedback form.
- **Repos:** `wbw-ios-fontend` (iOS) **and** `~/Student-Union-Server` (SUS, Go)
- **Depends on:** `2026-08-02-forest-3d-background-design.md` (spec 1). This
  spec extends the `GET /wbw/me/progress` endpoint that spec 1 introduces and
  the `CheckinProgressStore` that consumes it. Spec 1 must land first.

## Context

`POST /wbw/staff/checkin` (`internal/handler/wbw_staff_handler.go:39`) writes a
`check_in` row and returns the participant's name, bib, medical flag, and
`already_checked_in`. Nothing else happens: the participant's phone is never
told, and no opinion about the base is ever collected.

The infrastructure needed is mostly already there:

- `notification` supports `audience='user'` with `audience_id` holding a user
  id, and `notification_read` tracks read state per user
  (`db/migrations/000005_wbw.up.sql`). Per-person notifications work end to end
  today — the app lists them in `NotificationsView` and badges them through
  `NotiStore.unreadCount`.
- FCM push exists (`internal/service/wbw_push_service.go`, `WBW/AppDelegate.swift`),
  with device registration already wired up.

Two things are missing: `wbw_push_service.go` can only `SendChatPush`, and
there is no way to send a push to one specific user; and there is no feedback
storage at all.

## Goal

1. When a participant is scanned into a base, they get a notification.
2. If they miss it, the notification waits in the notification list and still
   opens the feedback form.
3. The feedback form states which base and which activity it is about.
4. Feedback is one rating of three levels plus optional free text.
5. The collected feedback is readable without opening a database client.

## Non-Goals (YAGNI)

- No editing an answer once submitted.
- No feedback for service points (`requires_checkin = false`).
- No reminder push chasing people who never answered.
- No admin UI for reading feedback — an endpoint only; the SUS web app can
  build a screen later.
- No changes to `~/su-wbw-website`.

## Decisions taken

| Question | Decision |
|---|---|
| What is collected | Free text + 3 levels: dislike / neutral / like |
| Attribution | Tied to the participant, and the form says so in plain words |
| App is open when scanned | In-app toast (chat-style), and the tree grows immediately |
| How the app finds out | FCM push primary, 60 s foreground poll as a safety net |
| Form look | White card on the cream `#FAF7F0` background, matching `NotificationsView` |

The rejected realtime alternatives: **push only** dies completely on builds
without `GoogleService-Info.plist` (which is gitignored) and on any user who
declines notifications; **long-poll like chat** would need a new server-side
event bus and a held connection all day for an event that happens 8 times per
participant.

## Data model

Migration `000012_checkin_feedback`:

```sql
CREATE TABLE checkin_feedback (
  id             BIGSERIAL PRIMARY KEY,
  participant_id UUID NOT NULL REFERENCES app_user(user_id)         ON DELETE CASCADE,
  checkpoint_id  INT  NOT NULL REFERENCES checkpoint(checkpoint_id) ON DELETE CASCADE,
  rating         SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 3), -- 1 dislike, 2 neutral, 3 like
  comment        TEXT,
  client_id      UUID NOT NULL UNIQUE,
  device_time    TIMESTAMPTZ NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uniq_feedback_participant_checkpoint UNIQUE (participant_id, checkpoint_id)
);
CREATE INDEX idx_feedback_checkpoint ON checkin_feedback(checkpoint_id);

ALTER TABLE notification ADD COLUMN IF NOT EXISTS ref_id TEXT;
```

`client_id` makes a retry after a dropped connection idempotent, the same
pattern `check_in` and `wbw_messages` already use.

`ref_id` is how a notification row points at its checkpoint. Without it the app
would have to guess — "open the oldest unanswered base" — which breaks the
moment two bases are pending.

**"Pending" is not stored.** There is no status column and no state machine: a
base is pending when a `check_in` row exists and a `checkin_feedback` row does
not. A `LEFT JOIN` answers it, so the status cannot drift out of sync with
reality.

## Endpoints

### Extended: `GET /wbw/me/progress`

Spec 1 defines this endpoint to drive the growing tree. This spec adds the
feedback fields to the same payload rather than adding a second endpoint —
the 60 s poll has to run anyway, and splitting would mean two requests per
cycle against the same tables.

```json
{
  "total": 8,
  "checked_in": [
    { "checkpoint_id": 1,
      "name": "วิหารพระเจ้าล้านทอง",
      "activity_name": "ไหว้พระวิหารพระเจ้าล้านทอง",
      "sequence": 1,
      "at": "2026-08-29T09:12:03Z",
      "answered": false,
      "rating": null,
      "comment": null }
  ]
}
```

`activity_name` is added because the form names the activity, not just the base.

### New: `POST /wbw/me/feedback` (participant)

Request: `{client_id, checkpoint_id, rating, comment, device_time}`

| Case | Response |
|---|---|
| New answer | `201` with the stored row |
| Same `client_id` resent | `200` with the existing row — a retry, not an error |
| Same base, different `client_id` | `409` with the existing answer |
| Participant never checked in there | `403` |
| `rating` outside 1–3 | `400` |

### New: `GET /wbw/admin/feedback` (admin)

Raw rows — base, respondent, rating, comment, timestamp — plus a per-base count
by rating. No UI in this spec; this exists so the data is reachable from day one
instead of requiring database access. Registered in the existing `/wbw/admin`
block in `cmd/main.go`.

## Sending the notification

In `wbw_staff_service.Checkin`, after the `check_in` row is written **and only
when `already_checked_in` is false**:

1. Insert a `notification`: `type='checkin_feedback'`, `audience='user'`,
   `audience_id=<participant>`, `ref_id=<checkpoint_id>`, `level='info'`.
2. Call a new `SendUserPush(ctx, userID, title, body, data)` in
   `wbw_push_service.go`, with data `{"type":"checkin_feedback",
   "checkpoint_id":"N"}`.

Both must be fire-and-forget in the shape `SendChatPush` already uses
(`context.WithoutCancel` plus a goroutine). A slow or failing FCM call must
never turn into a 500 for the scanning staff member — they are standing in
front of a queue.

Scanning the same participant twice must not produce a second notification;
that is what the `already_checked_in` guard is for.

## App flow

Four entry points, one destination — `FeedbackView(checkpointId:)`. The view
reads its base name, activity name, and any existing answer out of the cached
progress response, so opening it for a base that was already answered shows
that answer read-only instead of an empty form.

Tapping a push jumps straight to the form without passing through
`NotificationsView`, which is where `markAllRead` runs today. That path must
mark its own notification read, or the bell keeps a badge for something the
user already dealt with.

| Entry | Mechanism |
|---|---|
| Tap push while app is closed/backgrounded | `AppDelegate.didReceive` reads `type` and `checkpoint_id` |
| Push arrives while app is open | `willPresent` returns `[]` to suppress the system banner, as chat already does (`AppDelegate.swift:111`), then posts an event |
| 60 s poll finds a base with `answered=false` that was not there last cycle | `CheckinProgressStore` diffs against the previous response |
| Tap a card in the notification list | `NotiCard` with `type='checkin_feedback'` becomes tappable, using `ref_id` |

### `PendingPush` has to carry an id

`PendingPush` (`AppDelegate.swift:16-31`) holds only a `Notification.Name`,
which was enough for "open announcements" and "open chat". Feedback needs to
know which base, so it must hold userInfo as well.

This code guards a real cold-launch trap — `didReceive` fires before
`MainTabView` installs its `.onReceive`, so the event is parked and replayed
once. The existing `consume()` / `clear()` semantics must survive the change
intact; the comments there document why each call exists.

### Toast

`ChatToast.swift` already contains a toast shell. Rather than copying it, the
shell moves to `WBW/Toast.swift` and both chat and feedback become thin
wrappers over it. This is deduplication caused by the work at hand, not an
unrelated refactor.

When several bases are pending at once — say three check-ins happened while the
phone was offline — one toast appears for the most recent base, with a trailing
"ยังมีอีก 2 ฐานรอประเมิน". The rest are in the notification list. Three stacked
toasts is not an option.

### Offline

Participants are standing in the hills with unreliable signal. Pressing send
must not lose what they typed.

`FeedbackOutbox` persists unsent answers to `UserDefaults`, **namespaced by
`Config.backend`** like every other cached value in the app, and flushes on
`scenePhase == .active` and after any later successful submit. The UI reports
success optimistically because `client_id` guarantees a resend cannot duplicate
a row. At most 8 items per participant can be queued, so SwiftData (which chat
needs) is overkill here.

## Form

White card on the cream `#FAF7F0` background, matching `NotificationsView`.
Adapted from the Uiverse reference the user supplied, with three changes:

- two face buttons become three (dislike / neutral / like)
- a header showing base name and activity name
- a line reading that the organising team can see who answered

The send button keeps the reference's paper-plane outline icon. Theme colours
come from `Config.swift`: `#DEC684` cream, `#C99A1F` gold, `#2B2B2B` ink,
`#40916C` forest green.

## Files

| File | Change |
|---|---|
| `WBW/Feedback/FeedbackView.swift` | **new** — the form |
| `WBW/Feedback/FeedbackStore.swift` | **new** — submit, outbox, state |
| `WBW/Toast.swift` | **new** — toast shell shared by chat and feedback |
| `WBW/Chat/ChatToast.swift` | reduced to its contents |
| `WBW/AppDelegate.swift` | `PendingPush` carries userInfo; route `checkin_feedback` |
| `WBW/NotificationsView.swift` | `checkin_feedback` cards are tappable, own icon and accent |
| `WBW/MainTabView.swift` | wire the toast and present `FeedbackView` as a sheet |
| `WBW/CheckinProgressStore.swift` | (from spec 1) pending list, new-base diff, 60 s poll |
| `WBW/APIClient.swift` | `submitFeedback` |
| SUS `db/migrations/000012_checkin_feedback.{up,down}.sql` | **new** |
| SUS `wbw_feedback_repository.go` / `_service.go` / `_handler.go` | **new** |
| SUS `wbw_checkpoint_repository.go` | progress query joins feedback |
| SUS `wbw_push_service.go` | `SendUserPush` |
| SUS `wbw_staff_service.go` | create notification + push after a first check-in |
| SUS `cmd/main.go` | three routes |

## Failure handling

| Failure | Behaviour |
|---|---|
| Submit fails (network) | Goes to the outbox silently; the user sees success |
| `409` already answered | Drop from the outbox, show the existing answer read-only. Not an error. |
| `403` never checked in there | Drop from the outbox and say so plainly — it should be unreachable if the UI is correct |
| Push disabled or declined | The notification row still exists; the 60 s poll and the notification list both still work |
| Notification insert fails server-side | Log it; the check-in itself still succeeds |

The bell badge needs no work: these are ordinary `notification` rows, so
`NotiStore.unreadCount` counts them already.

## Testing

**Go unit**

- Progress query joined to feedback: answered, unanswered, and a checkpoint
  deleted after a check-in referenced it
- `POST /wbw/me/feedback` across all five cases in the table above
- `Checkin` creates a notification only when `already_checked_in` is false

**Swift unit (`WBWTests`)**

- `CheckinProgressStore` detects a genuinely new base, and a later poll
  returning the same data raises no second toast
- Outbox: success drops the item, `409`/`403` drop the item, other errors keep it
- Outbox key differs per `Config.backend`
- `PendingPush` carries userInfo while `consume()` still reads-and-clears once

**Not automated:** real push delivery (needs a device and FCM), and how the
form looks.
