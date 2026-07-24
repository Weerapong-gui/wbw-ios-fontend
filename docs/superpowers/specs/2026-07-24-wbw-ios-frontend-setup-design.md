# WBW iOS Frontend — Setup & Backend Contract

- **Date:** 2026-07-24
- **Status:** Approved (design), pending implementation plan
- **Repo:** `/Users/park/wbw-ios-fontend`

## Context

`wbw-ios-fontend` is the iOS frontend for the WBW ("เดินรอบดอย") project. The
existing native iOS app lives at `/Users/park/Desktop/WBW/ios_native` and was
built against the WBW **Node.js** backend (`/Users/park/Desktop/WBW/backend`,
deployed at `https://wbw.sumfu.store`).

The team is migrating the backend to **Student-Union-Server (SUS)**
(`/Users/park/Student-Union-Server`, Go + Chi + PostgreSQL), which already
serves a WBW web frontend (`web-next`) under a `/wbw/*` route prefix. A
teammate owns SUS; **this project must not modify SUS**. Instead we produce a
written API contract telling that teammate which endpoints SUS must add.

## Goals

Two deliverables:

1. **iOS repo** — clone `ios_native` into `wbw-ios-fontend`, adapt it so its
   backend base URL can switch between the current Node backend and SUS.
2. **Backend contract doc** (`docs/backend-contract.md`, **English**) — the
   list of endpoints, request/response shapes, and DB tables SUS must provide
   for the iOS app to run against it. This is the artifact handed to the
   teammate who owns SUS.

## Non-Goals (YAGNI)

