# โควตาออกจากกลุ่ม — ฝั่ง Backend (SUS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ทำให้ผู้เข้าร่วมออกจากกลุ่มได้จำกัดจำนวนครั้ง (เริ่มต้น 1) มีบันทึกทุกการเข้า/ออก/ปรับสิทธิ์
และ admin อ่าน/ปรับสิทธิ์คงเหลือรายคนได้

**Architecture:** เพิ่มคอลัมน์ `participant_profile.leave_quota` เป็นแหล่งความจริงเดียวของ "เหลือกี่ครั้ง"
และตาราง `group_membership_log` เป็นประวัติ · การหักสิทธิ์เกิดใน `UPDATE` statement เดียวกับที่เคลียร์
`group_id` จึงกันการหักเกินโดยไม่ต้องล็อกเพิ่ม · `join` ตอนที่ยังมีกลุ่มถูกปฏิเสธ เพื่อให้โควตามีจุดหักจุดเดียว

**Tech Stack:** Go 1.x, pgx v5, chi, golang-migrate, PostgreSQL

**Repo:** `~/Projects/Student-Union-Server` (ไม่ใช่ repo ที่ไฟล์แผนนี้อยู่)

**สเปก:** `~/Projects/wbw-ios-fontend/docs/superpowers/specs/2026-08-09-group-leave-quota-and-chat-flow-design.md`

## Global Constraints

- ตารางผู้ใช้ชื่อ `wbw_user` (เปลี่ยนชื่อจาก `app_user` ตั้งแต่ migration `000012`) — SQL ใหม่ทุกอันต้องใช้ชื่อนี้
- migration ถัดไปคือ `000016` ต้องมีทั้ง `.up.sql` และ `.down.sql` เสมอ
- คอมเมนต์ในโค้ดและข้อความ error ที่ส่งถึงผู้ใช้เป็นภาษาไทย · คอมเมนต์ต้องบอก **"ทำไม"** ไม่ใช่ "ทำอะไร"
- เทส repository ต้องต่อ Postgres จริง เปิดด้วย `WBW_DB_TESTS=1` เท่านั้น ไม่งั้น `t.Skip` (ทรงเดียวกับ `internal/repository/wbw_feedback_repository_test.go`)
- บัญชีทดสอบคือ username `6931900011` (ค่าคงที่ `testUsername` มีอยู่แล้วใน package `repository`)
- commit ข้อความภาษาไทย ขึ้นต้นด้วย `feat:` / `fix:` / `test:` / `refactor:` / `docs:`
- **ห้าม `git add -A` หรือ `git add .`** — add ทีละไฟล์เสมอ
- ค่าโควตาที่ admin ตั้งได้อยู่ในช่วง 0–10 (ตัวเลขนี้ตายตัว ใช้ทั้งฝั่ง validation และ dashboard)
- action ใน `group_membership_log` มี 3 ค่าเท่านั้น: `'join'`, `'leave'`, `'quota_adjust'`
- **ห้ามแตะฐานข้อมูลระหว่างลงมือ (ตัดสินใจ 2026-08-09)** — ฐาน dev บนเครื่องนี้ drift อยู่ก่อนแล้ว
  (`schema_migrations` = 12 ไม่ dirty · ตารางของ migration 13–15 มีครบ · แต่ตารางผู้ใช้ยังชื่อ `app_user`
  ไม่ใช่ `wbw_user` ที่โค้ดทั้ง repo query) การซ่อมมันไม่ใช่งานของแผนนี้ · ผลที่ตามมา: ห้ามรัน
  `make migrate-up/down/force`, `psql`, หรืออะไรก็ตามที่ต่อฐาน · เทสที่ต้องใช้ Postgres จริงจะ `t.Skip`
  ตัวเอง (ไม่ตั้ง `WBW_DB_TESTS=1`) — **ยังต้องเขียนเทสให้ครบตามแผน** แต่หลักฐานที่รายงานได้คือ
  `go build` + `go vet` + `go test ./internal/...` ที่ขึ้น skip เท่านั้น ห้ามเคลมว่าเทส DB ผ่าน
  · การ verify จริงของ migration และ SQL ทั้งหมดเลื่อนไปตอน deploy บนฐานที่ schema ตรงกับโค้ด

## File Structure

| ไฟล์ | สถานะ | รับผิดชอบ |
|---|---|---|
| `db/migrations/000016_group_leave_quota.up.sql` | สร้าง | คอลัมน์ `leave_quota` + ตาราง `group_membership_log` + backfill |
| `db/migrations/000016_group_leave_quota.down.sql` | สร้าง | ย้อนกลับทั้งสองอย่าง |
| `internal/repository/wbw_group_repository.go` | แก้ | `Join` ปฏิเสธคนที่มีกลุ่มแล้ว · `Leave` หักโควตาแบบ atomic · เขียน log ทั้งสองทาง |
| `internal/repository/wbw_group_repository_test.go` | สร้าง | เทส SQL จริงของ Join/Leave/โควตา/การแข่งกัน |
| `internal/handler/wbw_group_handler.go` | แก้ | แปลง `ErrNoQuota` / `ErrAlreadyInGroup` เป็น 409 พร้อมข้อความไทย |
| `internal/model/wbw_model.go` | แก้ | `LeaveQuota` ใน `Participant`, `ParticipantDetail`, `ParticipantPatch` + `MembershipLogEntry` |
| `internal/repository/wbw_admin_repository.go` | แก้ | select/scan คอลัมน์ใหม่ · patch โควตา + log · ประวัติรายคน |
| `internal/service/wbw_admin_service.go` | แก้ | validate ช่วง 0–10 แล้วส่ง actor ต่อให้ repository |
| `internal/handler/wbw_admin_handler.go` | แก้ | ส่ง actor เข้า service + เขียน `admin_log` action `ปรับสิทธิ์ออกกลุ่ม` |

`internal/service/wbw_group_service.go` **ไม่ต้องแก้** — มันแค่ส่งต่อ error กับปลุก long-poll ซึ่งไม่เปลี่ยน

---

### Task 1: Migration

**Files:**
- Create: `db/migrations/000016_group_leave_quota.up.sql`
- Create: `db/migrations/000016_group_leave_quota.down.sql`

**Interfaces:**
- Consumes: ตาราง `participant_profile`, `participant_group`, `wbw_user` ที่มีอยู่
- Produces: คอลัมน์ `participant_profile.leave_quota INT NOT NULL DEFAULT 1` · ตาราง `group_membership_log(log_id, user_id, group_id, action, quota_after, actor_id, created_at)` · index `idx_gml_user`

- [ ] **Step 1: เขียนไฟล์ up**

