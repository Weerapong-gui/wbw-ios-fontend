import Foundation
import SwiftData

enum MessageState: String, Codable {
    case pending   // รอส่ง (นาฬิกา)
    case sent      // ส่งแล้ว (เช็ค)
    case failed    // ล้มเหลว (แตะ retry)
}

/// ข้อความแชท เก็บใน SwiftData — รอด app restart, ใช้เป็นทั้ง cache และ outbox
@Model
final class ChatMessage {
    @Attribute(.unique) var clientId: String
    var serverId: Int64?         // nil จนส่งสำเร็จ — ใช้เรียงลำดับ
    var groupId: Int
    var senderId: String
    var body: String
    var deviceTime: Date         // นาฬิกาเครื่อง (แสดง/tiebreak เท่านั้น)
    var createdAt: Date?
    var senderName: String
    var stateRaw: String

    init(clientId: String, serverId: Int64?, groupId: Int, senderId: String,
         body: String, deviceTime: Date, createdAt: Date?, senderName: String, state: MessageState) {
        self.clientId = clientId
        self.serverId = serverId
        self.groupId = groupId
        self.senderId = senderId
        self.body = body
        self.deviceTime = deviceTime
        self.createdAt = createdAt
        self.senderName = senderName
        self.stateRaw = state.rawValue
    }

    var state: MessageState {
        get { MessageState(rawValue: stateRaw) ?? .sent }
        set { stateRaw = newValue.rawValue }
    }
}
