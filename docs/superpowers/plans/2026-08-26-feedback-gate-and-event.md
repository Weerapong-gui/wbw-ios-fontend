# Feedback Gate + Event Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ถึงฐานแล้วฟอร์มให้คะแนนยึดจอจนกว่าจะตอบ (ยกเว้น SOS) และจบครบทุกฐานแล้วถามความเห็นทั้งงานหนึ่งครั้ง — ตรงกับ Android 0.3.0

**Architecture:** logic ตัดสินว่า gate ต้องขึ้นอะไรเป็น `static func` บริสุทธิ์ (`FeedbackGateState.decide`) · `MainTabView` ถือ `fullScreenCover(item:)` ใบเดียวขับด้วยค่าจาก `CheckinProgressStore` ที่ poll+push อยู่แล้ว · `FeedbackView` เดิมได้สองโหมดใหม่ (`blocking`, `kind: .base/.event`) · endpoint event ยังไม่มีใน SUS — 404 พาให้ปุ่มข้ามโผล่

**Tech Stack:** SwiftUI, XCTest, URLProtocol stub (ท่าเดียวกับ `ChatSyncTransportTests`)

**Spec:** `docs/superpowers/specs/2026-08-26-feedback-gate-and-event-design.md`

## Global Constraints

- ข้อความผู้ใช้เห็นผ่านคีย์ localization เสมอ · นอก View ใช้ `Loc.t("key")` (กติกา skill ข้อ 10)
- คำในคีย์ใหม่ต้องตรง Android คำต่อคำ (strings.xml เทียบด้านล่าง)
- TDD: เทส fail ก่อนเสมอ · assert มีข้อความไทยบอกเหตุผล
- `git add` ทีละไฟล์ · commit ภาษาไทยบอก "ทำไม"
- ไฟล์ใหม่ = `xcodegen generate` ก่อน build
- จอใหม่/แก้จอ = สกรีนช็อต simulator ประกอบ

---

### Task 1: `CheckinProgress` รู้จัก `event_feedback_answered` + `complete`

**Files:**
- Modify: `WBW/Models.swift:405-425` (struct `CheckinProgress`)
- Test: `WBWTests/FeedbackGateStateTests.swift` (สร้างใหม่ — ใช้ต่อใน Task 2)

**Interfaces:**
- Produces: `CheckinProgress.eventFeedbackAnswered: Bool`, `CheckinProgress.complete: Bool`, memberwise init มี default `eventFeedbackAnswered: Bool = false` (โค้ด/เทสเดิมที่สร้าง `CheckinProgress(total:checkedIn:)` ต้องคอมไพล์ผ่านโดยไม่แก้)

- [ ] **Step 1: เขียนเทส fail**

```swift
import XCTest
@testable import WBW

/// กติกาการตัดสินใจของ feedback gate — ยกจาก FeedbackGate.kt ฝั่ง Android คำต่อคำ
/// (สเปก: docs/superpowers/specs/2026-08-26-feedback-gate-and-event-design.md)
final class FeedbackGateStateTests: XCTestCase {

    private func item(_ id: Int, answered: Bool, at: String) -> CheckinProgressItem {
        CheckinProgressItem(checkpointId: id, name: "ฐาน \(id)", activityName: nil,
                            sequence: id, at: at, answered: answered,
                            rating: answered ? 4 : nil, comment: nil)
    }

    // ===== ฟิลด์ใหม่บน CheckinProgress =====

    /// server ยังไม่ส่ง event_feedback_answered มา (SUS ยังไม่มี endpoint) — ขาดต้องเป็น false
    /// ไม่ใช่ decode ล่ม: ถามซ้ำดีกว่าแอปเปิดไม่ขึ้น
    func testEventFeedbackAnsweredDefaultsToFalseWhenAbsent() throws {
        let json = #"{"total":2,"checked_in":[]}"#
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let p = try dec.decode(CheckinProgress.self, from: Data(json.utf8))
        XCTAssertFalse(p.eventFeedbackAnswered)
    }

    func testEventFeedbackAnsweredDecodesWhenPresent() throws {
        let json = #"{"total":2,"checked_in":[],"event_feedback_answered":true}"#
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let p = try dec.decode(CheckinProgress.self, from: Data(json.utf8))
        XCTAssertTrue(p.eventFeedbackAnswered)
    }

    /// complete สูตรเดียวกับ Android: total > 0 && count >= total —
    /// งานที่ไม่มีฐานเลยต้องไม่นับว่าจบ ไม่งั้น event form เด้งใส่ทุกคนตั้งแต่ยังไม่เริ่มเดิน
    func testCompleteRequiresANonZeroTotalFullyCollected() {
        XCTAssertFalse(CheckinProgress(total: 0, checkedIn: []).complete,
                       "งานที่ไม่มีฐาน = ยังไม่จบ ไม่ใช่จบตั้งแต่เกิด")
        XCTAssertFalse(CheckinProgress(total: 2, checkedIn: [item(1, answered: true, at: "a")]).complete)
        XCTAssertTrue(CheckinProgress(total: 1, checkedIn: [item(1, answered: true, at: "a")]).complete)
    }
}
```