```sql
-- โควตาการออกจากกลุ่ม — ผู้เข้าร่วมออกจากกลุ่มได้จำกัดจำนวนครั้ง กันย้ายกลุ่มไปมาจนกลุ่มไม่นิ่งก่อนวันงาน
--
-- คนที่ "มีกลุ่มอยู่แล้ว" ณ วันขึ้นระบบตั้งเป็น 0 ตั้งใจ — ถือว่าเขาเลือกจบไปแล้วก่อนกติกานี้จะมี
-- ถ้าตั้งเป็น 1 เท่ากันหมด ทุกคนจะได้สิทธิ์ย้ายเพิ่มฟรีหนึ่งครั้งพร้อมกันทั้งงาน ซึ่งตรงข้ามกับเป้าหมาย
-- คนที่ควรได้คืนเป็นราย ๆ ให้ admin ปรับให้ทีหลังได้
ALTER TABLE participant_profile
  ADD COLUMN leave_quota INT NOT NULL DEFAULT 1;

UPDATE participant_profile SET leave_quota = 0 WHERE group_id IS NOT NULL;

-- แยกจาก admin_log ตั้งใจ — admin_log เป็นบันทึกของ admin ถ้ายัดการเข้า/ออกของผู้เข้าร่วม 2,000 คน
-- ลงไป บันทึกของ admin จะถูกกลบจนใช้ไม่ได้ และ admin_log.detail เป็น TEXT ก้อนเดียว
-- ตอบคำถาม "คนนี้ออกกี่ครั้ง" ด้วย query ไม่ได้
CREATE TABLE group_membership_log (
  log_id      BIGSERIAL PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES wbw_user(user_id) ON DELETE CASCADE,
  -- กลุ่มที่เข้า/ที่ออกมา · NULL ได้เฉพาะ quota_adjust ตอนคนนั้นยังไม่มีกลุ่ม
  group_id    INT REFERENCES participant_group(group_id),
  action      TEXT NOT NULL,   -- 'join' | 'leave' | 'quota_adjust'
  -- สิทธิ์คงเหลือ "หลัง" ทำรายการ — เก็บทุกแถวเพื่อให้อ่านประวัติแล้วเห็นสถานะ ณ ตอนนั้นได้เลย
  -- ไม่ต้องไล่บวกลบย้อนจากแถวแรก
  quota_after INT NOT NULL,
  -- NULL = ผู้ใช้ทำเอง · มีค่า = admin คนนั้นเป็นคนทำให้
  actor_id    UUID REFERENCES wbw_user(user_id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- หน้ารายละเอียดผู้เข้าร่วมอ่านประวัติทีละคน เรียงใหม่ไปเก่า
CREATE INDEX idx_gml_user ON group_membership_log (user_id, log_id DESC);
```

- [ ] **Step 2: เขียนไฟล์ down**

```sql
DROP TABLE IF EXISTS group_membership_log;
ALTER TABLE participant_profile DROP COLUMN IF EXISTS leave_quota;
```

- [ ] **Step 3: รัน migration ขึ้น**

Run: `make migrate-up`
Expected: ไม่มี error · `make migrate-version` แสดง `16`

- [ ] **Step 4: ตรวจผล backfill ด้วยตา**

Run (แทนค่า DSN ตาม `.env` ของเครื่อง):
```bash
psql "$DB_URL" -c "SELECT leave_quota, count(*), bool_and(group_id IS NOT NULL) AS ทุกแถวมีกลุ่ม
                     FROM participant_profile GROUP BY leave_quota ORDER BY leave_quota;"
```
Expected: แถว `leave_quota = 0` ต้องมี `ทุกแถวมีกลุ่ม = t` และแถว `leave_quota = 1` ต้องมี `f`
(คนไม่มีกลุ่มได้ 1, คนมีกลุ่มได้ 0 — ถ้ากลับกันแสดงว่า `UPDATE` ใน up ผิดเงื่อนไข)

- [ ] **Step 5: ตรวจว่าย้อนกลับได้จริง**

Run: `make migrate-down N=1 && make migrate-up`
Expected: ทั้งสองคำสั่งผ่าน · `make migrate-version` กลับมาเป็น `16` (ถ้า down พัง จะ deploy แล้วถอยไม่ได้)

- [ ] **Step 6: Commit**

```bash
git add db/migrations/000016_group_leave_quota.up.sql db/migrations/000016_group_leave_quota.down.sql
git commit -m "feat(group): คอลัมน์ leave_quota + ตาราง group_membership_log"
```

---

### Task 2: `Leave` หักโควตาแบบ atomic

**Files:**
- Create: `internal/repository/wbw_group_repository_test.go`
- Modify: `internal/repository/wbw_group_repository.go:13-18` (บล็อก `var (...)` ของ error), `:146-185` (ฟังก์ชัน `Leave`)

**Interfaces:**
- Consumes: schema จาก Task 1
- Produces: `repository.ErrNoQuota` · `Leave(ctx, userID) (int, error)` เดิม (คืน group_id เดิม) แต่หักโควตาและเขียน log ให้ด้วย · helper เทส `openGroupTestDB(t) (*pgxpool.Pool, string)`, `setMembership(t, pool, uid, groupID *int, quota int)`, `freeGroupID(t, pool) int` ที่ Task 3 ใช้ต่อ

- [ ] **Step 1: เขียนเทสที่ต้องแดงก่อน**

สร้าง `internal/repository/wbw_group_repository_test.go`:

