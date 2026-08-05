import Foundation

/// คำตอบของ GET /groups/:id/chat/sync — ข้อความ + สถานะอ่าน ในคำขอเดียว
struct ChatSyncResponse: Codable {
    /// จุดตัดประวัติของเรา — ข้อความ id <= ค่านี้ห้ามเห็น (ใช้ล้าง cache เครื่อง)
    let sinceId: Int64
    let memberCount: Int
    let messages: [MessageDTO]
    /// อ่านถึงไหน ของสมาชิกคนอื่น (server ตัดตัวเราออกให้แล้ว)
    let cursors: [ReadCursor]
}

struct ReadCursor: Codable, Equatable {
    let userId: String
    let lastReadId: Int64
}
