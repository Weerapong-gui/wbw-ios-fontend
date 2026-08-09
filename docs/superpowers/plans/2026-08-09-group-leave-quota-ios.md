# โควตาออกจากกลุ่ม + flow แท็บกลุ่มใหม่ — ฝั่ง iOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** แท็บกลุ่มเปิดเข้าจอแชทตรง ๆ เมื่อมีกลุ่มแล้ว (หน้ากลุ่ม/สมาชิก/ออกจากกลุ่มย้ายไปอยู่หลังการกด
ชื่อกลุ่มบนหัวจอ) และผู้ใช้เห็นสิทธิ์ออกจากกลุ่มคงเหลือทุกจุดที่ตัดสินใจ

**Architecture:** ยุบ overlay `chatOpen` ทิ้งทั้งหมด แล้วให้แท็บ 3 เป็น `NavigationStack` เดียวที่มี
`GroupChatView` เป็นราก · การบอก `ChatSession` ว่า "จอแชทเปิดอยู่ไหม" ย้ายจาก lifecycle ของ view
ไปเป็นค่าที่ `MainTabView` คำนวณ (แท็บ + ความลึกของ stack) เพราะ `onAppear`/`onDisappear` ของ
view ใน `TabView`/`NavigationStack` ไม่รับประกันว่าจะยิง

**Tech Stack:** SwiftUI, iOS 18 deployment target, XcodeGen, XCTest, SwiftData (ของเดิม ไม่แตะ)

**ต้องทำก่อน:** แผนฝั่ง backend (`2026-08-09-group-leave-quota-backend.md`) ต้องขึ้นเซิร์ฟเวอร์ที่แอป
ชี้อยู่แล้ว ไม่งั้น `leave_quota` เป็น nil ตลอดและปุ่มออกจะหายไปทั้งที่ยังไม่ควรหาย

**สเปก:** `docs/superpowers/specs/2026-08-09-group-leave-quota-and-chat-flow-design.md`

## Global Constraints

- อ่าน `.claude/skills/wbw-ios/SKILL.md` ก่อนเริ่ม — กติกา 8 ข้อในนั้นใช้กับทุก task ของแผนนี้
- **`xcodegen generate` ทุกครั้งที่เพิ่ม/ลบ/ย้ายไฟล์ใน `WBW/` หรือ `WBWTests/`** ไม่งั้น build ไม่เห็นไฟล์ใหม่
- **ห้ามแก้ `Config.backend` แล้ว commit** · **ห้าม `git add -A` / `git add .`**
- คอมเมนต์ในโค้ดและ commit เป็นภาษาไทย บอก **"ทำไม"** ไม่ใช่ "ทำอะไร"
- เขียนเทสที่ fail ก่อนเสมอ แล้วค่อยเขียนโค้ดให้ผ่าน
- งานที่แตะ UI ต้องมีสกรีนช็อตจาก simulator จริงประกอบ — build ผ่านไม่นับว่าเสร็จ
- ข้อความบนจอทั้งหมดเป็นภาษาไทย ใช้คำว่า "สิทธิ์ออกจากกลุ่ม" ให้ตรงกันทุกที่
- สีใช้จากธีมเดิม (`Color.wbwGold`, `.wbwInk`, `.wbwSurface`, `.wbwBg`) ห้ามใส่ค่าสีดิบ

## File Structure

| ไฟล์ | สถานะ | รับผิดชอบ |
|---|---|---|
| `WBW/GroupQuotaText.swift` | สร้าง | ข้อความโควตาทุกอันเป็นฟังก์ชันบริสุทธิ์ เทสได้โดยไม่ต้องเรนเดอร์ |
| `WBWTests/GroupQuotaTextTests.swift` | สร้าง | เทสข้อความทุกกรณี |
| `WBWTests/GroupLeaveTransportTests.swift` | สร้าง | เทสว่า 409 จาก `/groups/leave` ถึงมือผู้เรียกจริง |
| `WBWTests/MeDecodeTests.swift` | สร้าง | เทสว่า `Me` ที่ไม่มี `leave_quota` ยัง decode ผ่าน |
| `WBW/Models.swift` | แก้ | `Me.leaveQuota` |
| `WBW/APIClient.swift` | แก้ | `leaveGroup` เลิกกลืน error |
| `WBW/GroupTabView.swift` | แก้ | `NavigationStack` + `GroupRoute` · `GroupHomeView` แสดงสิทธิ์/ปุ่มออกตามโควตา |
| `WBW/GroupJoinView.swift` | แก้ | ถอด `NavigationStack` ของตัวเอง + alert ยืนยันก่อนเข้ากลุ่ม |
| `WBW/GroupChatView.swift` | แก้ | หัวจอเป็นปุ่มไปหน้ากลุ่ม · ตัด `onClose` และการคุม `setScreenVisible` ออก |
| `WBW/Chat/ChatSession.swift` | แก้ | เก็บสแนป `myLastReadId` ตอนจอเปิด (ย้ายมาจาก view) |
| `WBW/MainTabView.swift` | แก้ | ตัด `chatOpen` ทิ้ง · ถือ `groupPath` · คำนวณ `chatVisible` |

---

### Task 1: `Me.leaveQuota` + ข้อความโควตา

**Files:**
- Create: `WBW/GroupQuotaText.swift`, `WBWTests/GroupQuotaTextTests.swift`, `WBWTests/MeDecodeTests.swift`
- Modify: `WBW/Models.swift:37-60` (`struct Me`)

**Interfaces:**
- Produces: `Me.leaveQuota: Int?` · `GroupQuotaText.joinWarning(groupNumber:quota:)`,
  `GroupQuotaText.leaveWarning(groupNumber:quota:)`, `GroupQuotaText.remaining(quota:)` — ทุกตัวคืน `String`
  และรับ `quota` เป็นสิทธิ์ **ก่อน** ทำรายการ

- [ ] **Step 1: เขียนเทสที่ต้องแดงก่อน**

`WBWTests/GroupQuotaTextTests.swift`:

```swift
import XCTest
@testable import WBW

/// ข้อความพวกนี้คือสิ่งเดียวที่บอกผู้ใช้ว่า "กดแล้วจะเสียอะไร" — ถ้าเลขเพี้ยนไปหนึ่ง ผู้ใช้ตัดสินใจผิด
/// แล้วแก้กลับเองไม่ได้ (สิทธิ์หักไปแล้ว) จึงตรึงทุกกรณีไว้ด้วยเทส
final class GroupQuotaTextTests: XCTestCase {

    func testJoinWarningWithQuotaLeft() {
        let s = GroupQuotaText.joinWarning(groupNumber: 7, quota: 1)
        XCTAssertTrue(s.contains("กลุ่ม 7"), s)
        XCTAssertTrue(s.contains("1 ครั้ง"), s)
    }

    func testJoinWarningWhenQuotaExhausted() {
        let s = GroupQuotaText.joinWarning(groupNumber: 12, quota: 0)
        XCTAssertTrue(s.contains("หมดแล้ว"), s)
        XCTAssertTrue(s.contains("เปลี่ยนกลุ่มไม่ได้อีก"), s)
        XCTAssertFalse(s.contains("0 ครั้ง"), "ห้ามบอกว่าเหลือ 0 ครั้ง — ต้องบอกผลที่ตามมาแทน: \(s)")
    }

    func testLeaveWarningWithMoreThanOneLeft() {
        let s = GroupQuotaText.leaveWarning(groupNumber: 3, quota: 2)
        XCTAssertTrue(s.contains("1 ครั้ง"), "เหลือ 2 ก่อนออก = เหลือ 1 หลังออก: \(s)")
    }

    func testLeaveWarningOnLastChance() {
        let s = GroupQuotaText.leaveWarning(groupNumber: 3, quota: 1)
        XCTAssertTrue(s.contains("อีกครั้งเดียว"), s)
    }

    func testRemaining() {
        XCTAssertTrue(GroupQuotaText.remaining(quota: 2).contains("2 ครั้ง"))
        XCTAssertTrue(GroupQuotaText.remaining(quota: 0).contains("ครบแล้ว"))
    }
}
```

`WBWTests/MeDecodeTests.swift`:

```swift
import XCTest
@testable import WBW

/// backend ที่ยังไม่ได้ deploy โควตา (หรือ backend ทดสอบตัวอื่น) ไม่ส่ง leave_quota มา —
/// ถ้า field นี้ไม่เป็น optional โปรไฟล์จะ decode ไม่ผ่านทั้งก้อน = แอปเปิดมาแล้วว่างทั้งจอ
/// โดยไม่มี error ให้เห็น เทสนี้ตรึงไว้ว่าต้องรอด
final class MeDecodeTests: XCTestCase {

    private func decode(_ json: String) throws -> Me {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(Me.self, from: Data(json.utf8))
    }

    func testDecodesWithoutLeaveQuota() throws {
        let me = try decode(#"{"user_id":"u1","username":"6931900011","role":"participant"}"#)
        XCTAssertNil(me.leaveQuota)
    }

    func testDecodesLeaveQuota() throws {
        let me = try decode(#"{"user_id":"u1","username":"x","role":"participant","leave_quota":2}"#)
        XCTAssertEqual(me.leaveQuota, 2)
    }
}
```

- [ ] **Step 2: ลงทะเบียนไฟล์ใหม่แล้วรันให้เห็นว่าแดง**

Run:
```bash
xcodegen generate && xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -20
```
Expected: build error `cannot find 'GroupQuotaText' in scope` และ `value of type 'Me' has no member 'leaveQuota'`

- [ ] **Step 3: เพิ่ม field ใน `Me`**

ใน `struct Me` ต่อจาก `groupNumber`:

```swift
    /// สิทธิ์ออกจากกลุ่มคงเหลือ · optional เพราะ backend ที่ยังไม่ได้ deploy โควตาไม่ส่ง key นี้มา
    /// ผู้ใช้ค่านี้ต้องอ่านเป็น `?? 0` เสมอ — พลาดไปทาง "ไม่มีสิทธิ์" ปลอดภัยกว่าทาง "แจกฟรี"
    let leaveQuota: Int?
```

- [ ] **Step 4: เขียน `GroupQuotaText`**

`WBW/GroupQuotaText.swift`:

```swift
import Foundation

/// ข้อความทั้งหมดที่พูดถึงสิทธิ์ออกจากกลุ่ม — ฟังก์ชันบริสุทธิ์ ไม่มี view/state
///
/// `quota` ของทุกฟังก์ชันคือสิทธิ์ **ก่อน** ทำรายการเสมอ (ค่าที่อ่านได้จากโปรไฟล์ ณ ตอนนั้น)
/// การเข้ากลุ่มไม่หักสิทธิ์ ส่วนการออกหัก 1 — ตัวข้อความคำนวณผลลัพธ์ให้เอง ผู้เรียกไม่ต้องลบเอง
/// ไม่งั้นจุดเรียกแต่ละที่จะลบกันคนละแบบจนเลขไม่ตรงกัน
enum GroupQuotaText {

    static func joinWarning(groupNumber: Int, quota: Int) -> String {
        quota > 0
            ? "หลังเข้ากลุ่ม \(groupNumber) แล้ว ท่านเหลือสิทธิ์ออกจากกลุ่มอีก \(quota) ครั้ง"
            : "สิทธิ์ออกจากกลุ่มของท่านหมดแล้ว เข้ากลุ่ม \(groupNumber) แล้วจะเปลี่ยนกลุ่มไม่ได้อีก"
    }

    // quota <= 0 แยกเคสเอง (แก้ 2026-08-10 หลังรีวิว) — เดิมใช้ max(quota-1, 0) ตัวเดียว ทำให้ 0 กับ 1
    // ได้ประโยคเดียวกันคือ "เลือกกลุ่มใหม่ได้อีกครั้งเดียว" ซึ่งเป็นคำสัญญาเท็จกับคนที่สิทธิ์หมดไปแล้ว
    static func leaveWarning(groupNumber: Int, quota: Int) -> String {
        guard quota > 0 else {
            return "สิทธิ์ออกจากกลุ่มของท่านหมดแล้ว ไม่สามารถออกจากกลุ่ม \(groupNumber) ได้อีก"
        }
        let after = quota - 1
        return after == 0
            ? "ออกจากกลุ่ม \(groupNumber) แล้วสิทธิ์จะหมด — เลือกกลุ่มใหม่ได้อีกครั้งเดียว แล้วจะออกไม่ได้อีก"
            : "หลังออกจากกลุ่ม \(groupNumber) ท่านจะเหลือสิทธิ์ออกจากกลุ่มอีก \(after) ครั้ง"
    }

    // ใช้คำว่า "สิทธิ์ออกจากกลุ่ม" ให้ตรงกับที่อื่นทั้งฟีเจอร์ (เดิมเขียนว่า "สิทธิ์เปลี่ยนกลุ่ม" อยู่ที่เดียว)
    static func remaining(quota: Int) -> String {
        quota > 0 ? "สิทธิ์ออกจากกลุ่มคงเหลือ \(quota) ครั้ง" : "สิทธิ์ออกจากกลุ่มของท่านหมดแล้ว"
    }
}
```