หมายเหตุ: เช็ค signature จริงของ `CheckinProgressItem` ใน `WBW/Models.swift` ก่อน — ถ้า field ไม่ตรง (เช่นไม่มี `activityName`) ปรับ helper ให้คอมไพล์ตรงของจริง ห้ามแก้ struct จริงเพื่อให้เทสสวย

- [ ] **Step 2: รันให้เห็น fail** — `xcodegen generate` แล้ว `xcodebuild ... test -only-testing:WBWTests/FeedbackGateStateTests` คาด: compile error `eventFeedbackAnswered` ไม่มี

- [ ] **Step 3: แก้ `CheckinProgress`**

```swift
struct CheckinProgress: Codable, Equatable {
    let total: Int
    let checkedIn: [CheckinProgressItem]
    /// ตอบความเห็นทั้งงานไปแล้วหรือยัง — server เป็นคนจำ (หลักเดียวกับ answered ต่อฐาน:
    /// เครื่องไม่จำเอง กันลบแอป/เครื่องที่สองแล้วถามคนที่ตอบแล้วซ้ำ) · SUS ยังไม่ส่งฟิลด์นี้
    /// = false ไปก่อน ฟอร์มถามซ้ำได้แต่แอปห้ามเปิดไม่ขึ้น
    let eventFeedbackAnswered: Bool

    init(total: Int, checkedIn: [CheckinProgressItem], eventFeedbackAnswered: Bool = false) { ... }

    init(from decoder: Decoder) throws {
        // decodeIfPresent ?? false เฉพาะฟิลด์ใหม่ — total/checkedIn เข้มเท่าเดิม
    }

    /// ครบทุกฐานแล้วจริง — สูตรเดียวกับ Android (ProgressDto.complete)
    var complete: Bool { total > 0 && checkedIn.count >= total }
    // stage / pending เดิมคงไว้
}
```

(custom `init(from:)` ทำให้ memberwise หาย — เขียนคืนพร้อม default ตาม Produces)

- [ ] **Step 4: รันเทสไฟล์นี้ให้เขียว + รัน suite เต็มหนึ่งรอบ** (จุดเสี่ยง: ที่อื่นที่ decode/สร้าง `CheckinProgress`)

- [ ] **Step 5: Commit** — `feat(feedback): CheckinProgress รู้จัก event_feedback_answered กับ complete`

---

### Task 2: `FeedbackGateState.decide` — กติกา gate ทั้งหมดในฟังก์ชันเดียว

**Files:**
- Create: `WBW/Feedback/FeedbackGateState.swift`
- Test: `WBWTests/FeedbackGateStateTests.swift` (ต่อจาก Task 1)

**Interfaces:**
- Consumes: `CheckinProgress.complete`, `.eventFeedbackAnswered` (Task 1)
- Produces:

```swift
enum FeedbackGateState: Equatable {
    case base(CheckinProgressItem)
    case event
    /// ตัดสินว่า gate ต้องยึดจอด้วยอะไร — nil = ปล่อยแอปทำงานปกติ
    /// pending เรียง "เก่าก่อน" (ตอบตามลำดับที่เดินถึง) — ตรงข้าม CheckinProgress.pending
    /// ของ toast ที่ใหม่ก่อน
    static func decide(progress: CheckinProgress?, eventDismissed: Bool) -> FeedbackGateState?
}
```

