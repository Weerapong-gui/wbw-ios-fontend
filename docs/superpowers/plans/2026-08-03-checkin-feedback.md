# Check-in Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a staff member scans a participant into a base, the participant gets a notification that opens a short feedback form naming that base — and if they miss the notification, it waits for them in the notification list.

**Architecture:** "Pending" is never stored: a base is awaiting feedback when a `check_in` row exists and a `checkin_feedback` row does not, answered by a `LEFT JOIN`. The existing `GET /wbw/me/progress` response grows the feedback fields rather than gaining a sibling endpoint, so the app's one poll drives both the growing tree and the pending list. Delivery is FCM push as the primary path with a 60 s foreground poll as the safety net, because push dies entirely on builds without a Firebase plist and on any user who declines notifications.

**Tech Stack:** Go 1.x + chi + pgx + Postgres (SUS backend); SwiftUI + XCTest, iOS 18.0 deployment target, XcodeGen (iOS); FCM v1 over HTTP.

**Spec:** `docs/superpowers/specs/2026-08-02-checkin-feedback-design.md`

## Global Constraints

- **Two repos, both ours.** iOS is `/Users/park/wbw-ios-fontend`. SUS is `/Users/park/Student-Union-Server`. Commit in each separately. There is no rule against modifying SUS.
- Create the working branches before Task 1:
  - SUS: `git checkout -b feat/wbw-feedback` from `feat/wbw-progress` (which holds this feature's prerequisite endpoint and is **not yet merged**).
  - iOS: `git checkout -b feature/checkin-feedback` from `feature/forest-3d` (same reason).
- **`WBW/Config.swift` is permanently dirty and must never be staged.** It currently holds `case susLan` plus `Config.backend = .susLan` pointing at a LAN address for device testing. Check `git status --short` before every commit: it must show ` M WBW/Config.swift` and nothing unexpected.
- **Do not change any existing endpoint's response shape** beyond the additive fields this plan names. The companion website `~/su-wbw-website` and a shipped Android app both read this backend. `~/su-wbw-website` is read-only for this work.
- iOS deployment target is **18.0**. Swift comments in the iOS repo are **Thai**; Go comments in SUS are **Thai**. Match both.
- Colours come only from `WBW/Config.swift`'s theme extension — `wbwCream` `#DEC684`, `wbwInk` `#2B2B2B`, `wbwGold` `#C99A1F`, `wbwGreen` `#40916C` — plus the cream `Color(red: 250/255, green: 247/255, blue: 240/255)` already used in `NotificationsView`. Do not invent named colours.
- New `.swift` files under `WBW/` are picked up by XcodeGen's `sources: - WBW`. **Run `xcodegen generate` after creating any new file**, before building.
- `WBW.xcodeproj/` is gitignored. Never `git add` it — the command fails on an ignored path.
- iOS build: `cd /Users/park/wbw-ios-fontend && xcodegen generate && xcodebuild -scheme WBW -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build`
- iOS test: `cd /Users/park/wbw-ios-fontend && xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17'`
- **`xcodebuild build` without `clean` will serve stale bundled resources from DerivedData and still print `** BUILD SUCCEEDED **`.** Measured on this machine during the previous plan. Whenever you verify appearance, build with `clean` or a fresh `-derivedDataPath`. A screenshot after a plain incremental build is not evidence.
- Xcode runs take minutes — use a Bash timeout up to `600000` ms.
- `timeout`/`gtimeout` are **not installed**. Never run `xcrun simctl spawn booted log stream` unbounded — background it and `kill` it after a `sleep`. An agent on the previous plan stalled for 600 s that way.
- There is **no UI tap tooling**. Drive state with the existing `#if DEBUG` launch arguments (`-uitestToken`, `-uitestUser`, `-uitestRole`, `-uitestTab`, `-uitestChat`, `-uitestProgress`, `-uitestTabSequence`) or programmatically. Add new `-uitest*` hooks in the same `#if DEBUG` style when you need a transition.
- SUS local stack: `cd /Users/park/Student-Union-Server && docker compose up -d` → API on `127.0.0.1:8080`, Postgres container `postgres-db`, database `sudb`, user `admin`. Inspect with `docker exec postgres-db psql -U admin -d sudb -c '<sql>'`.
- **SUS has no database-backed test harness and this plan does not add one.** Its Go tests are pure unit tests (`internal/service/wbw_push_service_test.go`, `internal/model/booth_model_test.go`, `internal/model/wbw_progress_model_test.go`). SQL is verified with `curl` against the running local stack, with the expected JSON written into the step. Never describe a query as "tested" when it was only compiled. JSON contract shapes **are** unit-testable and this plan does test them — follow `internal/model/wbw_progress_model_test.go`, added by the previous plan for exactly this purpose.
- Migrations are files under `db/migrations/`, applied by the compose stack's `migrate/migrate`. Write them idempotent (`IF NOT EXISTS`, `ON CONFLICT DO NOTHING`) and always ship the matching `.down.sql`.
- Stage only explicit paths. Never `git add -A` or `git commit -a`. Interactive git flags (`-i`, `git add -p`) are not supported in this environment.

---

## Environment setup (do this once, before Task 1)

- [ ] **Step A: Create both branches**

```bash
cd /Users/park/Student-Union-Server && git checkout feat/wbw-progress && git checkout -b feat/wbw-feedback && git status --short
cd /Users/park/wbw-ios-fontend && git checkout feature/forest-3d && git checkout -b feature/checkin-feedback && git status --short
```

Expected: SUS clean on the new branch; iOS shows only ` M WBW/Config.swift`.

- [ ] **Step B: Start the stack and confirm the prerequisite endpoint**

```bash
cd /Users/park/Student-Union-Server && docker compose up -d
until curl -sf http://localhost:8080/wbw/notifications/public >/dev/null; do sleep 1; done
TOKEN=$(curl -s -X POST http://localhost:8080/wbw/auth/login -H 'content-type: application/json' \
  -d '{"username":"6931900011","password":"chatv2test"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -s http://localhost:8080/wbw/me/progress -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

Expected: a `total` and a `checked_in` array. This endpoint is what Task 2 extends; if it 404s, the branch base is wrong.

Save the token somewhere you can re-read — shell variables do not survive between tool calls.

---

## Task 1: Schema and the `ref_id` plumbing

**Files:**
- Create: `db/migrations/000012_checkin_feedback.up.sql`, `db/migrations/000012_checkin_feedback.down.sql`
- Modify: `internal/model/wbw_model.go` (append types; add `RefID` to two existing structs)
- Modify: `internal/repository/wbw_notification_repository.go` (carry `ref_id` through every notification read/write)
- Test: `internal/model/wbw_feedback_model_test.go` (new)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - table `checkin_feedback` and column `notification.ref_id`
  - `model.CheckinFeedback{ID int64; CheckpointID int; Rating int; Comment *string; CreatedAt string}`
  - `model.FeedbackRequest{ClientID string; CheckpointID int; Rating int; Comment *string; DeviceTime string}`
  - `model.NotificationRequest.RefID *string` and `model.Notification.RefID *string`, both `json:"ref_id"`

- [ ] **Step 1: Write the migration**

`db/migrations/000012_checkin_feedback.up.sql`:

```sql
-- ความเห็นต่อฐานที่เช็คอินแล้ว
--
-- ไม่มีคอลัมน์ "ยังไม่ตอบ" โดยตั้งใจ — pending = มีแถวใน check_in แต่ไม่มีแถวที่นี่
-- ตอบด้วย LEFT JOIN สถานะจึงเพี้ยนจากความจริงไม่ได้ตามนิยาม
CREATE TABLE IF NOT EXISTS checkin_feedback (
  id             BIGSERIAL PRIMARY KEY,
  participant_id UUID NOT NULL REFERENCES app_user(user_id)         ON DELETE CASCADE,
  checkpoint_id  INT  NOT NULL REFERENCES checkpoint(checkpoint_id) ON DELETE CASCADE,
  rating         SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 3), -- 1 ไม่ชอบ · 2 เฉยๆ · 3 ชอบ
  comment        TEXT,
  -- ส่งซ้ำตอนเน็ตหลุดต้องไม่เกิดแถวซ้ำ — ทรงเดียวกับ check_in และ group_message
  client_id      UUID NOT NULL UNIQUE,
  device_time    TIMESTAMPTZ NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uniq_feedback_participant_checkpoint UNIQUE (participant_id, checkpoint_id)
);
CREATE INDEX IF NOT EXISTS idx_feedback_checkpoint ON checkin_feedback(checkpoint_id);

-- ทางเดียวที่หน้าแจ้งเตือนจะรู้ว่าแถวนี้ชี้ไปฐานไหน
-- ทางเลี่ยงคือ "ตอนแตะให้เดาจากฐานที่ยังไม่ตอบตัวเก่าสุด" ซึ่งพังทันทีที่มี 2 ฐานค้าง
ALTER TABLE notification ADD COLUMN IF NOT EXISTS ref_id TEXT;
```

`db/migrations/000012_checkin_feedback.down.sql`:

```sql
ALTER TABLE notification DROP COLUMN IF EXISTS ref_id;
DROP INDEX IF EXISTS idx_feedback_checkpoint;
DROP TABLE IF EXISTS checkin_feedback;
```

- [ ] **Step 2: Apply and confirm the schema**

```bash
cd /Users/park/Student-Union-Server && docker compose up -d --build
sleep 5
docker exec postgres-db psql -U admin -d sudb -c '\d checkin_feedback'
docker exec postgres-db psql -U admin -d sudb -c "SELECT column_name FROM information_schema.columns WHERE table_name='notification' AND column_name='ref_id'"
```

Expected: the table description lists all eight columns and both unique constraints; the second query returns one row, `ref_id`.

If `migrate` reports a dirty version, read `docker compose logs su-migrate` — do not hand-patch the database, fix the migration and re-run.

- [ ] **Step 3: Write the failing model test**

Create `internal/model/wbw_feedback_model_test.go`:

```go
package model

import (
	"encoding/json"
	"strings"
	"testing"
)

// สัญญา JSON ที่ฝั่ง iOS decode — เทสไว้เพราะ SUS ไม่มี harness เทส DB
// รูป JSON เป็นสิ่งเดียวที่เทสได้โดยไม่ต้องต่อฐานข้อมูล และเป็นสิ่งที่พังเงียบที่สุด
func TestFeedbackRequestDecodesSnakeCase(t *testing.T) {
	raw := `{"client_id":"6f9d1e7a-0000-4000-8000-000000000001","checkpoint_id":3,
	         "rating":2,"comment":"สนุกดี","device_time":"2026-08-29T09:12:03Z"}`
	var req FeedbackRequest
	if err := json.Unmarshal([]byte(raw), &req); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if req.CheckpointID != 3 || req.Rating != 2 {
		t.Fatalf("got checkpoint=%d rating=%d", req.CheckpointID, req.Rating)
	}
	if req.Comment == nil || *req.Comment != "สนุกดี" {
		t.Fatalf("comment = %v", req.Comment)
	}
}

func TestFeedbackRequestAllowsMissingComment(t *testing.T) {
	var req FeedbackRequest
	if err := json.Unmarshal([]byte(`{"client_id":"x","checkpoint_id":1,"rating":3,"device_time":"t"}`), &req); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if req.Comment != nil {
		t.Fatalf("comment should be nil, got %v", *req.Comment)
	}
}

// ref_id ต้องอยู่ใน JSON เสมอ แม้เป็น null — แอปอ่านคีย์นี้เพื่อรู้ว่าแจ้งเตือนชี้ไปฐานไหน
// ถ้าใส่ omitempty คีย์จะหายไปทั้งดวงตอนเป็น nil และ decoder ฝั่ง iOS จะเจอ key ไม่ครบ
func TestNotificationAlwaysCarriesRefIDKey(t *testing.T) {
	out, err := json.Marshal(Notification{ID: 1, Type: "announcement", Title: "t"})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if !strings.Contains(string(out), `"ref_id":null`) {
		t.Fatalf(`expected "ref_id":null in %s`, out)
	}

	ref := "7"
	out, _ = json.Marshal(Notification{ID: 2, Type: "checkin_feedback", Title: "t", RefID: &ref})
	if !strings.Contains(string(out), `"ref_id":"7"`) {
		t.Fatalf(`expected "ref_id":"7" in %s`, out)
	}
}
```

- [ ] **Step 4: Run the test to verify it fails**

```bash
cd /Users/park/Student-Union-Server && go test ./internal/model/ -run 'Feedback|RefID' 2>&1 | tail -10
```

Expected: compile failure — `undefined: FeedbackRequest` and `unknown field RefID in struct literal`.

- [ ] **Step 5: Add the model types**

Append to `internal/model/wbw_model.go`:

```go
/* ---------- ความเห็นต่อฐาน ---------- */