```go
package repository

import (
	"context"
	"errors"
	"os"
	"sync"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

/*
เทสชุดนี้ต้องมี Postgres จริง — ปลอมไม่ได้

สิ่งที่เทสคือพฤติกรรมของ SQL ล้วน ๆ: การหักโควตาต้องเกิดใน UPDATE statement เดียวกับที่เคลียร์
group_id (ไม่งั้นสองคำขอพร้อมกันหักเกินได้) และ FK/constraint ของ group_membership_log
ของปลอมไม่มีทางรู้เรื่องเหล่านี้ เทสกับของปลอมจึงเท่ากับไม่ได้เทสอะไรเลย

เปิดด้วย WBW_DB_TESTS=1 เท่านั้น · เขียนทับ group_id/leave_quota ของบัญชีทดสอบ 6931900011
แล้วคืนค่าเดิมให้ครบทุกครั้งใน Cleanup
*/

func openGroupTestDB(t *testing.T) (*pgxpool.Pool, string) {
	t.Helper()
	if os.Getenv("WBW_DB_TESTS") != "1" {
		t.Skip("ข้าม: ต้องมี Postgres จริง — ตั้ง WBW_DB_TESTS=1 เพื่อเปิด")
	}
	_ = godotenv.Load("../../.env")

	dsn := os.Getenv("WBW_TEST_DSN")
	if dsn == "" {
		dsn = "postgres://" + os.Getenv("DB_USER") + ":" + os.Getenv("DB_PASS") +
			"@" + os.Getenv("DB_HOST") + ":" + os.Getenv("DB_PORT") + "/" + os.Getenv("DB_NAME")
	}

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("เปิดสวิตช์ WBW_DB_TESTS=1 ไว้แล้วแต่ต่อฐานข้อมูลไม่ได้ (%v)", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		t.Fatalf("เปิดสวิตช์ WBW_DB_TESTS=1 ไว้แล้วแต่ ping ไม่ผ่าน (%v)", err)
	}
	t.Cleanup(pool.Close) // ลงทะเบียนก่อน = ทำงานทีหลังสุด (Cleanup เป็น LIFO) คืนค่าเสร็จค่อยปิด pool

	var uid string
	if err := pool.QueryRow(ctx,
		`SELECT user_id::text FROM wbw_user WHERE username = $1`, testUsername).Scan(&uid); err != nil {
		t.Fatalf("ไม่มีบัญชีทดสอบ %s ในฐานข้อมูลนี้ (%v)", testUsername, err)
	}

	var prevGroup *int
	var prevQuota int
	if err := pool.QueryRow(ctx,
		`SELECT group_id, leave_quota FROM participant_profile WHERE user_id = $1`, uid,
	).Scan(&prevGroup, &prevQuota); err != nil {
		t.Fatalf("อ่านสถานะเดิมของบัญชีทดสอบไม่ได้ (%v)", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		if _, err := pool.Exec(ctx,
			`UPDATE participant_profile SET group_id = $2, leave_quota = $3 WHERE user_id = $1`,
			uid, prevGroup, prevQuota); err != nil {
			t.Errorf("คืนสถานะเดิมของบัญชีทดสอบไม่สำเร็จ (%v)", err)
		}
		pool.Exec(ctx, `DELETE FROM group_membership_log WHERE user_id = $1`, uid)
		pool.Exec(ctx, `DELETE FROM group_chat_state WHERE user_id = $1`, uid)
	})

	return pool, uid
}

// setMembership — ตั้งสถานะตั้งต้นของบัญชีทดสอบ แล้วล้าง log เก่าทิ้ง ให้แต่ละเทสนับแถวได้ตรง ๆ
func setMembership(t *testing.T, pool *pgxpool.Pool, uid string, groupID *int, quota int) {
	t.Helper()
	ctx := context.Background()
	if _, err := pool.Exec(ctx,
		`UPDATE participant_profile SET group_id = $2, leave_quota = $3 WHERE user_id = $1`,
		uid, groupID, quota); err != nil {
		t.Fatalf("ตั้งสถานะตั้งต้นไม่สำเร็จ (%v)", err)
	}
	if _, err := pool.Exec(ctx, `DELETE FROM group_membership_log WHERE user_id = $1`, uid); err != nil {
		t.Fatalf("ล้าง log เก่าไม่สำเร็จ (%v)", err)
	}
}

// freeGroupID — กลุ่มที่ยังมีที่นั่งว่าง ใช้เป็นปลายทางของ join ในเทส
func freeGroupID(t *testing.T, pool *pgxpool.Pool) int {
	t.Helper()
	var gid int
	if err := pool.QueryRow(context.Background(),
		`SELECT group_id FROM participant_group WHERE member_count < capacity ORDER BY group_id LIMIT 1`,
	).Scan(&gid); err != nil {
		t.Fatalf("ไม่มีกลุ่มว่างให้ทดสอบ (%v)", err)
	}
	return gid
}

func membershipLogCount(t *testing.T, pool *pgxpool.Pool, uid, action string) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT count(*) FROM group_membership_log WHERE user_id = $1 AND action = $2`,
		uid, action).Scan(&n); err != nil {
		t.Fatalf("นับ log ไม่สำเร็จ (%v)", err)
	}
	return n
}

func readMembership(t *testing.T, pool *pgxpool.Pool, uid string) (*int, int) {
	t.Helper()
	var gid *int
	var quota int
	if err := pool.QueryRow(context.Background(),
		`SELECT group_id, leave_quota FROM participant_profile WHERE user_id = $1`, uid,
	).Scan(&gid, &quota); err != nil {
		t.Fatalf("อ่านสถานะไม่สำเร็จ (%v)", err)
	}
	return gid, quota
}

func TestLeaveWithoutQuotaIsRejected(t *testing.T) {
	pool, uid := openGroupTestDB(t)
	repo := NewWBWGroupRepository(pool)
	gid := freeGroupID(t, pool)
	setMembership(t, pool, uid, &gid, 0)

	_, err := repo.Leave(context.Background(), uid)
	if !errors.Is(err, ErrNoQuota) {
		t.Fatalf("อยากได้ ErrNoQuota แต่ได้ %v", err)
	}
	got, quota := readMembership(t, pool, uid)
	if got == nil || *got != gid {
		t.Errorf("ต้องยังอยู่กลุ่มเดิม %d แต่ได้ %v", gid, got)
	}
	if quota != 0 {
		t.Errorf("โควตาต้องคงที่ 0 แต่ได้ %d", quota)
	}
	if n := membershipLogCount(t, pool, uid, "leave"); n != 0 {
		t.Errorf("ห้ามมี log leave ตอนออกไม่สำเร็จ แต่มี %d แถว", n)
	}
}

func TestLeaveSpendsQuotaAndLogs(t *testing.T) {
	pool, uid := openGroupTestDB(t)
	repo := NewWBWGroupRepository(pool)
	gid := freeGroupID(t, pool)
	setMembership(t, pool, uid, &gid, 1)

	prev, err := repo.Leave(context.Background(), uid)
	if err != nil {
		t.Fatalf("ออกจากกลุ่มไม่สำเร็จ (%v)", err)
	}
	if prev != gid {
		t.Errorf("ต้องคืนกลุ่มเดิม %d แต่ได้ %d", gid, prev)
	}
	got, quota := readMembership(t, pool, uid)
	if got != nil {
		t.Errorf("ต้องไม่มีกลุ่มแล้ว แต่ยังอยู่กลุ่ม %d", *got)
	}
	if quota != 0 {
		t.Errorf("โควตาต้องเหลือ 0 แต่ได้ %d", quota)
	}

	var loggedGroup int
	var quotaAfter int
	if err := pool.QueryRow(context.Background(),
		`SELECT group_id, quota_after FROM group_membership_log
		  WHERE user_id = $1 AND action = 'leave' ORDER BY log_id DESC LIMIT 1`, uid,
	).Scan(&loggedGroup, &quotaAfter); err != nil {
		t.Fatalf("ไม่มีแถว log leave (%v)", err)
	}
	if loggedGroup != gid || quotaAfter != 0 {
		t.Errorf("log ต้องเป็น (กลุ่ม %d, quota_after 0) แต่ได้ (%d, %d)", gid, loggedGroup, quotaAfter)
	}
}

