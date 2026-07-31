# Group Chat v2 — Join Cut-off, Timestamps, Realtime, Read Receipts, Push

- **Date:** 2026-07-31
- **Status:** Approved (design), pending implementation plan
- **Scope:** group chat only — no other screen or feature is touched
- **Repos:** `wbw-ios-fontend` (iOS) **and** `~/Desktop/WBW/backend` (Node API)

## Context

Group chat works today but is minimal. `ChatStore` (`WBW/ChatStore.swift`) is an
offline-first engine: SwiftData cache + outbox, optimistic send, and a 5–8 s
jittered poll of `GET /groups/:id/messages?after=<id>`. `GroupChatView`
(`WBW/GroupChatView.swift`) renders a flat list of bubbles.

Six gaps, all inside chat:

1. A user who joins a group sees the group's entire prior conversation.
2. Messages show no time, and there is no day boundary marker.
3. Receive latency is 5–8 s (send is already optimistic and instant).
4. No read status beyond a single "sent" check on your own messages.
5. No notification when a member is in the group but not on the chat screen.
6. The list scrolls and animates like a plain `ScrollView`, not like iMessage.

Items 1, 4 and 5 cannot be built client-only — they need server state. The Node
backend at `~/Desktop/WBW/backend` is owned by us and is what the app actually
talks to (`Config.backend = .prodNode`), so it is in scope. The SUS backend
(`/Users/park/Student-Union-Server`) is owned by a teammate and is **not**
touched by this work.

## Goals

1. **Join cut-off** — a member sees only messages sent after they joined.
2. **Time and day separators** on messages.
3. **Sub-second receive latency**, without losing offline-first stability.
4. **Read receipts** — "read by N" under your own latest message.
5. **Push + in-app notification** for members not looking at the chat.
6. **Native iMessage-grade** scrolling, grouping and animation.

## Non-Goals (YAGNI)

- Typing indicators, reactions, reply/quote, image or file messages
- Per-group mute setting, quiet hours
- Message edit or delete, search, pagination into older history
- Direct (1:1) messages
- Mirroring any of this into the Android app (noted as a follow-up risk below)
- Any change to SUS

## Decisions

| Question | Decision |
|---|---|
| Backend scope | Modify the Node backend; leave SUS alone |
| Leave then rejoin the same group | Cut off again — history from the previous membership is gone for good |
| Read receipt display | Count under **the latest message I sent** only |
| Transport | HTTP long-poll (`wait` param), Postgres `LISTEN/NOTIFY` to wake it |
| Push behaviour | One push per message, collapsed per group |
| iMessage feel | Pure SwiftUI (iOS 18 APIs), no UIKit bridge |

---

## 1. Server design (Node)

### 1.1 Schema

New migration `db/migrations/003_chat_v2.sql`. One table carries both the
cut-off point and the read cursor, keyed by (user, group):

```sql
CREATE TABLE group_chat_state (
  user_id      uuid   NOT NULL,
  group_id     int    NOT NULL,
  since_id     bigint NOT NULL DEFAULT 0,  -- visible only where message.id > since_id
  last_read_id bigint NOT NULL DEFAULT 0,
  read_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, group_id)
);
CREATE INDEX ON group_chat_state (group_id);

-- existing members keep their full history
INSERT INTO group_chat_state (user_id, group_id)
SELECT user_id, group_id FROM participant_profile WHERE group_id IS NOT NULL;
```

`since_id = 0` for the backfill is deliberate: the cut-off applies to people who
join **after** this ships, not retroactively to current members.

Note that group membership today is a single `participant_profile.group_id`
column with no join timestamp — this table is the first place a join instant is
recorded.

### 1.2 Existing endpoints to change

**`POST /groups/:groupId/join`** — inside the existing transaction, after the
`UPDATE participant_profile ... SET group_id`:

- delete the caller's `group_chat_state` row for the group they are leaving;
- upsert a row for the new group with
  `since_id = last_read_id = COALESCE((SELECT MAX(id) FROM group_message WHERE group_id = $1), 0)`
  and `read_at = now()`, with
  `ON CONFLICT (user_id, group_id) DO UPDATE` setting the same values.

The `ON CONFLICT` branch is what implements "cut off again on every rejoin".

