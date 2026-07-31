import XCTest
@testable import WBW

final class ChatRowTests: XCTestCase {
    private let me = "me"
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return c
    }()

    /// ข้อความปลอม — serverId ใส่เองเพื่อคุมสถานะอ่าน
    private func msg(_ id: Int64?, _ sender: String, _ at: Date, _ body: String = "x") -> ChatMessage {
        ChatMessage(clientId: "c\(id ?? -1)-\(sender)-\(at.timeIntervalSince1970)",
                    serverId: id, groupId: 1, senderId: sender, body: body,
                    deviceTime: at, createdAt: at, senderName: sender,
                    state: id == nil ? .pending : .sent)
    }

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        return f.date(from: iso)!
    }

    func testEmptyListProducesNoRows() {
        XCTAssertTrue(ChatRowBuilder.build([], myLastReadId: 0, myId: me, calendar: cal).isEmpty)
    }

    func testInsertsOneDayPillPerDay() {
        let rows = ChatRowBuilder.build([
            msg(1, "a", date("2026-07-30T23:50:00+07:00")),
            msg(2, "a", date("2026-07-31T00:05:00+07:00")),
        ], myLastReadId: 99, myId: me, calendar: cal)
        let days = rows.filter { if case .day = $0 { return true } else { return false } }
        XCTAssertEqual(days.count, 2)
    }

    func testSameDayProducesOneDayPill() {
        let rows = ChatRowBuilder.build([
            msg(1, "a", date("2026-07-31T09:00:00+07:00")),
            msg(2, "a", date("2026-07-31T09:01:00+07:00")),
        ], myLastReadId: 99, myId: me, calendar: cal)
        let days = rows.filter { if case .day = $0 { return true } else { return false } }
        XCTAssertEqual(days.count, 1)
    }

    func testGroupsSameSenderWithinFiveMinutes() {
        let rows = ChatRowBuilder.build([
            msg(1, "a", date("2026-07-31T09:00:00+07:00")),
            msg(2, "a", date("2026-07-31T09:04:00+07:00")),
        ], myLastReadId: 99, myId: me, calendar: cal)
        let layouts = rows.compactMap { if case let .message(_, l) = $0 { return l } else { return nil } }
        XCTAssertEqual(layouts.map(\.isFirstInGroup), [true, false])
        XCTAssertEqual(layouts.map(\.isLastInGroup), [false, true])
        XCTAssertEqual(layouts.map(\.showTime), [false, true])
    }

    func testBreaksGroupAfterFiveMinutes() {
        let rows = ChatRowBuilder.build([
            msg(1, "a", date("2026-07-31T09:00:00+07:00")),
            msg(2, "a", date("2026-07-31T09:06:00+07:00")),
        ], myLastReadId: 99, myId: me, calendar: cal)
        let layouts = rows.compactMap { if case let .message(_, l) = $0 { return l } else { return nil } }
        XCTAssertEqual(layouts.map(\.isFirstInGroup), [true, true])
    }

    func testBreaksGroupOnSenderChange() {
        let rows = ChatRowBuilder.build([
            msg(1, "a", date("2026-07-31T09:00:00+07:00")),
            msg(2, "b", date("2026-07-31T09:00:30+07:00")),
        ], myLastReadId: 99, myId: me, calendar: cal)
        let layouts = rows.compactMap { if case let .message(_, l) = $0 { return l } else { return nil } }
        XCTAssertEqual(layouts.map(\.isFirstInGroup), [true, true])
    }

    func testBreaksGroupOnDayChangeEvenWithinFiveMinutes() {
        // ห่างกันแค่ 3 นาที (ในหน้าต่างจับกลุ่ม) แต่ข้ามเที่ยงคืน — ต้องเริ่มชุดใหม่เพราะเงื่อนไข sameDay
        let rows = ChatRowBuilder.build([
            msg(1, "a", date("2026-07-30T23:58:00+07:00")),
            msg(2, "a", date("2026-07-31T00:01:00+07:00")),
        ], myLastReadId: 99, myId: me, calendar: cal)
        let layouts = rows.compactMap { if case let .message(_, l) = $0 { return l } else { return nil } }
        XCTAssertEqual(layouts.map(\.isFirstInGroup), [true, true])
    }

    func testGroupsAtExactlyFiveMinuteBoundary() {
        // ห่างกันพอดี 300 วินาที — เงื่อนไข <= ต้องยังนับว่าจับกลุ่มกัน
        let rows = ChatRowBuilder.build([
            msg(1, "a", date("2026-07-31T09:00:00+07:00")),
            msg(2, "a", date("2026-07-31T09:05:00+07:00")),
        ], myLastReadId: 99, myId: me, calendar: cal)
        let layouts = rows.compactMap { if case let .message(_, l) = $0 { return l } else { return nil } }
        XCTAssertEqual(layouts.map(\.isFirstInGroup), [true, false])
    }

    func testUnreadMarkSitsBeforeFirstUnreadFromOthers() {
        let rows = ChatRowBuilder.build([
            msg(1, "a", date("2026-07-31T09:00:00+07:00")),
            msg(2, "a", date("2026-07-31T09:10:00+07:00")),
        ], myLastReadId: 1, myId: me, calendar: cal)
        guard let markIndex = rows.firstIndex(where: { if case .unreadMark = $0 { return true } else { return false } })
        else { return XCTFail("ไม่มีเส้นข้อความใหม่") }
        // แถวถัดจากเส้นต้องเป็นข้อความ id 2
        guard case let .message(m, _) = rows[markIndex + 1] else { return XCTFail("แถวถัดไปไม่ใช่ข้อความ") }
        XCTAssertEqual(m.serverId, 2)
    }

    func testNoUnreadMarkWhenEverythingRead() {
        let rows = ChatRowBuilder.build([
            msg(1, "a", date("2026-07-31T09:00:00+07:00")),
        ], myLastReadId: 5, myId: me, calendar: cal)
        XCTAssertFalse(rows.contains { if case .unreadMark = $0 { return true } else { return false } })
    }

    func testMyOwnUnreadMessagesDoNotTriggerTheMark() {
        let rows = ChatRowBuilder.build([
            msg(9, me, date("2026-07-31T09:00:00+07:00")),
        ], myLastReadId: 0, myId: me, calendar: cal)
        XCTAssertFalse(rows.contains { if case .unreadMark = $0 { return true } else { return false } })
    }

    func testPendingMessageStillRenders() {
        let rows = ChatRowBuilder.build([
            msg(nil, me, date("2026-07-31T09:00:00+07:00")),
        ], myLastReadId: 0, myId: me, calendar: cal)
        XCTAssertEqual(rows.compactMap { if case .message = $0 { return true } else { return nil } }.count, 1)
    }

    // ===== ป้ายวัน / เวลา =====

    func testDayLabelToday() {
        let now = date("2026-07-31T18:00:00+07:00")
        XCTAssertEqual(ChatFormat.dayLabel(for: date("2026-07-31T09:00:00+07:00"), now: now, calendar: cal), "วันนี้")
    }

    func testDayLabelYesterday() {
        let now = date("2026-07-31T18:00:00+07:00")
        XCTAssertEqual(ChatFormat.dayLabel(for: date("2026-07-30T09:00:00+07:00"), now: now, calendar: cal), "เมื่อวาน")
    }

    func testDayLabelOlderThisYearHasNoYear() {
        let now = date("2026-07-31T18:00:00+07:00")
        let label = ChatFormat.dayLabel(for: date("2026-03-02T09:00:00+07:00"), now: now, calendar: cal)
        XCTAssertFalse(label.contains("25"), "ปีนี้ไม่ต้องมีปี: \(label)")
    }

    func testDayLabelPreviousYearHasBuddhistYear() {
        let now = date("2026-07-31T18:00:00+07:00")
        let label = ChatFormat.dayLabel(for: date("2025-12-31T09:00:00+07:00"), now: now, calendar: cal)
        XCTAssertTrue(label.contains("2568"), "ปีก่อนต้องมี พ.ศ.: \(label)")
    }

    func testTimeIs24Hour() {
        XCTAssertEqual(ChatFormat.time(date("2026-07-31T21:07:00+07:00"),
                                       timeZone: TimeZone(identifier: "Asia/Bangkok")!), "21:07")
    }
}
