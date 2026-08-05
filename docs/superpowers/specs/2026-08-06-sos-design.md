# Emergency SOS — One Button, Nearest Base, Group Backup

- **Date:** 2026-08-06
- **Status:** Approved (design), pending implementation plan
- **Scope:** a participant in trouble raises an alarm that reaches the staff at
  the nearest base and the central team with their identity and position, and
  reaches their own group of up to 50 people at the same time.
- **Repos:** `wbw-ios-fontend` (iOS) **and** `~/Student-Union-Server` (SUS, Go)
- **Not in scope:** `~/su-wbw-website`. The endpoints below are shaped so a web
  panel can be added later without touching the server.

## Context

`sos_event` has existed since the very first WBW migration
(`db/migrations/000005_wbw.up.sql:148`) with `client_id`, `participant_id`,
`device_time`, `lat`, `lng`, `message`, and `resolved` / `resolved_by` /
`resolved_at`. **No Go code has ever written to it.** Two places read it: the
admin dashboard counts open events (`internal/repository/wbw_admin_repository.go:78`)
and account deletion cleans it up (`:285`, `:287`). There is no endpoint, no
screen, and no push.

Most of what an SOS feature needs is already built and running on production:

- **All 12 checkpoints carry coordinates** (`db/migrations/000006_wbw_seed.up.sql:39-53`),
  spread over roughly 1.5 km × 1 km with 300–500 m between bases. "Nearest
  base" is a meaningful distinction on this course, not a rounding error.
- **Staff are already scoped to bases.** `checkpoint_staff` maps a staff user
  to the bases they work; `WBWStaffRepository.Checkpoints`
  (`internal/repository/wbw_staff_repository.go:26-58`) gives `admin` every
  base and everyone else only their assigned ones.
- **Roles that matter already exist.** `staff_role`
  (`db/migrations/000013_wbw_staff.up.sql`) includes `medical`, `security`, and
  `checkpoint`.
- **Push works on production** — FCM HTTP v1 → APNs, proven end to end on a
  real iPhone on 2026-08-04. `SendChatPush` and `SendUserPush` exist
  (`internal/service/wbw_push_service.go:141`, `:240`), and `ChatPushTargets`
  already resolves every device in a group except the sender
  (`internal/repository/wbw_staff_repository.go:164`).
- **Near-real-time delivery already has a proven shape in this codebase.**
  `internal/service/wbw_chat_events.go` uses one Postgres `LISTEN`/`NOTIFY`
  channel to wake 25-second long-polls, and `WBW/Chat/ChatSession.swift` is the
  iOS half: cache, outbox, optimistic send, flush on reconnect.
- **Queue-and-retry on bad signal has a precedent** — `WBW/Feedback/FeedbackOutbox.swift`
  persists answers in `UserDefaults`, namespaced per backend via
  `BackendCacheKey`, because signal in the hills is unreliable.
- **Personal data for a rescue is already collected.** `participant_profile`
  (`db/migrations/000005_wbw.up.sql:60-78`) holds `contact_phone`,
  `emergency_contact_name` / `emergency_contact_phone`, `bib_number`, and
  `group_id`. `health_details` (`:97`) holds blood type, allergies, chronic
  disease, medication, and physical limitations, gated by
  `consent.consent_health_data` (`:117`).

Three things are genuinely missing:

1. **The iOS app does not import CoreLocation anywhere.** The
   `NSLocationWhenInUseUsageDescription` key was deliberately deleted, and
   `WBW/Info.plist:4-12` carries a comment explaining why: shipping a
   permission string for a feature the app does not use is a direct App Review
   rejection. Adding location back is a considered reversal, not an oversight.
2. There is no way for a participant to signal anything to staff. The only
   participant → staff channel is being scanned.
3. Staff have exactly one screen. `WBW/RootView.swift:64` sends any
   `staff`/`admin` login straight into `StaffScanView`.

## Goal

