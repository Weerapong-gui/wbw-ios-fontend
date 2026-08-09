# โควตาออกจากกลุ่ม + flow แท็บกลุ่มใหม่

**เป้าหมาย:** สองอย่างที่แยกกันไม่ได้เพราะแตะจอเดียวกัน

1. **โควตาออกจากกลุ่ม** — ผู้เข้าร่วมออกจากกลุ่มได้จำกัดจำนวนครั้ง (ค่าเริ่มต้น 1) แทนที่จะเข้า-ออกไม่จำกัด
   ทุกครั้งที่เข้า/ออก/ถูกปรับสิทธิ์ต้องมี log และ admin เห็นสิทธิ์คงเหลือรายคนพร้อมปรับเพิ่ม-ลดได้
2. **flow แท็บกลุ่ม** — มีกลุ่มแล้วให้เข้าจอแชทเลย ไม่ต้องผ่านหน้า "กลุ่มของฉัน" คั่น
   หน้ากลุ่ม/ออกจากกลุ่มย้ายไปอยู่หลังการกดชื่อกลุ่มบนหัวจอแชท

**ที่มา:** บรีฟจาก Park 2026-08-09 · เหตุผลของโควตาคือกันคนย้ายกลุ่มไปมาจนกลุ่มไม่นิ่งก่อนวันงาน

**ขอบเขต:** 3 repo

| repo | ส่วนที่แตะ |
|---|---|
| `Student-Union-Server` (Go) | migration, `wbw_group_repository.go`, `wbw_group_service.go`, `wbw_group_handler.go`, admin participant patch, `/wbw/me` |
| `wbw-ios-fontend` (SwiftUI) | `GroupTabView`, `GroupJoinView`, `GroupChatView`, `MainTabView`, `Models.swift`, `APIClient` |
| `su-wbw-website` (Next.js) | `lib/adminApi.ts`, `components/dashboard/Participants.tsx`, `Logs.tsx` |

**ไม่อยู่ในขอบเขตรอบนี้** (ตกลงกันแล้วว่าแยก spec): หน้าตาจอแชท (header/ฟอง/input),
ฟีเจอร์แชทเพิ่ม (รูป, reply, reaction), การรื้อ toast/แจ้งเตือน

---

## 1. สภาพปัจจุบัน

**iOS** — แชทเป็น overlay ไม่ใช่หน้าใน navigation:

| ไฟล์ | บทบาทตอนนี้ |
|---|---|
| `WBW/GroupTabView.swift:5` | สลับตาม `profile.me?.groupId` — ไม่มีกลุ่ม = `GroupJoinView`, มีกลุ่ม = `GroupHomeView` |
| `WBW/GroupTabView.swift:20` | `GroupHomeView` — การ์ดเลขกลุ่ม + ปุ่ม "เปิดแชทกลุ่ม" + ลิงก์สมาชิก + ออกจากกลุ่ม |
| `WBW/GroupChatView.swift:6` | จอแชท มี `onClose` + ปุ่ม `chevron.down` ปิดตัวเอง |
| `WBW/MainTabView.swift:16,242` | `@State chatOpen` + overlay `.transition(.move(edge: .bottom))` ทับ TabView ทั้งจอ |
| `WBW/GroupJoinView.swift:14` | มี `NavigationStack` ของตัวเอง |

**Backend** — `participant_profile.group_id` เปลี่ยนได้ไม่จำกัด · `POST /wbw/groups/{id}/join`
ย้ายกลุ่มได้ตรง ๆ ทั้งที่ยังมีกลุ่มอยู่ (`wbw_group_repository.go:80`) · `POST /wbw/groups/leave`
ไม่มีเงื่อนไขอะไรเลย · ไม่มี log ของการเข้า/ออกกลุ่ม

**Dashboard** — `components/dashboard/Participants.tsx` (ตาราง + โมดัลแก้ไข ผ่าน `patchParticipant`)
และ `Logs.tsx` (อ่าน `admin_log`)

---

## 2. กติกาโควตา (ตัดสินแล้ว)

1. หน่วยของโควตาคือ **"จำนวนครั้งที่ออกจากกลุ่มได้"** หักตอนกด *ออกจากกลุ่ม* เท่านั้น
   ไม่ใช่ตอนเข้ากลุ่ม
