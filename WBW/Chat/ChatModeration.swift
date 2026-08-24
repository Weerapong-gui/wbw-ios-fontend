import Foundation

/// เครื่องมือจัดการเนื้อหาในแชทกลุ่ม — บล็อกคนที่ก่อกวน กับรายงานข้อความให้ทีมงาน
///
/// **มีเพราะ Guideline 1.2 บังคับ** แอปที่มี user-generated content ต้องมีทั้งทางรายงาน
/// เนื้อหา ทางบล็อกผู้ใช้ และช่องทางติดต่อที่เผยแพร่ไว้ · แชทกลุ่มของงานเข้าเงื่อนไขนี้เต็มตัว
/// และของที่ขาดไปคือเหตุตีกลับได้ทันทีโดยไม่ต้องรอให้มีใครก่อกวนจริงก่อน
///
/// ทำฝั่งเครื่องล้วน ไม่แตะ backend: **บล็อก = ซ่อนบนเครื่องนี้** (ข้อความยังอยู่บนเซิร์ฟเวอร์
/// และคนอื่นยังเห็น) ส่วน **รายงาน = เปิดแอปเมล**พร้อมข้อมูลที่ทีมงานใช้ตามหาข้อความนั้นได้
/// · ถ้าวันหนึ่ง SUS มี endpoint ลบข้อความ/แบนจริง ค่อยต่อยอดจากที่นี่
enum ChatModeration {

    /// ข้อความที่เหลือหลังกรองคนที่ถูกบล็อกออก
    ///
    /// กรองตอนแสดงผล ไม่ใช่ตอน sync — cache กับ cursor ของแชทยังต้องตรงกับเซิร์ฟเวอร์
    /// ไม่งั้นปลดบล็อกแล้วข้อความเก่าจะไม่กลับมา และเลข "อ่านแล้ว" จะเพี้ยนตามไปด้วย
    static func visible(_ messages: [ChatMessage], blocked: Set<String>) -> [ChatMessage] {
        blocked.isEmpty ? messages : messages.filter { !blocked.contains($0.senderId) }
    }

    /// อีเมลรายงานข้อความ — เปิดแอปเมลของเครื่องพร้อมเนื้อหาที่กรอกไว้ให้แล้ว
    ///
    /// ใส่ id ของข้อความ ผู้ส่ง และผู้รายงานมาด้วยเสมอ ไม่งั้นทีมงานได้อีเมลที่บอกแค่ว่า
    /// "มีคนพิมพ์ไม่ดี" แล้วตามหาข้อความนั้นไม่เจอ · ตัวข้อความจริงแนบไปด้วยเพราะผู้ส่ง
    /// ลบเองไม่ได้ก็จริง แต่แอดมินอาจลบก่อนทีมงานเปิดอ่าน
    static func reportMailURL(for message: ChatMessage, reporterId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Config.contactEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: Loc.t("chat_report_mail_subject")),
            URLQueryItem(name: "body", value: body(for: message, reporterId: reporterId)),
        ]
        return components.url
    }

    private static func body(for message: ChatMessage, reporterId: String) -> String {
        let time = ISO8601DateFormatter().string(from: message.createdAt ?? message.deviceTime)
        return """
        \(Loc.t("chat_report_mail_intro"))

        message: \(message.clientId) (server \(message.serverId.map(String.init) ?? "-"))
        group: \(message.groupId)
        sender: \(message.senderName) (\(message.senderId))
        time: \(time)
        reporter: \(reporterId)

        ---
        \(message.body)
        ---

        \(Loc.t("chat_report_mail_outro"))
        """
    }
}

/// รายชื่อคนที่ผู้ใช้บล็อกไว้ — อยู่บนเครื่องนี้เท่านั้น
///
/// เก็บชื่อคู่กับ id ด้วย เพราะจอ "ผู้ใช้ที่บล็อกไว้" ในตั้งค่าต้องบอกได้ว่าใครเป็นใคร
/// ตอนที่ข้อความของคนนั้นถูกซ่อนไปหมดแล้ว (ไม่มีที่ไหนให้ย้อนดูชื่อจาก id อีก)
///
/// คีย์ต่อ `CacheScope.suffix` เหมือน cache ตัวอื่นของแอป — บล็อกในโหมดเดโม่ต้องไม่ข้าม
/// ไปโผล่ในบัญชีจริง
final class BlockedUsers: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id: String
        let name: String
    }

    /// ต้นคีย์ร่วมของทุก scope — `clearAll` กวาดจากตัวนี้ ไม่ใช่จาก `storageKey` ตัวเดียว
    static let keyPrefix = "wbw.chat.blocked"
    static var storageKey: String { keyPrefix + CacheScope.suffix }

    /// ล้างรายชื่อที่บล็อกไว้ **ทุก scope** — เรียกจาก `ChatSession.purgeForLogout()`
    ///
    /// คีย์ขึ้นต้นด้วย `wbw.` จึงรอดจากการกวาด `hasPrefix("chat.")` ของ `purgeForLogout` มาตลอด
    /// บัญชีที่ 2 ที่ login เครื่องเดียวกันจึงสืบทอดรายการบล็อกของบัญชีก่อน และ **เห็นชื่อ** คนที่
    /// บัญชีก่อนบล็อกไว้ในหน้าตั้งค่า (คลาสนี้เก็บชื่อคู่กับ id เพื่อให้จอนั้นแสดงได้ ดูคอมเมนต์
    /// หัวคลาส) — เป็นการรั่วข้อมูลข้ามบัญชี ไม่ใช่แค่ของค้าง
    static func clearAll(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    @Published private(set) var entries: [Entry] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = Self.read(from: defaults)
    }

    var ids: Set<String> { Set(entries.map(\.id)) }

    func isBlocked(_ senderId: String) -> Bool { entries.contains { $0.id == senderId } }

    func block(_ senderId: String, name: String) {
        guard !isBlocked(senderId) else { return }
        write(entries + [Entry(id: senderId, name: name)])
    }

    func unblock(_ senderId: String) {
        write(entries.filter { $0.id != senderId })
    }

    private func write(_ next: [Entry]) {
        let sorted = next.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        defaults.set(Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0.name) }),
                     forKey: Self.storageKey)
        entries = sorted
    }

    private static func read(from defaults: UserDefaults) -> [Entry] {
        let stored = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        return stored
            .map { Entry(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
