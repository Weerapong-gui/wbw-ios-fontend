# WBW iOS — Backend API Contract for SUS

The WBW iOS app talks to a backend under the base path `<host>/wbw`. This
document lists every endpoint the app calls. Endpoints in §2 already exist in
SUS (verify shapes). Endpoints in §3 must be added. Behavior is defined by the
original Node backend — file references point to
`Desktop/WBW/backend/api/src/routes/` so logic can be ported 1:1.

## Conventions
- Base: `<host>/wbw`. Auth header: `Authorization: Bearer <jwt>`.
- Roles: `participant`, `staff`, `admin`.
- JSON, snake_case. Field names must match exactly (the iOS client decodes by key).
- Errors: non-2xx returns `{ "error": "<message>" }`.

## 1. Auth model
- `POST /wbw/auth/login` issues a JWT the app stores and sends on every call.
- The app switches to SUS wholesale (re-login), so SUS's own JWT is fine — it
  never mixes tokens with the old Node backend.

## 2. Already in SUS — verify only

| Method | Path | Request | Response |
|---|---|---|---|
| POST | `/wbw/auth/login` | `{username, password}` | `{user:{user_id,username,role}, token}` |
| GET | `/wbw/groups` | — | `[{group_id,group_number,capacity,member_count,seats_left}]` |
| GET | `/wbw/notifications` | — | `[Notification]` (see §4 id note) |
| GET | `/wbw/me` | — | full profile (see below) |

`GET /wbw/me` must return the full participant profile (snake_case keys):
`user_id, username, role, student_id, first_name, last_name, date_of_birth,
sex, contact_phone, school_name, major, year, group_id, group_number,
bib_number, qr_token, photo_url, emergency_contact_name,
emergency_contact_phone, blood_type, food_allergies, chronic_disease,
medications, weight_kg, height_cm`.
`weight_kg`/`height_cm` may be a number or numeric string. If the current
`/wbw/me` omits medical fields, `qr_token`, or `bib_number`, extend it.

## 3. Endpoints to add (mirror Node paths under `/wbw`)

| # | Method | Path | Role | Request | Response / status | Node source |
|---|---|---|---|---|---|---|
| 1 | PATCH | `/wbw/me` | participant | `{photo_url}` | `200` | `authRoutes.js:119` |
| 2 | POST | `/wbw/notifications/{id}/read` | participant | — | `200` | `notificationRoutes.js:69` |
| 3 | GET | `/wbw/groups/members/index` | participant | — | `[{user_id,first_name,last_name,group_id,group_number}]` | `groupRoutes.js:17` |
| 4 | GET | `/wbw/groups/{id}/members` | participant | — | `{members:[{user_id,first_name,last_name,photo_url,bib,school}], count}` | `groupRoutes.js:39` |
| 5 | POST | `/wbw/groups/{id}/join` | participant | — | `200`; `409 {error}` when full | `groupRoutes.js:55` |
| 6 | POST | `/wbw/groups/leave` | participant | — | `200` | `groupRoutes.js:85` |
| 7 | GET | `/wbw/groups/{id}/messages?after=<id>&limit=<n>` | participant | — | `[Message]` (below), ordered ascending | `groupRoutes.js:132` |
| 8 | POST | `/wbw/groups/{id}/messages` | participant | `{client_id, body, device_time}` | `201` with `Message`; idempotent on `client_id` | `groupRoutes.js:96` |
| 9 | GET | `/wbw/staff/checkpoints` | staff/admin | — | `[{id,name,sequence}]` | `staffRoutes.js:9` |
| 10 | POST | `/wbw/staff/checkin` | staff/admin | `{checkpoint_id, qr_token?, bib?}` | `{first_name,last_name,bib,has_medical_flag,already_checked_in}`; 4xx `{error}` | `staffRoutes.js:31` |
| 11 | POST | `/wbw/devices/register` | participant | `{token, platform}` | `200`/`204` | `deviceRoutes.js:8` |
| 12 | POST | `/wbw/devices/unregister` | participant | `{token}` | `200`/`204` | `deviceRoutes.js:21` |

`Message` shape (endpoints 7 & 8):
`{id, group_id, sender_id, client_id, body, device_time, created_at, first_name, last_name}`.

## 4. Known type note
The iOS app treats `notification.id` and `message.id` as **strings** (the Node
backend emitted PG `bigint` as a string). SUS returns them as `int64` numbers.
The app is being updated to accept either number or string for these ids, so
**no change is required on the SUS side** — returning numbers is fine.

## 5. New DB tables
- `wbw_messages`: `id` (bigint pk), `group_id`, `sender_id`, `client_id`
  (unique per sender+group, for idempotent resend), `body`, `device_time`,
  `created_at`. Index `(group_id, id)` for `after`-based polling.
- `device_tokens`: `user_id`, `token` (unique), `platform`, `created_at`.
  Upsert on register, delete on unregister.
- Group membership, checkpoint↔staff assignment, and notification-read
  tracking are assumed to already exist (they back current admin features) —
  verify, no new table expected.