2. ค่าเริ่มต้น **1** สำหรับผู้ใช้ใหม่
3. **การเข้ากลุ่มไม่ถูกจำกัดด้วยโควตา** — คนที่สิทธิ์เหลือ 0 และยังไม่มีกลุ่ม ยังเลือกกลุ่มได้
   แต่เข้าแล้วออกไม่ได้อีก
4. **ย้ายกลุ่มตรง ๆ ไม่ได้** — `join` ตอนที่ยังมีกลุ่มอยู่ = `409` ต้อง `leave` ก่อนเสมอ
   (ปิดช่องเลี่ยงโควตาด้วยการยิง API ตรง และทำให้โควตามีจุดหักจุดเดียว)
5. **migrate:** คนที่มีกลุ่มอยู่แล้ว ณ วันขึ้นระบบ = **0** (ถือว่าเลือกจบแล้ว) · คนที่ยังไม่มีกลุ่ม = 1
6. admin ปรับเพิ่ม-ลดได้รายคน ทุกครั้งที่ปรับต้องมี log ว่าใครปรับ

**flow เต็มของผู้ใช้ใหม่ 1 คน:**

```
เปิดแอปครั้งแรก (quota=1, ไม่มีกลุ่ม)
  กด "เข้ากลุ่ม 7"  → popup: "หลังเข้าแล้ว ท่านเหลือสิทธิ์ออกจากกลุ่มอีก 1 ครั้ง" → ยืนยัน
  อยู่กลุ่ม 7 (quota=1)  → หน้ากลุ่มของฉันมีปุ่มออก
  กดออกจากกลุ่ม   → popup: "หลังออกจะเหลือสิทธิ์อีก 0 ครั้ง" → ยืนยัน
  ไม่มีกลุ่ม (quota=0)  → เลือกกลุ่มใหม่ได้
  กด "เข้ากลุ่ม 12" → popup: "สิทธิ์ออกจากกลุ่มของท่านหมดแล้ว เข้ากลุ่มนี้แล้วจะเปลี่ยนกลุ่มไม่ได้อีก" → ยืนยัน
  อยู่กลุ่ม 12 (quota=0) → หน้ากลุ่มของฉัน "ไม่มี" ปุ่มออกอีกต่อไป
```

---

## 3. Backend (SUS)

### 3.1 Migration `000006_group_leave_quota`

```sql
-- up
ALTER TABLE participant_profile
  ADD COLUMN leave_quota INT NOT NULL DEFAULT 1;
UPDATE participant_profile SET leave_quota = 0 WHERE group_id IS NOT NULL;

CREATE TABLE group_membership_log (
  log_id      BIGSERIAL PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES app_user(user_id) ON DELETE CASCADE,
  group_id    INT REFERENCES participant_group(group_id),  -- NULL ได้เฉพาะ quota_adjust
  action      TEXT NOT NULL,          -- 'join' | 'leave' | 'quota_adjust'
  quota_after INT NOT NULL,           -- สิทธิ์คงเหลือ "หลัง" ทำรายการ
  actor_id    UUID REFERENCES app_user(user_id) ON DELETE SET NULL,  -- NULL = user ทำเอง
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_gml_user ON group_membership_log (user_id, log_id DESC);

-- down: DROP TABLE group_membership_log; ALTER TABLE participant_profile DROP COLUMN leave_quota;
```

`quota_after` เก็บค่าหลังทำรายการทุกแถว เพื่อให้อ่านประวัติแล้วเห็นสถานะ ณ ตอนนั้นได้เลย
ไม่ต้องไล่บวกลบย้อนจากต้น (log ถูกอ่านในหน้ารายละเอียดผู้เข้าร่วม ซึ่งอ่านทีละคน)

เก็บแยกจาก `admin_log` ตั้งใจ: `admin_log` เป็นบันทึกของ *admin* ถ้ายัด join/leave ของผู้เข้าร่วม
2,000 คนลงไป log ของ admin จะถูกกลบจนใช้งานไม่ได้ และ `admin_log.detail` เป็น TEXT ก้อนเดียว
query "คนนี้ออกกี่ครั้ง" ไม่ได้

### 3.2 API