- [ ] **Step 5: รันเทสให้เขียว**

Run:
```bash
xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "GroupQuotaText|MeDecode|Test Suite .* passed|failed"
```
Expected: เทสทั้ง 7 ตัวผ่าน

- [ ] **Step 6: Commit**

```bash
git add WBW/GroupQuotaText.swift WBW/Models.swift \
        WBWTests/GroupQuotaTextTests.swift WBWTests/MeDecodeTests.swift project.yml WBW.xcodeproj
git commit -m "feat(group): ข้อความสิทธิ์ออกจากกลุ่ม + อ่าน leave_quota จากโปรไฟล์"
```

---

### Task 2: `leaveGroup` เลิกกลืน error

**Files:**
- Create: `WBWTests/GroupLeaveTransportTests.swift`
- Modify: `WBW/APIClient.swift:231-233` (`leaveGroup`)

**Interfaces:**
- Produces: `APIClient.leaveGroup(token:)` โยน `AppError.message(<ข้อความจาก server>)` เมื่อ status ไม่ใช่ 200

ปัญหาของเดิม: `leaveGroup` เรียก `deviceCall` ซึ่งลงท้ายด้วย `_ = try? await Self.send(req)` —
**กลืนทุก error รวมทั้ง 409** ถ้าไม่แก้ ผู้ใช้จะกดออกจากกลุ่มตอนสิทธิ์หมดแล้วจอเงียบสนิท
ไม่มีอะไรเกิดขึ้นและไม่มีคำอธิบาย

- [ ] **Step 1: เขียนเทสที่ต้องแดงก่อน**

`WBWTests/GroupLeaveTransportTests.swift`:

```swift
import XCTest
@testable import WBW

/// พิสูจน์ว่า 409 จาก /groups/leave เดินทางถึงผู้เรียกจริง ไม่ถูกกลืนระหว่างทาง
/// (ของเดิม leaveGroup ใช้ deviceCall ซึ่ง `try?` ทิ้งทุก error — จอจะเงียบสนิทตอนสิทธิ์หมด)
/// วิธีเดียวกับ FeedbackTransportTests: URLProtocol ปลอมดัก URLSession.shared
final class GroupLeaveTransportTests: XCTestCase {

    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var body = Data()

        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.path.hasSuffix("/groups/leave") == true
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(StubURLProtocol.self)
    }
    override func tearDown() {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        super.tearDown()
    }

    func testLeaveConflictSurfacesServerMessage() async {
        StubURLProtocol.status = 409
        StubURLProtocol.body = Data(#"{"error":"สิทธิ์ออกจากกลุ่มหมดแล้ว"}"#.utf8)
        do {
            try await APIClient.shared.leaveGroup(token: "t")
            XCTFail("ต้องโยน error ไม่ใช่ผ่านเงียบ ๆ")
        } catch {
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "สิทธิ์ออกจากกลุ่มหมดแล้ว")
        }
    }

    func testLeaveSuccessDoesNotThrow() async throws {
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data(#"{"ok":true}"#.utf8)
        try await APIClient.shared.leaveGroup(token: "t")
    }
}
```

- [ ] **Step 2: รันให้เห็นว่าแดง**

Run:
```bash
xcodegen generate && xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:WBWTests/GroupLeaveTransportTests 2>&1 | tail -20
```
Expected: `testLeaveConflictSurfacesServerMessage` FAIL ที่ `ต้องโยน error ไม่ใช่ผ่านเงียบ ๆ`

- [ ] **Step 3: เขียน `leaveGroup` ใหม่**

```swift
    /// ออกจากกลุ่ม — ไม่ใช้ deviceCall เพราะตัวนั้น `try?` ทิ้งทุก error ทิ้ง (ตั้งใจสำหรับ device token
    /// ที่ล้มเหลวแล้วไม่มีอะไรให้ผู้ใช้ทำ) · ที่นี่ 409 "สิทธิ์ออกจากกลุ่มหมดแล้ว" คือคำตอบที่ผู้ใช้
    /// ต้องเห็น ไม่ใช่ความเงียบ
    func leaveGroup(token: String) async throws {
        guard let url = URL(string: "\(Config.apiBase)/groups/leave") else {
            throw AppError.message("URL ไม่ถูกต้อง")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.offline }
        guard let http = resp as? HTTPURLResponse else { throw AppError.message("ผิดพลาด") }
        if http.statusCode == 200 { return }
        let b = try? JSONDecoder().decode(APIErrorBody.self, from: data)
        throw AppError.message(b?.error ?? "ออกจากกลุ่มไม่สำเร็จ")
    }
```

- [ ] **Step 4: รันเทสให้เขียว**

Run: คำสั่งเดิมจาก Step 2
Expected: PASS ทั้ง 2 ตัว

- [ ] **Step 5: Commit**

```bash
git add WBW/APIClient.swift WBWTests/GroupLeaveTransportTests.swift project.yml WBW.xcodeproj
git commit -m "fix(group): ออกจากกลุ่มไม่สำเร็จต้องมีข้อความ ไม่ใช่เงียบ"
```

---

### Task 3: `ChatSession` เก็บสแนปเส้น "ข้อความใหม่" เอง

**Files:**
- Modify: `WBW/Chat/ChatSession.swift:118-126` (`setScreenVisible`)
- Modify: `WBW/GroupChatView.swift:17-23, 54-64, 92-95`

**Interfaces:**
- Produces: `ChatSession.unreadLineSnapshot: Int64` (`@Published private(set)`) — ค่า `myLastReadId`
  ณ วินาทีที่จอแชทเปิด · `.max` เมื่อจอปิด (แปลว่า "อ่านหมดแล้ว" ไม่ใช่ "ยังไม่อ่านเลย")