func TestLeaveWithoutGroupKeepsQuota(t *testing.T) {
	pool, uid := openGroupTestDB(t)
	repo := NewWBWGroupRepository(pool)
	setMembership(t, pool, uid, nil, 1)

	_, err := repo.Leave(context.Background(), uid)
	if !errors.Is(err, ErrNoGroup) {
		t.Fatalf("อยากได้ ErrNoGroup แต่ได้ %v", err)
	}
	if _, quota := readMembership(t, pool, uid); quota != 1 {
		t.Errorf("โควตาต้องไม่ถูกแตะ (1) แต่ได้ %d", quota)
	}
}

func TestLeaveConcurrentSpendsQuotaOnce(t *testing.T) {
	pool, uid := openGroupTestDB(t)
	repo := NewWBWGroupRepository(pool)
	gid := freeGroupID(t, pool)
	setMembership(t, pool, uid, &gid, 1)

	var wg sync.WaitGroup
	errs := make([]error, 2)
	for i := range errs {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, errs[i] = repo.Leave(context.Background(), uid)
		}(i)
	}
	wg.Wait()

	success := 0
	for _, err := range errs {
		if err == nil {
			success++
		} else if !errors.Is(err, ErrNoQuota) && !errors.Is(err, ErrNoGroup) {
			t.Errorf("ตัวที่ล้มเหลวต้องเป็น ErrNoQuota/ErrNoGroup แต่ได้ %v", err)
		}
	}
	if success != 1 {
		t.Errorf("ต้องสำเร็จแค่ 1 จาก 2 แต่สำเร็จ %d", success)
	}
	if _, quota := readMembership(t, pool, uid); quota != 0 {
		t.Errorf("โควตาห้ามติดลบหรือหักเกิน — ต้องเป็น 0 แต่ได้ %d", quota)
	}
	if n := membershipLogCount(t, pool, uid, "leave"); n != 1 {
		t.Errorf("ต้องมี log leave แถวเดียว แต่มี %d", n)
	}
}
```

- [ ] **Step 2: รันเทสให้เห็นว่าแดง**

Run: `WBW_DB_TESTS=1 go test ./internal/repository/ -run TestLeave -v`
Expected: compile error `undefined: ErrNoQuota` (ยังไม่ได้ประกาศ)

- [ ] **Step 3: เพิ่ม `ErrNoQuota`**

ใน `internal/repository/wbw_group_repository.go` บล็อก `var (...)` เดิม เพิ่มต่อท้าย:

```go
	// ErrNoQuota — สิทธิ์ออกจากกลุ่มหมดแล้ว (handler แปลงเป็น 409)
	ErrNoQuota = errors.New("no leave quota")