**`POST /groups/leave`** — delete the caller's `group_chat_state` row, so a
departed member never counts toward a read receipt.

**`POST /groups/:groupId/messages`** — unchanged response, plus two
fire-and-forget side effects after the 201 is sent: `NOTIFY` (§1.4) and
`sendChatPush` (§1.5).

### 1.3 New endpoints

The existing `GET`/`POST /groups/:id/messages` pair keeps its exact request and
response shape. The Android app in the field uses it, so it must not change.
Chat v2 is additive, in a new `api/src/routes/chatRoutes.js` (the chat handlers
currently in `groupRoutes.js` move there too, leaving that file to group
membership).

| Method | Path | Body / query | Response |
|---|---|---|---|
| GET | `/groups/:id/chat/sync` | `after=<id>&wait=<0..25>` | `{since_id, member_count, messages:[Message], cursors:[{user_id,last_read_id}]}` |
| POST | `/groups/:id/chat/read` | `{last_read_id}` | `200 {ok:true}` |

Both require membership (`isMember`, already in `groupRoutes.js`) and return
`403` otherwise.

**`/chat/sync` semantics**

1. Load the caller's `since_id` (0 if no row).
2. Select messages where `group_id = $1 AND id > GREATEST($after, $since_id)`,
   ascending, `LIMIT 50`. `Message` is the shape the existing endpoints already
   return: `{id, group_id, sender_id, client_id, body, device_time, created_at,
   first_name, last_name}`. When a backlog exceeds 50 the response is truncated,
   the client's `after` advances, and because the response was non-empty the
   loop immediately requests the next batch until it drains.
3. If the result is non-empty, or `wait` is 0, respond immediately.
4. Otherwise wait up to `wait` seconds (capped at 25) for a group event
   (§1.4), then re-run the query once and respond. A timeout responds `200`
   with `messages: []` — that is a normal outcome, not an error.
5. `cursors` lists the current members' read cursors excluding the caller,
   joined against `participant_profile` so departed members drop out.
   Group sizes are in the tens, so this is a small payload and the client can
   derive a read count for any message locally.
6. `since_id` is echoed back so the client can purge stale cached messages.

**`/chat/read` semantics** — `UPDATE group_chat_state SET last_read_id =
GREATEST(last_read_id, $1), read_at = now()` for (caller, group), then `NOTIFY`.
Monotonic, so out-of-order or replayed calls cannot move the cursor backwards.

### 1.4 Realtime wake-up

`cluster.js` forks one worker per core, so an in-process `EventEmitter` alone
cannot reach a request parked on another worker. New `api/src/chatEvents.js`:

- one dedicated `pg.Client` per worker running `LISTEN chat_event`
  (a dedicated connection, not one borrowed from the pool);
- publishers call `NOTIFY chat_event, '{"group_id":12,"actor":"<uuid>"}'` on
  message insert and on read-cursor update;
- on notification, the worker re-emits on a local `EventEmitter`;
- `waitForGroup(groupId, ms, exceptActor)` returns a promise that resolves on
  the first matching event or on timeout. Events whose `actor` is the waiting
  user are ignored, so a client's own `read` call does not wake its own poll.

If the `LISTEN` connection drops, reconnect with backoff; while it is down,
`waitForGroup` degrades to a plain timeout, which turns long-poll into a 25 s
poll rather than an outage.

### 1.5 Push

New `sendChatPush(message)` in `api/src/push.js`, reusing the existing
firebase-admin init and `device_token` table:

- **recipients** — group members, minus the sender, minus anyone whose
  `read_at` is within the last 25 seconds. That last filter reuses read-cursor
  data as a cheap presence signal: someone who marked messages read moments ago
  is looking at the chat and should not be buzzed. It only works because the
  client posts `/chat/read` as a 10-second heartbeat while the chat screen is
  visible (§2.4) — without that, a member reading a quiet chat would look idle
  and get pushed.
- **payload** — title `<sender first name>`, body = message text (truncated to
  120 chars), `data: {type: "chat", group_id}`.
- **collapse** — `apns-collapse-id: chat-<group_id>` and APNs `thread-id`, so a
  burst replaces itself on the lock screen instead of stacking.