| endpoint | เปลี่ยนอะไร |
|---|---|
| `GET /wbw/me` | เพิ่ม `leave_quota` (int) |
| `POST /wbw/groups/{id}/join` | มีกลุ่มอยู่แล้ว → `ErrAlreadyInGroup` → `409 "ท่านอยู่ในกลุ่มอยู่แล้ว ต้องออกจากกลุ่มเดิมก่อน"` · สำเร็จ → INSERT log `join` (`quota_after` = ค่าปัจจุบัน ไม่เปลี่ยน) |
| `POST /wbw/groups/leave` | quota = 0 → `ErrNoQuota` → `409 "สิทธิ์ออกจากกลุ่มหมดแล้ว"` · สำเร็จ → quota−1 + INSERT log `leave` · ไม่มีกลุ่มอยู่แล้ว → `200` เหมือนเดิม และ **ไม่หักสิทธิ์** |
| `PATCH /wbw/admin/participants/{id}` | รับ `leave_quota` (0–10) → เขียน `group_membership_log` action `quota_adjust` (`actor_id` = admin, `group_id` = กลุ่มปัจจุบันหรือ NULL) **และ** `admin_log` action `ปรับสิทธิ์ออกกลุ่ม` |
| `GET /wbw/admin/participants` | เพิ่ม `leave_quota` ในแถว |
| `GET /wbw/admin/participants/{id}` | เพิ่ม `membership_log` — 10 แถวล่าสุดของ user นั้น |

### 3.3 Leave — statement เดียวคือหัวใจ

```sql
WITH target AS (
  SELECT user_id, group_id
    FROM participant_profile
   WHERE user_id = $1 AND group_id IS NOT NULL AND leave_quota > 0
     FOR UPDATE
)
UPDATE participant_profile p
   SET group_id = NULL, leave_quota = p.leave_quota - 1, updated_at = now()
  FROM target t
 WHERE p.user_id = t.user_id
RETURNING t.group_id AS prev_group_id, p.leave_quota
```

- กลุ่มเดิมมาจาก CTE ตรง ๆ ไม่ใช่ subquery ใน `RETURNING` — เหตุผลเดียวกับคอมเมนต์ที่มีอยู่ใน
  `wbw_group_repository.go:155` (ค่าจาก subquery ใน `RETURNING` ขึ้นกับ snapshot semantics
  อ่านแล้วเดาไม่ออกว่าได้ค่าก่อนหรือหลัง UPDATE)
- **0 แถวกลับมา** = ทำไม่ได้ ต้องแยกสาเหตุด้วย `SELECT group_id, leave_quota` ตามหลังในทรานแซกชัน
  เดียวกัน: `group_id IS NULL` → `ErrNoGroup` (ตอบ 200 ตามพฤติกรรมเดิม) · ไม่งั้น → `ErrNoQuota` (409)
  · แถวไม่มีเลย → `ErrNotFound`
- ข้อบังคับ: เงื่อนไข `leave_quota > 0` ต้องอยู่ใน statement เดียวกับที่เคลียร์ `group_id`
  ห้ามแยกเป็น SELECT เช็คก่อนแล้วค่อย UPDATE — การหักสิทธิ์กับการออกจึงเกิดพร้อมกันเสมอ
  กดรัว ๆ / สองเครื่องพร้อมกัน หักเกินหรือทำ quota ติดลบไม่ได้ และเหลือ 1 round trip แทน 2 ของเดิม
- ทั้ง `UPDATE`, `DELETE FROM group_chat_state`, `INSERT INTO group_membership_log`
  อยู่ทรานแซกชันเดียวกัน · `ChatEvents.NotifyGroup` ยังเรียกหลัง commit เหมือนเดิม

### 3.4 Join

เพิ่มเงื่อนไขเดียว: อ่าน `group_id` ปัจจุบันในทรานแซกชัน ถ้าไม่ใช่ NULL → `ErrAlreadyInGroup`
ที่เหลือ (ล็อกแถวกลุ่ม, เช็คที่นั่ง, ตัดประวัติแชทผ่าน `group_chat_state`) คงเดิม แล้วต่อท้ายด้วย
INSERT log

**ผลข้างเคียงที่ยอมรับ:** เดิม `join` กลุ่มเดิมซ้ำได้เพื่อรีเซ็ตจุดตัดประวัติแชท
(`wbw_group_repository.go:99` `alreadyHere`) — ความสามารถนี้หายไป ไม่มี UI ไหนเรียกใช้

---

## 4. iOS

### 4.1 โครงใหม่ของแท็บ 3

