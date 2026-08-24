import XCTest
@testable import WBW

/// รายชื่อสมาชิกเต็ม (ตัวที่มีรูป) ถูกแคชไว้ตลอดอายุแอป — ต้องมีทางล้าง
///
/// `GroupStore.members` คืนของในแคชทันทีถ้ามี และไม่เคยหมดอายุเลย · `GroupStore` ถูกสร้างที่
/// `WBWApp` จึงอยู่ยาวเท่าโปรเซส ผลสองอย่าง:
///
/// 1. **คนที่เพิ่งเข้ากลุ่มไม่มีรูปในแชท** — จอแชทโหลดรายชื่อครั้งเดียวใน `.task` แล้ว
///    `members[senderId]` ของคนใหม่เป็น nil ตลอด ฟองของเขาได้ avatar ตัวอักษรแทนรูปจริง
///    จนกว่าจะปิด-เปิดแอป ซึ่งเป็นสิ่งที่ไม่มีใครทำระหว่างเดินอยู่บนดอย
/// 2. **ข้ามบัญชี** — logout แล้ว login บัญชีใหม่บนเครื่องเดียวกัน แคชของบัญชีก่อนยังอยู่ครบ
///    (เรื่องเดียวกับที่ `ChatSession.purgeForLogout` กับ `Session.logout` ไล่ล้างไปแล้วทุกก้อน
///    แต่ก้อนนี้ตกหล่น)
@MainActor
final class GroupMembersCacheTests: XCTestCase {

    /// ดักเฉพาะ GET /groups/{id}/members — `/groups/members/index` ลงท้ายด้วย "index" จึงไม่โดน
    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var body = Data()
        nonisolated(unsafe) static var requestCount = 0

        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.path.hasSuffix("/members") == true
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.requestCount += 1
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private static func payload(_ userIds: [String]) -> Data {
        let rows = userIds.map {
            #"{"user_id":"\#($0)","first_name":"ดิน","last_name":"ก","photo_url":null,"bib":1,"school":"MFU"}"#
        }.joined(separator: ",")
        return Data(#"{"members":[\#(rows)],"count":\#(userIds.count)}"#.utf8)
    }

    override func setUp() {
        super.setUp()
        // เหตุผลเต็มอยู่ที่ FeedbackTransportTests.setUp — โหมดเดโม่มีทางลัดอยู่ก่อนทุกฟังก์ชันที่ยิงเน็ต
        DemoMode.forcedActive = false
        URLProtocol.registerClass(StubURLProtocol.self)
        StubURLProtocol.body = Self.payload(["u1"])
        StubURLProtocol.requestCount = 0
    }

    override func tearDown() {
        DemoMode.forcedActive = nil
        URLProtocol.unregisterClass(StubURLProtocol.self)
        super.tearDown()
    }

    /// แคชยังต้องทำงานเหมือนเดิม — จอแชทเรียกทุกครั้งที่ `.task` รัน ยิงเน็ตทุกครั้งไม่ไหว
    func testSecondCallUsesCacheWithoutHittingNetwork() async {
        let store = GroupStore()
        _ = await store.members(groupId: 1, token: "t")
        _ = await store.members(groupId: 1, token: "t")
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func testForcedCallRefetchesAndReplacesCache() async {
        let store = GroupStore()
        let first = await store.members(groupId: 1, token: "t")
        XCTAssertEqual(first.map(\.userId), ["u1"])

        StubURLProtocol.body = Self.payload(["u1", "u2"])
        let second = await store.members(groupId: 1, token: "t", force: true)

        XCTAssertEqual(StubURLProtocol.requestCount, 2)
        XCTAssertEqual(second.map(\.userId), ["u1", "u2"], "คนที่เพิ่งเข้ากลุ่มต้องโผล่")
        XCTAssertEqual(store.membersByGroup[1]?.map(\.userId), ["u1", "u2"], "แคชต้องถูกทับด้วยของใหม่")
    }

    /// ยิงพลาดตอน force ต้องไม่ล้างของเดิมทิ้ง — จอแชทจะกลายเป็น avatar ตัวอักษรทั้งจอ
    /// ทั้งที่เมื่อกี้ยังมีรูปครบ เพราะเน็ตสะดุดรอบเดียว
    func testFailedForcedCallKeepsTheOldCache() async {
        let store = GroupStore()
        _ = await store.members(groupId: 1, token: "t")

        StubURLProtocol.body = Data("ไม่ใช่ JSON".utf8)
        let after = await store.members(groupId: 1, token: "t", force: true)

        XCTAssertEqual(after.map(\.userId), ["u1"])
        XCTAssertEqual(store.membersByGroup[1]?.map(\.userId), ["u1"])
    }

    /// logout ต้องล้างได้ — ไม่งั้นบัญชีถัดไปบนเครื่องเดียวกันเห็นรายชื่อของบัญชีก่อน
    func testClearDropsEverythingSoNextCallRefetches() async {
        let store = GroupStore()
        _ = await store.members(groupId: 1, token: "t")
        XCTAssertFalse(store.membersByGroup.isEmpty)

        store.clear()

        XCTAssertTrue(store.membersByGroup.isEmpty)
        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertTrue(store.memberIndex.isEmpty)
        XCTAssertFalse(store.loaded)

        _ = await store.members(groupId: 1, token: "t")
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }
}
