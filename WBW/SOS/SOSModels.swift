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
    /// user id ของคนที่กดค้างครบตอนสร้าง draft นี้ — ไม่มีดีฟอลต์ตั้งใจ (พบจากรีวิว Task 14 รอบสาม)
    ///
    /// SOSOutbox ผูกกับ backend เท่านั้น ไม่ผูกกับบัญชี ถ้าไม่มีฟิลด์นี้ SOSStore.init ไม่มีทางแยกออก
    /// ว่า draft ที่เหลือค้างในเครื่องเป็นของบัญชีที่กำลัง login อยู่จริงหรือเป็นของบัญชีก่อนหน้าที่
    /// เพิ่งล็อกเอาต์อัตโนมัติไป (ดู Session.logout(automatic:)) — บัญชีที่สอง login บนเครื่องเดียวกัน
    /// จะกู้ draft ของบัญชีแรกมาเป็นของตัวเองเงียบๆ แล้ว resumeIfNeeded ยิงมันด้วย token ของบัญชีที่สอง
    /// ถ้า draft นั้นยังไม่เคยถึงเซิร์ฟเวอร์ (serverId เป็น nil — เกิดขึ้นได้จริงเมื่อ 401 ที่ทำให้
    /// ล็อกเอาต์อัตโนมัติคือคำตอบของการยิง SOS เอง) ผลคือเซิร์ฟเวอร์ INSERT เคสใหม่ที่ผูกกับ
    /// participant_id ของบัญชีที่สอง แต่มีพิกัด/ข้อความของบัญชีแรก — เคสฉุกเฉินจริงที่ผูกกับคนผิดคน
    /// เกิดขึ้นเองแค่เพราะ login (ดูรายงาน Task 14 รอบสามสำหรับที่มาเต็ม) ทุกจุดที่สร้าง SOSDraft ใหม่
    /// (มีที่เดียวคือ raise()) ต้องส่งค่านี้มาจริงเสมอ ไม่มีดีฟอลต์ให้เผลอลืม
    let ownerId: String
}

/// สถานะที่คนกดเห็น · สามชั้นแรกล้มเหลวคนละสาเหตุกัน จึงห้ามยุบรวมเป็นตัวหมุนเดียว
enum SOSStatus: Equatable {
    case queued      // ยังอยู่ในเครื่อง ยังไม่ถึงเซิร์ฟเวอร์
    case received    // เซิร์ฟเวอร์รับแล้ว — ข้อพิสูจน์เดียวว่าเน็ตใช้ได้
    case onTheWay    // มีเจ้าหน้าที่กดรับเรื่อง — ข้อพิสูจน์เดียวว่ามีคนเห็น
    case closed(reason: String?)

    /// เคสยังไม่จบ (ต้องกันปุ่มกดซ้ำ + จอสถานะต้องค้างอยู่) — closed ไม่นับ กดเคสใหม่ได้เสมอ
    ///
    /// SOSStore.raise() เองไม่มีการ์ดกันเรียกซ้ำโดยตั้งใจ (ดูคอมเมนต์ที่ raise()) — รีวิว Task 12
    /// ทิ้งเรื่องนี้ไว้ให้ชั้น UI (Task 14) กันแทน ตัวนี้คือกฎที่ SOSButton ใช้ตัดสินใจว่าจะเริ่มนับ
    /// ถอยหลังใหม่ หรือแค่พาไปจอสถานะเดิม
    var isActive: Bool {
        switch self {
        case .queued, .received, .onTheWay: return true
        case .closed: return false
        }
    }
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
