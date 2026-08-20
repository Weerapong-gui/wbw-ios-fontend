import Foundation

/// จัดประกาศเป็นกลุ่มตามวันสำหรับ `NotificationsView`
///
/// แยกออกมาจากตัวจอเพราะเป็นตรรกะที่ผูกกับ "วันนี้" — ทดสอบผ่าน view ไม่ได้เลยถ้าเวลาปัจจุบัน
/// มาจาก `Date()` ข้างใน จึงรับ `now` กับ `calendar` เข้ามาเป็นพารามิเตอร์แทน
///
/// เดิมแต่ละแถวโชว์ `NotificationItem.timeText` ("16 ก.ค. 09:02") เหมือนกันหมดทั้งลิสต์ ตัวนั้นถูก
/// ย้ายมาอยู่ที่ `rowTime` ที่นี่แล้ว เพราะพอมีหัวกลุ่มบอกวัน แถวในกลุ่ม "วันนี้"/"เมื่อวาน"
/// ไม่ควรพูดวันซ้ำอีกรอบ
enum NotificationGrouping {

    struct Section: Identifiable {
        let id: String
        let title: String
        let items: [NotificationItem]
    }

    /// หัวกลุ่มของแถวที่ `createdAt` ใช้ไม่ได้ — ไม่ใช่การซ่อนแถวทิ้ง
    ///
    /// backend ส่ง `createdAt` เป็น null ได้จริง (แถวที่ job สร้าง) ถ้าคัดแถวพวกนี้ออกจากลิสต์
    /// ผู้ใช้จะไม่เห็นประกาศนั้นเลยทั้งที่ badge นับให้แล้ว — เห็นเป็นเลขที่กดเข้าไปแล้วไม่มีอะไร
    private static var undatedTitle: String { Loc.t("date_unknown_title") }

    static func sections(_ items: [NotificationItem], now: Date,
                         calendar: Calendar = .current) -> [Section] {
        var byDay: [Date: [(item: NotificationItem, at: Date)]] = [:]
        var undated: [NotificationItem] = []

        for item in items {
            guard let at = date(of: item) else { undated.append(item); continue }
            byDay[calendar.startOfDay(for: at), default: []].append((item, at))
        }

        var sections = byDay.keys.sorted(by: >).map { day in
            Section(id: dayId(day, calendar: calendar),
                    title: title(for: day, now: now, calendar: calendar),
                    items: byDay[day]!.sorted { $0.at > $1.at }.map(\.item))
        }
        if !undated.isEmpty {
            sections.append(Section(id: "undated", title: undatedTitle, items: undated))
        }
        return sections
    }

    /// เวลาที่โชว์ในแถว — **เหลือแค่ "09:02" เสมอ ไม่มีวันที่**
    ///
    /// ทุกแถวอยู่ใต้หัวกลุ่มที่บอกวันไปแล้ว (วันนี้ / เมื่อวาน / 16 ก.ค.) ใส่วันที่ซ้ำในแถวด้วย
    /// คือ noise ล้วน — เห็นชัดจากสกรีนช็อตจริง: หัวกลุ่ม "29 ส.ค." แล้วทุกแถวข้างใต้ขึ้นต้นด้วย
    /// "29 ส.ค." อีกรอบทั้งหน้า
    static func rowTime(_ item: NotificationItem, now: Date,
                        calendar: Calendar = .current) -> String {
        guard let at = date(of: item) else { return "" }
        return formatted(at, format: "HH:mm", calendar: calendar)
    }

    // MARK: - ภายใน

    /// รับทั้งแบบมีและไม่มีเศษวินาที — SUS ส่งมาไม่เหมือนกันทุก endpoint และ `ISO8601DateFormatter`
    /// ที่ตั้ง `.withFractionalSeconds` ไว้จะคืน nil กับสตริงที่ไม่มีเศษวินาที (ไม่ใช่ยืดหยุ่นให้เอง)
    private static func date(of item: NotificationItem) -> Date? {
        guard let raw = item.createdAt else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private static func title(for day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return Loc.t("date_today") }
        if isYesterday(day, now: now, calendar: calendar) { return Loc.t("date_yesterday") }
        return formatted(day, format: "d MMM", calendar: calendar)
    }

    private static func isYesterday(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return false }
        return calendar.isDate(date, inSameDayAs: yesterday)
    }

    /// id ของกลุ่มต้องไม่ผูกกับหัวข้อที่โชว์ — "16 ก.ค." ของคนละปีเป็นคำเดียวกันเป๊ะ
    /// `ForEach` จะทิ้งกลุ่มที่ id ซ้ำไปเงียบ ๆ (ไม่ crash ไม่เตือน แค่หายไปทั้งกลุ่ม)
    private static func dayId(_ day: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: day)
    }

    private static func formatted(_ date: Date, format: String, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "th_TH")
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f.string(from: date)
    }
}