- [ ] **Step 1: เขียนเทส fail** (เพิ่มใน `FeedbackGateStateTests`)

```swift
    // ===== decide =====

    func testNoProgressMeansNoGate() {
        XCTAssertNil(FeedbackGateState.decide(progress: nil, eventDismissed: false))
    }

    /// ทีละฐาน เรียงตามลำดับที่เดินถึง — โดนสแกนสามฐานตอนมือถืออยู่ในกระเป๋า
    /// ต้องเจอฟอร์มของฐานแรกก่อน ไม่ใช่ฐานล่าสุด (ตรงข้ามกับ toast)
    func testPendingBaseComesOldestFirst() {
        let p = CheckinProgress(total: 5, checkedIn: [
            item(3, answered: false, at: "2026-08-29T10:30:00Z"),
            item(1, answered: false, at: "2026-08-29T09:00:00Z"),
            item(2, answered: true,  at: "2026-08-29T10:00:00Z"),
        ])
        XCTAssertEqual(FeedbackGateState.decide(progress: p, eventDismissed: false),
                       .base(p.checkedIn[1]), "ฐานที่ถึงก่อนต้องถูกถามก่อน")
    }

    func testAllAnsweredButRouteUnfinishedMeansNoGate() {
        let p = CheckinProgress(total: 5, checkedIn: [item(1, answered: true, at: "a")])
        XCTAssertNil(FeedbackGateState.decide(progress: p, eventDismissed: false))
    }

    /// ครบทุกฐาน + ตอบครบ + ยังไม่เคยตอบทั้งงาน = ถึงคิว event form
    func testEventDueWhenRouteCompleteAndEverythingAnswered() {
        let p = CheckinProgress(total: 1, checkedIn: [item(1, answered: true, at: "a")])
        XCTAssertEqual(FeedbackGateState.decide(progress: p, eventDismissed: false), .event)
    }

    /// ฐานค้างตอบมาก่อน event เสมอ — แม้เส้นทางจะครบแล้ว
    func testPendingBaseBeatsEventEvenWhenComplete() {
        let p = CheckinProgress(total: 1, checkedIn: [item(1, answered: false, at: "a")])
        XCTAssertEqual(FeedbackGateState.decide(progress: p, eventDismissed: false),
                       .base(p.checkedIn[0]))
    }

    func testEventAnsweredOnServerMeansNoGate() {
        let p = CheckinProgress(total: 1, checkedIn: [item(1, answered: true, at: "a")],
                                eventFeedbackAnswered: true)
        XCTAssertNil(FeedbackGateState.decide(progress: p, eventDismissed: false))
    }

    /// ข้ามไปก่อน (ส่งไม่สำเร็จ) = เงียบแค่รันนี้ — decide เคารพ flag ที่ caller ถือ
    func testEventDismissedThisRunMeansNoGate() {
        let p = CheckinProgress(total: 1, checkedIn: [item(1, answered: true, at: "a")])
        XCTAssertNil(FeedbackGateState.decide(progress: p, eventDismissed: true))
    }
```

- [ ] **Step 2: รันให้เห็น fail** (compile error — type ไม่มี)

- [ ] **Step 3: implement**

```swift
import Foundation

/// gate ให้คะแนน — คำตอบเดียวของคำถาม "ตอนนี้ต้องยึดจอด้วยฟอร์มไหน"
///
/// ยกกติกามาจาก FeedbackGate.kt ฝั่ง Android คำต่อคำ (เหตุผลเต็มอยู่ในสเปก):
/// ฐานค้างตอบมาก่อนเสมอ ทีละฐานเรียงตามเวลาที่เดินถึง · event form เฉพาะเมื่อครบทุกฐาน
/// ตอบครบ server ยังไม่เคยได้คำตอบทั้งงาน และผู้ใช้ยังไม่กดข้ามในรันนี้
enum FeedbackGateState: Equatable {
    case base(CheckinProgressItem)
    case event

    static func decide(progress: CheckinProgress?, eventDismissed: Bool) -> FeedbackGateState? {
        guard let p = progress else { return nil }
        if let first = p.checkedIn.filter({ !$0.answered }).min(by: { $0.at < $1.at }) {
            return .base(first)
        }
        if p.complete && !p.eventFeedbackAnswered && !eventDismissed { return .event }
        return nil
    }
}
```