- No changes to `/Users/park/Student-Union-Server` (teammate's repo).
- No rewrite of the SwiftUI views or the networking layer architecture.
- No `steps` / `sync` / `ranking` endpoints — the iOS `APIClient` never calls
  them.
- No new product features. Port for parity only.
- No automated UI test harness. Manual simulator testing per endpoint.

## Key Insight

The iOS app was written against Node routes like `/auth/login`,
`/groups/{id}/messages`, `/notifications`. SUS serves everything under `/wbw`.
If the contract places the missing endpoints under `/wbw/...` mirroring the
Node paths, **the entire Node↔SUS difference collapses to the `/wbw` prefix**,
with one exception: the current-user profile is `/auth/me` on Node but
`/wbw/me` on SUS. So switching backend = swapping `apiBase` plus one
per-backend `mePath`. Both JSON APIs are snake_case, so decoding is compatible.

---

## 1. Repo Setup

Copy from `Desktop/WBW/ios_native` into `wbw-ios-fontend`:

- `WBW/` — all 27 `.swift` files, `Assets.xcassets`, `Info.plist`,
  `WBW.entitlements`, `GoogleService-Info.plist`.
- `WBW.xcodeproj/`, `project.yml`.
- **Exclude** `build/` (build artifacts).

Build tooling:

- `project.yml` is the source of truth (XcodeGen). Run `xcodegen generate` to
  (re)generate `WBW.xcodeproj`.
- SPM resolves dependencies on first build: MapLibre
  (`maplibre-gl-native-distribution` ≥ 6.0.0), Firebase
  (`firebase-ios-sdk` ≥ 11.0.0, product `FirebaseMessaging`).
- Target settings (from `project.yml`): bundle id `th.ac.mfu.wbwSwift`,
  deployment target iOS 18.0, Swift 5.0, team `NJL4K64JX5`, iPhone only.

`.gitignore` additions:

- `build/`, `DerivedData/`, `*.xcuserstate`
- `WBW/GoogleService-Info.plist` — Firebase secret; keep local, do not commit.
  (Record the fact that the Firebase project / APNs config is already wired to
  bundle `th.ac.mfu.wbwSwift`.)

**Baseline gate:** app builds and runs on the simulator against the existing
Node backend (`https://wbw.sumfu.store`) and login succeeds **before** any code
change. This proves the clone is intact.

## 2. Backend Environment Switch (`Config.swift`)

Replace the single `apiBase` constant with an environment enum:

| Env | `apiBase` | `mePath` |
|---|---|---|
| `.prodNode` (default) | `https://wbw.sumfu.store` | `/auth/me` |
| `.susLocal` | `http://localhost:8080/wbw` | `/me` |
| `.susProd` | *TBD (teammate's SUS URL)* | `/me` |

- `Config` exposes `current`, `apiBase`, and `mePath`.
- `APIClient` change is minimal: the only hardcoded path that differs between
  backends is the profile path. Replace the two `"/auth/me"` literals (GET in
  `me(token:)`, PATCH in `updatePhoto(token:)`) with `Config.mePath`. Every
  other call already appends to `Config.apiBase` and needs no change, because
  SUS mirrors the Node paths under `/wbw`.
- `.susLocal` uses `http://localhost` → add an ATS exception
  (`NSAllowsLocalNetworking`) under `NSAppTransportSecurity` in `Info.plist`.

**Auth constraint:** Node and SUS sign JWTs with different secrets. A token
issued by one backend does not validate on the other. Therefore the switch is
**whole-app** (log in again on the selected backend); do **not** mix endpoints
across backends within one session.

## 3. Backend Contract Deliverable (`docs/backend-contract.md`)

Written in **English**. This is what the teammate implements in SUS. Structure:

### 3.1 Preamble
- Base URL: `<host>/wbw`. Auth: `Authorization: Bearer <jwt>`. Roles:
  `participant`, `staff`, `admin`.
- All bodies and responses are JSON, snake_case. Field names must match the
  iOS models **exactly** (listed per endpoint below).
- Errors: non-2xx return `{ "error": "<message>" }`; iOS surfaces `error`.

### 3.2 Already in SUS — verify shapes (no new work expected)

| Endpoint | iOS response type | Note |
|---|---|---|
| `POST /wbw/auth/login` `{username,password}` | `{user:{user_id,username,role}, token}` | matches SUS `AuthResponse` |
| `GET /wbw/groups` | `[{group_id,group_number,capacity,member_count,seats_left}]` | matches SUS `Group` |
| `GET /wbw/notifications` | `[Notification]` (see 3.4 id note) | matches SUS `Notification` |
| `GET /wbw/me` | full profile (see 3.3) | **verify SUS returns all fields** |

`GET /wbw/me` must return the full participant profile the iOS `Me` model
decodes (snake_case): `user_id, username, role, student_id, first_name,
last_name, date_of_birth, sex, contact_phone, school_name, major, year,
group_id, group_number, bib_number, qr_token, photo_url,
emergency_contact_name, emergency_contact_phone, blood_type, food_allergies,
chronic_disease, medications, weight_kg, height_cm`. `weight_kg`/`height_cm`
may be number or numeric-string (iOS tolerates both). If the existing
`/wbw/me` omits medical / `qr_token` / `bib_number`, it must be extended.

### 3.3 Endpoints SUS must add

Each entry cites the Node source file to port logic 1:1. Node routes are
mounted without the `/wbw` prefix; add the prefix in SUS.

1. **`PATCH /wbw/me`** — update own photo. Body `{photo_url}` (base64 data
   URL). Auth: participant. → `200`. Source: `authRoutes.js:119`.
2. **`POST /wbw/notifications/{id}/read`** — mark read. Auth: participant. →
   `200`. Upserts into the existing notification-reads table (the one that
   already backs `read_at` in `GET /wbw/notifications`). Source:
   `notificationRoutes.js:69`.
3. **`GET /wbw/groups/members/index`** — lightweight cross-group member index.
   → `[{user_id,first_name,last_name,group_id,group_number}]`. Source:
   `groupRoutes.js:17`.
4. **`GET /wbw/groups/{id}/members`** →
   `{members:[{user_id,first_name,last_name,photo_url,bib,school}], count}`.
   Source: `groupRoutes.js:39`.
5. **`POST /wbw/groups/{id}/join`** — join group. → `200`; **`409`** when full
   (iOS maps 409 → "group full"). Source: `groupRoutes.js:55`.
6. **`POST /wbw/groups/leave`** — leave current group. → `200`. Source:
   `groupRoutes.js:85`.
7. **`GET /wbw/groups/{id}/messages?after=<id>&limit=<n>`** — poll chat.
   `after` = last seen message id (optional), `limit` default 50. →
   `[{id,group_id,sender_id,client_id,body,device_time,created_at,first_name,last_name}]`
   ordered so the client can append. Source: `groupRoutes.js:132`.
8. **`POST /wbw/groups/{id}/messages`** — send chat. Body
   `{client_id,body,device_time}`. Idempotent on `client_id` (resend returns
   the same row). → `201` with the message object (same shape as GET).
   Source: `groupRoutes.js:96`.
9. **`GET /wbw/staff/checkpoints`** — checkpoints this staff is assigned to.
   Auth: staff/admin. → `[{id,name,sequence}]`. Source: `staffRoutes.js:9`.
10. **`POST /wbw/staff/checkin`** — check a participant in at a checkpoint.
    Auth: staff/admin. Body `{checkpoint_id, qr_token?, bib?}` (one of
    `qr_token`/`bib`). →
    `{first_name,last_name,bib,has_medical_flag,already_checked_in}`; errors →
    4xx `{error}`. Source: `staffRoutes.js:31`.
11. **`POST /wbw/devices/register`** — register FCM token. Body
    `{token, platform}`. → `200`/`204`. Source: `deviceRoutes.js:8`.
12. **`POST /wbw/devices/unregister`** — remove FCM token. Body `{token}`. →
    `200`/`204`. Source: `deviceRoutes.js:21`.

### 3.4 New DB tables

- **`wbw_messages`** (group chat): `id` (bigint pk), `group_id`, `sender_id`,
  `client_id` (unique per sender/group for idempotency), `body`, `device_time`,
  `created_at`. Indexed on `(group_id, id)` for `after`-polling.
- **`device_tokens`** (push): `user_id`, `token` (unique), `platform`,
  `created_at`. Upsert on register, delete on unregister.
- Likely **already present** in SUS (verify, no new table expected): group
  membership, checkpoint↔staff assignment, notification reads. These back the
  admin features SUS already ships.

### 3.5 Known type mismatch to resolve

SUS `Notification.id` is `int64` (JSON number); the iOS `NotificationItem.id`
is `String` (the Node backend emitted PG bigint as string). Chat message ids
have the same shape difference. **Resolution: fix on the iOS side** (decode
id/`sender_id` as int-or-string, reusing the existing `LossyNumber` pattern),
consistent with "adapt iOS to SUS." The contract notes this so the teammate
need not stringify ids; if they prefer to return strings, that also works.

## 4. iOS Adaptation & Migration Sequence

- **Phase 0** — clone; build green on Node; login works (baseline gate).
- **Phase 1** — add the `Config` env switch + `mePath`; add the ATS exception;
  make id decoding tolerant (3.5). Default stays `.prodNode`; app still works.
- **Phase 2** — as the teammate ships each SUS endpoint, switch the whole app
  to `.susLocal`, log in, and test the affected screen. Confirm SUS `/wbw/me`
  returns `role` so staff/admin gating works.
- Testing: manual on the iOS simulator, smoke each endpoint as it lands.

## Open Questions

- `.susProd` URL — teammate's deployed SUS host (placeholder until provided).
- Confirm whether SUS's existing `/wbw/me` already returns the full profile
  (3.2) or needs extension.

## Acceptance Criteria

- iOS project builds via `xcodegen generate` + Xcode and runs on the simulator.
- Login and core screens work against `.prodNode` (baseline) unchanged.
- `Config` switches backend by changing one enum value; `.susLocal` reaches SUS
  for every endpoint SUS has shipped.
- `docs/backend-contract.md` (English) lists every endpoint in §3 with method,
  path, auth/role, request, response, status codes, and required DB tables.