1. A participant can raise an alarm in about three seconds, one-handed, from
   any screen in the app.
2. Staff at the base nearest the participant learn who pressed and where they
   are, precisely enough to walk to them.
3. The central team (admin, medical, security) always learns, regardless of
   which base is nearest.
4. The participant's own group is told at the same time, because the people
   standing 20 m away arrive before anyone else can.
5. Pressing for someone else works and is distinguishable from pressing for
   yourself.
6. Casual or accidental presses are cheap to prevent and cheap to undo, without
   slowing down a real one.
7. Every step degrades honestly when the network is bad, and the person who
   pressed can always tell which step they are stuck on.

## Non-Goals (YAGNI)

- No naming *which* friend is hurt when pressing on someone else's behalf.
- No peer-to-peer relay (MultipeerConnectivity / BLE mesh) for participants
  with no cell signal at all.
- No live position tracking. `track_point` stays unused; an SOS captures
  position at the moment it is raised and when a better fix arrives, nothing
  more.
- No automatic escalation timers on the server.
- No automatic case closing.
- No web panel in `su-wbw-website` in this spec.
- No Apple Critical Alerts entitlement.
- No chat thread attached to a case — the group chat already exists.

## Decisions taken

| Question | Decision |
|---|---|
| Who is alerted | Staff of the nearest base **plus** the central team (`admin` + `staff_role` in `medical`, `security`) always |
| No usable position | Fall back to the last base the participant checked into; failing that, alert everyone |
| Where staff see it | iOS first; `su-wbw-website` later on the same endpoints |
| Bad network | Local queue + retry, three-layer status, phone-call fallback surfaced after 20 s |
| Pressing for a friend | A flag, not a name. `for_other = true`, reporter identified, no victim identity |
| The group of 50 | Told immediately, with the position |
| Gesture | Hold 3 s with a countdown ring; 15 s undo window after sending |
| Closing a case | Two steps — "on my way" (ack), then close with a reason |

## Architecture and data flow

The rule that shapes everything: **do not wait for GPS.** A first fix under
tree cover can take 10–30 seconds, and that is the most expensive time in the
whole incident. The press and the fix are two independent tracks.

```
hold completes (3 s)
  ├─ create case locally: client_id = UUID, device_time, for_other
  ├─ POST /wbw/me/sos immediately with whatever position is already known
  │     (possibly none)
  └─ in parallel: one-shot GPS, 8 s timeout
        └─ on fix: POST again with the same client_id → updates the same row

server (idempotent on client_id — a repeat is an UPDATE, never a second INSERT)
  ├─ lat/lng present  → nearest checkpoint, loc_source = 'gps'
  ├─ absent           → last checked-in base from check_in, loc_source = 'last_checkin'
  ├─ neither          → checkpoint_id NULL, loc_source = 'none'
  ├─ NOTIFY wbw_sos   → wakes every staff long-poll currently parked
  └─ push, three audiences at once:
        · staff of the resolved base
        · central team, always
        · the presser's group, minus the presser

staff taps "on my way"  → acked_at / acked_by → NOTIFY → the presser sees it in ~1 s
staff taps "close"      → resolved + reason   → NOTIFY → second push to the group
```

**A better fix can move the case to a different base.** When it does, push the
new base as well and **do not retract the old one**. The first base may already
be walking; telling people to stop is more dangerous than two teams arriving.

**Only the raise and the close ever reach the group.** Bumps, position updates,
and base changes re-push staff audiences only. The group of fifty gets exactly
two notifications per case, no matter what happens in between.

**Three status layers, because three different things fail.** `not sent yet`
means the case is still in the on-device outbox. `received` means the server
answered 2xx — the only proof the network works. `on the way` means a staff
member acked — the only proof a human saw it. Collapsing these into one
spinner is what makes people give up on a working system. A fourth display
state, `closed`, ends the sequence and carries the reason back to the presser.

**Its own NOTIFY channel.** `wbw_sos`, not the existing `wbw_chat`. SOS has far
fewer listeners than chat and must never be crowded out by message traffic.