(เทียบ `at` เป็น string ตรง ๆ ได้ — สัญญา RFC3339 คงที่ที่ `CheckinProgress.pending` จดไว้แล้ว)

- [ ] **Step 4: รันให้เขียว**
- [ ] **Step 5: Commit** — `feat(feedback): FeedbackGateState.decide — กติกา gate เป็นฟังก์ชันบริสุทธิ์`

---

### Task 3: `POST /me/event-feedback` + `EventFeedbackDraft`

**Files:**
- Create: `WBW/Feedback/EventFeedbackDraft.swift`
- Modify: `WBW/APIClient.swift` (ข้าง `submitFeedback` ~บรรทัด 420)
- Test: `WBWTests/EventFeedbackTests.swift` (สร้างใหม่)

**Interfaces:**
- Produces:

```swift
struct EventFeedbackDraft: Codable, Equatable {
    let clientId: String
    let rating: Int                 // ภาพรวมทั้งเดิน — ข้อเดียวที่บังคับ
    var ratingActivity: Int?        // กิจกรรมตลอดเส้นทาง — ข้อที่ย้ายมาจากต่อฐาน
    let comment: String?
    let deviceTime: String
}
// APIClient:
static func eventFeedbackBody(draft: EventFeedbackDraft) -> [String: Any]
func submitEventFeedback(token: String, draft: EventFeedbackDraft) async -> FeedbackSubmitOutcome
```

- ใช้ `FeedbackSubmitOutcome` เดิม (`saved` / `alreadyAnswered` / `failed` — ไม่มีเคส `notCheckedIn` เกิดได้ แต่ enum เดิมพอ) · **404 = `.failed`** — endpoint ยังไม่เกิดใน SUS เป็นทางที่พาปุ่มข้ามโผล่ · ไม่มี outbox (ตามสเปก: ฟอร์มค้างจอจนส่งสำเร็จหรือข้าม)

- [ ] **Step 1: เขียนเทส fail**