เหตุผลที่ต้องย้าย: Task 5 จะให้ `MainTabView` เป็นคนเรียก `setScreenVisible` ซึ่งเกิด**นอก** `GroupChatView`
ลำดับ "สแนปก่อน markRead" จึงรักษาไว้ใน view ไม่ได้อีก · เอาความรู้เรื่องลำดับไปไว้ในตัว
`ChatSession` เองแทน ผู้เรียกจะเรียกจากที่ไหนก็ถูกเสมอ

- [ ] **Step 1: เพิ่มเทสที่ต้องแดงก่อน**

ต่อท้าย `WBWTests/ChatSessionTests.swift`:

```swift
    /// เส้น "ข้อความใหม่" คำนวณจากค่านี้ · ถ้าอ่านค่าสดจาก myLastReadId เส้นจะไม่มีวันโผล่
    /// เพราะ setScreenVisible เรียก markRead() ซึ่งดัน myLastReadId ขึ้นสุดในเฟรมเดียวกัน
    @MainActor
    func testUnreadLineSnapshotTakenBeforeMarkRead() {
        let s = ChatSession()
        s.testSetup(groupId: 1, myId: "me")
        XCTAssertEqual(s.unreadLineSnapshot, .max, "ก่อนเปิดจอต้องแปลว่าอ่านหมดแล้ว")

        s.setScreenVisible(true)
        XCTAssertEqual(s.unreadLineSnapshot, 0, "สแนปต้องเป็นค่า myLastReadId ก่อน markRead")

        s.setScreenVisible(false)
        XCTAssertEqual(s.unreadLineSnapshot, .max, "ปิดจอแล้วต้องรีเซ็ตกลับ")
    }
```

- [ ] **Step 2: รันให้เห็นว่าแดง**

Run:
```bash
xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:WBWTests/ChatSessionTests 2>&1 | tail -15
```
Expected: build error `value of type 'ChatSession' has no member 'unreadLineSnapshot'`

- [ ] **Step 3: เพิ่มใน `ChatSession`**

ประกาศข้าง `@Published` ตัวอื่น:

```swift
    /// ค่า myLastReadId ณ วินาทีที่จอแชทเปิด — ChatRowBuilder ใช้วางเส้น "ข้อความใหม่"
    ///
    /// เริ่มที่ .max ไม่ใช่ 0 ตั้งใจ: "ยังไม่สแนป" ต้องแปลว่า "อ่านหมดแล้ว" ไม่ใช่ "ยังไม่อ่านเลย"
    /// ถ้าเริ่มที่ 0 เฟรมแรกก่อนสแนปจะมองว่าข้อความคนอื่นแทบทุกอันยังไม่อ่าน เส้นจะไปโผล่ที่
    /// ข้อความเก่าสุดก่อนวาบไปตำแหน่งจริง
    @Published private(set) var unreadLineSnapshot: Int64 = .max
```

ใน `setScreenVisible` สแนป**ก่อน** `markRead()`:

```swift
    func setScreenVisible(_ visible: Bool) {
        screenVisible = visible
        heartbeatTask?.cancel(); heartbeatTask = nil
        guard visible else {
            unreadLineSnapshot = .max   // เปิดครั้งหน้าคำนวณจากค่า ณ ตอนนั้นใหม่ทั้งหมด
            return
        }
        unreadLineSnapshot = myLastReadId   // ต้องมาก่อน markRead() บรรทัดล่าง — markRead ดันค่าขึ้นสุดทันที
        UNUserNotificationCenter.current().setBadgeCount(0)
        markRead()
        armHeartbeat()
    }
```

- [ ] **Step 4: ให้ `GroupChatView` อ่านค่าจาก store**

- ลบ `@State private var readSnapshot` พร้อมคอมเมนต์ยาวเหนือมัน (ย้ายสาระไปอยู่ที่ `ChatSession` แล้ว)
- ใน `rows` เปลี่ยน `myLastReadId: readSnapshot` เป็น `myLastReadId: store.unreadLineSnapshot`
- ใน `.task` ลบบรรทัด `readSnapshot = ...` และใน `.onDisappear` ลบบรรทัด `readSnapshot = .max`
  (คงบรรทัด `store.setScreenVisible(...)` ไว้ก่อน — Task 5 จะมาเอาออกทีเดียว)

- [ ] **Step 5: รันเทสทั้งชุดแชทให้เขียว**

Run:
```bash
xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:WBWTests/ChatSessionTests -only-testing:WBWTests/ChatRowTests 2>&1 | tail -15
```
Expected: PASS ทั้งหมด

- [ ] **Step 6: Commit**

```bash
git add WBW/Chat/ChatSession.swift WBW/GroupChatView.swift WBWTests/ChatSessionTests.swift
git commit -m "refactor(chat): ย้ายสแนปเส้นข้อความใหม่เข้า ChatSession ให้ลำดับถูกไม่ว่าใครเรียก"
```

---

### Task 4: แท็บกลุ่มเป็น NavigationStack เดียว

**Files:**
- Modify: `WBW/GroupTabView.swift:1-17`
- Modify: `WBW/GroupJoinView.swift:13-46` (ถอด `NavigationStack`)
- Modify: `WBW/GroupChatView.swift:31-83` (หัวจอเป็นปุ่ม, ตัด `onClose`)

**Interfaces:**
- Consumes: `GroupChatView(store:)` ไม่มีพารามิเตอร์ `onClose` อีกต่อไป
- Produces: `enum GroupRoute: Hashable { case home, members }` · `GroupTabView(path:onBack:)`
  — `path` เป็น `Binding<[GroupRoute]>` ที่ `MainTabView` ถือ (Task 5 ใช้)

- [ ] **Step 1: เขียน `GroupTabView` ใหม่**