**Its own outbox, not SwiftData.** A participant has at most one open case, so
the chat's SwiftData store is overkill. Follow `FeedbackOutbox`: `UserDefaults`,
namespaced per backend through `BackendCacheKey`.

## Data model

Migration `000015_wbw_sos` extends the existing table. Nothing is dropped.

```sql
ALTER TABLE sos_event
  ADD COLUMN IF NOT EXISTS for_other      BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS group_id       INT  REFERENCES participant_group(group_id),
  ADD COLUMN IF NOT EXISTS checkpoint_id  INT  REFERENCES checkpoint(checkpoint_id),
  ADD COLUMN IF NOT EXISTS accuracy_m     DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS loc_source     TEXT,          -- gps | last_checkin | none
  ADD COLUMN IF NOT EXISTS acked_at       TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS acked_by       UUID REFERENCES app_user(user_id),
  ADD COLUMN IF NOT EXISTS resolve_reason TEXT,          -- helped | false_alarm | unreachable | canceled_by_user
  ADD COLUMN IF NOT EXISTS last_push_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS updated_at     TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS sos_one_open_per_user
  ON sos_event (participant_id) WHERE NOT resolved;

CREATE INDEX IF NOT EXISTS sos_feed_idx ON sos_event (updated_at DESC);
```

`resolved` stays the terminal flag it always was. A self-cancel sets
`resolved = TRUE, resolve_reason = 'canceled_by_user'`, which keeps the
existing `OpenSOS` count (`wbw_admin_repository.go:78`, `WHERE resolved = FALSE`)
correct without editing that query.

`group_id` is a snapshot taken when the case is raised, so re-grouping later
never rewrites who was told.

**The partial unique index is the anti-abuse mechanism, not a validation
detail.** One person can hold one open case. A second press while a case is
open is a **bump**: it refreshes the position on the existing row and returns
that row's id. A bump may re-push only if `last_push_at` is at least 60 s old.
Pressing ten times in a row produces one case and one push. The bump is also
genuinely useful — it is how someone says "still here, nobody has come".

## API

### Participant

| Method | Path | Response |
|---|---|---|
| POST | `/wbw/me/sos` | `201` new case · `200` when `client_id` repeats (position update, no push) or an open case exists (bump) |
| POST | `/wbw/me/sos/{id}/cancel` | `200` · `409` once a staff member has acked |
| GET | `/wbw/me/sos/active?wait=25` | The caller's open case, or one closed in the last 5 minutes so the presser sees the ending; long-poll |
| GET | `/wbw/me/sos/{id}` | One case, readable by the presser and by members of that case's `group_id`; `404` to anyone else |

`POST /wbw/me/sos` body: `client_id` (UUID), `device_time`, `for_other` (bool),
optional `lat`, `lng`, `accuracy_m`, `message`.

`message` is never collected before sending — the hold gesture sends with no
text at all. It is the **note the presser can add from the status view while
waiting**, posted through this same endpoint with the same `client_id`. That is
the only writer of `sos_event.message`.

On a bump or repeat, `for_other` is OR-ed rather than overwritten: once any
press on the case says someone else is hurt, the case keeps saying so.

Inserting takes the open case with `SELECT … FOR UPDATE` inside the same
transaction rather than racing `sos_one_open_per_user` and handling the
conflict afterwards.

Nearest base is haversine over the 12 seeded checkpoint coordinates. There are
twelve rows; there is no reason for PostGIS.

The response carries the case (`id`, status, `checkpoint` id and name,
`loc_source`, timestamps) **and `emergency_phone`**. `GET /wbw/me/progress`
returns `emergency_phone` too — it is polled every 60 s while the app is open,
so the cached number is fresh *before* the first emergency rather than only
after one.