```

- [ ] **Step 4: เขียน `Leave` ใหม่**

แทนที่ฟังก์ชัน `Leave` เดิมทั้งฟังก์ชัน:

```go
// Leave — ออกจากกลุ่ม + หักโควตา 1 ครั้ง ในทรานแซกชันเดียว
//
// เงื่อนไข leave_quota > 0 อยู่ใน WHERE ของ UPDATE ตัวเดียวกับที่เคลียร์ group_id ตั้งใจ —
// ถ้าแยกเป็น SELECT เช็คก่อนแล้วค่อย UPDATE สองคำขอที่มาพร้อมกันจะอ่านเห็น quota = 1 ทั้งคู่
// แล้วหักคนละครั้งจน quota ติดลบและออกได้สองรอบ
//
// กลุ่มเดิมดึงมาจาก CTE ไม่ใช่ subquery ใน RETURNING — subquery ใน RETURNING ให้ค่าตาม
// snapshot semantics ซึ่งอ่านแล้วเดาไม่ออกว่าได้ค่าก่อนหรือหลัง UPDATE (เหตุผลเดียวกับที่โค้ดเดิม
// เลี่ยงไว้) · ลบ chat state ด้วย ไม่งั้นคนที่ออกไปแล้วยังถูกนับใน "อ่านแล้ว N"
func (r *WBWGroupRepository) Leave(ctx context.Context, userID string) (int, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)

	var prevGroup, quotaAfter int
	err = tx.QueryRow(ctx, `
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
		RETURNING t.group_id, p.leave_quota`, userID).Scan(&prevGroup, &quotaAfter)
	if errors.Is(err, pgx.ErrNoRows) {
		// ไม่โดนแถวไหนเลย — ต้องแยกว่าเพราะไม่มีกลุ่ม (ผลลัพธ์ที่ต้องการเกิดแล้ว) หรือสิทธิ์หมด (ปฏิเสธ)
		return 0, leaveBlockedReason(ctx, tx, userID)
	}
	if err != nil {
		return 0, err
	}

	if _, err := tx.Exec(ctx, `DELETE FROM group_chat_state WHERE user_id = $1`, userID); err != nil {
		return 0, err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO group_membership_log (user_id, group_id, action, quota_after)
		VALUES ($1, $2, 'leave', $3)`, userID, prevGroup, quotaAfter); err != nil {
		return 0, err
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return prevGroup, nil
}

// leaveBlockedReason — อ่านสถานะจริงในทรานแซกชันเดียวกัน เพื่อบอกสาเหตุที่ UPDATE ไม่โดนแถวไหน
func leaveBlockedReason(ctx context.Context, tx pgx.Tx, userID string) error {
	var groupID *int
	var quota int
	err := tx.QueryRow(ctx,
		`SELECT group_id, leave_quota FROM participant_profile WHERE user_id = $1`,
		userID).Scan(&groupID, &quota)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if groupID == nil {
		return ErrNoGroup
	}
	return ErrNoQuota
}
```

- [ ] **Step 5: รันเทสให้เขียว**

Run: `WBW_DB_TESTS=1 go test ./internal/repository/ -run TestLeave -v`
Expected: PASS ทั้ง 4 ตัว

- [ ] **Step 6: ตรวจว่าไม่ได้พังของเดิม**

Run: `go build ./... && go vet ./...`
Expected: ไม่มี output

- [ ] **Step 7: Commit**

```bash
git add internal/repository/wbw_group_repository.go internal/repository/wbw_group_repository_test.go
git commit -m "feat(group): หักโควตาตอนออกจากกลุ่มใน statement เดียวกับที่เคลียร์ group_id"
```

---

### Task 3: `Join` ปฏิเสธคนที่ยังมีกลุ่ม + เขียน log

**Files:**
- Modify: `internal/repository/wbw_group_repository.go:76-144` (ฟังก์ชัน `Join`) และบล็อก error
- Modify: `internal/repository/wbw_group_repository_test.go` (เพิ่มเทส ใช้ helper จาก Task 2)

**Interfaces:**
- Consumes: `openGroupTestDB`, `setMembership`, `freeGroupID`, `membershipLogCount`, `readMembership` จาก Task 2
- Produces: `repository.ErrAlreadyInGroup`

- [ ] **Step 1: เขียนเทสที่ต้องแดงก่อน**

ต่อท้าย `internal/repository/wbw_group_repository_test.go`:

```go
func TestJoinWhileInGroupIsRejected(t *testing.T) {
	pool, uid := openGroupTestDB(t)
	repo := NewWBWGroupRepository(pool)
	gid := freeGroupID(t, pool)
	setMembership(t, pool, uid, &gid, 1)

	// เป้าหมายคนละกลุ่มกับที่อยู่ — ถ้าไม่ปิดช่องนี้ จะย้ายกลุ่มได้โดยไม่เสียโควตาเลย
	var other int
	if err := pool.QueryRow(context.Background(),
		`SELECT group_id FROM participant_group
		  WHERE member_count < capacity AND group_id <> $1 ORDER BY group_id LIMIT 1`, gid,
	).Scan(&other); err != nil {
		t.Fatalf("ต้องมีกลุ่มว่างอีกกลุ่มเพื่อทดสอบ (%v)", err)
	}

	err := repo.Join(context.Background(), uid, other)
	if !errors.Is(err, ErrAlreadyInGroup) {
		t.Fatalf("อยากได้ ErrAlreadyInGroup แต่ได้ %v", err)
	}
	got, _ := readMembership(t, pool, uid)
	if got == nil || *got != gid {
		t.Errorf("ต้องยังอยู่กลุ่มเดิม %d แต่ได้ %v", gid, got)
	}
	if n := membershipLogCount(t, pool, uid, "join"); n != 0 {
		t.Errorf("ห้ามมี log join ตอนถูกปฏิเสธ แต่มี %d แถว", n)
	}
}

func TestJoinLogsWithoutSpendingQuota(t *testing.T) {
	pool, uid := openGroupTestDB(t)
	repo := NewWBWGroupRepository(pool)
	setMembership(t, pool, uid, nil, 1)
	gid := freeGroupID(t, pool)

	if err := repo.Join(context.Background(), uid, gid); err != nil {
		t.Fatalf("เข้ากลุ่มไม่สำเร็จ (%v)", err)
	}
	got, quota := readMembership(t, pool, uid)
	if got == nil || *got != gid {
		t.Errorf("ต้องอยู่กลุ่ม %d แต่ได้ %v", gid, got)
	}
	if quota != 1 {
		t.Errorf("การเข้ากลุ่มห้ามหักโควตา — ต้องเหลือ 1 แต่ได้ %d", quota)
	}

	var loggedGroup, quotaAfter int
	if err := pool.QueryRow(context.Background(),
		`SELECT group_id, quota_after FROM group_membership_log
		  WHERE user_id = $1 AND action = 'join' ORDER BY log_id DESC LIMIT 1`, uid,
	).Scan(&loggedGroup, &quotaAfter); err != nil {
		t.Fatalf("ไม่มีแถว log join (%v)", err)
	}
	if loggedGroup != gid || quotaAfter != 1 {
		t.Errorf("log ต้องเป็น (กลุ่ม %d, quota_after 1) แต่ได้ (%d, %d)", gid, loggedGroup, quotaAfter)
	}
}
```

- [ ] **Step 2: รันเทสให้เห็นว่าแดง**

Run: `WBW_DB_TESTS=1 go test ./internal/repository/ -run TestJoin -v`
Expected: compile error `undefined: ErrAlreadyInGroup`

- [ ] **Step 3: เพิ่ม `ErrAlreadyInGroup`**

```go
	// ErrAlreadyInGroup — ยังอยู่ในกลุ่มอื่น ต้องออกก่อนถึงจะเข้ากลุ่มใหม่ได้ (handler แปลงเป็น 409)
	ErrAlreadyInGroup = errors.New("already in a group")
```

- [ ] **Step 4: แก้ `Join`** (แก้ 2026-08-09 หลังรีวิว — ลำดับล็อกเปลี่ยนจากฉบับแรกของแผน)

**ลำดับล็อกต้องเป็น "แถวผู้ใช้ก่อน แล้วค่อยแถวกลุ่ม"** — ฉบับแรกของแผนสั่งกลับกัน (ล็อกกลุ่มก่อน)
ซึ่งสวนทางกับ `Leave` ที่ล็อกแถวผู้ใช้ก่อนแล้วปล่อยให้ trigger `trg_group_count`
(`db/migrations/000005_wbw.up.sql:229`) ไป `UPDATE participant_group` ต่อในทรานแซกชันเดียวกัน =
ล็อกแถวกลุ่มทีหลัง · ลำดับสวนกันแบบนั้นทำให้ join กับ leave ของ **ผู้ใช้คนเดียวกัน** ที่ชนกันพอดี
(กดรัว/client retry) เกิด `deadlock detected` แล้วโผล่เป็น 500

ดังนั้นให้ **ย้าย** บล็อกอ่าน/ล็อกแถวกลุ่ม (`SELECT capacity, member_count ... FOR UPDATE`)
ลงไปไว้ *หลัง* การเช็คผู้ใช้ แล้วโครงของ `Join` ช่วงต้นเป็นแบบนี้:

```go
	// ล็อกแถวผู้ใช้ก่อนแถวกลุ่มเสมอ — Leave ล็อกผู้ใช้ก่อนแล้ว trigger trg_group_count ค่อยไปแตะ
	// participant_group ต่อในทรานแซกชันเดียวกัน ถ้าที่นี่ล็อกกลุ่มก่อน สองทางจะจับล็อกสวนลำดับกัน
	// แล้ว join/leave ของคนเดียวกันที่ชนกันพอดีจะ deadlock (โผล่เป็น 500 ที่ผู้ใช้แก้อะไรไม่ได้)
	//
	// อยู่กลุ่มไหนอยู่แล้วห้ามย้ายตรง ๆ — ถ้ายอม จะเลี่ยงโควตาได้ทั้งหมดเพราะโควตาหักตอน leave เท่านั้น
	// (เดิมยอมให้เข้ากลุ่มเดิมซ้ำเพื่อรีเซ็ตจุดตัดประวัติแชท — ความสามารถนั้นหายไป ไม่มี UI ไหนเรียกใช้)
	var current *int
	if err := tx.QueryRow(ctx,
		`SELECT group_id FROM participant_profile WHERE user_id = $1 FOR UPDATE`,
		userID).Scan(&current); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		return err
	}
	if current != nil {
		return ErrAlreadyInGroup
	}

	// ล็อกแถวกลุ่มปลายทาง กันสองคนแย่งที่นั่งสุดท้ายพร้อมกัน
	var capacity, memberCount int
	err = tx.QueryRow(ctx,
		`SELECT capacity, member_count FROM participant_group WHERE group_id = $1 FOR UPDATE`,
		groupID).Scan(&capacity, &memberCount)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if memberCount >= capacity {
		return ErrGroupFull
	}
```

แล้วเปลี่ยน `UPDATE participant_profile ... WHERE user_id = $2` ให้คืนโควตากลับมาใช้เขียน log:

```go
	var quota int
	if err := tx.QueryRow(ctx,
		`UPDATE participant_profile SET group_id = $1, updated_at = now()
		  WHERE user_id = $2 RETURNING leave_quota`,
		groupID, userID).Scan(&quota); err != nil {
		return err
	}
```

และก่อน `return tx.Commit(ctx)` เพิ่ม:

```go
	// quota_after = ค่าปัจจุบัน (การเข้ากลุ่มไม่หักสิทธิ์) — เก็บไว้เพื่อให้ไทม์ไลน์อ่านแล้วเห็นสถานะ ณ ตอนนั้น
	if _, err := tx.Exec(ctx, `
		INSERT INTO group_membership_log (user_id, group_id, action, quota_after)
		VALUES ($1, $2, 'join', $3)`, userID, groupID, quota); err != nil {
		return err
	}
```

- [ ] **Step 5: รันเทสทั้งไฟล์ให้เขียว**

Run: `WBW_DB_TESTS=1 go test ./internal/repository/ -run "TestJoin|TestLeave" -v`
Expected: PASS ทั้ง 6 ตัว

- [ ] **Step 6: Commit**

```bash
git add internal/repository/wbw_group_repository.go internal/repository/wbw_group_repository_test.go
git commit -m "feat(group): ปฏิเสธการเข้ากลุ่มตอนยังมีกลุ่มอยู่ + เขียน log ทุกครั้งที่เข้ากลุ่ม"
```

---

### Task 4: Handler แปลง error เป็น 409

**Files:**
- Modify: `internal/handler/wbw_group_handler.go:47-68` (`Join`), `:70-90` (`Leave`)

**Interfaces:**
- Consumes: `repository.ErrNoQuota`, `repository.ErrAlreadyInGroup`
- Produces: สัญญา HTTP ที่ฝั่ง iOS และ dashboard จะยึด — `409 {"error": "..."}` สองข้อความนี้ตรงตัว

- [ ] **Step 1: เพิ่ม case ใน `Join`**

ใน `switch` ของ `Join` เพิ่มก่อน `case err != nil`:

```go
	case errors.Is(err, repository.ErrAlreadyInGroup):
		middleware.WriteError(w, http.StatusConflict, "ท่านอยู่ในกลุ่มอยู่แล้ว ต้องออกจากกลุ่มเดิมก่อน")
```

- [ ] **Step 2: เพิ่ม case ใน `Leave`**

```go
	case errors.Is(err, repository.ErrNoQuota):
		middleware.WriteError(w, http.StatusConflict, "สิทธิ์ออกจากกลุ่มหมดแล้ว")
```

`case errors.Is(err, repository.ErrNoGroup)` เดิมที่ตอบ 200 **คงไว้** — ออกทั้งที่ไม่มีกลุ่มคือผลลัพธ์
ที่ต้องการเกิดขึ้นแล้ว ไม่ใช่ความผิดพลาด (และห้ามหักโควตา ซึ่ง Task 2 การันตีไว้แล้ว)

- [ ] **Step 3: build + vet**

Run: `go build ./... && go vet ./...`
Expected: ไม่มี output

- [ ] **Step 4: ยิงจริงด้วย curl**

Run (ต้องมีเซิร์ฟเวอร์รันอยู่ + token ของบัญชีทดสอบที่ยังมีกลุ่ม):
```bash
curl -si -X POST localhost:8080/wbw/groups/1/join -H "Authorization: Bearer $TOKEN" | head -3
```
Expected: `HTTP/1.1 409` และ body มีข้อความ `ท่านอยู่ในกลุ่มอยู่แล้ว ต้องออกจากกลุ่มเดิมก่อน`

- [ ] **Step 5: Commit**

```bash
git add internal/handler/wbw_group_handler.go
git commit -m "feat(group): ตอบ 409 พร้อมเหตุผล เมื่อสิทธิ์ออกหมดหรือยังอยู่ในกลุ่ม"
```

---

### Task 5: ส่ง `leave_quota` ออกไปกับโปรไฟล์

**Files:**
- Modify: `internal/model/wbw_model.go:99-113` (`Participant`), `:114-150` (`ParticipantDetail`)
- Modify: `internal/repository/wbw_admin_repository.go:24-49` (`participantSelect` + `scanParticipant`), `:117-157` (`ParticipantDetail`)

**Interfaces:**
- Produces: `GET /wbw/me` และ `GET /wbw/admin/participants/{id}` มี key `leave_quota` (int) · `GET /wbw/admin/participants` ทุกแถวมี `leave_quota`

หมายเหตุสำคัญ: `/wbw/me` ของแอป iOS ใช้ `WBWAdminHandler.Me` ซึ่งคืน `model.ParticipantDetail`
ตัวเดียวกับที่ admin ใช้ — แก้ที่เดียวได้ทั้งสองทาง

- [ ] **Step 1: เพิ่ม field ใน model**

ใน `type Participant struct` ต่อท้าย `BloodType`:
```go
	LeaveQuota   int     `json:"leave_quota"`
```

ใน `type ParticipantDetail struct` ต่อท้าย `CheckedIn`:
```go
	LeaveQuota                int      `json:"leave_quota"`
```

- [ ] **Step 2: เพิ่มคอลัมน์ใน `participantSelect`**

เปลี่ยนบรรทัดสุดท้ายของ SELECT (`h.blood_type::text`) เป็น:
```sql
	       h.blood_type::text,
	       p.leave_quota
```

- [ ] **Step 3: เพิ่มตัวรับใน `scanParticipant`**

```go
	err := row.Scan(&p.ID, &p.StudentID, &p.Created, &p.Bib, &p.FirstName, &p.LastName,
		&p.ContactPhone, &p.SchoolID, &p.SchoolName, &p.Major, &p.Sex,
		&p.GroupID, &p.GroupNumber, &p.CheckedIn, &p.BloodType, &p.LeaveQuota)
```

- [ ] **Step 4: เพิ่มใน query ของ `ParticipantDetail`**

ต่อท้ายรายการ SELECT (หลัง `h.food_allergies, h.chronic_disease, h.medications`) เพิ่ม `,
p.leave_quota` และต่อท้าย `.Scan(...)` เพิ่ม `&d.LeaveQuota`

- [ ] **Step 5: build แล้วยิงจริง**

Run:
```bash
go build ./... && curl -s localhost:8080/wbw/me -H "Authorization: Bearer $TOKEN" | grep -o '"leave_quota":[0-9]*'
```
Expected: `"leave_quota":0` หรือ `1` ตามสถานะบัญชีนั้น — ถ้าไม่เจอ key แปลว่า scan ไม่ครบ

- [ ] **Step 6: Commit**

```bash
git add internal/model/wbw_model.go internal/repository/wbw_admin_repository.go
git commit -m "feat(admin): ส่ง leave_quota ไปกับโปรไฟล์และรายชื่อผู้เข้าร่วม"
```

---

### Task 6: admin ปรับสิทธิ์ได้ + log สองที่

**Files:**
- Modify: `internal/model/wbw_model.go:157-174` (`ParticipantPatch`)
- Modify: `internal/repository/wbw_admin_repository.go:159-240` (`UpdateParticipant`)
- Modify: `internal/service/wbw_admin_service.go` (ฟังก์ชัน `UpdateParticipant`)
- Modify: `internal/handler/wbw_admin_handler.go:206-232` (`UpdateParticipant`)

**Interfaces:**
- Consumes: `leave_quota` จาก Task 5
- Produces: `PATCH /wbw/admin/participants/{id}` รับ `leave_quota` (0–10) · `service.ErrBadQuota` · `UpdateParticipant(ctx, id, patch, actorID)` (เพิ่มพารามิเตอร์ที่ 4)

- [ ] **Step 1: เพิ่ม field ใน patch**

```go
	LeaveQuota            *int     `json:"leave_quota"`
```

- [ ] **Step 2: validate ที่ service**

ใน `internal/service/wbw_admin_service.go` เพิ่ม error และเช็คก่อนเรียก repository:

```go
// ErrBadQuota — โควตานอกช่วงที่ยอมรับ · เพดาน 10 กันพิมพ์พลาดเป็นหลักพันจนกติกาหายไปทั้งงาน
var ErrBadQuota = errors.New("leave quota out of range")
```

```go
	if patch.LeaveQuota != nil && (*patch.LeaveQuota < 0 || *patch.LeaveQuota > 10) {
		return nil, ErrBadQuota
	}
```

แล้วเปลี่ยน signature ให้รับ actor ต่อไปยัง repository:
```go
func (s *WBWAdminService) UpdateParticipant(ctx context.Context, id string, patch model.ParticipantPatch, actorID string) (*model.Participant, error)
```
(เรียก `s.repo.UpdateParticipant(ctx, id, patch, actorID)`)

- [ ] **Step 3: เขียนค่าและ log ที่ repository**

ใน `UpdateParticipant` เปลี่ยน signature เป็น
`func (r *WBWAdminRepository) UpdateParticipant(ctx context.Context, id string, patch model.ParticipantPatch, actorID string) (*model.Participant, error)`

เพิ่มบรรทัดในคำสั่ง `UPDATE participant_profile SET` (ต่อจาก `checked_in`):
```sql
		  leave_quota             = COALESCE($13, leave_quota),
```
และเพิ่ม `patch.LeaveQuota` ต่อท้ายรายการอาร์กิวเมนต์

หลังคำสั่งนั้น ก่อน block `HasHealthFields()` เพิ่ม:

```go
	// log เฉพาะตอนที่ค่านี้ถูกส่งมาจริง — PATCH ตัวอื่น (แก้ชื่อ, เช็คอิน) ไม่ควรสร้างแถวประวัติโควตาขึ้นมา
	// อ่าน group_id สดในทรานแซกชันเดียวกัน เพื่อให้ไทม์ไลน์บอกได้ว่าตอนถูกปรับ เขาอยู่กลุ่มไหน
	if patch.LeaveQuota != nil {
		if _, err := tx.Exec(ctx, `
			INSERT INTO group_membership_log (user_id, group_id, action, quota_after, actor_id)
			SELECT $1, group_id, 'quota_adjust', $2, $3
			  FROM participant_profile WHERE user_id = $1`,
			id, *patch.LeaveQuota, actorID); err != nil {
			return nil, err
		}
	}
```

- [ ] **Step 4: ส่ง actor จาก handler + log ฝั่ง admin**

ใน `UpdateParticipant` ของ handler เปลี่ยนการเรียกและเพิ่ม case:

```go
	aid, aname := actor(r)
	p, err := h.service.UpdateParticipant(r.Context(), id, patch, aid)
	switch {
	case errors.Is(err, service.ErrBadQuota):
		middleware.WriteError(w, http.StatusBadRequest, "สิทธิ์ออกจากกลุ่มต้องอยู่ระหว่าง 0 ถึง 10")
```

และใน `default:` เพิ่มบรรทัด log แยกเมื่อมีการปรับโควตา (ทำให้โผล่ในหน้า Logs ของ dashboard):

```go
		if patch.LeaveQuota != nil {
			h.service.Log(r.Context(), aid, aname, "ปรับสิทธิ์ออกกลุ่ม",
				fmt.Sprintf("%s → %d ครั้ง", derefStr(p.StudentID), *patch.LeaveQuota))
		}
```

(ย้ายบรรทัด `aid, aname := actor(r)` เดิมที่อยู่ใน `default:` ขึ้นไปข้างบนแทน ไม่ให้ประกาศซ้ำ
และเพิ่ม `"fmt"` ใน import ถ้ายังไม่มี)

- [ ] **Step 5: build แล้วยิงจริงทั้งทางถูกและทางผิด**

Run:
```bash
go build ./... && \
curl -si -X PATCH localhost:8080/wbw/admin/participants/$UID \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' \
  -d '{"leave_quota": 99}' | head -3
```
Expected: `HTTP/1.1 400` ข้อความ `สิทธิ์ออกจากกลุ่มต้องอยู่ระหว่าง 0 ถึง 10`

Run:
```bash
curl -s -X PATCH localhost:8080/wbw/admin/participants/$UID \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' \
  -d '{"leave_quota": 2}' | grep -o '"leave_quota":[0-9]*'
```
Expected: `"leave_quota":2`

- [ ] **Step 6: ตรวจว่า log ลงครบสองที่**

Run:
```bash
psql "$DB_URL" -c "SELECT action, quota_after, actor_id IS NOT NULL AS มีadmin
                     FROM group_membership_log ORDER BY log_id DESC LIMIT 1;"
psql "$DB_URL" -c "SELECT action, detail FROM admin_log ORDER BY log_id DESC LIMIT 1;"
```
Expected: แถวแรก `quota_adjust | 2 | t` · แถวสอง action `ปรับสิทธิ์ออกกลุ่ม`

- [ ] **Step 7: Commit**

```bash
git add internal/model/wbw_model.go internal/repository/wbw_admin_repository.go \
        internal/service/wbw_admin_service.go internal/handler/wbw_admin_handler.go
git commit -m "feat(admin): ปรับสิทธิ์ออกกลุ่มรายคนได้ พร้อมบันทึกทั้งสองตาราง"
```

---

### Task 7: ประวัติรายคนในหน้ารายละเอียด

**Files:**
- Modify: `internal/model/wbw_model.go` (เพิ่ม `MembershipLogEntry` + field ใน `ParticipantDetail`)
- Modify: `internal/repository/wbw_admin_repository.go:117-157` (`ParticipantDetail`)

**Interfaces:**
- Produces: `GET /wbw/admin/participants/{id}` มี key `membership_log` — array เรียงใหม่ไปเก่า สูงสุด 10 แถว
  แต่ละแถว `{action, group_id, group_number, quota_after, actor_name, created_at}` (dashboard Task ฝั่งเว็บใช้ตัวนี้)

- [ ] **Step 1: เพิ่ม model**

```go
// MembershipLogEntry — หนึ่งบรรทัดของประวัติเข้า/ออก/ปรับสิทธิ์ ในหน้ารายละเอียดผู้เข้าร่วม
// actor_name เป็น NULL แปลว่าผู้ใช้ทำเอง ไม่ใช่ admin ทำให้
type MembershipLogEntry struct {
	Action      string  `json:"action"`
	GroupID     *int    `json:"group_id"`
	GroupNumber *int    `json:"group_number"`
	QuotaAfter  int     `json:"quota_after"`
	ActorName   *string `json:"actor_name"`
	CreatedAt   string  `json:"created_at"`
}
```

ใน `ParticipantDetail` เพิ่มท้ายสุด:
```go
	MembershipLog             []MembershipLogEntry `json:"membership_log"`
```

- [ ] **Step 2: query ต่อท้ายใน `ParticipantDetail`**

หลังจาก `Scan(...)` สำเร็จ ก่อน `return &d, nil`:

```go
	// 10 แถวล่าสุดพอสำหรับคำถามที่หน้านี้ตอบ ("คนนี้ออกกี่ครั้ง ตอนไหน ใครปรับให้") — index
	// idx_gml_user (user_id, log_id DESC) ทำให้เป็นการอ่าน 10 แถวแรกตรง ๆ ไม่ใช่การเรียงทั้งตาราง
	rows, err := r.db.Query(ctx, `
		SELECT l.action, l.group_id, g.group_number, l.quota_after, a.display_name, l.created_at::text
		  FROM group_membership_log l
		  LEFT JOIN participant_group g ON g.group_id = l.group_id
		  LEFT JOIN wbw_user          a ON a.user_id  = l.actor_id
		 WHERE l.user_id = $1
		 ORDER BY l.log_id DESC
		 LIMIT 10`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	d.MembershipLog = []model.MembershipLogEntry{}
	for rows.Next() {
		var e model.MembershipLogEntry
		if err := rows.Scan(&e.Action, &e.GroupID, &e.GroupNumber, &e.QuotaAfter,
			&e.ActorName, &e.CreatedAt); err != nil {
			return nil, err
		}
		d.MembershipLog = append(d.MembershipLog, e)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
```

`d.MembershipLog = []...{}` ก่อนวนลูปจำเป็น — nil slice จะกลายเป็น `null` ใน JSON ซึ่งฝั่ง
dashboard ต้องเขียนเช็คเพิ่ม ส่วน `[]` ใช้ `.map()` ได้เลย

- [ ] **Step 3: build แล้วยิงจริง**

Run:
```bash
go build ./... && curl -s localhost:8080/wbw/admin/participants/$UID \
  -H "Authorization: Bearer $ADMIN_TOKEN" | python3 -m json.tool | grep -A 8 membership_log
```
Expected: array ที่มีแถว `quota_adjust` จาก Task 6 อยู่บนสุด

- [ ] **Step 4: ตรวจว่า `/wbw/me` ไม่พัง**

Run: `curl -s localhost:8080/wbw/me -H "Authorization: Bearer $TOKEN" | python3 -m json.tool | tail -20`
Expected: มี `membership_log` และ `leave_quota` · แอป iOS ปัจจุบัน decode `Me` แบบ field ที่ไม่รู้จัก
จะถูกข้าม จึงไม่พัง (ยืนยันด้วยการเปิดแอปเวอร์ชันปัจจุบันแล้วเข้าหน้าโปรไฟล์)

- [ ] **Step 5: Commit**

```bash
git add internal/model/wbw_model.go internal/repository/wbw_admin_repository.go
git commit -m "feat(admin): ส่งประวัติเข้า/ออกกลุ่ม 10 รายการล่าสุดไปกับรายละเอียดผู้เข้าร่วม"
```

---

### Task 8: เอกสารสัญญา API

**Files:**
- Modify: `~/Projects/wbw-ios-fontend/docs/backend-contract.md:44-56` (ตารางกลุ่ม)

**Interfaces:**
- Consumes: สัญญาจาก Task 4, 5, 6, 7

- [ ] **Step 1: แก้ตารางในเอกสาร**

- แถว `POST /wbw/groups/{id}/join` — เพิ่ม `409 {error}` เมื่ออยู่ในกลุ่มอยู่แล้ว
- แถว `POST /wbw/groups/leave` — เพิ่ม `409 {error}` เมื่อสิทธิ์หมด
- ส่วน `/wbw/me` — เพิ่ม `leave_quota` และ `membership_log` ในรายการ key
- ส่วนตารางฐานข้อมูล — เพิ่ม `group_membership_log` และคอลัมน์ `participant_profile.leave_quota`

- [ ] **Step 2: Commit (ใน repo iOS ไม่ใช่ SUS)**

```bash
cd ~/Projects/wbw-ios-fontend
git add docs/backend-contract.md
git commit -m "docs: สัญญา API ของโควตาออกจากกลุ่ม"
```

---

## เช็คก่อนปิดแผนนี้

- [ ] `WBW_DB_TESTS=1 go test ./internal/...` ผ่านทั้งหมด (ไม่ใช่แค่ชุดใหม่)
- [ ] `go build ./... && go vet ./...` สะอาด
- [ ] บัญชีทดสอบ `6931900011` กลับมาอยู่สถานะเดิม (`SELECT group_id, leave_quota ...`)
- [ ] แอป iOS เวอร์ชันปัจจุบัน (ยังไม่แก้) ยังใช้งานได้: เปิดแอป เข้าหน้าโปรไฟล์ เข้าหน้ากลุ่ม ไม่มีจอว่าง