```swift
/// ปลายทางที่ push ต่อจากจอแชทได้ — แชทเป็นรากของแท็บ ไม่ใช่ overlay อีกต่อไป
enum GroupRoute: Hashable {
    case home       // กลุ่มของฉัน (ออกจากกลุ่ม, สิทธิ์คงเหลือ)
    case members    // รายชื่อสมาชิก
}

/// แท็บ 3 — ยังไม่เข้ากลุ่ม = หน้าจับกลุ่ม · เข้าแล้ว = จอแชทเลย (หน้ากลุ่มอยู่หลังการกดหัวจอ)
struct GroupTabView: View {
    @EnvironmentObject var profile: ProfileStore
    @ObservedObject var chat: ChatSession
    @Binding var path: [GroupRoute]
    var onBack: () -> Void = {}

    var body: some View {
        // NavigationStack ตัวเดียวของทั้งแท็บ — ทั้งสองสาขาใช้ร่วมกัน ไม่งั้น NavigationLink
        // ในหน้าจับกลุ่ม (ดูสมาชิกก่อนเข้ากลุ่ม) จะไม่มี stack ให้ push แล้วกดแล้วไม่ไปไหนเงียบ ๆ
        NavigationStack(path: $path) {
            Group {
                if profile.me?.groupId == nil {
                    GroupJoinView(onBack: onBack)
                } else {
                    GroupChatView(store: chat)
                }
            }
            .navigationDestination(for: GroupRoute.self) { route in
                switch route {
                case .home:
                    GroupHomeView(path: $path)
                case .members:
                    GroupMembersView(groupId: profile.me?.groupId ?? 0,
                                     groupNumber: profile.me?.groupNumber ?? 0)
                }
            }
        }
    }
}
```

- [ ] **Step 2: ถอด `NavigationStack` ออกจาก `GroupJoinView`**

ลบ `NavigationStack {` (บรรทัด 14) กับวงเล็บปิดของมัน แล้วเลื่อน `.navigationBarHidden(true)`
และ `.task { ... }` มาติดกับ `ZStack` แทน · `NavigationLink` ดูสมาชิกในการ์ดกลุ่มไม่ต้องแก้ —
มันจะใช้ stack ของ `GroupTabView` เอง

- [ ] **Step 3: หัวจอแชทเป็นปุ่ม**

ใน `GroupChatView` ลบ `let onClose: () -> Void` แล้วเขียน `header` ใหม่:

```swift
    /// หัวจอ = ทางเข้าเดียวไปหน้ากลุ่ม (ไม่มีปุ่มปิดแล้ว — แชทเป็นแท็บ ไม่ใช่จอที่ลอยทับ)
    private var header: some View {
        NavigationLink(value: GroupRoute.home) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("กลุ่ม \(profile.me?.groupNumber.map(String.init) ?? "")")
                            .font(.system(size: 17, weight: .bold)).foregroundStyle(Color.wbwInk)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    Text("\(store.memberCount) คน").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())   // แตะได้ทั้งแถบ ไม่ใช่เฉพาะบนตัวอักษร
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        .background(Color.wbwBg)
    }
```

และเพิ่ม `.navigationBarHidden(true)` ที่ `VStack` นอกสุดของ `body` (หัวจอเป็นของเราเอง)

- [ ] **Step 4: เปลี่ยน `GroupHomeView` ให้รับ `path`**

Task นี้เปลี่ยน call site ของ `GroupHomeView` แล้ว ต้องเปลี่ยนตัวมันให้ตรงกันในรอบเดียว
ไม่งั้น compile ไม่ผ่าน (เนื้อหาโควตาเข้ามาใน Task 6):

- ลบ `var onOpenChat: () -> Void = {}` แล้วใส่ `@Binding var path: [GroupRoute]` แทน
- ลบปุ่ม "เปิดแชทกลุ่ม" ทั้งบล็อก — แชทเป็นรากของ stack แล้ว หน้านี้อยู่ *บน* แชท การมีปุ่มพากลับ
  ไปที่แชทซ้อนอีกชั้นทำให้ stack ลึกขึ้นเรื่อย ๆ ทุกครั้งที่กด
- เปลี่ยน `NavigationLink { GroupMembersView(...) }` เป็นปุ่มที่ทำ `path.append(.members)`
  (ปลายทางประกาศไว้ที่ `navigationDestination` ของ `GroupTabView` แล้ว)
- ลบ `NavigationStack { ... }` ที่ห่อ `body` ของ `GroupHomeView` ออก แล้วย้าย `.navigationTitle` /
  `.navigationBarTitleDisplayMode` มาติดกับ `ZStack` แทน — ตอนนี้มันเป็นหน้าที่ถูก push ไม่ใช่รากของ stack

- [ ] **Step 5: แก้ call site ใน `MainTabView` ให้ compile ผ่านชั่วคราว**

Task 5 จะรื้อไฟล์นี้จริง ตอนนี้แค่ทำให้ build ผ่าน:

```swift
                Tab(value: 3) {
                    GroupTabView(chat: chat, path: .constant([]), onBack: { tab = 0 })
                } label: { ... }
```
และในบล็อก overlay เปลี่ยน `GroupChatView(store: chat, onClose: { chatOpen = false })`
เป็น `GroupChatView(store: chat)` (ตัว overlay จะถูกลบทั้งบล็อกใน Task 5)

Run: `xcodebuild -scheme WBW -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add WBW/GroupTabView.swift WBW/GroupJoinView.swift WBW/GroupChatView.swift WBW/MainTabView.swift
git commit -m "feat(group): แท็บกลุ่มเป็น NavigationStack เดียว มีแชทเป็นราก"
```

---

### Task 5: ตัด `chatOpen` ออกจาก `MainTabView`

**Files:**
- Modify: `WBW/MainTabView.swift` — บรรทัด `16` (`chatOpen`), `51-56` (Tab 3), `101-109` (`uitestChatCloseAfter`), `176-190` (`.openGroupChat`), `216-223` (`kickedOut`), `224-239` (scene gate), `241-265` (overlay + toast), `286-288` (animation), `342-373` (`updateSceneGate`, `canShowCheckinToast`)

**Interfaces:**
- Consumes: `GroupTabView(chat:path:onBack:)` จาก Task 4
- Produces: จอแชทเปิด/ปิดถูกกำหนดโดย `chatVisible` ตัวเดียว — `ChatSession.setScreenVisible` ไม่ถูกเรียกจากที่อื่นอีก

- [ ] **Step 1: แทน `chatOpen` ด้วย `groupPath`**

