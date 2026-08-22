import XCTest
@testable import WBW

/// การจัดกลุ่มประกาศตามวัน — ตรรกะล้วนที่แยกออกมาจาก `NotificationsView` เพื่อให้ตรึงเวลาได้
///
/// สองอาการที่ทดสอบผ่านจอไม่ได้เลย: แถวที่ `createdAt` อ่านไม่ออกต้อง "ตกไปกลุ่มท้าย" ไม่ใช่หายจากจอ
/// (backend เคยส่ง field นี้มาเป็น null ตอนสร้างแถวจาก job) และหัวกลุ่มต้องเทียบกับ "วันนี้ของผู้ใช้"
/// ตาม timezone ของเครื่อง ไม่ใช่ UTC — ไทยเป็น +07 ประกาศที่ยิงตอนหัวค่ำจึงข้ามวันใน UTC ไปแล้ว
/// ทั้งที่ผู้ใช้ยังนับเป็นวันเดียวกันอยู่
final class NotificationGroupingTests: XCTestCase {

    private let bangkok = TimeZone(identifier: "Asia/Bangkok")!

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = bangkok
        return c
    }

    /// 2026-08-20 09:00 ตามเวลาไทย
    private var now: Date {
        ISO8601DateFormatter().date(from: "2026-08-20T02:00:00Z")!
    }

    private func item(_ id: String, _ createdAt: String?) -> NotificationItem {
        NotificationItem(id: id, type: nil, title: "หัวข้อ \(id)", body: nil, level: "info",
                         audience: nil, audienceId: nil, refId: nil,
                         createdAt: createdAt, readAt: nil)
    }

    // เวลาไทยที่แต่ละตัวหมายถึง: 08:30 วันนี้ · 07:00 วันนี้ · 22:00 เมื่อวาน · 09:02 วันที่ 16 ก.ค.
    private var todayLate: NotificationItem { item("1", "2026-08-20T01:30:00.000Z") }
    private var todayEarly: NotificationItem { item("2", "2026-08-20T00:00:00.000Z") }
    private var yesterday: NotificationItem { item("3", "2026-08-19T15:00:00.000Z") }
    private var july: NotificationItem { item("4", "2026-07-16T02:02:00.000Z") }
    private var undated: NotificationItem { item("5", nil) }

    // MARK: - หัวกลุ่ม

    func testSplitsIntoTodayYesterdayAndDatedGroups() {
        let sections = NotificationGrouping.sections(
            [july, yesterday, todayEarly, todayLate], now: now, calendar: calendar)

        XCTAssertEqual(sections.map(\.title),
                       [Loc.t("date_today"), Loc.t("date_yesterday"), "16 ก.ค."],
                       "วันนี้/เมื่อวานต้องเป็นคำ ไม่ใช่วันที่ · วันเก่ากว่านั้นถึงโชว์วันที่")
    }

    /// 22:00 ของเมื่อวานตามเวลาไทย = 15:00Z ซึ่งยังเป็นวันเดียวกับ 01:30Z ของวันนี้ใน UTC
    /// จัดกลุ่มด้วย UTC เมื่อไหร่สองแถวนี้จะไปกองอยู่กลุ่มเดียวกันทันที
    func testGroupsByTheUsersCalendarDayNotUTC() {
        let sections = NotificationGrouping.sections([todayLate, yesterday], now: now, calendar: calendar)

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.first?.items.map(\.id), ["1"])
        XCTAssertEqual(sections.last?.items.map(\.id), ["3"])
    }

    func testOrdersNewestFirstBothAcrossAndInsideGroups() {
        let sections = NotificationGrouping.sections(
            [todayEarly, july, todayLate, yesterday], now: now, calendar: calendar)

        XCTAssertEqual(sections.flatMap { $0.items.map(\.id) }, ["1", "2", "3", "4"])
    }

    // MARK: - แถวที่ไม่มีเวลา

    func testKeepsUndatedItemsInATrailingGroup() {
        let sections = NotificationGrouping.sections([undated, todayLate], now: now, calendar: calendar)

        XCTAssertEqual(sections.map(\.title),
                       [Loc.t("date_today"), Loc.t("date_unknown_title")],
                       "createdAt เป็น null ต้องยังเห็นแถวอยู่ ไม่ใช่หายจากจอ")
        XCTAssertEqual(sections.last?.items.map(\.id), ["5"])
    }

    func testTreatsUnparseableTimestampsAsUndated() {
        let broken = item("6", "เมื่อวานตอนบ่าย")
        let sections = NotificationGrouping.sections([broken], now: now, calendar: calendar)

        XCTAssertEqual(sections.map(\.title), [Loc.t("date_unknown_title")])
    }

    func testSectionIdsAreUniqueSoForEachDoesNotDropRows() {
        let sections = NotificationGrouping.sections(
            [todayLate, yesterday, july, undated], now: now, calendar: calendar)
        let ids = sections.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count, "id ซ้ำกันแล้ว ForEach จะวาดกลุ่มหายไปเงียบ ๆ")
    }

    func testReturnsNothingForAnEmptyList() {
        XCTAssertTrue(NotificationGrouping.sections([], now: now, calendar: calendar).isEmpty)
    }

    // MARK: - เวลาในแถว

    /// หัวกลุ่มบอกวันไปแล้ว แถวจึงเหลือแค่เวลาเสมอ — ซ้ำวันที่อีกรอบคือ noise ล้วน
    /// (เห็นชัดจากสกรีนช็อตจริง: หัวกลุ่ม "29 ส.ค." แล้วทุกแถวข้างใต้ขึ้นต้นด้วย "29 ส.ค." อีกรอบ)
    func testRowTimeIsJustTheClockNeverTheDate() {
        XCTAssertEqual(NotificationGrouping.rowTime(todayLate, now: now, calendar: calendar), "08:30")
        XCTAssertEqual(NotificationGrouping.rowTime(yesterday, now: now, calendar: calendar), "22:00")
        XCTAssertEqual(NotificationGrouping.rowTime(july, now: now, calendar: calendar), "09:02",
                       "วันที่อยู่ที่หัวกลุ่มแล้ว ห้ามซ้ำในแถว")
    }

    func testRowTimeIsEmptyWhenThereIsNoUsableTimestamp() {
        XCTAssertEqual(NotificationGrouping.rowTime(undated, now: now, calendar: calendar), "")
    }
}