**The server-side cancel window is 120 s, not 15.** The UI counts down 15 s,
but a case that sat in the outbox for 40 s before going out would otherwise
answer a perfectly reasonable cancel tap with `409`, and the person pressing
would conclude the system is broken at the worst possible moment. The rule is:
cancel is allowed while `acked_at IS NULL` and `server_received_at` is within
120 s.

### Staff

| Method | Path | |
|---|---|---|
| GET | `/wbw/staff/sos?wait=25&since=<updated_at>\|<id>` | Every open case, plus cases closed within the last 30 minutes so a base can see what just happened; long-poll |
| POST | `/wbw/staff/sos/{id}/ack` | "On my way". A second staff member gets `200` and sees who was first — not an error |
| POST | `/wbw/staff/sos/{id}/resolve` | `{reason}` from the four-value list; anything else is `400` |

The `since` cursor is the pair `updated_at|id`, not a bare timestamp. `updated_at` is not
unique, and a strict `>` on it drops any case that shares an instant with the cursor — from
that client's every later poll, permanently, because nothing paginates it back. The pair is
compared with Postgres row-value ordering. A `since` with no `|` is read as that timestamp
with id `0`, so an older client keeps working.

### Who sees which case

- `admin`, and staff whose `staff_role` is `medical` or `security`: every case.
- Any other staff: cases whose `checkpoint_id` matches one of their rows in
  `checkpoint_staff`.
- **If no one is assigned to that base at all, the case is visible to every
  staff member.** "Nobody assigned means everybody sees it" is the safe
  direction to fail, and it is the net under an empty `checkpoint_staff` on
  production.
- A case with `checkpoint_id IS NULL` (no position at all) is visible to
  everyone by the same rule.
- A case whose `accuracy_m` exceeds 200 m does not trust its base assignment:
  it is pushed and shown to everyone, and the card states the accuracy.

### The staff case card

Assembled from data that already exists: full name, bib, and group number from
`participant_profile`; `contact_phone` and `emergency_contact_phone` as tappable
call buttons; the `for_other` flag rendered as "someone else is hurt — history
unknown"; position with accuracy, `loc_source`, and timestamp; the resolved
base; current status and who acked.

**Health data keeps the gate the schema already gives it.** `health_details` is
included only when all three hold: `consent.consent_health_data = TRUE`, the
case is open, and `for_other = false`. It is not a lookup staff can perform on
anyone at any time. `docs/privacy-policy-draft.md` (committed 2026-08-05 in
`9d99773`) must be updated to cover both this and location collection before
the App Store submission.

## iOS — the participant

**The button lives on every tab.** `MainTabView.swift:25-35` already has five
tabs; a sixth would mean switching tabs before pressing, which is slow and
unfindable under stress. It is a 64 pt red floating button above the tab bar,
overlaid on the `TabView`, reachable without changing screens.

**The gesture.** Press and hold; a ring sweeps for 3 s with haptics increasing
in frequency, then one heavy tap at completion. Releasing early retracts the
ring and sends nothing. No confirmation dialog.

**Completing the hold opens a full-screen status view immediately** — not a
toast. The person who pressed needs to see what is happening, and the cancel
and call buttons have to be in front of them.

```
WBW/SOS/
  SOSButton.swift      floating button, 3 s ring, haptics
  SOSLocator.swift     CoreLocation one-shot
  SOSOutbox.swift      UserDefaults queue, namespaced by BackendCacheKey
  SOSStore.swift       @Observable: send, retry, status long-poll, cancel
  SOSStatusView.swift  three-layer status, cancel, call fallback
  SOSFriendView.swift  what a group member sees
  SOSModels.swift
WBW/APIClient+SOS.swift
```

**Location.** `desiredAccuracy = kCLLocationAccuracyNearestTenMeters`, not
`Best` — under canopy, `Best` spends much longer chasing precision that does
not change which base is nearest or how easily a team finds someone. A cached
fix younger than 60 s is used instantly; a fresh one-shot runs in parallel with
an 8 s timeout and triggers the update POST when it lands.