```swift
    // เส้นทางของแท็บกลุ่ม — ว่าง = อยู่ที่จอแชท · ถือไว้ที่นี่เพราะ push แจ้งเตือนและ toast
    // ต้องสั่งเด้งกลับรากได้จากข้างนอก GroupTabView
    @State private var groupPath: [GroupRoute] = []
```

- [ ] **Step 2: แก้ Tab 3 และลบ overlay**

```swift
                Tab(value: 3) {
                    GroupTabView(chat: chat, path: $groupPath, onBack: { tab = 0 })
                } label: {
                    Image(systemName: profile.me?.groupId == nil ? "sharedwithyou" : "message.fill")
                }
                .badge(chat.unreadCount)
```

ลบทั้งบล็อก `if chatOpen, profile.me?.groupId != nil { GroupChatView(...) ... }` และ
`.animation(..., value: chatOpen)`

- [ ] **Step 3: เปลี่ยนทุกจุดที่เคยอ่าน `chatOpen`**

| จุด | แก้เป็น |
|---|---|
| `.onReceive(...openGroupChat)` | `tab = 3; groupPath = []` (แทน `chatOpen = true`) |
| ChatToast `if let m = chat.incoming, !chatOpen` | `if let m = chat.incoming, tab != 3` |
| toast แชท `onTap` | `chat.incoming = nil; tab = 3; groupPath = []` |
| `canShowCheckinToast` | `tab != 3 && !showNotifications && feedbackCheckpoint == nil && chat.incoming == nil` |
| `.onChange(of: chat.kickedOut)` | `groupPath = []` (แทน `chatOpen = false`) |
| `updateSceneGate()` | `host.suppressed = !(tab == 0 || tab == 4)` |
| `.onChange(of: chatOpen) { updateSceneGate() }` | ลบทิ้ง |
| `uitestChat` (DEBUG) | `if UserDefaults.standard.bool(forKey: "uitestChat") { tab = 3 }` |
| `uitestChatCloseAfter` (DEBUG) | ลบทั้งบล็อก — ไม่มีจอให้ปิดแล้ว |

- [ ] **Step 4: คุม `setScreenVisible` ที่เดียว**

เพิ่ม property + modifier:

```swift
    /// จอแชทกำลังถูกมองเห็นจริงไหม — TabView เก็บ view ไว้ตอนสลับแท็บ และ NavigationStack push
    /// ทับก็ไม่รับประกันว่า onDisappear จะยิง จึงเชื่อ lifecycle ของ view ไม่ได้ ต้องคำนวณเอง
    /// ไม่คุมตรงนี้ = heartbeat วิ่งค้างตอนผู้ใช้ไปแท็บอื่น server เข้าใจว่ายังจ้อจออยู่แล้วไม่ส่ง
    /// push ให้เลย (พังเงียบสนิท ไม่มี error ให้เห็น)
    private var chatVisible: Bool {
        tab == 3 && profile.me?.groupId != nil && groupPath.isEmpty
    }
```

```swift
            .onChange(of: chatVisible) { _, visible in chat.setScreenVisible(visible) }
```

และใน `.task` ตัวแรก หลัง `chat.configure(...)` เพิ่ม `chat.setScreenVisible(chatVisible)`
(`onChange` ไม่ยิงตอน mount — เข้าแอปมาที่แท็บ 3 เลยจะไม่มีใครบอก store ว่าจอเปิดอยู่)

- [ ] **Step 5: ลบการเรียกใน `GroupChatView`**

ลบ `.task { store.setScreenVisible(true) ... }` เฉพาะบรรทัด `setScreenVisible` และลบ `.onDisappear`
ทั้งบล็อก · `.task` ที่เหลือยังต้องโหลด `members` อยู่เหมือนเดิม

- [ ] **Step 6: build + รันเทสทั้งชุด**

Run:
```bash
xcodegen generate && xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED` + เทสทั้งหมดผ่าน

- [ ] **Step 7: ตรวจด้วยตาบน simulator**

```bash
xcrun simctl boot 'iPhone 17' 2>/dev/null
APP=$(xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' -showBuildSettings 2>/dev/null \
  | awk -F'= ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)/WBW.app
xcrun simctl install booted "$APP"
xcrun simctl launch booted th.ac.mfu.wbwSwift -uitestTab 3
sleep 4 && xcrun simctl io booted screenshot /tmp/wbw-tab3-chat.png
```
Expected: ภาพต้องเป็นจอแชท (หัวจอ "กลุ่ม N" + ช่องพิมพ์) ไม่ใช่การ์ด "กลุ่มของฉัน" — ต้องล็อกอิน
ด้วยบัญชีที่มีกลุ่มก่อน · เปิดภาพดูจริงด้วย `Read` ไม่ใช่เชื่อว่าไฟล์มีอยู่แล้วจบ

- [ ] **Step 8: ตรวจว่า heartbeat หยุดจริงตอนสลับแท็บ**

```bash
xcrun simctl launch --console booted th.ac.mfu.wbwSwift -uitestTab 3 -uitestTabSequence "8:0" 2>&1 | grep "\[chat\]"
```
Expected: บรรทัด `[chat] heartbeat` โผล่ช่วง 10 วิแรก แล้ว**หยุด**หลังวินาทีที่ 8 (สลับไปแท็บ 0)
ถ้ายังโผล่ต่อ แปลว่า `chatVisible` ไม่ได้ถูกผูก

- [ ] **Step 9: Commit**

```bash
git add WBW/MainTabView.swift WBW/GroupChatView.swift
git commit -m "feat(group): แชทเป็นเนื้อของแท็บ 3 เลิกใช้ overlay chatOpen"
```

---

### Task 6: หน้ากลุ่มของฉัน — สิทธิ์คงเหลือ + ปุ่มออกตามโควตา

**Files:**
- Modify: `WBW/GroupTabView.swift:20-87` (`GroupHomeView`)

**Interfaces:**
- Consumes: `GroupQuotaText`, `Me.leaveQuota`, `GroupRoute`
- Produces: `GroupHomeView(path: Binding<[GroupRoute]>)`

- [ ] **Step 1: เขียน `GroupHomeView` ใหม่**