```
GroupTabView                      ← NavigationStack ตัวเดียวของทั้งแท็บ
├── ไม่มีกลุ่ม → GroupJoinView    (ถอด NavigationStack ของตัวเองออก ใช้ของแม่)
└── มีกลุ่ม    → GroupChatView    (root ของ stack — หัวจอกดได้)
                  └ push .home    → GroupHomeView
                      └ push .members → GroupMembersView
```

```swift
enum GroupRoute: Hashable { case home, members }
```

`path` อยู่ที่ `MainTabView` (`@State private var groupPath: [GroupRoute] = []`) ส่ง `Binding` ลง
`GroupTabView` — เพราะ push แจ้งเตือนและ toast ต้องเด้งกลับ root ได้จากข้างนอก

### 4.2 สิ่งที่หายไปจาก `MainTabView`

`chatOpen`, overlay `GroupChatView` + transition, `.animation(value: chatOpen)`,
`.onChange(of: chatOpen)`

| ของเดิม | ของใหม่ |
|---|---|
| `updateSceneGate()` เช็ค `chatOpen` ด้วย | เหลือ `host.suppressed = !(tab == 0 \|\| tab == 4)` |
| `.openGroupChat` → `tab=3; chatOpen=true` | `tab=3; groupPath=[]` |
| ChatToast แสดงเมื่อ `!chatOpen` | แสดงเมื่อ `tab != 3` |
| `canShowCheckinToast` เช็ค `!chatOpen` | เช็ค `tab != 3` |
| `kickedOut` → `chatOpen=false` | `groupPath=[]` + `profile.load()` (GroupTabView สลับกลับหน้าลิสต์เอง) |
| `chevron.down` ปิดแชท (`GroupChatView:69`) | ตัดทิ้งพร้อม `onClose` — หัวจอเป็นปุ่มไป `.home` แทน |

`GroupChatView.onClose` หายไป ทำให้ launch arg `uitestChatCloseAfter` (`MainTabView:103`) ไม่มี
ความหมายอีก — ลบทิ้งพร้อมกัน ส่วน `uitestChat` เปลี่ยนเป็นตั้ง `tab = 3`

### 4.3 `setScreenVisible` ต้องย้ายตัวคุม

ของเดิมอยู่ที่ `.task` / `.onDisappear` ของ `GroupChatView` ซึ่งเชื่อไม่ได้แล้ว: `TabView` เก็บ
view ไว้ตอนสลับแท็บ และ `NavigationStack` push ทับก็ไม่รับประกันว่า `onDisappear` จะยิง
ถ้าไม่ย้าย heartbeat จะวิ่งค้างตอนผู้ใช้ไปแท็บอื่น → server เข้าใจว่ายังจ้อจออยู่ → ไม่ส่ง push ให้เลย
(อาการเงียบสนิท ไม่มี error ให้เห็น)

```swift
// MainTabView
private var chatVisible: Bool {
    tab == 3 && profile.me?.groupId != nil && groupPath.isEmpty
}
// .onChange(of: chatVisible) { _, v in chat.setScreenVisible(v) }
// + เรียกครั้งแรกใน .task ด้วย (onChange ไม่ยิงตอน mount)
```

`readSnapshot` ใน `GroupChatView` (บรรทัด 23) ที่ผูกกับ `.task` ต้องย้ายมาผูกกับ `chatVisible`
ด้วยเหตุผลเดียวกัน — สแนป `myLastReadId` **ก่อน** `setScreenVisible(true)` เสมอ ไม่งั้นเส้น
"ข้อความใหม่" ไม่มีวันโผล่ (เหตุผลเต็มอยู่ในคอมเมนต์ที่ตัวแปรนั้น)

### 4.4 Quota ใน UI

`Me.leaveQuota: Int?` — `convertFromSnakeCase` แปลง `leave_quota` ให้เอง · เป็น optional เพื่อไม่ให้
decode พังกับ backend เก่า และ UI อ่านเป็น `?? 0` = พลาดไปทาง "ไม่มีสิทธิ์" ไม่ใช่ทางแจกฟรี

