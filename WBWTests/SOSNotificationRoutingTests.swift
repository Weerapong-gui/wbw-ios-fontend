import XCTest
@testable import WBW

final class SOSNotificationRoutingTests: XCTestCase {

    /// ทางเดียวกับที่ checkin_feedback ใช้ ref_id อยู่แล้ว — ไม่ต้องมีท่อใหม่
    func testAnSOSNotificationExposesItsCaseID() throws {
        let json = Data("""
        {"id":"91","type":"sos","title":"เพื่อนในกลุ่มขอความช่วยเหลือ","body":"ใกล้สวนกุหลาบ",
         "level":"urgent","audience":"group","audience_id":"3","ref_id":"7",
         "created_at":"2026-08-06T10:00:00Z","read_at":null}
        """.utf8)
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        XCTAssertEqual(try dec.decode(NotificationItem.self, from: json).sosId, 7)
    }

    func testANonSOSNotificationHasNoCaseID() throws {
        let json = Data("""
        {"id":"92","type":"checkin_feedback","title":"เช็คอินแล้ว","body":null,"level":"info",
         "audience":"user","audience_id":"u1","ref_id":"2",
         "created_at":"2026-08-06T10:00:00Z","read_at":null}
        """.utf8)
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let item = try dec.decode(NotificationItem.self, from: json)
        XCTAssertNil(item.sosId)
        XCTAssertEqual(item.feedbackCheckpointId, 2, "ทางเดิมต้องไม่พัง")
    }

    func testAPushPayloadOfTypeSOSCarriesTheCaseID() {
        let payload: [AnyHashable: Any] = ["type": "sos", "sos_id": "7"]
        XCTAssertEqual(PendingPush.sosId(from: payload), 7)
    }

    func testAChatPushIsNotMistakenForAnSOS() {
        XCTAssertNil(PendingPush.sosId(from: ["type": "chat", "group_id": "3"]))
    }
}