- **badge** — per-user unread count (`COUNT(*) WHERE id > last_read_id`), which
  means one message object per recipient: use `sendEach`, not
  `sendEachForMulticast`.
- **failure** — logged only. Push never affects the `201` returned to the
  sender.

---

## 2. iOS design — data layer

### 2.1 Lifting the store out of the view

`GroupChatView` currently constructs `ChatStore` as a `@StateObject`, so closing
the chat destroys the engine and the app stops knowing about new messages.
`MainTabView` takes ownership instead and injects it:

```swift
@StateObject private var chat = ChatSession()   // lives as long as the app
```

`ChatSession` is `ChatStore` moved to `WBW/Chat/ChatSession.swift`, extended
with a settable group (switching groups resets cursor and cache) and the sync
loop below. It runs whenever the app is in the foreground and the user is in a
group, whether or not the chat screen is open. That gives the tab badge for
free and means opening the chat shows current messages immediately.

### 2.2 Sync loop

Replaces `startPoll`/`pollOnce`:

```swift
private func syncLoop() async {
    var backoff: UInt64 = 1
    while !Task.isCancelled {
        guard connectivity.online else { try? await sleep(seconds: 2); continue }
        do {
            let r = try await APIClient.shared.chatSync(groupId: gid, after: cursor, wait: 25)
            apply(r)                       // purge → merge → cursors → member count
            if hasPending { await flushOutbox() }
            backoff = 1                    // success: loop again immediately
        } catch {
            try? await sleep(seconds: backoff)
            backoff = min(backoff * 2, 10)
        }
    }
}
```

- The request sets `URLRequest.timeoutInterval = 35`, safely above `wait = 25`.
- An empty `messages` array is a normal timeout — loop again with no delay.
- Offline is handled by `Connectivity` exactly as today: the existing
  `onReconnect` hook flushes the outbox and restarts the loop.
- Backoff 1→2→4→8→10 s prevents a hammering stampede if the API is down.
- Sending stays a direct `POST` with optimistic insert. Send latency is already
  effectively zero; long-poll fixes the receive side.

### 2.3 Cache hygiene for the cut-off

Every sync response carries `since_id`. The client self-heals:

```swift
if r.sinceId > 0 {
    deleteLocal { $0.serverId != nil && $0.serverId! <= r.sinceId }
}
```

Cached messages from a previous membership disappear on the first sync after a
rejoin, without depending on any client-side event firing at the right moment.
Join and leave additionally purge the group's cache immediately so the user
never sees a stale frame.

### 2.4 Read cursor

- `myLastReadId` persists in `UserDefaults` under `chat.read.<groupId>`, and is
  reconciled with the server value on each sync.
- `POST /chat/read` fires when the chat screen opens, when a new message
  arrives while the screen is open and scrolled to the bottom, and when the app
  returns to the foreground with the screen open.
- It also fires as a **10-second heartbeat while the chat screen is visible**,
  even when the cursor has not moved. The server reads `read_at` as a presence
  signal when deciding whom to push (§1.5); without the heartbeat, a member
  reading a quiet chat would go stale after 25 seconds and start getting
  notifications for a conversation they are watching. The heartbeat stops the
  moment the screen closes or the app backgrounds.
- Cursor-advancing calls are debounced 500 ms and skipped when the cursor would
  not move; the heartbeat is exempt from that skip.
- Failures are silent and retried by the next trigger.

### 2.5 Derived values

| Value | Derivation |
|---|---|
| `unreadCount` | `messages.count { ($0.serverId ?? 0) > myLastReadId && !isMine($0) }` |
| `readCount(msg)` | `cursors.count { $0.lastReadId >= (msg.serverId ?? .max) }` (cursors already exclude me) |
| `memberCount` | from the sync response — no separate `/members` call for the header |

### 2.6 Lifecycle

Driven by `scenePhase`: `.active` starts the loop, `.background` cancels it
(iOS suspends sockets anyway and push takes over), returning to `.active`
restarts it with one immediate `wait=0` sync.

`ChatMessage` (SwiftData) needs **no schema change** — read counts are derived
from cursors, never stored per message. No migration on the client.

---

## 3. iOS design — UI

### 3.1 Rows as data

Day separators and message grouping are computed by a pure function in
`WBW/Chat/ChatRow.swift`, so they are unit-testable without a view or network:

