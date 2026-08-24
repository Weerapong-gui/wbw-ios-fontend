import Foundation

/// คำตอบของ GET /groups/:id/chat/sync — ข้อความ + สถานะอ่าน ในคำขอเดียว
///
/// **decode ทีละแถว ไม่ใช่ทั้งก้อน** — แถวเดียวที่ประกอบเป็นข้อความไม่ได้ต้องถูกทิ้งไป
/// ไม่ใช่ลากทั้งคำตอบล่มไปด้วย · ก่อนหน้านี้มันล่มทั้งก้อน แล้ว `syncLoop` เข้า backoff
/// วนตลอดไปโดยไม่มี error บนจอเลย (แคชเก่ายังโชว์ครบ) = แชทเงียบไปทั้งห้องแบบหาสาเหตุไม่ได้
struct ChatSyncResponse: Codable {
    /// จุดตัดประวัติของเรา — ข้อความ id <= ค่านี้ห้ามเห็น (ใช้ล้าง cache เครื่อง)
    let sinceId: Int64
    let memberCount: Int
    let messages: [MessageDTO]
    /// อ่านถึงไหน ของสมาชิกคนอื่น (server ตัดตัวเราออกให้แล้ว)
    let cursors: [ReadCursor]

    init(sinceId: Int64, memberCount: Int, messages: [MessageDTO], cursors: [ReadCursor]) {
        self.sinceId = sinceId
        self.memberCount = memberCount
        self.messages = messages
        self.cursors = cursors
    }

    /// กล่องที่ decode **ไม่เคย throw** — แถวเสียกลายเป็น nil แทนที่จะพาทั้ง array ล่ม
    ///
    /// ต้องห่อแบบนี้ ไม่ใช่ `try?` ทีละ element บน `UnkeyedDecodingContainer` — ตัวนั้นไม่การันตี
    /// ว่า cursor ของ container ขยับเมื่อ decode ล้ม ลูปอาจไม่จบ · decode เป็น `[Row]` ทั้งก้อน
    /// ปลอดภัยเพราะ `Row.init` สำเร็จเสมอ container จึงเดินหน้าตามปกติ
    private struct Row: Decodable {
        let value: MessageDTO?
        init(from decoder: Decoder) throws { value = try? MessageDTO(from: decoder) }
    }

    /// ค่าที่ขาดอ่านเป็นค่าที่ปลอดภัยที่สุดเสมอ ไม่ใช่ throw — `sinceId` 0 = ไม่ purge อะไรเลย
    /// (ไม่ใช่ล้างประวัติทิ้ง) · `cursors` ว่าง = ยังไม่มีใครอ่าน (ไม่ใช่โชว์เลขมั่ว) ·
    /// `memberCount` 0 = ไม่โชว์จำนวนสมาชิก ซึ่งจอแชทรองรับอยู่แล้ว (ดู `GroupChatView` หัวจอ)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sinceId = try c.decodeIfPresent(Int64.self, forKey: .sinceId) ?? 0
        memberCount = try c.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        cursors = try c.decodeIfPresent([ReadCursor].self, forKey: .cursors) ?? []
        messages = (try c.decodeIfPresent([Row].self, forKey: .messages) ?? []).compactMap(\.value)
    }
}

struct ReadCursor: Codable, Equatable {
    let userId: String
    let lastReadId: Int64
}