```swift
import XCTest
@testable import WBW

/// ความเห็นทั้งงาน — endpoint ที่ SUS ยังไม่มี แอปส่งล่วงหน้าแบบเดียวกับ Android:
/// วันที่ endpoint เกิด ทุกเครื่องเริ่มส่งได้ทันที ระหว่างนั้น 404 ต้องเป็นความล้มเหลว
/// ที่ฟอร์มรับมือได้ (ปุ่มข้าม) ไม่ใช่ crash หรือค้างเงียบ
final class EventFeedbackTests: XCTestCase {

    private let deviceTime = "2026-08-29T17:00:00Z"

    func testBodyOmitsUnansweredKeys() {
        let sparse = EventFeedbackDraft(clientId: "e1", rating: 5,
                                        comment: nil, deviceTime: deviceTime)
        let body = APIClient.eventFeedbackBody(draft: sparse)
        XCTAssertEqual(body["client_id"] as? String, "e1")
        XCTAssertEqual(body["rating"] as? Int, 5)
        XCTAssertEqual(body["device_time"] as? String, deviceTime)
        for absent in ["rating_activity", "comment", "checkpoint_id"] {
            XCTAssertNil(body[absent], "คีย์ \(absent) ไม่ควรอยู่ในก้อน — event feedback ไม่ผูกกับฐานไหน")
        }
    }

    func testBodyCarriesActivityAndCommentWhenGiven() {
        let full = EventFeedbackDraft(clientId: "e2", rating: 4, ratingActivity: 3,
                                      comment: "สนุกมาก", deviceTime: deviceTime)
        let body = APIClient.eventFeedbackBody(draft: full)
        XCTAssertEqual(body["rating_activity"] as? Int, 3)
        XCTAssertEqual(body["comment"] as? String, "สนุกมาก")
    }

    // ===== transport (URLProtocol stub — ท่าเดียวกับ ChatSyncTransportTests) =====

    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var status = 201
        nonisolated(unsafe) static var body = Data("{}".utf8)
        nonisolated(unsafe) static var failsWithError = false
        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.path.hasSuffix("/me/event-feedback") == true
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            if Self.failsWithError {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
            }
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
        DemoMode.forcedActive = false
        URLProtocol.registerClass(StubURLProtocol.self)
        StubURLProtocol.status = 201
        StubURLProtocol.body = Data("{}".utf8)
        StubURLProtocol.failsWithError = false
    }
    override func tearDown() {
        DemoMode.forcedActive = nil
        URLProtocol.unregisterClass(StubURLProtocol.self)
        super.tearDown()
    }

    private func draft() -> EventFeedbackDraft {
        EventFeedbackDraft(clientId: "e9", rating: 5, comment: nil, deviceTime: deviceTime)
    }

    func testCreatedMeansSaved() async {
        let out = await APIClient.shared.submitEventFeedback(token: "t", draft: draft())
        XCTAssertEqual(out, .saved)
    }

    /// SUS ยังไม่มี endpoint — 404 คือชีวิตจริงวันงานถ้า migration ยังไม่ลง
    /// ต้องเป็น .failed (พาปุ่มข้ามโผล่) ไม่ใช่ .saved ปลอม ๆ ที่ทำให้คำตอบหายเงียบ
    func testMissingEndpointMeansFailedNotSilentSuccess() async {
        StubURLProtocol.status = 404
        let out = await APIClient.shared.submitEventFeedback(token: "t", draft: draft())
        XCTAssertEqual(out, .failed)
    }

    /// ยิงซ้ำด้วย client_id เดิม (server ตอบ 200 แถวเดิม) = สำเร็จ ไม่ใช่ error
    func testDuplicateResendIsStillSuccess() async {
        StubURLProtocol.status = 200
        let out = await APIClient.shared.submitEventFeedback(token: "t", draft: draft())
        XCTAssertEqual(out, .saved)
    }

    func testConflictMeansAlreadyAnswered() async {
        StubURLProtocol.status = 409
        let out = await APIClient.shared.submitEventFeedback(token: "t", draft: draft())
        XCTAssertEqual(out, .alreadyAnswered)
    }

    func testNetworkFailureIsFailed() async {
        StubURLProtocol.failsWithError = true
        let out = await APIClient.shared.submitEventFeedback(token: "t", draft: draft())
        XCTAssertEqual(out, .failed,
                       "ไม่มี outbox ของ event feedback — เน็ตล่มคือ .failed ให้ฟอร์มโชว์ปุ่มลองใหม่/ข้าม")
    }
}
```

- [ ] **Step 2: `xcodegen generate` + รันให้เห็น fail** (compile error)

- [ ] **Step 3: implement** — `EventFeedbackDraft` ตาม Produces (คอมเมนต์หัวไฟล์อธิบายว่าทำไมไม่ผูก checkpoint + ทำไมไม่มี outbox) · `submitEventFeedback` โครงเดียวกับ `submitFeedback`: DemoMode → `.saved`, ยิง POST, 201/200 → `.saved`, 409 → `.alreadyAnswered`, อื่น/โยน → `.failed` (ไม่ throw — คืน outcome เสมอ ฟอร์มไม่ต้อง catch)

- [ ] **Step 4: รันให้เขียว**
- [ ] **Step 5: Commit** — `feat(feedback): POST /me/event-feedback — ส่งล่วงหน้าก่อน SUS มี endpoint`

---

### Task 4: `FeedbackView` โหมด `blocking` + `kind: .event` + สาย strings

**Files:**
- Modify: `WBW/Feedback/FeedbackView.swift`
- Modify: `WBW/th.lproj/Localizable.strings`, `WBW/en.lproj/Localizable.strings`
- Test: ไม่มีเทสหน่วยใหม่ (view ล้วน — logic ตัดสินใจอยู่ Task 2/3 หมดแล้ว) · ยืนยันด้วยสกรีนช็อต Task 5

**Interfaces:**
- Produces:

```swift
struct FeedbackView: View {
    enum Kind: Equatable { case base(checkpointId: Int); case event }
    let kind: Kind
    let blocking: Bool          // true = ไม่มีปุ่มปิด (gate เป็นคนถอยเองด้วยข้อมูล)
    let onClose: () -> Void     // .event: เรียกตอนส่งสำเร็จ หรือกดข้าม
    // ทางเรียกเดิมทั้ง 4 ทางใน MainTabView คงหน้าตา FeedbackView(checkpointId:onClose:)
    // ด้วย init สะดวก: init(checkpointId: Int, onClose: ...) = .base + blocking: false
}
```

- [ ] **Step 1: เพิ่มคีย์ strings** (คำตรง Android `values*/strings.xml`)

| คีย์ | th | en |
|---|---|---|
| `feedback_event_name` | ตลอดเส้นทาง | The whole route |
| `feedback_q_overall_event` | ภาพรวม | Overall |
| `feedback_q_overall_event_hint` | การเดินโดยรวม | The walk as a whole |
| `feedback_q_activity_event_hint` | กิจกรรมที่ได้ทำตลอดเส้นทาง | The things you did along the route |
| `feedback_give_up` | ข้ามไปก่อน | Continue without sending |

(`feedback_q_activity` มีอยู่แล้ว ใช้เป็นหัวข้อคู่กับ hint ใหม่ — ตรงกับที่ Android ทำ)

- [ ] **Step 2: แก้ view**

- `Kind` + `blocking` ตาม Produces · toolbar ปุ่มปิดห่อ `if !blocking`
- `.event`: หัวการ์ดใช้ `Loc.t("feedback_event_name")` ไม่โชว์ activityName · แถวคำถามเหลือสอง: `questionRow("feedback_q_overall_event", "feedback_q_overall_event_hint", $rating)` + `questionRow("feedback_q_activity", "feedback_q_activity_event_hint", $ratingActivity)` (state `ratingActivity` กลับมาเฉพาะโหมดนี้) + TextEditor comment เดิม
- `.event` submit: สร้าง `EventFeedbackDraft` (clientId สร้างครั้งเดียวเก็บใน `@State` — กดส่งซ้ำหลัง fail ต้องใช้ตัวเดิม server จะได้ไม่เกิดสองแถว) → `await APIClient.shared.submitEventFeedback` → `.saved`/`.alreadyAnswered` = เรียก `onClose()` · `.failed` = โชว์ `feedback_send_failed` + ปุ่มข้าม `feedback_give_up` โผล่ (`@State eventSendFailed = true`) — ปุ่มข้ามเรียก `onClose()`
- `.base` โหมด blocking: submit สำเร็จไม่ต้องทำอะไรเพิ่ม — `FeedbackView.send` เดิมเรียก `progress.load()` ท้าย closure อยู่แล้ว gate อ่านค่าใหม่แล้วถอยเอง (สเปกข้อ 6)
- ปุ่มข้ามเป็นปุ่มรอง (ตัวหนังสือเฉย ๆ ใต้ปุ่มส่ง สี `wbwInk.opacity(0.6)`) — ไม่ใช่ปุ่มเด่นแข่งกับส่ง

- [ ] **Step 3: build ผ่าน + รัน suite เต็ม** (ทางเรียกเดิม 4 ทางต้องคอมไพล์ผ่านไม่แตะ)
- [ ] **Step 4: `./scripts/check-localization.sh`** — ขาด 0
- [ ] **Step 5: Commit** — `feat(feedback): FeedbackView โหมด blocking กับฟอร์มความเห็นทั้งงาน`

---

### Task 5: Gate mount ที่ `MainTabView` + SOS + uitest flags + สกรีนช็อต

**Files:**
- Modify: `WBW/MainTabView.swift` (ข้างชุด `feedbackCheckpoint` เดิม ~บรรทัด 57, 465)
- Modify: `WBW/Feedback/FeedbackGateState.swift` (เพิ่ม `Identifiable` wrapper ถ้าจำเป็น)
- Test: `WBWTests/FeedbackGateStateTests.swift` (เทส id ของ wrapper ถ้ามี logic)

**Interfaces:**
- Consumes: `FeedbackGateState.decide` (Task 2), `FeedbackView(kind:blocking:onClose:)` (Task 4), `SOSButton(store:token:showStatus:)` + `$showSOSStatus` ที่ `MainTabView` ถืออยู่แล้ว (บรรทัด 38/506)