**Ask for location permission right after a successful login, not at the
moment of pressing.** A permission dialog in the middle of an emergency is both
the slowest and the most likely to be denied. This shares a screen with moving
the push-notification prompt to the same point, which is already the approved
plan in the paused push brainstorm. If permission is denied, SOS still sends,
and the status view says so plainly — "location not allowed; staff will only
see the last base you checked into" — with a button into Settings.

**Retry.** Immediately, then at 2, 5, 10, 20, 30, 60 s, then every 60 s until
it succeeds or the case closes. Extra flushes when the app returns to
foreground and when `Connectivity` flips to online.

**No error class may silently drop an SOS.** `FeedbackStore.flush` once deleted
a user's answer on any error that was not `offline` — fixed in `12e7cbc` — and
SOS must be stricter than that fix. A `401` keeps the case queued and asks for
re-login; `403`, `408`, `409`, and every `5xx` keep it queued; anything that is
not `2xx` keeps it queued and raises the call button. There is no code path
that discards a case without the user cancelling it.

**The call fallback** appears once the status has been `not sent yet` for 20 s,
and is reachable from the status view at any time. The number has a default in
`Config.swift`, is overridden by `emergency_phone` from the server, and is
cached in `UserDefaults` so it survives having no network.

**Plists.** `NSLocationWhenInUseUsageDescription` returns to both `Info.plist`
and `Info-Debug.plist`; the warning comment at `WBW/Info.plist:4-12` must be
rewritten to say the key is now backed by a real feature.
`InfoPlistParityTests` must pass. `PrivacyInfo.xcprivacy` gains Precise
Location — linked to the user, not used for tracking, purpose App Functionality.

## iOS — the group member

The group push goes out with the staff push, not after it. Wording follows
`for_other`: "*<name>* needs help · near *<base>*" versus "*<name>* reports
someone is hurt · near *<base>*".

A `notification` row is written with `type = 'sos'`, `audience = 'group'`,
`audience_id` = the group, and `ref_id` = the `sos_event` id. That makes it
appear in the existing notification list with no new plumbing — the same
`ref_id` route `checkin_feedback` already uses.

Tapping opens `SOSFriendView`: name, time, nearest base, position, an **Open in
Apple Maps** button (this app has no offline map; Apple Maps does), a shortcut
into the group chat, and the line that matters most on the screen — *"Do not
move the casualty. If you are close, send one or two people; everyone else stay
put."* That sentence is what stops fifty people converging at once; withholding
the position is not. The view reads the same `sos_event` through
`/wbw/me/sos/{id}` scoped to the caller's group, so a group member sees status
changes without being able to enumerate other groups' cases.

A second push when the case closes: "staff have taken care of it" or
"cancelled". The group is not told the reason — `false_alarm` is between the
presser and staff — but it must be told the case ended, or fifty people stay
worried all day. **Two pushes per case, maximum.**

The presser's phone number is not exposed to the group. `contact_phone` has
never been visible to peers in this app and this feature does not change that;
the group chat is the channel.

## iOS — staff

`RootView.swift:64` becomes a two-tab `TabView` for staff — Scan and SOS, with
a badge counting open cases. The `AVCaptureSession` must stop when the SOS tab
is active; `RootView.swift:92-98` already establishes the suppression pattern
for exactly this kind of takeover.

**A new case presents as a full-screen cover over the scanner, not a badge.**
Staff are looking down at a QR code; a number in the corner will not be seen.
Two buttons: "On my way" and "Later".

**Do not use Critical Alerts.** `com.apple.developer.usernotifications.critical-alerts`
requires a separate application to Apple with an approval wait that will not
land before the event. `interruption-level: time-sensitive` breaks through
Focus without any entitlement, layered on the `apns-priority: 10` already in
use.

The SOS tab lists cases newest first with the card described above, plus the
call buttons, Open in Apple Maps, "On my way", and "Close" with the reason
picker. The list holds a 25 s long-poll while it is on screen and relies on
push while it is not.

