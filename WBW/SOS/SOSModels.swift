import Foundation

/// เคสหนึ่งอันที่รอส่ง
///
/// clientId สร้างครั้งเดียวตอนกดครบ 3 วิ แล้วใช้ค่าเดิมทุกครั้งที่ retry —
/// backend unique บนคอลัมน์นี้ ส่งซ้ำจึงได้แถวเดิมกลับมา ไม่เกิดเคสซ้ำ
///
/// serverId ว่างจนกว่าจะยิงถึงเซิร์ฟเวอร์ครั้งแรก — เป็นตัวแยก "ยังไม่ส่ง"
/// ออกจาก "ส่งถึงแล้ว" โดยไม่ต้องพึ่งสถานะแยกอีกตัว
struct SOSDraft: Codable, Equatable {
    let clientId: String
    let deviceTime: String
    var forOther: Bool
    var lat: Double?
    var lng: Double?
    var accuracyM: Double?
    var message: String?
    var serverId: Int64?
}

/// สถานะที่คนกดเห็น · สามชั้นแรกล้มเหลวคนละสาเหตุกัน จึงห้ามยุบรวมเป็นตัวหมุนเดียว
enum SOSStatus: Equatable {
    case queued      // ยังอยู่ในเครื่อง ยังไม่ถึงเซิร์ฟเวอร์
    case received    // เซิร์ฟเวอร์รับแล้ว — ข้อพิสูจน์เดียวว่าเน็ตใช้ได้
    case onTheWay    // มีเจ้าหน้าที่กดรับเรื่อง — ข้อพิสูจน์เดียวว่ามีคนเห็น
    case closed(reason: String?)
}

struct SOSCase: Codable, Equatable {
    let id: Int64
    let forOther: Bool
    let lat: Double?
    let lng: Double?
    let accuracyM: Double?
    let locSource: String?
    let checkpointId: Int?
    let checkpointName: String?
    let message: String?
    let resolved: Bool
    let resolveReason: String?
    let ackedAt: String?
    let ackedByName: String?
    let createdAt: String
    let emergencyPhone: String?

    var status: SOSStatus {
        if resolved { return .closed(reason: resolveReason) }
        if ackedAt != nil { return .onTheWay }
        return .received
    }
}