// FeedbackRequest — สิ่งที่แอปส่งมาตอนกดส่งความเห็น
//
// ClientID ทำให้ส่งซ้ำตอนเน็ตหลุดไม่เกิดแถวซ้ำ (unique ใน DB) — แอปสร้างเองก่อนยิง
// และใช้ค่าเดิมทุกครั้งที่ retry
type FeedbackRequest struct {
	ClientID     string  `json:"client_id"`
	CheckpointID int     `json:"checkpoint_id"`
	Rating       int     `json:"rating"` // 1 ไม่ชอบ · 2 เฉยๆ · 3 ชอบ
	Comment      *string `json:"comment"`
	DeviceTime   string  `json:"device_time"`
}

// CheckinFeedback — ความเห็นหนึ่งอันที่บันทึกแล้ว
type CheckinFeedback struct {
	ID           int64   `json:"id"`
	CheckpointID int     `json:"checkpoint_id"`
	Rating       int     `json:"rating"`
	Comment      *string `json:"comment"`
	CreatedAt    string  `json:"created_at"`
}
```

Then add `RefID *string \`json:"ref_id"\`` to **both** `Notification` (after `AudienceID`) and `NotificationRequest` (after `AudienceID`). **Do not add `omitempty`** — the key must always be present.

- [ ] **Step 6: Carry `ref_id` through the notification repository**

`internal/repository/wbw_notification_repository.go` has four SQL statements that name notification columns: `Create` (INSERT … RETURNING), `ListSent`, `ListForUser`, and `ListPublic`. Add `ref_id` to the column list and the `RETURNING`/`SELECT` list of each, add `n.ref_id` to the scan target list in the matching order, and add the parameter to `Create`'s argument list.

Read each statement and its `Scan` call together before editing — a column added to `SELECT` without a matching `Scan` target fails at runtime, not at compile time, and only for that one endpoint.

`ListPublic` is the unauthenticated announcements feed the website reads. Adding a nullable column to its response is additive and safe, but **confirm the website still parses it** in Step 8.

- [ ] **Step 7: Run the test to verify it passes**

```bash
cd /Users/park/Student-Union-Server && go build ./... && go test ./internal/model/ -v -run 'Feedback|RefID' 2>&1 | tail -15
```

Expected: `go build` silent, three tests `PASS`.

- [ ] **Step 8: Verify no existing endpoint broke**

```bash
cd /Users/park/Student-Union-Server && docker compose up -d --build && sleep 6
TOKEN=$(curl -s -X POST http://localhost:8080/wbw/auth/login -H 'content-type: application/json' \
  -d '{"username":"6931900011","password":"chatv2test"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
echo "--- notifications (authed) ---"
curl -s http://localhost:8080/wbw/notifications -H "Authorization: Bearer $TOKEN" | python3 -m json.tool | head -20
echo "--- public announcements ---"
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/wbw/notifications/public
echo "--- progress still fine ---"
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/wbw/me/progress -H "Authorization: Bearer $TOKEN"
```

Expected: the authed list returns rows each carrying `"ref_id": null`; both status codes are `200`.

- [ ] **Step 9: Commit**

```bash
cd /Users/park/Student-Union-Server
git add db/migrations/000012_checkin_feedback.up.sql db/migrations/000012_checkin_feedback.down.sql \
        internal/model/wbw_model.go internal/model/wbw_feedback_model_test.go \
        internal/repository/wbw_notification_repository.go
git commit -m "feat(wbw): ตาราง checkin_feedback + คอลัมน์ ref_id บน notification"
```

---

## Task 2: Extend `/wbw/me/progress` with the feedback fields

**Files:**
- Modify: `internal/model/wbw_model.go` (`CheckinProgressItem`)
- Modify: `internal/repository/wbw_checkpoint_repository.go` (`Progress`)
- Modify: `internal/model/wbw_progress_model_test.go`

**Interfaces:**
- Consumes: `checkin_feedback` from Task 1.
- Produces: each `checked_in` entry additionally carries `activity_name` (string, nullable), `answered` (bool), `rating` (int, nullable), `comment` (string, nullable). Task 7 decodes exactly these keys.

- [ ] **Step 1: Extend the model**

In `internal/model/wbw_model.go`, `CheckinProgressItem` becomes:

```go
type CheckinProgressItem struct {
	CheckpointID int     `json:"checkpoint_id"`
	Name         string  `json:"name"`
	ActivityName *string `json:"activity_name"`
	Sequence     *int    `json:"sequence"`
	At           string  `json:"at"`
	// Answered = มีแถวใน checkin_feedback แล้ว · ไม่ได้เก็บสถานะไว้ที่ไหน คำนวณจาก LEFT JOIN
	Answered bool    `json:"answered"`
	Rating   *int    `json:"rating"`
	Comment  *string `json:"comment"`
}
```

- [ ] **Step 2: Extend the query**

In `internal/repository/wbw_checkpoint_repository.go`, `Progress`'s second query becomes:

```go
	rows, err := r.db.Query(ctx, `
		SELECT c.checkpoint_id, c.name, c.activity_name, c.sequence, ci.server_received_at,
		       (f.id IS NOT NULL) AS answered, f.rating, f.comment
		  FROM check_in ci
		  JOIN checkpoint c ON c.checkpoint_id = ci.checkpoint_id
		  LEFT JOIN checkin_feedback f
		         ON f.participant_id = ci.participant_id
		        AND f.checkpoint_id  = ci.checkpoint_id
		 WHERE ci.participant_id = $1::uuid AND c.requires_checkin
		 ORDER BY c.sequence NULLS LAST, c.checkpoint_id`, participantID)
```

and the scan becomes:

```go
		if err := rows.Scan(&it.CheckpointID, &it.Name, &it.ActivityName, &it.Sequence, &at,
			&it.Answered, &it.Rating, &it.Comment); err != nil {
			return nil, err
		}
```

The `LEFT JOIN` must match on **both** participant and checkpoint. Matching on checkpoint alone would show one participant another's answer.

- [ ] **Step 3: Extend the contract test**

Append to `internal/model/wbw_progress_model_test.go`:

```go
// ฐานที่ยังไม่ตอบต้องส่ง answered=false พร้อม rating/comment เป็น null ไม่ใช่คีย์หาย —
// แอปแยก "ยังไม่ตอบ" กับ "ตอบแล้ว" จากคีย์นี้
func TestProgressItemCarriesFeedbackKeysWhenUnanswered(t *testing.T) {
	out, err := json.Marshal(CheckinProgressItem{CheckpointID: 1, Name: "ฐาน", At: "t"})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	for _, key := range []string{`"answered":false`, `"rating":null`, `"comment":null`, `"activity_name":null`} {
		if !strings.Contains(string(out), key) {
			t.Fatalf("expected %s in %s", key, out)
		}
	}
}

func TestProgressItemCarriesAnswerWhenAnswered(t *testing.T) {
	rating := 3
	comment := "ดีมาก"
	activity := "ปลูกป่า"
	out, _ := json.Marshal(CheckinProgressItem{
		CheckpointID: 5, Name: "จุดปลูก", ActivityName: &activity, At: "t",
		Answered: true, Rating: &rating, Comment: &comment,
	})
	for _, key := range []string{`"answered":true`, `"rating":3`, `"comment":"ดีมาก"`, `"activity_name":"ปลูกป่า"`} {
		if !strings.Contains(string(out), key) {
			t.Fatalf("expected %s in %s", key, out)
		}
	}
}
```

Add `"strings"` to that file's imports if it is not already there.

- [ ] **Step 4: Run tests and rebuild**

```bash
cd /Users/park/Student-Union-Server && go build ./... && go test ./internal/model/ 2>&1 | tail -5 && docker compose up -d --build && sleep 6
```

Expected: build silent, `ok  su-server/internal/model`, stack back up.

- [ ] **Step 5: Verify against the live stack**

```bash
TOKEN=$(curl -s -X POST http://localhost:8080/wbw/auth/login -H 'content-type: application/json' \
  -d '{"username":"6931900011","password":"chatv2test"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -s http://localhost:8080/wbw/me/progress -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

Expected: every entry now has `activity_name`, `answered: false`, `rating: null`, `comment: null`. `total` is unchanged.

- [ ] **Step 6: Verify the join with a hand-inserted answer, then undo it**

```bash
UID_=$(docker exec postgres-db psql -U admin -d sudb -tAc "SELECT user_id FROM app_user WHERE username='6931900011'" | tr -d '[:space:]')
docker exec postgres-db psql -U admin -d sudb -c \
  "INSERT INTO checkin_feedback (participant_id, checkpoint_id, rating, comment, client_id, device_time)
   VALUES ('$UID_', 1, 3, 'ทดสอบ', gen_random_uuid(), now())"
curl -s http://localhost:8080/wbw/me/progress -H "Authorization: Bearer $TOKEN" | python3 -m json.tool | head -25
docker exec postgres-db psql -U admin -d sudb -c "DELETE FROM checkin_feedback WHERE participant_id='$UID_'"
```

Expected: checkpoint 1 comes back `"answered": true, "rating": 3, "comment": "ทดสอบ"` while the others stay `false`/`null`; after the delete it returns to `false`.

- [ ] **Step 7: Commit**

```bash
cd /Users/park/Student-Union-Server
git add internal/model/wbw_model.go internal/model/wbw_progress_model_test.go \
        internal/repository/wbw_checkpoint_repository.go
git commit -m "feat(wbw): /me/progress บอกด้วยว่าฐานไหนตอบความเห็นแล้ว"
```

---

## Task 3: `POST /wbw/me/feedback`

**Files:**
- Create: `internal/repository/wbw_feedback_repository.go`, `internal/service/wbw_feedback_service.go`, `internal/handler/wbw_feedback_handler.go`
- Modify: `cmd/main.go`

**Interfaces:**
- Consumes: Task 1's table and models.
- Produces: `POST /wbw/me/feedback`, participant-authenticated. Task 8 calls it.

| Case | Response |
|---|---|
| New answer | `201` with the stored `CheckinFeedback` |
| Same `client_id` resent | `200` with the existing row — a retry, not an error |
| Same base, different `client_id` | `409` with the existing answer |
| Participant never checked in there | `403` |
| `rating` outside 1–3, or a missing field | `400` |

- [ ] **Step 1: Write the repository**

Create `internal/repository/wbw_feedback_repository.go`:

```go
package repository

