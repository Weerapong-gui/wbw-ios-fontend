import Foundation

extension ChatMessage {
    /// เวลาที่ใช้แสดง/จัดกลุ่ม — เวลา server ถ้ามี ไม่งั้นนาฬิกาเครื่อง (ข้อความที่ยังไม่ส่ง)
    var displayTime: Date { createdAt ?? deviceTime }
}

/// แถวในลิสต์แชท — ข้อความ, ป้ายคั่นวัน, เส้น "ข้อความใหม่"
enum ChatRow: Identifiable {
    struct Layout: Equatable {
        var isFirstInGroup: Bool   // ฟองแรกของชุด → โชว์ avatar + ชื่อ
        var isLastInGroup: Bool    // ฟองสุดท้ายของชุด → มีหาง
        var showTime: Bool         // โชว์เวลาใต้ฟอง
    }

    case day(Date)
    case unreadMark
    case message(ChatMessage, Layout)

    var id: String {
        switch self {
        case let .day(d):        return "day-\(Int(d.timeIntervalSince1970))"
        case .unreadMark:        return "unread-mark"
        case let .message(m, _): return m.clientId
        }
    }
}

enum ChatRowBuilder {
    /// ข้อความคนเดียวกันห่างไม่เกินนี้ = ชุดเดียวกัน
    static let groupingWindow: TimeInterval = 300

    /// สร้างแถวสำหรับแสดงผล — บริสุทธิ์ ไม่มี view/network เทสได้ตรงๆ
    /// - Parameters:
    ///   - msgs: เรียงจากเก่าไปใหม่แล้ว (ChatSession จัดให้)
    ///   - myLastReadId: อ่านถึง id ไหน — ใช้วางเส้น "ข้อความใหม่"
    ///   - myId: userId ของเรา — ข้อความตัวเองไม่ทำให้เกิดเส้นข้อความใหม่
    static func build(_ msgs: [ChatMessage],
                      myLastReadId: Int64,
                      myId: String,
                      calendar: Calendar = .current) -> [ChatRow] {
        guard !msgs.isEmpty else { return [] }

        // รอบแรก: ข้อความไหนเริ่มชุดใหม่
        var starts = [Bool](repeating: true, count: msgs.count)
        for i in 1..<msgs.count {
            let prev = msgs[i - 1], cur = msgs[i]
            let sameSender = prev.senderId == cur.senderId
            let close = cur.displayTime.timeIntervalSince(prev.displayTime) <= groupingWindow
            let sameDay = calendar.isDate(prev.displayTime, inSameDayAs: cur.displayTime)
            starts[i] = !(sameSender && close && sameDay)
        }

        // ข้อความแรกที่ยังไม่อ่านและไม่ใช่ของเรา
        // serverId เป็น nil ได้เฉพาะข้อความที่เรายังไม่ส่งเอง (ChatStore การันตี) — ข้อความของคนอื่น
        // มี serverId เสมอ ดังนั้น ?? 0 ตรงนี้ไม่มีทางทำให้ข้อความคนอื่นถูกนับว่ายังไม่อ่านผิดๆ
        let firstUnread = msgs.firstIndex {
            $0.senderId != myId && ($0.serverId ?? 0) > myLastReadId
        }

        var rows: [ChatRow] = []
        var lastDay: Date?
        for i in msgs.indices {
            let m = msgs[i]
            let day = calendar.startOfDay(for: m.displayTime)
            if lastDay != day {
                rows.append(.day(day))
                lastDay = day
            }
            if i == firstUnread { rows.append(.unreadMark) }
            let isLast = (i == msgs.count - 1) || starts[i + 1]
            rows.append(.message(m, .init(isFirstInGroup: starts[i],
                                          isLastInGroup: isLast,
                                          showTime: isLast)))
        }
        return rows
    }
}

/// ข้อความบนป้ายวัน + เวลาใต้ฟอง
enum ChatFormat {
    static func dayLabel(for day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "วันนี้" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) { return "เมื่อวาน" }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        let f = DateFormatter()
        f.locale = Locale(identifier: "th_TH")   // ได้ พ.ศ. อัตโนมัติ
        f.timeZone = calendar.timeZone
        f.dateFormat = sameYear ? "d MMM" : "d MMM yyyy"
        return f.string(from: day)
    }

    /// 24 ชั่วโมงเสมอ ไม่ตามการตั้งค่าเครื่อง (en_US_POSIX กัน AM/PM)
    static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
