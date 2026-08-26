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
medications, weight_kg, height_cm, leave_quota, membership_log`.
`weight_kg`/`height_cm` may be a number or numeric string. If the current
`/wbw/me` omits medical fields, `qr_token`, or `bib_number`, extend it.

`leave_quota` (int) is how many more times the participant may leave a group
(new accounts default to 1; 0 means no more leaves allowed). `membership_log`
is an array, newest first, up to 10 entries, of
`{action, group_id, group_number, quota_after, actor_name, created_at}` —
`action` is `join` / `leave` / `quota_adjust`; `group_id`/`group_number` are
`null` only for a `quota_adjust` row logged while the participant had no
group; `actor_name` is `null` when the participant did it themselves,
otherwise the admin's display name.

## 3. Endpoints to add (mirror Node paths under `/wbw`)

| # | Method | Path | Role | Request | Response / status | Node source |
|---|---|---|---|---|---|---|
| 1 | PATCH | `/wbw/me` | participant | `{photo_url}` | `200` | `authRoutes.js:119` |
| 2 | POST | `/wbw/notifications/{id}/read` | participant | — | `200` | `notificationRoutes.js:69` |
| 3 | GET | `/wbw/groups/members/index` | participant | — | `[{user_id,first_name,last_name,group_id,group_number}]` | `groupRoutes.js:17` |
| 4 | GET | `/wbw/groups/{id}/members` | participant | — | `{members:[{user_id,first_name,last_name,photo_url,bib,school}], count}` | `groupRoutes.js:39` |
| 5 | POST | `/wbw/groups/{id}/join` | participant | — | `200`; `409 {error}` when full or already in a group | `groupRoutes.js:55` |
| 6 | POST | `/wbw/groups/leave` | participant | — | `200` (also when not in any group — no-op, quota untouched); `409 {error}` when leave quota is exhausted | `groupRoutes.js:85` |
| 7 | GET | `/wbw/groups/{id}/messages?after=<id>&limit=<n>` | participant | — | `[Message]` (below), ordered ascending | `groupRoutes.js:132` |
| 8 | POST | `/wbw/groups/{id}/messages` | participant | `{client_id, body, device_time}` | `201` with `Message`; idempotent on `client_id` | `groupRoutes.js:96` |
| 9 | GET | `/wbw/staff/checkpoints` | staff/admin | — | `[{id,name,sequence}]` | `staffRoutes.js:9` |
| 10 | POST | `/wbw/staff/checkin` | staff/admin | `{checkpoint_id, qr_token?, bib?}` | `{first_name,last_name,bib,has_medical_flag,already_checked_in}`; 4xx `{error}` | `staffRoutes.js:31` |
| 13 | GET | `/wbw/checkpoints` | participant | — | `[{id,sequence,name,name_en,activity_name,activity_name_en,type,requires_checkin}]` เรียง `sequence` แล้วตามด้วย `id` · จุดบริการมี `sequence: null` · **ไม่มี `lat`/`lng`** | `wbw_checkpoint_handler.go` (SUS) |
| 14 | GET | `/wbw/me/progress` | participant | — | `{total, checked_in:[{checkpoint_id,name,activity_name,sequence,at,answered,rating,comment}], emergency_phone, event_feedback_answered}` · **ไม่มีฟิลด์ `_en`** · `event_feedback_answered` เป็นฟิลด์ใหม่ (bool) ดูหมายเหตุ 2026-08-26 | `wbw_progress_handler.go` (SUS) |
| 15 | POST | `/wbw/me/feedback` | participant | `{client_id, checkpoint_id, rating, comment?, device_time}` | `201` แถวใหม่ · `200` ยิงซ้ำด้วย `client_id` เดิม · `409` แถวเดิมของฐานนี้ · `403 {error}` ยังไม่เช็คอิน · `400 {error}` rating นอกช่วง | `wbw_feedback_handler.go` (SUS) |
| 16 | POST | `/wbw/me/event-feedback` | participant | `{client_id, rating, rating_activity?, comment?, device_time}` | `201` แถวใหม่ · `200` ยิงซ้ำด้วย `client_id` เดิม · `409` ตอบแล้ว | — ยังไม่มีใน SUS ดูหมายเหตุ 2026-08-26 |
| 11 | POST | `/wbw/devices/register` | participant | `{token, platform}` | `200`/`204` | `deviceRoutes.js:8` |
| 12 | POST | `/wbw/devices/unregister` | participant | `{token}` | `200`/`204` | `deviceRoutes.js:21` |

> **13–15 เพิ่ม 2026-08-21** — สามตัวนี้อยู่ใน SUS (Go) ไม่ใช่ Node เหมือนแถวอื่นในตาราง ·
> 14 กับ 15 แอปเรียกมาตั้งแต่รอบ check-in feedback แล้วแต่ไม่เคยถูกจดไว้ที่นี่เลย ทั้งที่เอกสารนี้
> เป็นที่เดียวที่รวมสัญญาไว้ (ยืนยันด้วย curl ที่ `docs/checkin-feedback-verification.md`) ·
> 13 เป็นของใหม่: ก่อนมีมัน แอปรู้ชื่อฐานเฉพาะฐานที่เช็คอินไปแล้ว เพราะ 14 คืนแค่ `checked_in`

> **16 เพิ่ม 2026-08-26 (ยังไม่มีใน SUS)** — แถว 16 คือ endpoint ที่ SUS **ยังไม่ได้ทำ** ตอนเขียนบรรทัด
> นี้ แอปทั้ง iOS และ Android ส่งล่วงหน้าไปแล้ว (ทรงเดียวกับแถว 15) เพื่อให้วันที่ SUS ship endpoint จริง
> เครื่องที่อัปเดตแล้วทุกเครื่องเริ่มส่งได้ทันทีโดยไม่ต้องรอออกแอปใหม่ · ฝั่งแอปตีความ `404` เป็นความ
> ล้มเหลว (ไม่ใช่ "ตอบแล้ว") ซึ่งเปิดปุ่ม "ข้ามไปก่อน" ให้ผู้เข้าร่วมกดผ่านได้ (ดู `submitEventFeedback`
> ใน `APIClient.swift`) · ฝั่งแอปยังไม่ตรวจ body ของ `409` ว่ามาจาก origin จริงหรือเปล่าเหมือนที่แถว 15
> ทำ (`isOriginFeedbackRow`) เพราะยังไม่มี response shape จริงจาก SUS ให้ pin ไว้ — ตอนนี้เชื่อ status
> เดี่ยว ๆ ไปก่อน วันที่ SUS ship endpoint นี้จริงแล้วมี response shape ยืนยันแล้ว ฝั่งแอปควรเพิ่ม
> origin-body check สำหรับ `409` ตามแบบแถว 15 · แถว 14 ก็ต้องเพิ่ม `event_feedback_answered` (bool)
> ให้ตรงกันด้วย — ถ้า SUS ยังไม่ส่งฟิลด์นี้ แอปทั้งสองฝั่ง (iOS/Android) default เป็น `false` เมื่อขาด
> ไม่ทำให้ decode พัง

`Message` shape (endpoints 7 & 8):
`{id, group_id, sender_id, client_id, body, device_time, created_at, first_name, last_name}`.

409 error text for endpoints 5 & 6 (`{ "error": "<message>" }`, copied verbatim from SUS):
- Join, already in a group: `ท่านอยู่ในกลุ่มอยู่แล้ว ต้องออกจากกลุ่มเดิมก่อน`
- Join, group full (pre-existing): `กลุ่มเต็มแล้ว เลือกกลุ่มอื่น`
- Leave, quota exhausted: `สิทธิ์ออกจากกลุ่มหมดแล้ว`

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
- `participant_profile.leave_quota` (int, not null, default `1`) — how many
  more times the participant may leave a group; decremented by 1 on each
  successful `POST /wbw/groups/leave`. Accounts that already had a group
  when this column was added were backfilled to `0`.
- `group_membership_log`: `log_id` (bigserial pk), `user_id`, `group_id`
  (nullable — `null` only for a `quota_adjust` row logged while the
  participant had no group), `action` (`join` / `leave` / `quota_adjust`),
  `quota_after` (leave_quota right after the action), `actor_id` (nullable —
  `null` means the participant did it themselves, otherwise the admin's
  `user_id`), `created_at`. Indexed on `(user_id, log_id DESC)`. Separate
  from `admin_log` on purpose (that table logs admin actions as free-text
  and would be swamped by per-participant join/leave rows).
- Group membership, checkpoint↔staff assignment, and notification-read
  tracking are assumed to already exist (they back current admin features) —
  verify, no new table expected.