```swift
/// หน้ากลุ่มของฉัน — เข้าถึงจากการกดหัวจอแชท · ดูสมาชิก / ดูสิทธิ์ / ออกจากกลุ่ม
struct GroupHomeView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @Binding var path: [GroupRoute]
    @State private var leaving = false
    @State private var confirmLeave = false
    @State private var error: String?

    private var groupNo: Int { profile.me?.groupNumber ?? 0 }
    /// อ่านเป็น 0 เมื่อไม่รู้ค่า — backend เก่าไม่ส่ง key นี้มา ปลอดภัยกว่าที่จะไม่โชว์ปุ่มออก
    /// (กดแล้วเจอ 409 จาก server อยู่ดี) ดีกว่าโชว์ปุ่มที่พาไปเจอทางตัน
    private var quota: Int { profile.me?.leaveQuota ?? 0 }

    var body: some View {
        ZStack {
            Color.wbwBg.ignoresSafeArea()
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("กลุ่มของฉัน").font(.system(size: 14)).foregroundStyle(.secondary)
                    Text("กลุ่ม \(groupNo)")
                        .font(.system(size: 34, weight: .heavy)).foregroundStyle(Color.wbwInk)
                    Text(GroupQuotaText.remaining(quota: quota))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
                .background(Color.wbwSurface, in: RoundedRectangle(cornerRadius: 20))

                Button { path.append(.members) } label: {
                    Label("สมาชิกในกลุ่ม", systemImage: "person.2.fill")
                        .font(.system(size: 16)).foregroundStyle(Color.wbwInk)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(Color.wbwSurface, in: RoundedRectangle(cornerRadius: 16))
                }

                Spacer()

                // สิทธิ์หมด = ไม่มีปุ่ม ไม่ใช่ปุ่มกดไม่ได้ — ไม่มีอะไรให้กดแล้วจริง ๆ
                // ปุ่มจาง ๆ ที่กดไม่ได้ชวนให้กดซ้ำแล้วสงสัยว่าแอปค้าง
                if quota > 0 {
                    Button(role: .destructive) { confirmLeave = true } label: {
                        Text(leaving ? "กำลังออก" : "ออกจากกลุ่ม")
                            .font(.system(size: 15)).foregroundStyle(.red)
                    }
                    .disabled(leaving)
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
            }
            .padding(20).padding(.top, 8)
        }
        .navigationTitle("กลุ่ม \(groupNo)")
        .navigationBarTitleDisplayMode(.inline)
        .alert("ออกจากกลุ่ม \(groupNo)?", isPresented: $confirmLeave) {
            Button("ยกเลิก", role: .cancel) {}
            Button("ออกจากกลุ่ม", role: .destructive) { Task { await leave() } }
        } message: {
            Text(GroupQuotaText.leaveWarning(groupNumber: groupNo, quota: quota))
        }
    }

    private func leave() async {
        guard let t = session.token else { return }
        error = nil
        leaving = true
        defer { leaving = false }
        do {
            try await APIClient.shared.leaveGroup(token: t)
            await profile.load(token: t)   // group_id = nil → GroupTabView สลับไปหน้าจับกลุ่มเอง
            path.removeAll()               // หน้านี้กำลังจะไม่มีกลุ่มให้แสดง เด้งกลับรากก่อน
        } catch {
            // 409 = admin ตัดสิทธิ์ระหว่างที่จอนี้เปิดค้าง หรือออกไปแล้วจากอีกเครื่อง
            // โหลดโปรไฟล์ใหม่ให้จอตรงกับความจริงทันที ไม่ใช่แค่โชว์ข้อความแล้วปล่อยค้าง
            self.error = (error as? LocalizedError)?.errorDescription ?? "ออกจากกลุ่มไม่สำเร็จ"
            await profile.load(token: t)
        }
    }
}
```

- [ ] **Step 2: build**

Run: `xcodebuild -scheme WBW -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: ตรวจด้วยตาทั้งสองสถานะ**

ตั้งโควตาผ่าน backend (ต้องมี admin token):
```bash
curl -s -X PATCH "$API/admin/participants/$UID" -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' -d '{"leave_quota": 1}' > /dev/null
```
เปิดแอป → แท็บ 3 → กดหัวจอ → ถ่ายภาพ: ต้องเห็น "สิทธิ์ออกจากกลุ่มคงเหลือ 1 ครั้ง" + ปุ่มออก
แล้วตั้งเป็น `0` ปิด-เปิดแอปใหม่ → ถ่ายอีกภาพ: ต้องเห็น "ท่านใช้สิทธิ์เปลี่ยนกลุ่มครบแล้ว" และ**ไม่มี**ปุ่มออก

```bash
xcrun simctl io booted screenshot /tmp/wbw-group-quota1.png
xcrun simctl io booted screenshot /tmp/wbw-group-quota0.png
```
เปิดทั้งสองภาพดูจริงด้วย `Read`

- [ ] **Step 4: ตรวจ alert ตอนกดออก**

กดปุ่ม "ออกจากกลุ่ม" ตอน quota = 1 แล้วถ่ายภาพ — ข้อความต้องเป็น
"ออกจากกลุ่ม N แล้วสิทธิ์จะหมด — เลือกกลุ่มใหม่ได้อีกครั้งเดียว แล้วจะออกไม่ได้อีก"

- [ ] **Step 5: Commit**

```bash
git add WBW/GroupTabView.swift
git commit -m "feat(group): หน้ากลุ่มของฉันบอกสิทธิ์คงเหลือ + ซ่อนปุ่มออกเมื่อสิทธิ์หมด"
```

---

### Task 7: ยืนยันก่อนเข้ากลุ่ม

**Files:**
- Modify: `WBW/GroupJoinView.swift:10-11, 22-29, 87-98` (`join`)

**Interfaces:**
- Consumes: `GroupQuotaText.joinWarning`, `Me.leaveQuota`

- [ ] **Step 1: เพิ่ม state และ alert**

```swift
    // กลุ่มที่รอการยืนยัน (nil = ไม่มี alert) — ผู้ใช้ต้องรู้ก่อนกดว่าจะเหลือสิทธิ์เท่าไร
    // ไม่ใช่รู้ทีหลังตอนอยากออกแล้วออกไม่ได้
    @State private var pendingJoin: GroupSummary?