- [ ] **Step 1: state + item**

```swift
/// ข้ามฟอร์มทั้งงานเฉพาะรันนี้ — จงใจไม่เขียนดิสก์: มันคือทางหนีจากการส่งที่ล้มเหลว
/// ไม่ใช่บันทึกว่าตอบแล้ว (server เป็นคนถือ) เปิดแอปใหม่ถามซ้ำคือถูกแล้ว
@State private var eventFeedbackDismissed = false

/// ฟอร์มที่ gate ต้องยึดจอ — คำนวณจาก progress สด ปิดตัวเองด้วยข้อมูล ไม่ใช่ navigation
private var feedbackGate: FeedbackGateItem? {
    FeedbackGateItem(state: FeedbackGateState.decide(progress: progress.progress,
                                                     eventDismissed: eventFeedbackDismissed))
}
```

`FeedbackGateItem` = struct `Identifiable` ห่อ `FeedbackGateState` (`id`: `"base-<checkpointId>"` / `"event"`) — `fullScreenCover(item:)` ต้องการ Identifiable และ id ที่**เปลี่ยนตามฐาน**ทำให้ตอบฐาน 1 แล้วฐาน 2 ขึ้นเป็นฟอร์มใหม่เอี่ยม ไม่ใช่ฟอร์มเดิมค้าง state (กับดักเดียวกับ `viewModel(key:)` ที่ Android จดไว้)

หมายเหตุ implement: `fullScreenCover(item:)` ต้องการ `Binding<Item?>` — ใช้ `Binding(get: { feedbackGate }, set: { _ in })` (setter เพิกเฉย — gate ปิดด้วยข้อมูลเท่านั้น ผู้ใช้ปิดเองไม่ได้)

- [ ] **Step 2: mount cover**

```swift
.fullScreenCover(item: Binding(get: { feedbackGate }, set: { _ in })) { item in
    FeedbackGateScreen(item: item, sos: sos, token: session.token ?? "",
                       showSOSStatus: $showSOSStatus,
                       onEventDone: { eventFeedbackDismissed = true })
        .interactiveDismissDisabled()
}
```

`FeedbackGateScreen` (ประกาศท้ายไฟล์ MainTabView หรือไฟล์ `WBW/Feedback/FeedbackGateScreen.swift` ถ้ายาว): `VStack { FeedbackView(kind:blocking:true, onClose:...) ; แถว SOSButton ชิดขวา }` — SOS มีแถวของตัวเองใต้ฟอร์ม ไม่ลอยทับ (เหตุผล Android: เคยชนปุ่มส่ง จอนี้กดผิดปุ่มเดียวคือแจ้งเหตุปลอม/ไม่ได้แจ้งเหตุจริง) · จอสถานะ SOS ใช้ `fullScreenCover(isPresented: $showSOSStatus)` **ซ้อนบน gate** — SwiftUI ซ้อน cover ได้เมื่อผูกกับ view ใน cover แรก: ผูกกับ `FeedbackGateScreen` ข้างใน ไม่ใช่กับ MainTabView (ตัวนอกโดน cover บังอยู่)
- `.base` `onClose`: ไม่ต้องทำอะไร (progress.load ท้าย send ปิด gate เอง) · `.event` `onClose`: `onEventDone()` → dismissed → cover หาย

- [ ] **Step 3: ทางเข้าเดิมไม่ชน gate** — sheet `feedbackCheckpoint` เดิม (4 ทางเข้า) คงไว้สำหรับดูคำตอบเก่า: ทางเข้าที่มาจาก toast "แตะเพื่อให้คะแนน" (บรรทัด ~428) จะไม่เกิดกับฐานที่ยังไม่ตอบอีกแล้ว (gate ขึ้นก่อน) แต่โค้ดไม่ต้องถอด — ฐาน answered แล้ว decide คืน nil, sheet เปิดได้ปกติ · เช็คว่า sheet กับ fullScreenCover ไม่เปิดพร้อมกัน (gate ขึ้น = sheet ถูกบังอยู่แล้ว ยอมรับได้)

- [ ] **Step 4: uitest flags** (DEBUG เท่านั้น ท่าเดียวกับ `-uitestFeedback`)