```swift
enum ChatRow: Identifiable {
    case day(Date)
    case unreadMark
    case message(ChatMessage, Layout)   // isFirstInGroup, isLastInGroup, showTime
}

func buildRows(_ msgs: [ChatMessage], myLastReadId: Int64, now: Date) -> [ChatRow]
```

### 3.2 Day separators

A `.day` row is inserted whenever `Calendar.isDate(_:inSameDayAs:)` differs
between consecutive messages. Rendered as a small grey pill, 11 pt, centred.
Labels use `Locale(identifier: "th_TH")`, which yields Buddhist-era years:

- same day → `วันนี้`
- previous day → `เมื่อวาน`
- same year → `31 ก.ค.`
- earlier year → `31 ก.ค. 2568`

### 3.3 Time

`HH:mm`, 10 pt, secondary colour, under the **last bubble of each consecutive
group**. Dragging the list left (up to 56 pt, springing back on release)
reveals a trailing time column showing the time of every message — the iMessage
gesture.

### 3.4 Message grouping and bubble shape

Messages from the same sender less than 5 minutes apart form one group:

- avatar and sender name render only on the first bubble of the group;
- spacing is 2 pt within a group, 10 pt between groups;
- the bubble **tail** renders only on the last bubble of a group; other bubbles
  are plain rounded rectangles. The tail is a custom SwiftUI `Shape` drawing
  the path directly.

### 3.5 Read status

One 10 pt trailing line under the latest message I sent:

| State | Text |
|---|---|
| `.pending` | clock icon (unchanged) |
| `.failed` | red icon, tap to retry (unchanged) |
| `.sent`, 0 readers | `ส่งแล้ว` |
| `.sent`, N readers | `อ่านแล้ว N` |
| `.sent`, `N == member_count - 1` | `อ่านแล้ว N · ทั้งกลุ่ม` |

Changes animate with `.easeOut(duration: 0.2)`.

### 3.6 Scrolling

```swift
ScrollView { LazyVStack(spacing: 0) { ForEach(rows) { RowView($0) } } }
    .defaultScrollAnchor(.bottom)
    .scrollDismissesKeyboard(.interactively)
    .onScrollGeometryChange(for: Bool.self) { g in
        g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 40
    } action: { _, atBottom in self.atBottom = atBottom }
```

- Opening the chat lands at the bottom without a manual `scrollTo`.
- Dragging down dismisses the keyboard, tracking the finger.
- New message while at the bottom → scroll along with
  `.spring(response: 0.35, dampingFraction: 0.82)`.