```

เปลี่ยน `onJoin` ของการ์ดเป็น `onJoin: { pendingJoin = g }` แล้วเพิ่มต่อจาก `.task { ... }`:

```swift
            .alert("เข้ากลุ่ม \(pendingJoin?.groupNumber ?? 0)?",
                   isPresented: Binding(get: { pendingJoin != nil },
                                        set: { if !$0 { pendingJoin = nil } }),
                   presenting: pendingJoin) { g in
                Button("ยกเลิก", role: .cancel) { pendingJoin = nil }
                Button("เข้ากลุ่ม") {
                    let target = g
                    pendingJoin = nil
                    Task { await join(target) }
                }
            } message: { g in
                Text(GroupQuotaText.joinWarning(groupNumber: g.groupNumber,
                                                quota: profile.me?.leaveQuota ?? 0))
            }
```

- [ ] **Step 2: ให้ `join` จัดการ 409 ด้วย**

ใน `catch` ของฟังก์ชัน `join` เพิ่มการโหลดโปรไฟล์ใหม่:

```swift
        } catch {
            // 409 "ท่านอยู่ในกลุ่มอยู่แล้ว" = เข้ากลุ่มไปแล้วจากอีกเครื่อง · โหลดโปรไฟล์ใหม่
            // ให้แท็บสลับไปจอแชทเอง แทนที่จะค้างอยู่หน้าลิสต์พร้อม error ที่ผู้ใช้แก้ไม่ได้
            self.error = (error as? LocalizedError)?.errorDescription ?? "เข้ากลุ่มไม่สำเร็จ"
            await profile.load(token: t)
        }
```

- [ ] **Step 3: build**

Run: `xcodebuild -scheme WBW -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: ตรวจด้วยตาทั้งสองข้อความ**

บัญชีที่ไม่มีกลุ่ม + quota = 1 → กด "เข้ากลุ่ม" → ภาพ: "หลังเข้ากลุ่ม N แล้ว ท่านเหลือสิทธิ์ออกจากกลุ่มอีก 1 ครั้ง"
ตั้ง quota = 0 แล้วทำซ้ำ → ภาพ: "สิทธิ์ออกจากกลุ่มของท่านหมดแล้ว เข้ากลุ่ม N แล้วจะเปลี่ยนกลุ่มไม่ได้อีก"

```bash
xcrun simctl io booted screenshot /tmp/wbw-join-quota1.png
xcrun simctl io booted screenshot /tmp/wbw-join-quota0.png
```

- [ ] **Step 5: Commit**

```bash
git add WBW/GroupJoinView.swift
git commit -m "feat(group): เตือนสิทธิ์คงเหลือก่อนยืนยันเข้ากลุ่ม"
```

---

### Task 8: เดินครบเส้นจริงบนเครื่อง

**Files:** ไม่แก้โค้ด (ถ้าเจอบั๊ก ให้แก้แล้ว commit แยกพร้อมเทสที่จับบั๊กนั้น)

- [ ] **Step 1: รันเทสทั้งหมด**

Run: `xcodebuild -scheme WBW -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -12`
Expected: ผ่านทั้งหมด ไม่มี skip ที่ไม่ได้ตั้งใจ

- [ ] **Step 2: เดินสถานการณ์จริงตามสเปกข้อ 2**

บัญชีทดสอบ quota = 1 ไม่มีกลุ่ม แล้วทำตามลำดับนี้ ถ่ายภาพทุกขั้น:
1. แท็บ 3 = หน้าลิสต์กลุ่ม → กดเข้ากลุ่ม → alert บอกเหลือ 1 ครั้ง → ยืนยัน
2. แท็บ 3 กลายเป็นจอแชททันที (ไม่มีหน้าคั่น)
3. กดหัวจอ → หน้ากลุ่มของฉัน มีปุ่มออก + "คงเหลือ 1 ครั้ง"
4. กดออก → alert เตือนว่าจะหมด → ยืนยัน → กลับไปหน้าลิสต์กลุ่ม
5. เข้ากลุ่มใหม่ → alert บอกว่าสิทธิ์หมด → ยืนยัน → จอแชท
6. กดหัวจอ → **ไม่มี**ปุ่มออกแล้ว

- [ ] **Step 3: ตรวจ push เข้าแชท**

ส่ง push type `chat` ขณะอยู่แท็บ 0 → แตะ → ต้องลงที่แท็บ 3 ที่จอแชท (ไม่ใช่หน้ากลุ่มของฉัน)
ถ้าตอนนั้นค้างอยู่หน้าสมาชิก ต้องเด้งกลับรากให้ด้วย

- [ ] **Step 4: ตรวจ toast ในแอป**

อยู่แท็บ 0 แล้วให้เพื่อนส่งข้อความ → ต้องมี ChatToast · อยู่แท็บ 3 (จอแชท) แล้วส่งอีกครั้ง →
**ต้องไม่มี** toast (เห็นข้อความอยู่แล้ว)

- [ ] **Step 5: ตรวจตอนถูกเตะออกจากกลุ่ม**

ให้ admin ย้ายบัญชีทดสอบออกจากกลุ่มผ่าน dashboard ขณะจอแชทเปิดค้าง → ภายใน ~25 วิ
แท็บ 3 ต้องกลายเป็นหน้าลิสต์กลุ่มเอง ไม่ค้างที่จอแชทเปล่า

- [ ] **Step 6: บันทึกผลการตรวจ**

เขียน `docs/group-leave-quota-verification.md` — ทรงเดียวกับ `docs/checkin-feedback-verification.md`
ที่มีอยู่: ทำอะไร เห็นอะไร ภาพไหนประกอบ แล้ว commit

```bash
git add docs/group-leave-quota-verification.md
git commit -m "docs: บันทึกผลตรวจโควตาออกจากกลุ่มบนเครื่องจริง"
```

---

## เช็คก่อนปิดแผนนี้

- [ ] `xcodegen generate` แล้ว `git status` ไม่มีไฟล์ project ค้างที่ยังไม่ commit
- [ ] เทสทั้งชุดผ่านบน simulator จริง
- [ ] `Config.backend` ยังเป็นค่าเดิมที่ commit ไว้ (`git diff main -- WBW/Config.swift` ต้องว่าง)
- [ ] ไม่มีคำว่า `chatOpen` เหลือใน `WBW/` (`grep -rn chatOpen WBW/` ต้องไม่มีผล)
- [ ] มีภาพครบทุกสถานะในเอกสารตรวจ