```swift
// ใน .task หลัง mount (ข้างชุด uitest เดิม ~บรรทัด 227):
// -uitestGateBase <checkpointId> — บังคับ gate ฐานด้วยข้อมูลจำลอง (คู่ -uitestDemo)
// -uitestGateEvent — บังคับ event form
```

ทางบังคับ: `@State` override `uitestGateState: FeedbackGateState?` — `feedbackGate` อ่านตัวนี้ก่อน `decide` (`#if DEBUG`)

- [ ] **Step 5: build + install + สกรีนช็อตสามใบ**: gate ฐาน (เห็นฟอร์ม + ปุ่ม SOS ไม่มีปุ่มปิด/แถบแท็บ) · event form · event form หลังส่ง fail (เห็นปุ่ม "ข้ามไปก่อน") — ใบสุดท้ายใช้ `-uitestGateEvent` โดยไม่มี stub อะไร: demo mode submit คืน `.saved`... ถ้าจอ fail ถ่ายไม่ได้ใน demo ให้เพิ่มแฟลก `-uitestGateEventFailed` ตั้ง `eventSendFailed = true` ตรง ๆ (ท่าเดียวกับ `-uitestNotiLoadFailed` ที่มีอยู่— บังคับสาขา UI ที่สร้างจากข้างนอกไม่ได้)
- [ ] **Step 6: รัน suite เต็ม + Commit** — `feat(feedback): gate ยึดจอจนกว่าจะตอบ — ยกเว้น SOS`

---

### Task 6: poll 60→20 วิ + เอกสาร/สัญญา

**Files:**
- Modify: `WBW/MainTabView.swift:269` (`Task.sleep(for: .seconds(60))`)
- Modify: `docs/backend-contract.md` (ตาราง §3)
- Modify: `.claude/skills/wbw-ios/*` เฉพาะถ้า `check-skill-refs.sh` ฟ้อง

- [ ] **Step 1: poll 20 วิ** — แก้เลข + แก้คอมเมนต์เหตุผล (ของเดิมอธิบาย 60 วิ/33 req/s): 20 วิ = ~100 req/s ที่ 2,000 คน เท่าที่ฝูง Android จ่ายให้ SUS อยู่แล้ว และคนยืนหน้า staff ที่เพิ่งสแกน เงียบเป็นนาทีอ่านว่าสแกนไม่ติด
- [ ] **Step 2: `docs/backend-contract.md`** — เพิ่มแถว 16: `POST /wbw/me/event-feedback` (role participant, body `{client_id, rating, rating_activity?, comment?, device_time}`, ตอบแบบเดียวกับแถว 15 + หมายเหตุ "ยังไม่มีใน SUS — แอปสองฝั่งส่งล่วงหน้า, 404 ฝั่งแอปกลายเป็นปุ่มข้าม") · เติมหมายเหตุแถว 14: `me/progress` จะต้องส่ง `event_feedback_answered` เพิ่ม
- [ ] **Step 3: `./scripts/check-skill-refs.sh`** — ไฟล์ใหม่ 2 ใบใน `WBW/Feedback/` + เทสใหม่ 2 ไฟล์ทำจำนวนขยับแน่ ๆ แก้ตัวเลข hardcode ในสคริปต์ + ข้อความ skill ที่อ้างจำนวน (เช่น `SKILL.md` "Feedback/ (4 ไฟล์)" → 6, จำนวนไฟล์เทส) ในคอมมิตเดียวกัน
- [ ] **Step 4: รัน suite เต็มรอบสุดท้าย + `check-localization.sh`**
- [ ] **Step 5: Commit** — `feat(feedback): poll ถี่เท่า Android · จดสัญญา event-feedback ให้ SUS`

---

## App Store checklist (ตอบก่อนปิดงาน — กติกาข้อ 12)

- สกรีนช็อต ASC: จอ gate/event ไม่อยู่ในชุด — ไม่บังคับ แต่คิวถ่ายใหม่มี `08-feedback` ค้างอยู่
- Description: ยังจริง (ฟีเจอร์ให้คะแนนประกาศแล้ว)
- สิทธิ์/background/Nutrition Label: ไม่เพิ่ม