- New message while scrolled up → **do not** yank the view (today's behaviour);
  show a floating `↓ ข้อความใหม่ N` pill that scrolls down on tap.
- Bubbles enter with `.move(edge: .bottom) + .opacity + .scale(0.92)`.
- `.sensoryFeedback(.impact(weight: .light))` on send, `.error` on send failure.
- A faint `ข้อความใหม่` divider marks where reading stopped; it clears when the
  screen closes.

### 3.7 Badge and in-app notification

- Tab 3 carries a native badge: `Tab { ... }.badge(chat.unreadCount)`.
- Foreground with the chat screen closed → a custom top toast (avatar, sender,
  text) that opens the chat on tap. `AppDelegate.userNotificationCenter(_:willPresent:)`
  returns `[]` for `type == "chat"` so the system banner does not double up.
  Non-chat notifications keep today's banner behaviour.
- Tapping a chat push from outside the app posts a new `.openGroupChat`
  notification; `MainTabView` selects tab 3 and opens the chat overlay. The
  existing `.openNotificationsTab` path is unchanged.

---

## 4. Files

| Node — `~/Desktop/WBW/backend` | Change |
|---|---|
| `db/migrations/003_chat_v2.sql` | new — table + backfill |
| `api/src/chatEvents.js` | new — `LISTEN/NOTIFY` bridge, `waitForGroup` |
| `api/src/routes/chatRoutes.js` | new — `/chat/sync`, `/chat/read`; existing chat handlers move here |
| `api/src/routes/groupRoutes.js` | edit — join/leave manage `group_chat_state`; `NOTIFY` + push on insert |
| `api/src/push.js` | edit — add `sendChatPush` |

| iOS — `wbw-ios-fontend` | Change |
|---|---|
| `WBW/Chat/ChatSession.swift` | new (from `ChatStore.swift`) — sync loop, cursors, purge, unread |
| `WBW/Chat/ChatRow.swift` | new — `buildRows`, pure |
| `WBW/Chat/ChatBubble.swift` | new — bubble, tail shape, day pill, read status |
| `WBW/Chat/ChatToast.swift` | new — in-app banner |
| `WBW/Chat/ChatDTOs.swift` | new — `ChatSyncResponse`, `ReadCursor` |
| `WBW/APIClient+Chat.swift` | new — `chatSync`, `chatRead` (keeps `APIClient.swift` from growing past its current 267 lines) |
| `WBW/GroupChatView.swift` | edit — screen scaffold and scrolling only |
| `WBW/MainTabView.swift` | edit — owns `ChatSession`, badge, toast, push routing |
| `WBW/AppDelegate.swift` | edit — route `type == "chat"` separately |
| `WBW/ChatStore.swift` | deleted (replaced by `ChatSession.swift`) |

---

## 5. Error handling

| Case | Behaviour |
|---|---|
| Long-poll timeout (`200`, empty) | Normal — loop again immediately, no UI change |
| Network drop mid-wait | Backoff 1→10 s, existing offline banner, outbox preserved |
| `403` (removed from group) | Close chat, purge that group's cache, reload profile |
| `401` | Existing `.wbwUnauthorized` auto-logout |
| Send `4xx` | Mark `.failed`, tap to retry (unchanged) |
| `POST /chat/read` failure | Silent, retried on the next trigger |
| Push send failure | Logged server-side only; never affects the sender's `201` |
| `LISTEN` connection lost | Reconnect with backoff; long-poll degrades to a 25 s poll |

## 6. Testing

**iOS unit — `WBWTests/ChatRowTests.swift`**

- day separator inserted across a midnight boundary; year shown only across years
- 5-minute grouping: first/last flags, avatar and name suppression
- unread divider position, and its absence when everything is read
- `readCount` excludes the sender; `unreadCount` excludes my own messages
- purge predicate removes exactly the messages at or below `since_id`

**Node — `api/scripts/chat-smoke.mjs`**

Log in as two users, then assert: A sends 3 messages → B joins → B's sync
returns **0** messages → A sends 1 → B sees exactly that one → B posts `read` →
A's sync reports `อ่านแล้ว 1` → a long-poll parked before A's send returns in
under 1 second.

**Manual — two devices or simulators**

Push arrives when backgrounded; no push while the chat screen is open; left
drag reveals times; scrolling up while messages arrive does not yank the view;
tab badge clears on open.

## 7. Phasing

Each phase leaves the app shippable.

1. Node: migration, `/chat/sync` with `wait=0`, join/leave cut-off.
2. Node: `chatEvents.js` and real long-poll.
3. iOS: `ChatSession` sync loop, cache purge, time and day separators — the
   first visible win.
4. iOS + Node: read cursor and `อ่านแล้ว N`.
5. Node + iOS: chat push, tab badge, in-app toast.
6. iOS: bubble tails, left-drag timestamps, new-message pill, haptics.

## 8. Risks

1. **Reverse proxy buffering or timeouts.** A parked 25 s request needs
   `proxy_buffering off` and a proxy read timeout above 30 s (nginx and
   Cloudflare default to 60 s, which is fine). Verify before deploying phase 2.
2. **Socket count.** Roughly one parked connection per active user. Node
   handles this asynchronously, but raise `ulimit -n` (65535) on the API host.
3. **Postgres connections.** One dedicated `LISTEN` connection per worker
   (`availableParallelism()`, e.g. 8) on top of the pool — check
   `max_connections`.
4. **Android read cursors stay at 0.** The Android app keeps using the old
   endpoints, so it never posts `/chat/read` and its users never count as
   readers. "อ่านแล้ว N" will under-report while Android users are in a group.
   Accepted for this iOS-first round; mirroring into Android is a follow-up.
5. **Push volume in a chatty group.** Collapse plus the 10-second active-reader
   filter should hold. If it does not, add a guard that skips push for a group
   exceeding roughly 20 messages per minute.
