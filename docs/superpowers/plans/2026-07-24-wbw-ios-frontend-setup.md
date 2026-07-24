# WBW iOS Frontend Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clone the existing native iOS app into this repo, add a Node↔SUS backend switch, and produce the English API contract the SUS owner must implement.

**Architecture:** Copy `Desktop/WBW/ios_native` into `wbw-ios-fontend` and drive the Xcode project from `project.yml` via XcodeGen. Replace the single `apiBase` constant with a backend enum (`.prodNode` default, `.susLocal`, `.susProd`) so the whole app points at one backend at a time. Make numeric-id fields decode from either JSON number or string so the app tolerates SUS's `int64` ids. The backend contract lives as a standalone Markdown doc for the teammate.

**Tech Stack:** SwiftUI, iOS 18, Swift 5, XcodeGen, SPM (MapLibre, FirebaseMessaging), XCTest.

## Global Constraints

- Do **not** modify `/Users/park/Student-Union-Server` (teammate's repo).
- Bundle id `th.ac.mfu.wbwSwift`; deployment target iOS 18.0; Swift 5.0; iPhone only; team `NJL4K64JX5`.
- All JSON is snake_case; response field names must match the iOS `Codable` models exactly.
- Never commit `WBW/GoogleService-Info.plist` (Firebase secret).
- Default backend stays `.prodNode` until the teammate's SUS is ready.
- Source-of-truth for endpoint behavior = the Node backend route files under `/Users/park/Desktop/WBW/backend/api/src/routes/`.

---

### Task 1: Clone iOS app + baseline build on Node

Bring the app into this repo and prove the clone is intact by building and logging in against the existing Node backend before changing any code.

**Files:**
- Create: `WBW/` (copied), `project.yml` (copied)
- Create: `.gitignore`
- Generated (not committed): `WBW.xcodeproj/`

**Interfaces:**
- Consumes: nothing.
- Produces: a buildable Xcode project named `WBW`; `Config.apiBase` (`String`, currently `https://wbw.sumfu.store`); `Config.mePath` does not exist yet.

- [ ] **Step 1: Verify XcodeGen is installed**

Run: `xcodegen --version`
Expected: prints a version (e.g. `Version: 2.x`). If "command not found", run `brew install xcodegen` first.

- [ ] **Step 2: Copy the app sources and project spec (excluding build artifacts)**

```bash
cp -R /Users/park/Desktop/WBW/ios_native/WBW /Users/park/wbw-ios-fontend/WBW
cp /Users/park/Desktop/WBW/ios_native/project.yml /Users/park/wbw-ios-fontend/project.yml
rm -f /Users/park/wbw-ios-fontend/WBW/.DS_Store
```

Note: we intentionally do **not** copy `ios_native/build/` (artifacts) or the old `WBW.xcodeproj` — XcodeGen regenerates the project from `project.yml`.

- [ ] **Step 3: Create `.gitignore`**

Create `/Users/park/wbw-ios-fontend/.gitignore`:

```gitignore
# Xcode / build
build/
DerivedData/
*.xcuserstate
*.xcworkspace/xcuserdata/

# XcodeGen output (project.yml is the source of truth)
WBW.xcodeproj/

# Secrets
WBW/GoogleService-Info.plist

# macOS
.DS_Store
```

- [ ] **Step 4: Generate the Xcode project**

Run: `cd /Users/park/wbw-ios-fontend && xcodegen generate`
Expected: `Created project at .../WBW.xcodeproj`.

- [ ] **Step 5: Build against the Node backend (baseline)**

Run: `cd /Users/park/wbw-ios-fontend && xcodebuild -scheme WBW -destination 'generic/platform=iOS Simulator' build`
Expected: SPM resolves MapLibre + Firebase, then `** BUILD SUCCEEDED **`. (First run may take several minutes to fetch packages.)

- [ ] **Step 6: Manual smoke — run and log in**

Open `WBW.xcodeproj` in Xcode, pick an iOS 18 simulator, Run. `Config.apiBase` is still `https://wbw.sumfu.store`.
Expected: the login screen appears; logging in with a valid WBW account reaches the home screen. This confirms the clone is wired correctly.

- [ ] **Step 7: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW project.yml .gitignore
git commit -m "feat: clone WBW iOS app, build baseline against Node backend"
```

---

### Task 2: Backend contract doc (English)

Write the standalone contract handed to the SUS owner. Independent of the iOS code changes; deliverable is the document itself.

**Files:**
- Create: `docs/backend-contract.md`

**Interfaces:**
- Consumes: nothing (references Node route files as source of truth).
- Produces: the contract document. No code interface.

- [ ] **Step 1: Write `docs/backend-contract.md`**

Create `/Users/park/wbw-ios-fontend/docs/backend-contract.md` with exactly this content:

````markdown
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
````

- [ ] **Step 2: Verify the doc is complete**

Run: `grep -c '/wbw/' /Users/park/wbw-ios-fontend/docs/backend-contract.md`
Expected: a count of at least `16` (4 verify-rows + 12 add-rows, plus prose mentions).

Run: `grep -E 'wbw_messages|device_tokens' /Users/park/wbw-ios-fontend/docs/backend-contract.md`
Expected: both table names appear.

- [ ] **Step 3: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add docs/backend-contract.md
git commit -m "docs: add backend API contract for SUS owner"
```

---

### Task 3: Backend environment switch in Config + APIClient

Replace the single `apiBase` constant with a backend enum and route the one
path that differs between backends (`me`) through `Config.mePath`.

**Files:**
- Modify: `WBW/Config.swift` (replace the `Config` enum; keep the `Color` theme extension)
- Modify: `WBW/APIClient.swift:50`, `WBW/APIClient.swift:124` (`/auth/me` → `Config.mePath`)

**Interfaces:**
- Consumes: `Config.apiBase` (`String`) from Task 1.
- Produces: `Backend` enum with `.prodNode`/`.susLocal`/`.susProd`; `Config.backend: Backend`; `Config.apiBase: String`; `Config.mePath: String`.

- [ ] **Step 1: Rewrite the `Config` enum in `WBW/Config.swift`**

Replace lines 1–7 (the `import Foundation` + `enum Config { ... }` block) with:

```swift
import Foundation

/// backend ปลายทาง — สลับทั้งแอปทีเดียว (JWT คนละ secret ต่อ backend)
enum Backend {
    case prodNode   // Node เดิม (ใช้งานได้จริงตอนนี้)
    case susLocal   // Student-Union-Server รันในเครื่อง
    case susProd    // SUS ที่ deploy แล้ว (รอ URL จากเพื่อน)

    var apiBase: String {
        switch self {
        case .prodNode: return "https://wbw.sumfu.store"
        case .susLocal: return "http://localhost:8080/wbw"
        case .susProd:  return "https://TODO-set-sus-host/wbw"
        }
    }

    /// โปรไฟล์ผู้ใช้ปัจจุบัน — Node อยู่ที่ /auth/me, SUS อยู่ที่ /me
    var mePath: String {
        switch self {
        case .prodNode:            return "/auth/me"
        case .susLocal, .susProd:  return "/me"
        }
    }
}

enum Config {
    /// เปลี่ยนค่าเดียวนี้เพื่อสลับ backend
    static let backend: Backend = .prodNode
    static var apiBase: String { backend.apiBase }
    static var mePath: String { backend.mePath }
}
```

Keep the existing `import SwiftUI` + `extension Color { ... }` block (lines 9–16) exactly as-is below this.

- [ ] **Step 2: Point the profile calls at `Config.mePath`**

In `WBW/APIClient.swift`, the two hardcoded `/auth/me` literals become `Config.mePath`.

Line ~50 (`me(token:)`):

```swift
        guard let url = URL(string: "\(Config.apiBase)\(Config.mePath)") else {
```

Line ~124 (`updatePhoto(token:)`):

```swift
        guard let url = URL(string: "\(Config.apiBase)\(Config.mePath)") else { throw AppError.message("URL ไม่ถูกต้อง") }
```

- [ ] **Step 3: Confirm ATS already allows local networking (no edit needed)**

Run: `grep -A1 NSAllowsLocalNetworking /Users/park/wbw-ios-fontend/WBW/Info.plist`
Expected: shows `<key>NSAllowsLocalNetworking</key>` followed by `<true/>`. (Already present — `.susLocal` http works with no plist change.)

- [ ] **Step 4: Regenerate and build; confirm still green on Node**

Run: `cd /Users/park/wbw-ios-fontend && xcodegen generate && xcodebuild -scheme WBW -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`. With `backend = .prodNode`, `apiBase` = `https://wbw.sumfu.store` and `mePath` = `/auth/me`, so behavior is unchanged from Task 1.

- [ ] **Step 5: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/Config.swift WBW/APIClient.swift
git commit -m "feat: switchable backend (Node/SUS) via Config enum + mePath"
```

---

### Task 4: Tolerant id decoding + unit test target

SUS returns `notification.id` and `message.id` as JSON numbers; the iOS models
type them as `String`. Add a `@FlexibleString` property wrapper that decodes
from number **or** string, apply it, and cover it with a unit test. This task
also introduces the first XCTest target.

**Files:**
- Create: `WBW/FlexibleString.swift`
- Create: `WBWTests/FlexibleStringTests.swift`
- Modify: `WBW/Models.swift:123` (`NotificationItem.id`), `WBW/Models.swift:196` (`MessageDTO.id`)
- Modify: `project.yml` (add `WBWTests` target + test action on the `WBW` scheme)

**Interfaces:**
- Consumes: `NotificationItem`, `MessageDTO` from Task 1.
- Produces: `@propertyWrapper struct FlexibleString` (wrapped value `String`, `Codable`).

- [ ] **Step 1: Add the `WBWTests` target to `project.yml`**

Under `targets:`, after the `WBW:` target block, add:

```yaml
  WBWTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - WBWTests
    dependencies:
      - target: WBW
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: th.ac.mfu.wbwSwiftTests
        GENERATE_INFOPLIST_FILE: YES
        IPHONEOS_DEPLOYMENT_TARGET: "18.0"
        SWIFT_VERSION: "5.0"
```

Then attach a test action to the app scheme — add this top-level `schemes:` block (at the same indentation as `targets:`):

```yaml
schemes:
  WBW:
    build:
      targets:
        WBW: all
    test:
      targets:
        - WBWTests
    run:
      config: Debug
```

- [ ] **Step 2: Write the failing test**

Create `/Users/park/wbw-ios-fontend/WBWTests/FlexibleStringTests.swift`:

```swift
import XCTest
@testable import WBW

final class FlexibleStringTests: XCTestCase {
    private struct Box: Codable { @FlexibleString var id: String }

    func testDecodesFromNumber() throws {
        let data = #"{"id": 123}"#.data(using: .utf8)!
        let box = try JSONDecoder().decode(Box.self, from: data)
        XCTAssertEqual(box.id, "123")
    }

    func testDecodesFromString() throws {
        let data = #"{"id": "456"}"#.data(using: .utf8)!
        let box = try JSONDecoder().decode(Box.self, from: data)
        XCTAssertEqual(box.id, "456")
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd /Users/park/wbw-ios-fontend && xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: compile failure — `cannot find 'FlexibleString' in scope` (type not defined yet). If `iPhone 16` is unavailable, run `xcrun simctl list devices available` and substitute an available iOS 18 device name.

- [ ] **Step 4: Implement `FlexibleString`**

Create `/Users/park/wbw-ios-fontend/WBW/FlexibleString.swift`:

```swift
import Foundation

/// รับค่า id ที่ backend อาจส่งมาเป็น number (SUS int64) หรือ string (Node bigint)
/// แล้วเก็บเป็น String เสมอ
@propertyWrapper
struct FlexibleString: Codable, Equatable {
    var wrappedValue: String

    init(wrappedValue: String) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            wrappedValue = s
        } else if let i = try? c.decode(Int64.self) {
            wrappedValue = String(i)
        } else if let d = try? c.decode(Double.self) {
            wrappedValue = String(Int64(d))
        } else {
            wrappedValue = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue)
    }
}
```

- [ ] **Step 5: Apply the wrapper to the numeric id fields**

In `WBW/Models.swift`, change the `NotificationItem` id declaration (line ~123):

```swift
struct NotificationItem: Codable, Identifiable {
    @FlexibleString var id: String
```

And the `MessageDTO` id declaration (line ~195–196):

```swift
struct MessageDTO: Codable {
    @FlexibleString var id: String
```

Leave every other field (including `sender_id`, which is a string user id) unchanged.

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd /Users/park/wbw-ios-fontend && xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: `Test Suite 'FlexibleStringTests' passed` — both tests pass, `** TEST SUCCEEDED **`.

- [ ] **Step 7: Verify the app still builds on Node**

Run: `cd /Users/park/wbw-ios-fontend && xcodebuild -scheme WBW -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **` (property-wrapped `id` still exposes a `String` to all existing call sites).

- [ ] **Step 8: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add project.yml WBW/FlexibleString.swift WBW/Models.swift WBWTests
git commit -m "feat: tolerate numeric/string ids from SUS; add unit test target"
```

---

## Migration note (post-plan, per-endpoint)

Once the teammate ships a SUS endpoint from the contract, set
`Config.backend = .susLocal` (or `.susProd` once its URL is known), re-run,
log in on SUS, and smoke-test the affected screen. Because JWTs differ per
backend, switch the whole app at once — never mix backends in one session.
Confirm `/wbw/me` returns `role` so staff/admin gating works.

## Self-Review Notes
- **Spec coverage:** §1 repo setup → Task 1; §2 Config switch → Task 3; §3
  contract doc → Task 2; §3.5 id mismatch → Task 4; §4 migration → Task 1–4 +
  migration note. ATS exception from spec §2 was already present in Info.plist
  (Task 3 Step 3 verifies rather than edits).
- **Type consistency:** `Config.apiBase`/`Config.mePath`/`Backend` used
  identically across Tasks 1, 3. `FlexibleString.wrappedValue: String` keeps
  `NotificationItem.id`/`MessageDTO.id` as `String` for all existing callers.