import (
	"context"
	"errors"

	"su-server/internal/model"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotCheckedIn — ส่งความเห็นฐานที่ยังไม่ได้ไป
var ErrNotCheckedIn = errors.New("not checked in at this checkpoint")

// ErrAlreadyAnswered — ฐานนี้ตอบไปแล้วด้วย client_id อื่น
type ErrAlreadyAnswered struct{ Existing *model.CheckinFeedback }

func (e ErrAlreadyAnswered) Error() string { return "already answered" }

type WBWFeedbackRepository struct {
	db *pgxpool.Pool
}

func NewWBWFeedbackRepository(db *pgxpool.Pool) *WBWFeedbackRepository {
	return &WBWFeedbackRepository{db: db}
}

const feedbackCols = `id, checkpoint_id, rating, comment, created_at`

func scanFeedback(row pgx.Row) (*model.CheckinFeedback, error) {
	var f model.CheckinFeedback
	if err := row.Scan(&f.ID, &f.CheckpointID, &f.Rating, &f.Comment, &f.CreatedAt); err != nil {
		return nil, err
	}
	return &f, nil
}

// Submit — บันทึกความเห็น
//
// ลำดับสำคัญ: เช็ค client_id เดิมก่อน (retry ตอนเน็ตหลุด ต้องได้แถวเดิมไม่ใช่ 409)
// แล้วค่อยเช็คว่าเคยเช็คอินฐานนี้จริงไหม แล้วค่อย insert
func (r *WBWFeedbackRepository) Submit(ctx context.Context, participantID string, req model.FeedbackRequest) (*model.CheckinFeedback, bool, error) {
	// 1. client_id เดิม = ส่งซ้ำ คืนแถวเดิม ไม่ใช่ error
	existing, err := scanFeedback(r.db.QueryRow(ctx,
		`SELECT `+feedbackCols+` FROM checkin_feedback WHERE client_id = $1::uuid`, req.ClientID))
	if err == nil {
		return existing, false, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, false, err
	}

	// 2. ต้องเคยเช็คอินฐานนี้จริง
	var checkedIn bool
	if err := r.db.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM check_in WHERE participant_id = $1::uuid AND checkpoint_id = $2)`,
		participantID, req.CheckpointID).Scan(&checkedIn); err != nil {
		return nil, false, err
	}
	if !checkedIn {
		return nil, false, ErrNotCheckedIn
	}

	// 3. insert · ชนคู่ (participant, checkpoint) = ตอบไปแล้วด้วย client_id อื่น
	created, err := scanFeedback(r.db.QueryRow(ctx, `
		INSERT INTO checkin_feedback (participant_id, checkpoint_id, rating, comment, client_id, device_time)
		VALUES ($1::uuid, $2, $3, $4, $5::uuid, $6::timestamptz)
		RETURNING `+feedbackCols,
		participantID, req.CheckpointID, req.Rating, req.Comment, req.ClientID, req.DeviceTime))
	if err != nil {
		if IsPGCode(err, "23505") {
			prev, qerr := scanFeedback(r.db.QueryRow(ctx,
				`SELECT `+feedbackCols+` FROM checkin_feedback
				  WHERE participant_id = $1::uuid AND checkpoint_id = $2`,
				participantID, req.CheckpointID))
			if qerr != nil {
				return nil, false, qerr
			}
			return nil, false, ErrAlreadyAnswered{Existing: prev}
		}
		return nil, false, err
	}
	return created, true, nil
}

// ListAll — ความเห็นทั้งหมด สำหรับแอดมิน
func (r *WBWFeedbackRepository) ListAll(ctx context.Context) ([]model.AdminFeedbackRow, error) {
	rows, err := r.db.Query(ctx, `
		SELECT f.id, f.checkpoint_id, c.name, c.activity_name,
		       f.participant_id::text, COALESCE(p.first_name,''), COALESCE(p.last_name,''),
		       p.bib_number, f.rating, f.comment, f.created_at
		  FROM checkin_feedback f
		  JOIN checkpoint c ON c.checkpoint_id = f.checkpoint_id
		  LEFT JOIN participant_profile p ON p.user_id = f.participant_id
		 ORDER BY f.created_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	list := []model.AdminFeedbackRow{}
	for rows.Next() {
		var a model.AdminFeedbackRow
		if err := rows.Scan(&a.ID, &a.CheckpointID, &a.CheckpointName, &a.ActivityName,
			&a.ParticipantID, &a.FirstName, &a.LastName, &a.Bib,
			&a.Rating, &a.Comment, &a.CreatedAt); err != nil {
			return nil, err
		}
		list = append(list, a)
	}
	return list, rows.Err()
}