| จุด | พฤติกรรม |
|---|---|
| `GroupJoinView` กด "เข้ากลุ่ม" | `.alert` ยืนยัน **ก่อน** ยิง API · quota ≥1: "หลังเข้าแล้ว ท่านเหลือสิทธิ์ออกจากกลุ่มอีก {q} ครั้ง" · quota =0: "สิทธิ์ออกจากกลุ่มของท่านหมดแล้ว เข้ากลุ่มนี้แล้วจะเปลี่ยนกลุ่มไม่ได้อีก" · ปุ่ม: ยกเลิก / เข้ากลุ่ม |
| `GroupHomeView` | บรรทัดสถานะ "สิทธิ์ออกจากกลุ่มคงเหลือ {q} ครั้ง" · q=0 → "ท่านใช้สิทธิ์เปลี่ยนกลุ่มครบแล้ว" |
| ปุ่มออกจากกลุ่ม | โผล่เฉพาะ q>0 · q=0 ไม่มีปุ่ม (ไม่ใช่ปุ่ม disabled — ไม่มีอะไรให้กดแล้วจริง ๆ) |
| กดออก | `.alert` destructive "ออกจากกลุ่ม {N}?" / "หลังออกจะเหลือสิทธิ์อีก {q−1} ครั้ง" · ถ้า q−1 = 0 เติม "— เลือกกลุ่มใหม่ได้อีกครั้งเดียว แล้วจะออกไม่ได้อีก" |
| 409 จาก join/leave | แสดงข้อความจาก server แล้วเรียก `profile.load()` ทันที ให้จอตรงกับความจริง (เกิดตอน admin ตัดสิทธิ์ระหว่างนั้น หรือเข้ากลุ่มจากอีกเครื่อง) |

ข้อความ quota ทุกอันแยกเป็น `enum GroupQuotaText` ฟังก์ชันบริสุทธิ์ ทรงเดียวกับ
`ChatReadStatus.text` (`Chat/ChatBubble.swift:136`) เพื่อให้เทสได้ตรง ๆ โดยไม่ต้องเรนเดอร์ view

### 4.5 ไม่แตะ

`ChatSession`, `ChatRowBuilder`, `ChatBubble`, `ChatToast`, `APIClient+Chat` — flow เปลี่ยน
แต่เครื่องยนต์แชทเหมือนเดิมทั้งหมด · `chat.configure(...)` ยังถูกเรียกจาก
`.onChange(of: profile.me?.groupId)` ตัวเดิม

---

## 5. Dashboard (su-wbw-website)

**`lib/adminApi.ts`** — `type Participant` + `leave_quota: number` · `type ParticipantPatch` +
`leave_quota?: number` · `type ParticipantDetail` + `membership_log` · ไม่มี fetch ใหม่
(เดินบน `getParticipants` / `patchParticipant` / `getParticipantDetail` ที่มีอยู่)

**`Participants.tsx`**
- คอลัมน์ "สิทธิ์ออกกลุ่ม" — ป้ายตัวเลขโทนเดียวกับที่ไฟล์ใช้อยู่ (`0` = `bg-danger/12 text-danger`,
  `≥1` = `bg-forest/10 text-forest`)
- ในโมดัลแก้ไข: ช่องตัวเลข min 0 max 10 บันทึกผ่าน `patchParticipant` เส้นเดิม
- ตัวกรอง "เหลือสิทธิ์ 0" ข้างตัวกรองสำนักวิชา — คำถามจริงของ admin คือ "ใครติดล็อกบ้าง"
- ในโมดัลรายละเอียด: ไทม์ไลน์ `membership_log` (เข้า/ออก/ปรับสิทธิ์ พร้อมเวลาและผู้ทำ)

**`Logs.tsx`** — เพิ่ม tone ให้ action `ปรับสิทธิ์ออกกลุ่ม` ใน `ACTION_TONE` · โครงเดิมทั้งหมด ·
`group_membership_log` ไม่โผล่ในหน้านี้ (เหตุผลข้อ 3.1)

ข้อความใหม่ทุกอันต้องผ่าน `useT()` / dictionary เหมือนของเดิมในไฟล์ ไม่ hardcode ไทยตรง ๆ

---

## 6. เทส

**SUS (Go)**