**Staff can press SOS too.** The same floating button is mounted in the staff
UI — a staff member can fall down a slope like anyone else, and it costs one
line to reuse the component. `group_id` will be NULL because staff have no
`participant_profile` row (`db/migrations/000013_wbw_staff.up.sql:9`), so no
group is told, but the central team is.

## Error handling and edge cases

| Situation | Behaviour |
|---|---|
| No network at all | Stays queued, retries, call button surfaces after 20 s |
| No GPS and never checked in | `loc_source = 'none'`, `checkpoint_id` NULL, alerts the central team and all staff; still a real case |
| Accuracy worse than 200 m | Base assignment not trusted; alerts everyone; card prints `±<accuracy> m` |
| More than 2 km from the nearest base | Card is flagged "outside the event area"; **not blocked** — someone off-course is the person most likely to need help |
| Cancel after a staff ack | `409`; the view says "staff have already accepted — call them instead" and offers the call button |
| Two staff both ack | First wins, second gets `200` and sees the first name |
| App killed with the queue non-empty | `beginBackgroundTask` continues retrying ~30 s; flush on next launch; if the app is never reopened it never sends — which is exactly why the call button exists |
| Logout with an open case | Warn and require confirmation, then clear the outbox. Leaving it means the previous account's case is sent under the next account's token |
| Device clock wrong | Order by `server_received_at` always; `device_time` is recorded but never used for ordering |
| Case still open overnight | No auto-close. Closing a case by timer is a claim that someone attended, which may be false |
| Push never arrives (no device token) | The staff long-poll is the net. The `-uitestToken` incident in `checkin-feedback` is why this is not assumed away |

## Testing

**Go**

- Nearest-base selection against the real coordinates of all 12 checkpoints,
  including ties and points outside the course.
- `client_id` idempotency, bump behaviour, and the 60 s re-push rate limit.
- Visibility for every role: base staff at the right base, base staff at the
  wrong base, `medical`, `security`, `admin`, and the empty-`checkpoint_staff`
  fallback.
- Cancel before ack, cancel after ack (`409`), cancel after 120 s.
- Unknown resolve reason (`400`).
- Repository tests behind `WBW_DB_TESTS=1`, matching the feedback repository.

**iOS**

- `SOSOutbox` persists, restores, and retries across a cold launch.
- **Every HTTP status code is exercised to confirm none of them discards a
  case.** This is the regression test for the `FeedbackStore.flush` class of
  bug.
- `SOSLocator`: timeout with no fix, permission denied, cached-fix path.
- Releasing the button before 3 s sends nothing.
- Cancel inside 15 s; cancel rejected after ack.

**On real hardware, before it is called done**

Two iPhones — one presses, the other is signed in as staff and must receive the
push and see the case. Use the Release + `release-testing` export technique
from `checkin-feedback` rather than waiting on TestFlight.

## Operational prerequisites

These are not code, and without them the feature is theatre:

1. **`checkpoint_staff` must be populated on production.** Without it every
   case falls through to the everyone-sees-it net, and the whole event is loud.
2. **One real central phone number.** The entire fallback path hangs on it.
3. `staff_role` must be set to `medical` / `security` on the nurse and security
   accounts, or they are not part of the central team.
4. **App Store:** a new build, the location privacy answers, and the updated
   privacy policy. The event is roughly one to two weeks out; if review does
   not land in time, the fallback is a TestFlight build or a directly
   distributed `release-testing` build.
5. One full rehearsal before the event.

## Shipping order

Four independently shippable pieces:

1. **SUS** — migration, endpoints, push fan-out, `wbw_sos` NOTIFY. Must reach
   production first.
2. **iOS participant** — button, status view, location, outbox.
3. **iOS staff** — tab, case list, ack and close.
4. **iOS group member** — notification card and `SOSFriendView`.

Pieces 2–4 are parallel once 1 is live, and the app renders a readable error if
an older server answers any SOS endpoint with `404`.