// SummaryByCheckpoint — นับคะแนนต่อฐาน
func (r *WBWFeedbackRepository) SummaryByCheckpoint(ctx context.Context) ([]model.FeedbackSummary, error) {
	rows, err := r.db.Query(ctx, `
		SELECT c.checkpoint_id, c.name,
		       count(*) FILTER (WHERE f.rating = 1)::int,
		       count(*) FILTER (WHERE f.rating = 2)::int,
		       count(*) FILTER (WHERE f.rating = 3)::int
		  FROM checkpoint c
		  LEFT JOIN checkin_feedback f ON f.checkpoint_id = c.checkpoint_id
		 WHERE c.requires_checkin
		 GROUP BY c.checkpoint_id, c.name
		 ORDER BY c.sequence NULLS LAST, c.checkpoint_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	list := []model.FeedbackSummary{}
	for rows.Next() {
		var s model.FeedbackSummary
		if err := rows.Scan(&s.CheckpointID, &s.Name, &s.Dislike, &s.Neutral, &s.Like); err != nil {
			return nil, err
		}
		list = append(list, s)
	}
	return list, rows.Err()
}
```

`IsPGCode` already exists in this package — it is what `wbw_staff_repository.go` uses to detect the duplicate check-in.

- [ ] **Step 2: Add the admin response models**

Append to `internal/model/wbw_model.go`:

```go
// AdminFeedbackRow — ความเห็นหนึ่งแถวสำหรับแอดมิน (ผูกชื่อผู้ตอบ ตามที่ตกลงไว้ใน spec)
type AdminFeedbackRow struct {
	ID             int64   `json:"id"`
	CheckpointID   int     `json:"checkpoint_id"`
	CheckpointName string  `json:"checkpoint_name"`
	ActivityName   *string `json:"activity_name"`
	ParticipantID  string  `json:"participant_id"`
	FirstName      string  `json:"first_name"`
	LastName       string  `json:"last_name"`
	Bib            *int    `json:"bib"`
	Rating         int     `json:"rating"`
	Comment        *string `json:"comment"`
	CreatedAt      string  `json:"created_at"`
}

// FeedbackSummary — นับคะแนนต่อฐาน
type FeedbackSummary struct {
	CheckpointID int    `json:"checkpoint_id"`
	Name         string `json:"name"`
	Dislike      int    `json:"dislike"`
	Neutral      int    `json:"neutral"`
	Like         int    `json:"like"`
}

// AdminFeedbackResponse — สิ่งที่ GET /wbw/admin/feedback คืน
type AdminFeedbackResponse struct {
	Items   []AdminFeedbackRow `json:"items"`
	Summary []FeedbackSummary  `json:"summary"`
}
```

- [ ] **Step 3: Write the service**

Create `internal/service/wbw_feedback_service.go`:

```go
package service

import (
	"context"
	"errors"
	"strings"

	"su-server/internal/model"
	"su-server/internal/repository"
)

var (
	ErrBadRating       = errors.New("rating must be 1..3")
	ErrMissingClientID = errors.New("missing client_id")
)

type WBWFeedbackService struct {
	repo *repository.WBWFeedbackRepository
}

func NewWBWFeedbackService(repo *repository.WBWFeedbackRepository) *WBWFeedbackService {
	return &WBWFeedbackService{repo: repo}
}

// Submit — ตรวจค่าที่รับได้ก่อนแตะฐานข้อมูล · คืน (แถว, สร้างใหม่ไหม, error)
func (s *WBWFeedbackService) Submit(ctx context.Context, participantID string, req model.FeedbackRequest) (*model.CheckinFeedback, bool, error) {
	if strings.TrimSpace(req.ClientID) == "" {
		return nil, false, ErrMissingClientID
	}
	if req.Rating < 1 || req.Rating > 3 {
		return nil, false, ErrBadRating
	}
	if req.Comment != nil {
		trimmed := strings.TrimSpace(*req.Comment)
		if trimmed == "" {
			req.Comment = nil // ช่องว่างล้วน = ไม่ได้เขียนอะไร
		} else {
			req.Comment = &trimmed
		}
	}
	return s.repo.Submit(ctx, participantID, req)
}

func (s *WBWFeedbackService) AdminList(ctx context.Context) (*model.AdminFeedbackResponse, error) {
	items, err := s.repo.ListAll(ctx)
	if err != nil {
		return nil, err
	}
	summary, err := s.repo.SummaryByCheckpoint(ctx)
	if err != nil {
		return nil, err
	}
	return &model.AdminFeedbackResponse{Items: items, Summary: summary}, nil
}
```

- [ ] **Step 4: Write the handler**

Create `internal/handler/wbw_feedback_handler.go`:

```go
package handler

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"su-server/internal/middleware"
	"su-server/internal/model"
	"su-server/internal/repository"
	"su-server/internal/service"
)

type WBWFeedbackHandler struct {
	service *service.WBWFeedbackService
}

func NewWBWFeedbackHandler(s *service.WBWFeedbackService) *WBWFeedbackHandler {
	return &WBWFeedbackHandler{service: s}
}

// Submit POST /wbw/me/feedback — ผู้เข้าร่วมส่งความเห็นต่อฐานที่เช็คอินแล้ว
func (h *WBWFeedbackHandler) Submit(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFrom(r.Context())
	if claims == nil {
		middleware.WriteError(w, http.StatusUnauthorized, "ต้องล็อกอินก่อน")
		return
	}
	var req model.FeedbackRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, "รูปแบบข้อมูลไม่ถูกต้อง")
		return
	}

	saved, created, err := h.service.Submit(r.Context(), claims.Subject, req)
	switch {
	case err == nil:
		if created {
			middleware.WriteJSON(w, http.StatusCreated, saved)
		} else {
			// client_id เดิม = retry ตอนเน็ตหลุด ไม่ใช่ error
			middleware.WriteJSON(w, http.StatusOK, saved)
		}
	case errors.Is(err, service.ErrBadRating), errors.Is(err, service.ErrMissingClientID):
		middleware.WriteError(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, repository.ErrNotCheckedIn):
		middleware.WriteError(w, http.StatusForbidden, "ยังไม่ได้เช็คอินฐานนี้")
	default:
		var dup repository.ErrAlreadyAnswered
		if errors.As(err, &dup) {
			middleware.WriteJSON(w, http.StatusConflict, dup.Existing)
			return
		}
		slog.Error("submit feedback failed", "err", err)
		middleware.WriteError(w, http.StatusInternalServerError, "ส่งความเห็นไม่สำเร็จ")
	}
}

// AdminList GET /wbw/admin/feedback — ความเห็นทั้งหมด + สรุปต่อฐาน
func (h *WBWFeedbackHandler) AdminList(w http.ResponseWriter, r *http.Request) {
	out, err := h.service.AdminList(r.Context())
	if err != nil {
		slog.Error("list feedback failed", "err", err)
		middleware.WriteError(w, http.StatusInternalServerError, "โหลดความเห็นไม่สำเร็จ")
		return
	}
	middleware.WriteJSON(w, http.StatusOK, out)
}
```

- [ ] **Step 5: Wire both routes**

In `cmd/main.go`, beside the other WBW service construction (near `wbwProgressService`):

```go
	wbwFeedbackRepo := repository.NewWBWFeedbackRepository(pool)
	wbwFeedbackService := service.NewWBWFeedbackService(wbwFeedbackRepo)
	wbwFeedbackHandler := handler.NewWBWFeedbackHandler(wbwFeedbackService)
```

Beside `r.With(requireAuth).Get("/me/progress", …)`:

```go
		// ความเห็นต่อฐาน — ผู้เข้าร่วมส่งของตัวเอง
		r.With(requireAuth).Post("/me/feedback", wbwFeedbackHandler.Submit)
```

And inside the existing `r.Group(func(r chi.Router) { r.Use(requireAuth, requireAdmin)` block in `/admin`:

```go
				r.Get("/feedback", wbwFeedbackHandler.AdminList)
```

- [ ] **Step 6: Build and restart**

```bash
cd /Users/park/Student-Union-Server && go build ./... && go vet ./... && docker compose up -d --build && sleep 6 && echo up
```

Expected: both silent, `up`.

- [ ] **Step 7: Verify all five cases against the live stack**

```bash
API=http://localhost:8080/wbw
TOKEN=$(curl -s -X POST $API/auth/login -H 'content-type: application/json' \
  -d '{"username":"6931900011","password":"chatv2test"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
CID=$(uuidgen | tr 'A-Z' 'a-z')
post() { curl -s -o /tmp/fb.json -w '%{http_code}' -X POST $API/me/feedback \
  -H "Authorization: Bearer $TOKEN" -H 'content-type: application/json' -d "$1"; echo " <- $(head -c 200 /tmp/fb.json)"; }

echo "1. new answer (expect 201)"
post "{\"client_id\":\"$CID\",\"checkpoint_id\":2,\"rating\":3,\"comment\":\"ดีมาก\",\"device_time\":\"2026-08-29T09:00:00Z\"}"
echo "2. same client_id resent (expect 200, same row)"
post "{\"client_id\":\"$CID\",\"checkpoint_id\":2,\"rating\":3,\"comment\":\"ดีมาก\",\"device_time\":\"2026-08-29T09:00:00Z\"}"
echo "3. same base, new client_id (expect 409 + existing answer)"
post "{\"client_id\":\"$(uuidgen | tr 'A-Z' 'a-z')\",\"checkpoint_id\":2,\"rating\":1,\"device_time\":\"2026-08-29T09:00:00Z\"}"
echo "4. base never checked into (expect 403) — checkpoint 8"
post "{\"client_id\":\"$(uuidgen | tr 'A-Z' 'a-z')\",\"checkpoint_id\":8,\"rating\":2,\"device_time\":\"2026-08-29T09:00:00Z\"}"
echo "5. rating out of range (expect 400)"
post "{\"client_id\":\"$(uuidgen | tr 'A-Z' 'a-z')\",\"checkpoint_id\":3,\"rating\":9,\"device_time\":\"2026-08-29T09:00:00Z\"}"
```

Expected exactly: `201`, `200` with the same `id` as case 1, `409` carrying `"rating":3`, `403`, `400`.

Case 4 assumes the test account has **not** checked into checkpoint 8 — confirm first with `curl $API/me/progress` and pick a checkpoint id that is genuinely absent from `checked_in`.

- [ ] **Step 8: Verify the admin endpoint, then clean up**

```bash
docker exec postgres-db psql -U admin -d sudb -tAc \
  "UPDATE app_user SET role='admin' WHERE username='6931900011' RETURNING role"
ATOKEN=$(curl -s -X POST $API/auth/login -H 'content-type: application/json' \
  -d '{"username":"6931900011","password":"chatv2test"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -s $API/admin/feedback -H "Authorization: Bearer $ATOKEN" | python3 -m json.tool | head -30
docker exec postgres-db psql -U admin -d sudb -tAc \
  "UPDATE app_user SET role='participant' WHERE username='6931900011' RETURNING role"
```

Expected: `items` carries the answer from Step 7 with the respondent's name, and `summary` lists every activity checkpoint with counts. **The role must be restored to `participant`** — later tasks depend on this account being a participant.

- [ ] **Step 9: Commit**

```bash
cd /Users/park/Student-Union-Server
git add internal/repository/wbw_feedback_repository.go internal/service/wbw_feedback_service.go \
        internal/handler/wbw_feedback_handler.go internal/model/wbw_model.go cmd/main.go
git commit -m "feat(wbw): POST /me/feedback + GET /admin/feedback"
```

---

## Task 4: Notification and push when a participant is scanned

**Files:**
- Modify: `internal/repository/wbw_staff_repository.go` (return the participant id; add a per-user push target query)
- Modify: `internal/model/wbw_chat_model.go` (`CheckinResult`)
- Modify: `internal/service/wbw_push_service.go` (`SendUserPush`)
- Modify: `internal/service/wbw_staff_service.go` (create the notification, fire the push)
- Modify: `cmd/main.go` (inject the two dependencies)

**Interfaces:**
- Consumes: Task 1's `ref_id`.
- Produces: after a **first** check-in, a `notification` row with `type='checkin_feedback'`, `audience='user'`, `audience_id=<participant uuid>`, `ref_id=<checkpoint id>`, and an FCM message carrying `{"type":"checkin_feedback","checkpoint_id":"N"}`. Task 10 routes on those.

- [ ] **Step 1: Make the check-in return who was checked in**

`CheckinResult` currently carries only display fields. The service cannot address a notification without the participant's id.

In `internal/model/wbw_chat_model.go`, add to `CheckinResult`:

```go
	// ParticipantID — ไม่ส่งออกใน JSON (`-`) เพราะจอเจ้าหน้าที่ไม่ได้ใช้ และ id ผู้ใช้
	// ไม่ควรรั่วไปอยู่ในมือเครื่องอื่นโดยไม่จำเป็น · service ใช้ยิงแจ้งเตือนให้ถูกคน
	ParticipantID string `json:"-"`
```

In `internal/repository/wbw_staff_repository.go`'s `Checkin`, set `out.ParticipantID = userID` immediately after the participant lookup succeeds and before the medical-flag query.

- [ ] **Step 2: Add a per-user push target query**

Append to `internal/repository/wbw_staff_repository.go`, beside `ChatPushTargets`:

```go
// UserPushTargets — เครื่องทั้งหมดของผู้ใช้คนเดียว
//
// badge เป็น 0 เสมอ: จำนวนที่ยังไม่อ่านของแจ้งเตือนคิดคนละทางกับแชท และแอปนับ
// badge กระดิ่งเองจาก /notifications อยู่แล้ว
func (r *WBWDeviceRepository) UserPushTargets(ctx context.Context, userID string) ([]PushTarget, error) {
	rows, err := r.db.Query(ctx,
		`SELECT token FROM device_token WHERE user_id = $1::uuid`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	list := []PushTarget{}
	for rows.Next() {
		var t PushTarget
		if err := rows.Scan(&t.Token); err != nil {
			return nil, err
		}
		list = append(list, t)
	}
	return list, rows.Err()
}
```

- [ ] **Step 3: Add `SendUserPush`**

In `internal/service/wbw_push_service.go`, add beside `SendChatPush`. Read `sendChat` first and reuse its token acquisition, per-device send loop, and dead-token cleanup — do not write a second copy of that logic.

```go
// SendUserPush — push เข้าเครื่องของผู้ใช้คนเดียว · fire-and-forget
//
// ต้องไม่ทำให้คนเรียกช้าหรือพัง: เจ้าหน้าที่ยืนอยู่หน้าคิวตอนสแกน ถ้า FCM ช้า
// หรือล่มแล้วลากให้ /staff/checkin ตอบช้า คิวก็ยาวขึ้นทันที
// context.WithoutCancel เพราะ ctx ของ request ถูกยกเลิกทันทีที่ตอบ response เสร็จ
func (s *WBWPushService) SendUserPush(ctx context.Context, userID, title, body string, data map[string]string) {
	if s.tokens == nil {
		return
	}
	detached := context.WithoutCancel(ctx)
	go func() {
		c, cancel := context.WithTimeout(detached, pushTimeout)
		defer cancel()
		if err := s.sendUser(c, userID, title, body, data); err != nil {
			slog.Error("ส่ง push รายคนไม่สำเร็จ", "user_id", userID, "err", err)
		}
	}()
}
```

Write `sendUser` mirroring `sendChat`: fetch targets with `s.repo.UserPushTargets`, return early when empty, get one token for the whole round, then send per device and delete tokens FCM reports dead — exactly the classification `sendOne` already implements and `wbw_push_service_test.go` already covers.

- [ ] **Step 4: Give the staff service its new dependencies**

`internal/service/wbw_staff_service.go`:

```go
type WBWStaffService struct {
	repo *repository.WBWStaffRepository
	noti *WBWNotificationService
	push *WBWPushService
}

func NewWBWStaffService(repo *repository.WBWStaffRepository, noti *WBWNotificationService, push *WBWPushService) *WBWStaffService {
	return &WBWStaffService{repo: repo, noti: noti, push: push}
}
```

At the end of `Checkin`, after `res, err := s.repo.Checkin(...)` succeeds:

```go
	// เช็คอินสำเร็จครั้งแรกเท่านั้นถึงเด้ง — สแกนซ้ำคนเดิมต้องไม่แจ้งเตือนซ้ำ
	if !res.AlreadyCheckedIn && res.ParticipantID != "" {
		s.notifyFeedback(ctx, res.ParticipantID, *req.CheckpointID)
	}
	return res, nil
```

And the helper, in the same file:

```go
// notifyFeedback — แจ้งผู้เข้าร่วมว่าเช็คอินแล้วและขอความเห็นต่อฐาน
//
// ทั้งแถว notification และ push ต้องไม่ทำให้ /staff/checkin พัง: บันทึกแถวไม่สำเร็จ
// ก็แค่ log แล้วไปต่อ (การเช็คอินสำเร็จไปแล้วจริงๆ) · แอปยังเจอฐานที่ยังไม่ตอบได้
// จาก poll /me/progress อยู่ดี แจ้งเตือนเป็นทางลัด ไม่ใช่ทางเดียว
func (s *WBWStaffService) notifyFeedback(ctx context.Context, participantID string, checkpointID int) {
	name := s.repo.CheckpointName(ctx, checkpointID)
	title := "เช็คอิน " + name + " แล้ว"
	body := "แตะเพื่อให้คะแนนฐานนี้"
	typ, audience, level := "checkin_feedback", "user", "info"
	ref := strconv.Itoa(checkpointID)

	if _, err := s.noti.Create(ctx, model.NotificationRequest{
		Type: &typ, Title: title, Body: &body, Level: &level,
		Audience: &audience, AudienceID: &participantID, RefID: &ref,
	}, participantID); err != nil {
		slog.Error("สร้างแจ้งเตือนขอความเห็นไม่สำเร็จ", "err", err)
	}

	s.push.SendUserPush(ctx, participantID, title, body, map[string]string{
		"type":          "checkin_feedback",
		"checkpoint_id": ref,
	})
}
```

Add `CheckpointName(ctx, id) string` to `WBWStaffRepository` — one `SELECT name FROM checkpoint WHERE checkpoint_id = $1`, returning `""` on any error so a lookup failure degrades the title rather than skipping the notification.

Add the imports these need: `log/slog`, `strconv`, and `su-server/internal/model`.

- [ ] **Step 5: Update the constructor call**

In `cmd/main.go`, `wbwStaffService := service.NewWBWStaffService(wbwStaffRepo)` becomes:

```go
	wbwStaffService := service.NewWBWStaffService(wbwStaffRepo, wbwNotiService, wbwPushService)
```

Both already exist above that line — check the ordering compiles and move the construction if not.

- [ ] **Step 6: Build and restart**

```bash
cd /Users/park/Student-Union-Server && go build ./... && go vet ./... && go test ./... 2>&1 | tail -8 && docker compose up -d --build && sleep 6 && echo up
```

Expected: build and vet silent, all packages `ok`, `up`.

- [ ] **Step 7: Verify a scan produces exactly one notification**

Push cannot be exercised here — there is no Firebase service account in the local environment, so `s.tokens` is nil and `SendUserPush` returns immediately. That is expected; verify the notification row, which is the part that works without FCM.

```bash
API=http://localhost:8080/wbw
UID_=$(docker exec postgres-db psql -U admin -d sudb -tAc "SELECT user_id FROM app_user WHERE username='6931900011'" | tr -d '[:space:]')
QR=$(docker exec postgres-db psql -U admin -d sudb -tAc "SELECT qr_token FROM participant_profile WHERE user_id='$UID_'" | tr -d '[:space:]')
# ลบเช็คอินฐาน 7 ออกก่อน เพื่อให้สแกนรอบนี้เป็น "ครั้งแรก" จริง
docker exec postgres-db psql -U admin -d sudb -c "DELETE FROM check_in WHERE participant_id='$UID_' AND checkpoint_id=7"
docker exec postgres-db psql -U admin -d sudb -c "DELETE FROM notification WHERE type='checkin_feedback' AND audience_id='$UID_'"

# เครื่องนี้มีบัญชีสิทธิ์สูงแค่ `admin` ตัวเดียวและไม่รู้รหัสผ่าน จึงยืมบัญชีทดสอบใบที่สอง
# มาเป็นเจ้าหน้าที่ชั่วคราว · /wbw/staff/checkin ไม่ได้บังคับว่าเจ้าหน้าที่ต้องประจำฐานนั้น
# (repo insert ตรงๆ ไม่แตะตาราง checkpoint_staff) เจ้าหน้าที่คนไหนก็สแกนฐานไหนก็ได้
docker exec postgres-db psql -U admin -d sudb -tAc \
  "UPDATE app_user SET role='staff' WHERE username='6931900012' RETURNING role"
STOKEN=$(curl -s -X POST $API/auth/login -H 'content-type: application/json' \
  -d '{"username":"6931900012","password":"chatv2test"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')

echo "--- first scan ---"
curl -s -X POST $API/staff/checkin -H "Authorization: Bearer $STOKEN" -H 'content-type: application/json' \
  -d "{\"checkpoint_id\":7,\"qr_token\":\"$QR\"}" | python3 -m json.tool
echo "--- second scan (already_checked_in) ---"
curl -s -X POST $API/staff/checkin -H "Authorization: Bearer $STOKEN" -H 'content-type: application/json' \
  -d "{\"checkpoint_id\":7,\"qr_token\":\"$QR\"}" | python3 -m json.tool
echo "--- notification rows for this participant (expect exactly 1) ---"
docker exec postgres-db psql -U admin -d sudb -c \
  "SELECT id, type, audience, ref_id, title FROM notification WHERE type='checkin_feedback' AND audience_id='$UID_'"
```

Expected: the first scan returns `"already_checked_in": false`, the second `true`, and the table shows **exactly one** row with `ref_id = 7` and a title naming the base.

**Then restore the borrowed account — later tasks and the other test flows expect it to be a participant:**

```bash
docker exec postgres-db psql -U admin -d sudb -tAc \
  "UPDATE app_user SET role='participant' WHERE username='6931900012' RETURNING role"
```

Expected: `participant`. Run this even if the scan failed — leaving a stray staff account changes what `RootView` shows for that login.

- [ ] **Step 8: Confirm the participant can see it**

```bash
TOKEN=$(curl -s -X POST $API/auth/login -H 'content-type: application/json' \
  -d '{"username":"6931900011","password":"chatv2test"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -s $API/notifications -H "Authorization: Bearer $TOKEN" | python3 -c '
import sys,json
for n in json.load(sys.stdin):
    if n["type"] == "checkin_feedback":
        print(n["id"], n["type"], n["ref_id"], n["title"])'
```

Expected: one line with the checkpoint id in `ref_id`. This proves `audience='user'` targeting and the `ref_id` plumbing work end to end.

- [ ] **Step 9: Commit**

```bash
cd /Users/park/Student-Union-Server
git add internal/repository/wbw_staff_repository.go internal/model/wbw_chat_model.go \
        internal/service/wbw_push_service.go internal/service/wbw_staff_service.go cmd/main.go
git commit -m "feat(wbw): สแกนเช็คอินแล้วแจ้งเตือนผู้เข้าร่วมให้มาให้คะแนนฐาน"
```

---

## Task 5: iOS — decode the new fields and derive the pending list

**Files:**
- Modify: `WBW/Models.swift`
- Modify: `WBW/CheckinProgressStore.swift`
- Test: `WBWTests/CheckinProgressStoreTests.swift`

**Interfaces:**
- Consumes: Task 2's response shape.
- Produces:
  - `CheckinProgressItem` gains `activityName: String?`, `answered: Bool`, `rating: Int?`, `comment: String?`
  - `CheckinProgress.pending: [CheckinProgressItem]` — checked in, not answered, newest first
  - `CheckinProgressStore.item(checkpointId:) -> CheckinProgressItem?`
- Tasks 8, 9 and 11 read all of these.

- [ ] **Step 1: Write the failing tests**

Append to `WBWTests/CheckinProgressStoreTests.swift`:

```swift
    // MARK: - ฟิลด์ความเห็น (spec 2)

    private func decodeProgress(_ json: String) throws -> CheckinProgress {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(CheckinProgress.self, from: json.data(using: .utf8)!)
    }

    func testDecodesFeedbackFields() throws {
        let p = try decodeProgress("""
        {"total": 8, "checked_in": [
          {"checkpoint_id": 1, "name": "ฐานหนึ่ง", "activity_name": "กิจกรรมหนึ่ง", "sequence": 1,
           "at": "2026-08-29T09:00:00Z", "answered": true, "rating": 3, "comment": "ดีมาก"},
          {"checkpoint_id": 2, "name": "ฐานสอง", "activity_name": null, "sequence": 2,
           "at": "2026-08-29T10:00:00Z", "answered": false, "rating": null, "comment": null}
        ]}
        """)
        XCTAssertEqual(p.checkedIn[0].activityName, "กิจกรรมหนึ่ง")
        XCTAssertTrue(p.checkedIn[0].answered)
        XCTAssertEqual(p.checkedIn[0].rating, 3)
        XCTAssertNil(p.checkedIn[1].activityName)
        XCTAssertFalse(p.checkedIn[1].answered)
        XCTAssertNil(p.checkedIn[1].rating)
    }

    /// ฐานที่ยังไม่ตอบ เรียงใหม่สุดก่อน — toast เด้งของฐานล่าสุด
    func testPendingIsUnansweredNewestFirst() throws {
        let p = try decodeProgress("""
        {"total": 8, "checked_in": [
          {"checkpoint_id": 1, "name": "เก่าสุด", "activity_name": null, "sequence": 1,
           "at": "2026-08-29T09:00:00Z", "answered": false, "rating": null, "comment": null},
          {"checkpoint_id": 2, "name": "ตอบแล้ว", "activity_name": null, "sequence": 2,
           "at": "2026-08-29T10:00:00Z", "answered": true, "rating": 2, "comment": null},
          {"checkpoint_id": 3, "name": "ใหม่สุด", "activity_name": null, "sequence": 3,
           "at": "2026-08-29T11:00:00Z", "answered": false, "rating": null, "comment": null}
        ]}
        """)
        XCTAssertEqual(p.pending.map(\.checkpointId), [3, 1])
    }

    func testPendingEmptyWhenAllAnswered() throws {
        let p = try decodeProgress("""
        {"total": 8, "checked_in": [
          {"checkpoint_id": 1, "name": "ฐาน", "activity_name": null, "sequence": 1,
           "at": "2026-08-29T09:00:00Z", "answered": true, "rating": 1, "comment": null}
        ]}
        """)
        XCTAssertTrue(p.pending.isEmpty)
    }

    /// stage ต้องนับทุกฐานที่เช็คอิน ไม่ใช่เฉพาะที่ยังไม่ตอบ — ต้นไม้ไม่หดตอนตอบความเห็น
    func testStageUnaffectedByAnswering() throws {
        let p = try decodeProgress("""
        {"total": 8, "checked_in": [
          {"checkpoint_id": 1, "name": "a", "activity_name": null, "sequence": 1,
           "at": "t", "answered": true, "rating": 3, "comment": null},
          {"checkpoint_id": 2, "name": "b", "activity_name": null, "sequence": 2,
           "at": "t", "answered": false, "rating": null, "comment": null}
        ]}
        """)
        XCTAssertEqual(p.stage, 2)
    }

    @MainActor
    func testItemLookupByCheckpoint() throws {
        let store = CheckinProgressStore()
        store.cache(try decodeProgress("""
        {"total": 8, "checked_in": [
          {"checkpoint_id": 5, "name": "จุดปลูก", "activity_name": "ปลูกป่า", "sequence": 5,
           "at": "t", "answered": false, "rating": null, "comment": null}
        ]}
        """), backend: .susLocal)
        XCTAssertEqual(store.item(checkpointId: 5)?.name, "จุดปลูก")
        XCTAssertNil(store.item(checkpointId: 99))
        UserDefaults.standard.removeObject(forKey: CheckinProgressStore.cacheKey(for: .susLocal))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WBWTests/CheckinProgressStoreTests 2>&1 | tail -20
```

Expected: compile failure — no `activityName`, no `answered`, no `pending`, no `item(checkpointId:)`.

- [ ] **Step 3: Extend the model**

In `WBW/Models.swift`:

```swift
struct CheckinProgressItem: Codable, Equatable {
    let checkpointId: Int
    let name: String
    let activityName: String?
    let sequence: Int?
    let at: String
    /// ตอบความเห็นฐานนี้แล้วหรือยัง — backend คำนวณจาก LEFT JOIN ไม่ได้เก็บสถานะไว้
    let answered: Bool
    let rating: Int?
    let comment: String?
}
```

and add to `CheckinProgress`:

```swift
    /// ฐานที่เช็คอินแล้วแต่ยังไม่ได้ให้ความเห็น · ใหม่สุดก่อน (toast เด้งของฐานล่าสุด)
    var pending: [CheckinProgressItem] {
        checkedIn.filter { !$0.answered }.sorted { $0.at > $1.at }
    }
```

`stage` stays `checkedIn.count` — answering must not shrink the tree.

- [ ] **Step 4: Add the lookup**

In `WBW/CheckinProgressStore.swift`:

```swift
    /// หาฐานหนึ่งจาก progress ที่มีอยู่ — หน้า feedback ใช้อ่านชื่อฐาน/กิจกรรม
    /// และคำตอบเดิม (ถ้าเคยตอบแล้ว) โดยไม่ต้องยิงเน็ตซ้ำ
    func item(checkpointId: Int) -> CheckinProgressItem? {
        progress?.checkedIn.first { $0.checkpointId == checkpointId }
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WBWTests/CheckinProgressStoreTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`, 11 tests (the 6 from the previous plan plus these 5).

- [ ] **Step 6: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/Models.swift WBW/CheckinProgressStore.swift WBWTests/CheckinProgressStoreTests.swift
git commit -m "feat(feedback): อ่านสถานะความเห็นจาก /me/progress + คิดรายการฐานที่ยังไม่ตอบ"
```

---

## Task 6: iOS — submit API and the offline outbox

**Files:**
- Modify: `WBW/APIClient.swift`
- Create: `WBW/Feedback/FeedbackOutbox.swift`
- Create: `WBW/Feedback/FeedbackStore.swift`
- Create: `WBWTests/FeedbackOutboxTests.swift`

**Interfaces:**
- Consumes: Task 3's endpoint.
- Produces:
  - `struct FeedbackDraft: Codable, Equatable { let clientId: String; let checkpointId: Int; let rating: Int; let comment: String?; let deviceTime: String }`
  - `enum FeedbackSubmitOutcome { case saved, alreadyAnswered, notCheckedIn }`
  - `APIClient.submitFeedback(token:draft:) async throws -> FeedbackSubmitOutcome`
  - `FeedbackOutbox` — `static func key(for: Backend) -> String`, `add(_:)`, `remove(clientId:)`, `all()`, `clear()`
  - `@MainActor final class FeedbackStore: ObservableObject` — `@Published private(set) var submitting: Set<Int>`, `submit(_:token:) async -> FeedbackSubmitOutcome`, `flush(token:) async`
- Tasks 9 and 11 call `FeedbackStore`.

- [ ] **Step 1: Write the failing outbox tests**

Create `WBWTests/FeedbackOutboxTests.swift`:

```swift
import XCTest
@testable import WBW

/// outbox เก็บความเห็นที่ส่งไม่สำเร็จไว้ใน UserDefaults
///
/// คนยืนอยู่กลางเขา สัญญาณไม่แน่ กดส่งแล้วเน็ตหลุดต้องไม่หายไปเฉยๆ
/// key ต้องแยกตาม backend เหมือน cache ตัวอื่นทุกตัวในแอป — checkpoint_id คนละชุด
final class FeedbackOutboxTests: XCTestCase {

    private func freshOutbox(_ backend: Backend = .susLocal) -> FeedbackOutbox {
        UserDefaults.standard.removeObject(forKey: FeedbackOutbox.key(for: backend))
        return FeedbackOutbox(backend: backend)
    }

    private func draft(_ id: String, checkpoint: Int = 1) -> FeedbackDraft {
        FeedbackDraft(clientId: id, checkpointId: checkpoint, rating: 3,
                      comment: "ดี", deviceTime: "2026-08-29T09:00:00Z")
    }

    override func tearDown() {
        for b in [Backend.prodNode, .nodeLocal, .susLocal, .susProd, .susLan] {
            UserDefaults.standard.removeObject(forKey: FeedbackOutbox.key(for: b))
        }
        super.tearDown()
    }

    func testKeyDiffersPerBackend() {
        let keys = Set([Backend.prodNode, .nodeLocal, .susLocal, .susProd, .susLan]
            .map(FeedbackOutbox.key(for:)))
        XCTAssertEqual(keys.count, 5, "ทุก backend ต้องได้ key ไม่ซ้ำกัน")
    }

    func testAddThenAllRoundTrips() {
        let box = freshOutbox()
        box.add(draft("a"))
        XCTAssertEqual(box.all().map(\.clientId), ["a"])

        let reread = FeedbackOutbox(backend: .susLocal)
        XCTAssertEqual(reread.all().map(\.clientId), ["a"], "ต้องอ่านกลับได้จาก UserDefaults")
    }

    func testAddSameClientIdDoesNotDuplicate() {
        let box = freshOutbox()
        box.add(draft("a"))
        box.add(draft("a"))
        XCTAssertEqual(box.all().count, 1)
    }

    /// ตอบฐานเดิมซ้ำด้วย client_id ใหม่ ต้องแทนที่ของเดิมในคิว ไม่ใช่กองสองอัน
    func testAddSameCheckpointReplaces() {
        let box = freshOutbox()
        box.add(draft("a", checkpoint: 4))
        box.add(draft("b", checkpoint: 4))
        XCTAssertEqual(box.all().map(\.clientId), ["b"])
    }

    func testRemoveByClientId() {
        let box = freshOutbox()
        box.add(draft("a", checkpoint: 1))
        box.add(draft("b", checkpoint: 2))
        box.remove(clientId: "a")
        XCTAssertEqual(box.all().map(\.clientId), ["b"])
    }

    func testOtherBackendQueueIsInvisible() {
        let box = freshOutbox(.susLocal)
        box.add(draft("a"))
        XCTAssertTrue(FeedbackOutbox(backend: .prodNode).all().isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WBWTests/FeedbackOutboxTests 2>&1 | tail -15
```

Expected: `cannot find 'FeedbackOutbox' in scope`, `cannot find 'FeedbackDraft' in scope`.

- [ ] **Step 3: Write the outbox**

Create `WBW/Feedback/FeedbackOutbox.swift`:

```swift
import Foundation

/// ความเห็นหนึ่งอันที่รอส่ง
///
/// clientId สร้างครั้งเดียวตอนผู้ใช้กดส่ง แล้วใช้ค่าเดิมทุกครั้งที่ retry —
/// backend unique บนคอลัมน์นี้ ส่งซ้ำจึงได้แถวเดิมกลับมา ไม่เกิดแถวซ้ำ
struct FeedbackDraft: Codable, Equatable {
    let clientId: String
    let checkpointId: Int
    let rating: Int
    let comment: String?
    let deviceTime: String
}

/// คิวความเห็นที่ยังส่งไม่สำเร็จ เก็บลง UserDefaults
///
/// ทำไมไม่ใช้ SwiftData เหมือนแชท: ของค้างมีอย่างมากเท่าจำนวนฐาน (~8 ชิ้นต่อคน)
/// ไม่ต้องมี query ไม่ต้องมี index — ไฟล์ JSON ก้อนเดียวพอและพังยากกว่า
///
/// **key ผูกกับ backend** เหมือน cache ทุกตัวในแอป: checkpoint_id เดินคนละชุดต่อ
/// backend ถ้าใช้ key เดียวกัน ความเห็นจะถูกส่งไปฐานผิดตัวโดยไม่มี error
struct FeedbackOutbox {
    let backend: Backend

    init(backend: Backend = Config.backend) { self.backend = backend }

    static func key(for backend: Backend) -> String {
        "wbw.feedback.outbox.\(backend.cacheNamespace)"
    }

    func all() -> [FeedbackDraft] {
        guard let data = UserDefaults.standard.data(forKey: Self.key(for: backend)),
              let list = try? JSONDecoder().decode([FeedbackDraft].self, from: data)
        else { return [] }
        return list
    }

    /// เพิ่มเข้าคิว · ฐานเดิมที่ค้างอยู่ถูกแทนที่ (ผู้ใช้เปลี่ยนใจก่อนเน็ตกลับมา)
    func add(_ draft: FeedbackDraft) {
        var list = all().filter { $0.checkpointId != draft.checkpointId && $0.clientId != draft.clientId }
        list.append(draft)
        save(list)
    }

    func remove(clientId: String) {
        save(all().filter { $0.clientId != clientId })
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: Self.key(for: backend))
    }

    private func save(_ list: [FeedbackDraft]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(for: backend))
    }
}
```

- [ ] **Step 4: Run to verify they pass**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WBWTests/FeedbackOutboxTests 2>&1 | tail -15
```

Expected: `** TEST SUCCEEDED **`, 6 tests.

- [ ] **Step 5: Add the API call**

Append inside `struct APIClient` in `WBW/APIClient.swift`:

```swift
    /// ผลของการส่งความเห็น — แยก 409/403 ออกจาก error จริง เพราะทั้งคู่ไม่ใช่ความผิดพลาด
    /// ที่ต้อง retry: ตอบไปแล้ว หรือส่งฐานที่ไม่ได้ไป ยังไงก็ไม่สำเร็จรอบหน้า
    enum FeedbackSubmitOutcome {
        case saved
        case alreadyAnswered
        case notCheckedIn
    }

    /// ส่งความเห็นต่อฐาน — idempotent ด้วย clientId
    func submitFeedback(token: String, draft: FeedbackDraft) async throws -> FeedbackSubmitOutcome {
        guard let url = URL(string: "\(Config.apiBase)/me/feedback") else {
            throw AppError.message("URL ไม่ถูกต้อง")
        }
        var body: [String: Any] = [
            "client_id": draft.clientId,
            "checkpoint_id": draft.checkpointId,
            "rating": draft.rating,
            "device_time": draft.deviceTime,
        ]
        if let c = draft.comment { body["comment"] = c }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.offline }   // เน็ตล่ม → เก็บเข้า outbox รอรอบหน้า

        guard let http = resp as? HTTPURLResponse else { throw AppError.message("ผิดพลาด") }
        switch http.statusCode {
        case 200, 201: return .saved
        case 409:      return .alreadyAnswered
        case 403:      return .notCheckedIn
        default:
            let b = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw AppError.message(b?.error ?? "ส่งความเห็นไม่สำเร็จ")
        }
    }
```

`AppError.offline` already exists — `sendMessage` uses it for the same purpose.

- [ ] **Step 6: Write the store**

Create `WBW/Feedback/FeedbackStore.swift`:

```swift
import Foundation

/// ส่งความเห็น + คิวของที่ยังส่งไม่สำเร็จ
///
/// UI ตอบว่า "ส่งแล้ว" ทันทีแบบ optimistic ได้ เพราะ clientId การันตีว่าส่งซ้ำ
/// ไม่เกิดแถวซ้ำ — ที่เหลือเป็นเรื่องของ outbox กับ flush รอบหน้า
@MainActor
final class FeedbackStore: ObservableObject {
    /// checkpointId ที่กำลังส่งอยู่ — ปุ่มส่งของฐานนั้นกดซ้ำไม่ได้
    @Published private(set) var submitting: Set<Int> = []

    private var outbox: FeedbackOutbox { FeedbackOutbox() }

    /// ส่งหนึ่งอัน · ส่งไม่ผ่านเพราะเน็ต = เข้า outbox เงียบๆ แล้วคืน .saved
    /// (ผู้ใช้ไม่ต้องรู้ว่ามันยังไม่ถึงเซิร์ฟเวอร์ ระบบรับผิดชอบเอง)
    @discardableResult
    func submit(_ draft: FeedbackDraft, token: String) async -> APIClient.FeedbackSubmitOutcome {
        submitting.insert(draft.checkpointId)
        defer { submitting.remove(draft.checkpointId) }

        do {
            let outcome = try await APIClient.shared.submitFeedback(token: token, draft: draft)
            // 409/403 เป็นสถานะปลายทาง ไม่ต้อง retry — เอาออกจากคิวเหมือนสำเร็จ
            outbox.remove(clientId: draft.clientId)
            return outcome
        } catch {
            outbox.add(draft)
            return .saved
        }
    }

    /// ส่งของค้างทั้งหมด — เรียกตอนแอปกลับมา active และหลังส่งสำเร็จรอบถัดไป
    func flush(token: String) async {
        guard !token.isEmpty else { return }
        for draft in outbox.all() {
            do {
                _ = try await APIClient.shared.submitFeedback(token: token, draft: draft)
                outbox.remove(clientId: draft.clientId)
            } catch {
                // เน็ตยังไม่กลับมา — หยุดทั้งรอบ ไม่ต้องไล่ยิงตัวที่เหลือให้เปลืองเปล่า
                return
            }
        }
    }

    /// ล้างคิวตอน logout — ความเห็นของบัญชีก่อนต้องไม่ถูกส่งด้วย token ของบัญชีใหม่
    func clearForLogout() {
        outbox.clear()
    }
}
```

- [ ] **Step 7: Build and run the whole suite**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -12
```

Expected: `** TEST SUCCEEDED **`. Existing suites must still pass.

- [ ] **Step 8: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/APIClient.swift WBW/Feedback/FeedbackOutbox.swift WBW/Feedback/FeedbackStore.swift \
        WBWTests/FeedbackOutboxTests.swift
git commit -m "feat(feedback): ส่งความเห็น + outbox กันหายตอนเน็ตหลุด"
```

---

## Task 7: iOS — `PendingPush` carries an id, and push routing

**Files:**
- Modify: `WBW/AppDelegate.swift`
- Modify: `WBWTests/PendingPushTests.swift`

**Interfaces:**
- Consumes: Task 4's FCM data payload `{"type":"checkin_feedback","checkpoint_id":"N"}`.
- Produces:
  - `Notification.Name.openCheckinFeedback`
  - `PendingPush.hold(_ name: Notification.Name, info: [AnyHashable: Any]? = nil)` and `consume() -> (name: Notification.Name, info: [AnyHashable: Any]?)?`
- Task 11 subscribes to the notification and reads `checkpoint_id` from the userInfo.

`PendingPush` guards a real cold-launch trap: `didReceive` fires before `MainTabView` installs its `.onReceive`, because a splash screen sits in between, so the event is parked and replayed once. The existing comments document why each call exists. **`consume()` must keep reading-and-clearing in one step, and `clear()` must keep discarding a parked event once a live subscriber has handled one.**

- [ ] **Step 1: Write the failing tests**

Read `WBWTests/PendingPushTests.swift` first and keep its existing cases working — they cover the trap above. Append:

```swift
    func testHoldCarriesUserInfo() {
        PendingPush.clear()
        PendingPush.hold(.openCheckinFeedback, info: ["checkpoint_id": "7"])
        let taken = PendingPush.consume()
        XCTAssertEqual(taken?.name, .openCheckinFeedback)
        XCTAssertEqual(taken?.info?["checkpoint_id"] as? String, "7")
    }

    func testConsumeStillClearsInOneStep() {
        PendingPush.clear()
        PendingPush.hold(.openCheckinFeedback, info: ["checkpoint_id": "3"])
        _ = PendingPush.consume()
        XCTAssertNil(PendingPush.consume(), "consume ต้องอ่านแล้วเคลียร์ในตาเดียวเหมือนเดิม")
    }

    func testHoldWithoutInfoStillWorks() {
        PendingPush.clear()
        PendingPush.hold(.openGroupChat)
        let taken = PendingPush.consume()
        XCTAssertEqual(taken?.name, .openGroupChat)
        XCTAssertNil(taken?.info)
    }

    func testClearDiscardsInfoToo() {
        PendingPush.hold(.openCheckinFeedback, info: ["checkpoint_id": "1"])
        PendingPush.clear()
        XCTAssertNil(PendingPush.consume())
    }
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WBWTests/PendingPushTests 2>&1 | tail -15
```

Expected: compile failure on `openCheckinFeedback` and on `hold(_:info:)`.

- [ ] **Step 3: Extend `PendingPush` and add the route**

In `WBW/AppDelegate.swift`:

```swift
extension Notification.Name {
    /// โพสต์เมื่อผู้ใช้แตะ push ขอความเห็นต่อฐาน — userInfo["checkpoint_id"] เป็น String
    static let openCheckinFeedback = Notification.Name("openCheckinFeedback")
}
```

`PendingPush` becomes:

```swift
enum PendingPush {
    private static var pending: (name: Notification.Name, info: [AnyHashable: Any]?)?

    /// พก userInfo มาด้วยได้ — feedback ต้องรู้ว่าฐานไหน ไม่ใช่แค่ "เปิดหน้าไหน"
    static func hold(_ n: Notification.Name, info: [AnyHashable: Any]? = nil) {
        pending = (n, info)
    }

    /// อ่านแล้วเคลียร์ในตาเดียว กันโดนดึงไปใช้ซ้ำสองรอบ
    static func consume() -> (name: Notification.Name, info: [AnyHashable: Any]?)? {
        defer { pending = nil }
        return pending
    }

    static func clear() { pending = nil }
}
```

Keep every existing doc comment on these — they explain the cold-launch trap and why `clear()` exists.

In `didReceive`, route the new type:

```swift
        let info = response.notification.request.content.userInfo
        let type = info["type"] as? String
        let name: Notification.Name
        var carried: [AnyHashable: Any]?
        switch type {
        case "chat":
            name = .openGroupChat
        case "checkin_feedback":
            name = .openCheckinFeedback
            carried = ["checkpoint_id": info["checkpoint_id"] as? String ?? ""]
        default:
            name = .openNotificationsTab
        }
        PendingPush.hold(name, info: carried)
        NotificationCenter.default.post(name: name, object: nil, userInfo: carried)
        completionHandler()
```

In `willPresent`, suppress the system banner for the feedback type as chat already does, so the in-app toast is the only thing that appears:

```swift
        let type = info["type"] as? String
        if type == "chat" || type == "checkin_feedback" {
            completionHandler([])   // toast ในแอปเด้งเอง ไม่ให้ซ้อนกับ banner ระบบ
            return
        }
```

- [ ] **Step 4: Fix the existing call site**

`MainTabView.task` calls `PendingPush.consume()` and posts the name. It now receives a tuple. Update it to post the carried userInfo along with the name.

- [ ] **Step 5: Run the whole suite**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -12
```

Expected: `** TEST SUCCEEDED **`, with the pre-existing `PendingPushTests` cases still passing.

- [ ] **Step 6: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/AppDelegate.swift WBW/MainTabView.swift WBWTests/PendingPushTests.swift
git commit -m "feat(feedback): PendingPush พก checkpoint_id + route push ชนิด checkin_feedback"
```

---

## Task 8: iOS — the feedback form

**Files:**
- Create: `WBW/Feedback/FeedbackView.swift`

**Interfaces:**
- Consumes: `CheckinProgressStore.item(checkpointId:)`, `FeedbackStore.submit(_:token:)`, `FeedbackDraft`.
- Produces: `struct FeedbackView: View` with `init(checkpointId: Int, onClose: @escaping () -> Void)`.

**Design, decided during brainstorming and not open for reinterpretation:** a white card on the cream `Color(red: 250/255, green: 247/255, blue: 240/255)` background, matching `NotificationsView`. Adapted from a reference the user supplied, with three deliberate changes: **three** rating buttons rather than two (ไม่ชอบ / เฉยๆ / ชอบ), a header naming the base and its activity, and a line stating that the organising team can see who answered. The send button keeps a paper-plane outline icon.

- [ ] **Step 1: Write the view**

Create `WBW/Feedback/FeedbackView.swift`:

```swift
import SwiftUI

/// หน้าให้ความเห็นต่อฐานหนึ่ง
///
/// การ์ดขาวบนพื้นครีมชุดเดียวกับหน้าแจ้งเตือน · ตอบไปแล้วจะแสดงคำตอบเดิมแบบอ่านอย่างเดียว
/// ไม่ใช่ฟอร์มเปล่า (เข้าหน้านี้จากแจ้งเตือนเก่าได้ ไม่ได้มาจากการเช็คอินสดเสมอไป)
struct FeedbackView: View {
    let checkpointId: Int
    let onClose: () -> Void

    @EnvironmentObject var session: Session
    @EnvironmentObject var progress: CheckinProgressStore
    @EnvironmentObject var feedback: FeedbackStore

    @State private var rating: Int?
    @State private var comment = ""
    @State private var sent = false

    private let cream = Color(red: 250 / 255, green: 247 / 255, blue: 240 / 255)
    private var item: CheckinProgressItem? { progress.item(checkpointId: checkpointId) }
    private var answered: Bool { item?.answered == true || sent }

    var body: some View {
        NavigationStack {
            ZStack {
                cream.ignoresSafeArea()
                ScrollView {
                    card.padding(.horizontal, 16).padding(.top, 12)
                }
            }
            .navigationTitle("ประเมินฐาน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("ปิด", action: onClose).foregroundStyle(Color.wbwInk)
                }
            }
        }
        .onAppear {
            // ตอบไปแล้ว → โชว์คำตอบเดิม
            if let it = item, it.answered {
                rating = it.rating
                comment = it.comment ?? ""
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item?.name ?? "ฐานกิจกรรม")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color.wbwInk)
            if let activity = item?.activityName, !activity.isEmpty {
                Text(activity)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.wbwInk.opacity(0.55))
                    .padding(.top, 2)
            }

            HStack(spacing: 10) {
                faceButton(1, "hand.thumbsdown", "ไม่ชอบ")
                faceButton(2, "minus.circle", "เฉยๆ")
                faceButton(3, "hand.thumbsup", "ชอบ")
            }
            .padding(.top, 16)

            TextEditor(text: $comment)
                .font(.system(size: 14))
                .foregroundStyle(Color.wbwInk)
                .scrollContentBackground(.hidden)
                .frame(height: 110)
                .padding(8)
                .background(cream, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.wbwInk.opacity(0.12), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if comment.isEmpty {
                        Text("เล่าให้ฟังหน่อย… (ไม่บังคับ)")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.wbwInk.opacity(0.35))
                            .padding(.horizontal, 13).padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .disabled(answered)
                .padding(.top, 14)

            Text("ทีมงานเห็นชื่อผู้ตอบ")
                .font(.system(size: 11))
                .foregroundStyle(Color.wbwInk.opacity(0.5))
                .padding(.top, 8)

            if answered {
                Label("ส่งความเห็นแล้ว ขอบคุณ", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.wbwGreen)
                    .padding(.top, 14)
            } else {
                sendButton.padding(.top, 14)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.wbwInk.opacity(0.07), lineWidth: 1))
    }

    private func faceButton(_ value: Int, _ symbol: String, _ label: String) -> some View {
        let picked = rating == value
        return Button { if !answered { rating = value } } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(picked ? Color.wbwGreen : Color.wbwInk.opacity(0.5))
            .background(picked ? Color.wbwGreen.opacity(0.12) : cream,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(picked ? Color.wbwGreen : Color.wbwInk.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(answered)
    }

    private var sendButton: some View {
        Button(action: send) {
            HStack(spacing: 6) {
                Image(systemName: "paperplane").font(.system(size: 14, weight: .semibold))
                Text("ส่งความเห็น").font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(rating == nil ? Color.wbwInk.opacity(0.3) : Color.wbwGold,
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(rating == nil || feedback.submitting.contains(checkpointId))
    }

    private func send() {
        guard let rating else { return }
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = FeedbackDraft(
            clientId: UUID().uuidString.lowercased(),
            checkpointId: checkpointId,
            rating: rating,
            comment: trimmed.isEmpty ? nil : trimmed,
            deviceTime: ISO8601DateFormatter().string(from: Date()))
        sent = true   // optimistic — clientId การันตีว่าส่งซ้ำไม่เกิดแถวซ้ำ
        Task {
            await feedback.submit(draft, token: session.token ?? "")
            await progress.load(token: session.token ?? "")
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild -scheme WBW -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Look at it**

Add a temporary DEBUG launch hook in `MainTabView` that presents `FeedbackView(checkpointId:)` for a checkpoint id passed as `-uitestFeedback <id>`, following the `-uitestChat` pattern. Build **clean**, install, launch with a checkpoint the test account has checked into but not answered, screenshot, and **`Read` the PNG yourself**.

Confirm: the base name and activity name are both shown, three rating buttons are visible and selectable, the placeholder text appears, the "ทีมงานเห็นชื่อผู้ตอบ" line is present, and the send button is disabled until a rating is chosen.

Then launch again for a checkpoint that **is** answered and confirm the read-only state appears with the previous rating pre-selected instead of an empty form.

Keep the launch hook — it is the only way to reach this screen without tap tooling, and Task 11's verification needs it too.

- [ ] **Step 4: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/Feedback/FeedbackView.swift WBW/MainTabView.swift
git commit -m "feat(feedback): หน้าให้ความเห็นต่อฐาน — 3 ระดับ + ข้อความ + สถานะตอบแล้ว"
```

---

## Task 9: iOS — shared toast shell

**Files:**
- Create: `WBW/Toast.swift`
- Modify: `WBW/Chat/ChatToast.swift`
- Create: `WBW/Feedback/CheckinToast.swift`

**Interfaces:**
- Produces: `struct Toast<Leading: View, Content: View>: View` with `init(onTap:@ViewBuilder leading:@ViewBuilder content:)`, and `struct CheckinToast: View` with `init(baseName: String, remaining: Int, onTap: () -> Void)`.

`ChatToast` already holds a toast shell. Rather than copy it, extract the shell and let both be thin wrappers — deduplication caused by the work at hand, not an unrelated refactor.

- [ ] **Step 1: Extract the shell**

Read `WBW/Chat/ChatToast.swift` in full first. Move its container — the `Button`, the `HStack` spacing, the background, corner radius, shadow, and horizontal padding — into `WBW/Toast.swift` as a generic `Toast` taking a leading view and a content view. Leave the visual values exactly as they are; this task must not change how the chat toast looks.

- [ ] **Step 2: Rewrite `ChatToast` on top of it**

`ChatToast` keeps its `init(message:photoUrl:onTap:)` and renders `Toast { ProfileAvatar(...) } content: { ... }`. Its call site in `MainTabView` must not change.

- [ ] **Step 3: Write `CheckinToast`**

Create `WBW/Feedback/CheckinToast.swift`:

```swift
import SwiftUI

/// แบนเนอร์ในแอปตอนเพิ่งโดนสแกนเช็คอิน
///
/// เด้งของฐานล่าสุดตัวเดียว · ถ้ามีฐานอื่นค้างอยู่ด้วยบอกเป็นจำนวนต่อท้าย ไม่เด้งซ้อนกันหลายอัน
/// (เช็คอิน 3 ฐานตอนออฟไลน์แล้วเน็ตกลับมาพร้อมกันเกิดขึ้นได้จริง)
struct CheckinToast: View {
    let baseName: String
    /// จำนวนฐานที่ยังไม่ตอบ *นอกเหนือจาก* ฐานที่เด้งอยู่
    let remaining: Int
    let onTap: () -> Void

    var body: some View {
        Toast(onTap: onTap) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.wbwGreen)
                .frame(width: 34, height: 34)
        } content: {
            VStack(alignment: .leading, spacing: 1) {
                Text("เช็คอิน \(baseName) แล้ว")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.wbwInk)
                Text(remaining > 0
                     ? "แตะให้คะแนนฐานนี้ · ยังมีอีก \(remaining) ฐานรอประเมิน"
                     : "แตะเพื่อให้คะแนนฐานนี้")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
```

- [ ] **Step 4: Build and confirm chat is visually unchanged**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild -scheme WBW -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' clean build 2>&1 | tail -10
```

Then launch with `-uitestChat YES` against the local backend, have a second account post a message so the chat toast fires, screenshot, and **`Read` it**. Compare against the toast's appearance before this task — the refactor must be invisible. If you cannot make a message arrive, say so plainly rather than claiming the appearance is unchanged.

- [ ] **Step 5: Run the whole suite and commit**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -8
git add WBW/Toast.swift WBW/Chat/ChatToast.swift WBW/Feedback/CheckinToast.swift
git commit -m "refactor(toast): แยกเปลือก toast ให้แชทกับ feedback ใช้ร่วมกัน"
```

---

## Task 10: iOS — tappable notification cards

**Files:**
- Modify: `WBW/Models.swift` (`NotificationItem`)
- Modify: `WBW/NotificationsView.swift`

**Interfaces:**
- Consumes: Task 1's `ref_id` on the notification payload.
- Produces: `NotificationItem.refId: String?` and `NotificationItem.feedbackCheckpointId: Int?`; `NotificationsView(store:token:onOpenFeedback:)`.

- [ ] **Step 1: Extend the model**

In `WBW/Models.swift`, add to `NotificationItem`:

```swift
    /// ชี้ไปวัตถุที่แจ้งเตือนนี้พูดถึง · ตอนนี้ใช้เฉพาะ type == "checkin_feedback" = checkpoint_id
    let refId: String?

    /// เลขฐานที่แจ้งเตือนนี้ขอความเห็น · nil = ไม่ใช่แจ้งเตือนชนิดนี้
    var feedbackCheckpointId: Int? {
        guard type == "checkin_feedback", let refId else { return nil }
        return Int(refId)
    }
```

`refId` must be `let refId: String?` — `Optional` decodes a missing key as nil, so old payloads without the column still parse.

- [ ] **Step 2: Make the card tappable**

`NotificationsView` gains `let onOpenFeedback: (Int) -> Void`. In the `ForEach`, a card whose `feedbackCheckpointId` is non-nil is wrapped in a `Button` calling it; every other card renders exactly as today.

Give the feedback card its own accent and icon so it reads as actionable rather than as another announcement — use `Color.wbwGreen` and `"checkmark.seal.fill"`, and add a trailing chevron. Do this inside `NotiCard` by extending its existing `accent` and `icon` switches on `item.level` with a prior check on `item.type`, so the announcement styling stays untouched.

- [ ] **Step 3: Update the call site**

`MainTabView` presents `NotificationsView` in a sheet. Pass `onOpenFeedback:` through — Task 11 wires what it does. For this task, have it dismiss the sheet and store the checkpoint id in a `@State` so the build compiles and the tap is observable.

- [ ] **Step 4: Build, then verify against real data**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild -scheme WBW -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' clean build 2>&1 | tail -10
```

Task 4 Step 7 left a real `checkin_feedback` notification in the database for the test account. Launch, open the notifications sheet (`-uitestTab 0` then post `.openNotificationsTab`, or add a `-uitestNotifications` launch hook in the same `#if DEBUG` style), screenshot, and **`Read` it**. Confirm the feedback card is visually distinct from announcement cards and shows the base name from its title.

- [ ] **Step 5: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/Models.swift WBW/NotificationsView.swift WBW/MainTabView.swift
git commit -m "feat(feedback): การ์ดแจ้งเตือนขอความเห็นกดเข้าหน้าให้คะแนนได้"
```

---

## Task 11: iOS — wire the four entry points

**Files:**
- Modify: `WBW/MainTabView.swift`
- Modify: `WBW/CheckinProgressStore.swift`
- Modify: `WBW/Session.swift`
- Modify: `WBW/WBWApp.swift`

**Interfaces:**
- Consumes: everything from Tasks 5–10.
- Produces: the finished feature.

Four entry points, one destination — `FeedbackView(checkpointId:)`:

| Entry | Mechanism |
|---|---|
| Tap push while the app is closed or backgrounded | `AppDelegate.didReceive` → `PendingPush` → replayed in `MainTabView.task` |
| Push arrives while the app is open | `willPresent` returns `[]`, posts `.openCheckinFeedback` live |
| The 60 s poll finds a newly pending base | `CheckinProgressStore` diffs against the previous response |
| Tap a card in the notification list | `onOpenFeedback` from Task 10 |

- [ ] **Step 1: Teach the store to report newly pending bases**

In `WBW/CheckinProgressStore.swift`:

```swift
    /// ฐานที่เพิ่งกลายเป็น "รอประเมิน" ในการโหลดรอบล่าสุด — toast อ่านตัวนี้
    ///
    /// เทียบกับรอบก่อนเสมอ ไม่ใช่กับ "เคยเด้งไปหรือยัง" — poll รอบถัดไปที่ได้ข้อมูล
    /// ชุดเดิมจึงไม่เด้งซ้ำ · ตั้งเป็น [] ทุกครั้งที่ไม่มีอะไรใหม่
    @Published private(set) var newlyPending: [CheckinProgressItem] = []

    private var lastPendingIds: Set<Int> = []
```

At the end of `load(token:backend:)`, after `progress = fresh`:

```swift
        let ids = Set(fresh.pending.map(\.checkpointId))
        // โหลดครั้งแรกของ session ไม่นับว่า "เพิ่งเกิด" — เปิดแอปมาเจอของค้างเก่า
        // ไม่ควรเด้ง toast ราวกับเพิ่งโดนสแกนเมื่อกี้
        newlyPending = firstLoadDone ? fresh.pending.filter { !lastPendingIds.contains($0.checkpointId) } : []
        lastPendingIds = ids
        firstLoadDone = true
```

with `private var firstLoadDone = false` alongside. `clear()` must reset all three so the next account starts fresh.

- [ ] **Step 2: Write the failing test for the diff**

Append to `WBWTests/CheckinProgressStoreTests.swift`:

```swift
    @MainActor
    func testNewlyPendingIsEmptyOnFirstLoad() {
        let store = CheckinProgressStore()
        XCTAssertTrue(store.newlyPending.isEmpty)
    }

    @MainActor
    func testClearResetsPendingDiffState() {
        let store = CheckinProgressStore()
        store.clear()
        XCTAssertTrue(store.newlyPending.isEmpty)
        XCTAssertNil(store.progress)
    }
```

The full diff behaviour needs a network round trip, so it is exercised in Step 6 against the live backend rather than pretended at in a unit test. Say so in the report.

- [ ] **Step 3: Add the 60 s poll**

In `MainTabView`, alongside the existing `.task`:

```swift
            .task {
                // poll สำรอง — push เป็นทางหลัก แต่ build ที่ไม่มี GoogleService-Info.plist
                // ปิด push ทั้งอัน และผู้ใช้ปฏิเสธสิทธิ์ก็มี · 60 วิคือจุดที่คนยืนอยู่ที่ฐาน
                // รอไม่นานเกินไป และผู้เข้าร่วม 2,000 คนคิดเป็น ~33 req/s ซึ่งรับไหว
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled else { break }
                    await progress.load(token: session.token ?? "")
                }
            }
```

SwiftUI cancels a `.task` when the view disappears, so this stops on logout without extra code. It does **not** stop when the app backgrounds — the existing `scenePhase` handler already reloads on `.active`, and a suspended app's timer does not fire.

- [ ] **Step 4: Wire the toast and the sheet**

Add `@StateObject private var feedback = FeedbackStore()` in `WBWApp` and inject it, or hold it in `MainTabView` — follow whichever pattern `ChatSession` uses.

In `MainTabView`, add `@State private var feedbackCheckpoint: Int?`, present `FeedbackView` as a `.sheet(item:)`, and show `CheckinToast` when `progress.newlyPending` is non-empty and no sheet is open, using the first entry as the named base and `count - 1` as `remaining`. Dismiss it after 3.5 s exactly as the chat toast does.

Subscribe to `.openCheckinFeedback` and set `feedbackCheckpoint` from `userInfo["checkpoint_id"]`, calling `PendingPush.clear()` afterwards — the existing handlers document why.

Wire Task 10's `onOpenFeedback` to set `feedbackCheckpoint` and close the notifications sheet.

- [ ] **Step 5: Mark the notification read when the push path skips the list**

Tapping a push jumps straight to the form without passing through `NotificationsView`, which is where `markAllRead` runs. Without this the bell keeps a badge for something the user has dealt with.

When `FeedbackView` is opened from `.openCheckinFeedback`, find the matching unread `checkin_feedback` notification in `NotiStore.items` by `feedbackCheckpointId` and call `APIClient.shared.markRead` for it, updating the local item so the badge drops immediately.

- [ ] **Step 6: Clear the outbox on logout**

`Session.logout()` already owns clearing the progress cache. Add the feedback outbox to the same place — a queued answer must not be sent later under a different account's token. Use `FeedbackOutbox(backend: Config.backend).clear()`.

- [ ] **Step 7: Verify the poll path end to end**

This is the path that works when push does not, and push cannot be exercised locally at all — there is no Firebase service account, so `SendUserPush` returns immediately.

```bash
# ล้างเช็คอินฐาน 6 ให้เป็น "ยังไม่เคยไป"
UID_=$(docker exec postgres-db psql -U admin -d sudb -tAc "SELECT user_id FROM app_user WHERE username='6931900011'" | tr -d '[:space:]')
docker exec postgres-db psql -U admin -d sudb -c "DELETE FROM check_in WHERE participant_id='$UID_' AND checkpoint_id=6"
```

Launch the app on Home and leave it running. Then, while it is open, insert the check-in:

```bash
docker exec postgres-db psql -U admin -d sudb -c \
  "INSERT INTO check_in (client_id, participant_id, checkpoint_id, device_time)
   VALUES (gen_random_uuid(), '$UID_', 6, now())"
```

Within 60 s the toast must appear naming that base. Screenshot and **`Read` it**. Then confirm the tree also grew by one stage in the same screenshot — the poll drives both.

If the toast does not appear, check `progress.newlyPending` is actually being populated before blaming the view; the diff resetting on first load is the likely culprit.

- [ ] **Step 8: Verify the round trip**

Open the form from the toast, choose a rating, type a comment, send. Then:

```bash
docker exec postgres-db psql -U admin -d sudb -c \
  "SELECT checkpoint_id, rating, comment FROM checkin_feedback WHERE participant_id='$UID_' ORDER BY created_at DESC LIMIT 3"
curl -s http://localhost:8080/wbw/me/progress -H "Authorization: Bearer $TOKEN" | python3 -m json.tool | head -30
```

Expected: the row exists with the rating and comment you entered, and that checkpoint now reports `"answered": true` with the same values.

- [ ] **Step 9: Run the whole suite and commit**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -10
git add WBW/MainTabView.swift WBW/CheckinProgressStore.swift WBW/Session.swift WBW/WBWApp.swift \
        WBWTests/CheckinProgressStoreTests.swift
git commit -m "feat(feedback): ต่อทั้ง 4 ทางเข้าหน้าให้คะแนน + poll 60 วิสำรอง push"
```

---

## Task 12: Offline behaviour and the verification document

**Files:**
- Create: `docs/checkin-feedback-verification.md`

- [ ] **Step 1: Verify the outbox against a real network failure**

Stop the backend, submit an answer, confirm the UI reports success, then bring the backend back and confirm the answer lands.

```bash
cd /Users/park/Student-Union-Server && docker compose stop su-server
```

Submit from the app. The form must close and report success — the user is not told it failed. Then:

```bash
docker exec postgres-db psql -U admin -d sudb -c "SELECT count(*) FROM checkin_feedback WHERE checkpoint_id = <the one you answered>"
```

Expected: `0` — it is queued on the device, not saved.

Bring the backend back, send the app to the background and foreground it to trigger the flush, and re-run the count. Expected: `1`, with the rating and comment you entered.

```bash
cd /Users/park/Student-Union-Server && docker compose start su-server
```

- [ ] **Step 2: Verify the terminal cases drop out of the queue**

Answer a base twice from two different launches with different client ids. The second must produce `409`, and the queue must not retain it — a `409` is a terminal answer, not something to retry forever. Confirm the outbox is empty afterwards by reading the `UserDefaults` key from the app's container, or by adding a temporary DEBUG log of `FeedbackOutbox().all().count` and capturing it with a **bounded** log stream.

- [ ] **Step 3: Write the verification document**

Create `docs/checkin-feedback-verification.md`, in the same language as the other files under `docs/`. Record what was established and — with equal prominence — what was not. It must state at minimum:

- **FCM push has never been exercised.** There is no Firebase service account in the local environment, so `s.tokens` is nil and `SendUserPush` returns before contacting FCM. The payload shape, the `willPresent` suppression, the `didReceive` routing, and the cold-launch `PendingPush` replay are all **unverified against a real push**. Only the notification row and the 60 s poll path were proven.
- Which of the four entry points were actually exercised, and by what means.
- `xcodebuild build` without `clean` can serve stale bundled resources while reporting success.
- There is no UI tap tooling; every transition was driven by launch arguments or programmatic state changes.
- The known gaps carried from the previous plan that still apply: gyroscope parallax has never run, and the 3D scene's appearance was judged by eye rather than measured.
- The concrete facts: which endpoints were curl-verified and with what output, the iOS and Go test counts, and the database state left behind.

- [ ] **Step 4: Run both suites and commit**

```bash
cd /Users/park/Student-Union-Server && go test ./... 2>&1 | tail -6
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -8
git add docs/checkin-feedback-verification.md
git commit -m "docs(feedback): บันทึกสิ่งที่ยืนยันแล้วและที่ยังไม่ได้ยืนยัน"
```

---

## Self-review notes

Checked against the spec section by section:

- **Data model** — Task 1. Pending is derived, never stored: Task 2's `LEFT JOIN`.
- **Extended `/wbw/me/progress` rather than a second endpoint** — Task 2, as the spec requires so the one poll drives both the tree and the pending list.
- **`POST /wbw/me/feedback` with all five cases** — Task 3, each verified by `curl` with the expected status written into the step.
- **`GET /wbw/admin/feedback`** — Task 3, so the data is reachable from day one.
- **Notification and push on a first check-in only** — Task 4, guarded by `already_checked_in` and verified by counting rows after two scans.
- **`ref_id`** — Task 1 through the repository, Task 10 on the client.
- **Fire-and-forget push** — Task 4, mirroring `SendChatPush`'s `context.WithoutCancel` shape.
- **Four entry points** — Task 11.
- **`PendingPush` carrying an id, with the cold-launch trap preserved** — Task 7.
- **Shared toast shell, one toast with a count when several are pending** — Task 9.
- **Offline outbox namespaced per backend, optimistic UI, 409/403 terminal** — Task 6, exercised for real in Task 12.
- **Form design: white card on cream, three levels, base and activity named, attribution line** — Task 8.
- **Marking read when the push path skips the list** — Task 11 Step 5.
- **Bell badge needs no work** — true; these are ordinary `notification` rows.

Three things this plan does **not** deliver, stated plainly:

- **Real push delivery is not verified anywhere.** There is no Firebase service account locally and this plan does not add one. Everything downstream of `SendUserPush` — payload shape, banner suppression, tap routing, cold-launch replay — rests on code reading and on the chat push path that shares the same `sendOne`. Task 12 records this rather than hiding it.
- **No admin UI for reading feedback.** The spec explicitly scoped this to an endpoint; a screen belongs to the SUS web app.
- **No reminder push chasing people who never answered**, no editing an answer, and no feedback for service points — all spec Non-Goals, and none of them are implemented.

One latent issue inherited rather than created, worth an issue rather than a task: the admin checkpoint-create path omits `requires_checkin`, which defaults `TRUE`, and no admin endpoint can set it. An admin adding a restroom on event day silently raises `total`, which affects the tree and now also the feedback list. Recorded in the previous plan's ledger; unchanged here.