- `Leave` quota=0 → `ErrNoQuota`, `group_id` ไม่เปลี่ยน, ไม่มีแถว log เพิ่ม
- `Leave` สำเร็จ → quota ลด 1, มีแถว log `leave` ที่ `quota_after` ตรงกับค่าใหม่
- `Leave` ตอนไม่มีกลุ่ม → สำเร็จ (200) และ quota **ไม่** ลด
- `Leave` พร้อมกัน 2 goroutine ตอน quota=1 → สำเร็จอันเดียว อีกอัน `ErrNoQuota` (quota ไม่ติดลบ)
- `Join` ตอนมีกลุ่มอยู่ → `ErrAlreadyInGroup` ไม่มีแถว log
- `Join` สำเร็จ → มีแถว log `join`, quota ไม่เปลี่ยน
- admin ปรับ quota → มีทั้งแถว `group_membership_log` (`actor_id` = admin) และ `admin_log`
- migration: แถวที่มี `group_id` → 0, แถวที่ไม่มี → 1

**iOS (XCTest)**

- `GroupQuotaText` ทุกกรณี: join quota 2/1/0, leave quota 2/1 (ข้อความ "ครั้งเดียว" ตอนเหลือ 0)
- decode `Me` จาก JSON ที่ **ไม่มี** `leave_quota` → ไม่ throw และอ่านได้เป็น 0
- `APIClient.leaveGroup` เจอ 409 → โยน error ที่พาข้อความจาก server มาด้วย
- สกรีนช็อตจาก simulator ตามกติกาข้อ 7 ของ skill: (ก) แท็บ 3 ขึ้นแชทตรง ๆ ตอนมีกลุ่ม
  (ข) หน้ากลุ่มของฉันตอน quota=1 มีปุ่มออก (ค) ตอน quota=0 ไม่มีปุ่มออก (ง) popup ตอนกดเข้ากลุ่ม

**Dashboard** — ไม่มีชุดเทสใน repo นั้น ตรวจด้วยการรันจริง + ภาพ

## 7. ลำดับการทำและความเข้ากันได้

SUS (migration → repository → service → handler → admin) → iOS → dashboard

ระหว่างที่ iOS ยังไม่ปล่อย backend ต้อง deploy ได้เองโดยไม่พังแอปเก่า: แอปเวอร์ชันเก่าไม่รู้จัก
`leave_quota` แต่ยังกดออกได้ 1 ครั้งตามโควตา ครั้งที่ 2 เจอ 409 แล้วโชว์ error ตามปกติของหน้านั้น
— เสื่อมสภาพแบบยอมรับได้ ไม่ crash · `join` ตอนมีกลุ่มอยู่ก็เจอ 409 ซึ่งแอปเก่าไม่มีทางเรียกอยู่แล้ว
เพราะ UI ไม่มีปุ่ม

## 8. ความเสี่ยงที่รู้ล่วงหน้า

| เรื่อง | ผลถ้าพลาด | กัน |
|---|---|---|
| หักสิทธิ์แยกจาก UPDATE | กดรัว ๆ ออกได้เกินโควตา / quota ติดลบ | เงื่อนไข `leave_quota > 0` ต้องอยู่ใน `WHERE` ของ UPDATE เดียวกัน + เทส 2 goroutine |
| migration ตั้ง 0 ให้คนที่มีกลุ่มแล้ว | คนที่ยังไม่ได้ตั้งใจเลือกจริงติดล็อกทันที | ต้องประกาศให้ผู้เข้าร่วมรู้ก่อนขึ้นระบบ · admin ปรับคืนรายคนได้ |
| `setScreenVisible` ผูกกับ lifecycle ของ view | heartbeat ค้าง → ไม่ได้รับ push ตอนอยู่แท็บอื่น เงียบสนิท | ผูกกับ `chatVisible` ที่ MainTabView (ข้อ 4.3) |
| `readSnapshot` ย้ายที่ | เส้น "ข้อความใหม่" ไม่โผล่ หรือโผล่ผิดตำแหน่ง | สแนปก่อน `setScreenVisible(true)` เสมอ + ดูคอมเมนต์เดิมที่ `GroupChatView:23` |
| `GroupJoinView` ถอด NavigationStack | `NavigationLink` ดูสมาชิกในหน้าลิสต์พังเงียบ ๆ (กดแล้วไม่ไปไหน) | ต้องมี stack ของ `GroupTabView` ครอบทุกกรณี ทั้งมีกลุ่มและไม่มี |
| เพิ่มไฟล์ใหม่ใน `WBW/` | Xcode มองไม่เห็นไฟล์ build ไม่ผ่าน | `xcodegen generate` ทุกครั้ง (กติกาข้อ 1 ของ skill) |
