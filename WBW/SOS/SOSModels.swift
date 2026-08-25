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
    /// user id ของคนที่กดค้างครบตอนสร้าง draft นี้ — ไม่มีดีฟอลต์ในตัวสร้างปกติตั้งใจ (พบจากรีวิว
    /// Task 14 รอบสาม)
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

    private enum CodingKeys: String, CodingKey {
        case clientId, deviceTime, forOther, lat, lng, accuracyM, message, serverId, ownerId
    }

    /// ตัวสร้างปกติ (ไม่ใช่ decode) — เขียนเองแทนตัวที่ Swift จะ synthesize ให้ เพราะการเพิ่ม
    /// init(from:) ด้านล่างทำให้ Swift เลิก synthesize ตัวสร้างแบบ memberwise ให้อัตโนมัติ ทุก call
    /// site เดิม (raise() ในไฟล์นี้ กับเทสอีกหลายไฟล์) เรียกแบบนี้อยู่แล้วโดยไม่รู้ตัว
    init(clientId: String, deviceTime: String, forOther: Bool,
         lat: Double? = nil, lng: Double? = nil, accuracyM: Double? = nil,
         message: String? = nil, serverId: Int64? = nil, ownerId: String) {
        self.clientId = clientId
        self.deviceTime = deviceTime
        self.forOther = forOther
        self.lat = lat
        self.lng = lng
        self.accuracyM = accuracyM
        self.message = message
        self.serverId = serverId
        self.ownerId = ownerId
    }

    /// decode เอง (ไม่ใช้ตัวที่ Swift จะ synthesize ให้) เพื่อรับมือ draft ที่เขียนไว้บนดิสก์โดย
    /// build ก่อนหน้า commit ที่เพิ่ม ownerId เข้ามา — ไบต์เก่าพวกนั้นไม่มีคีย์ "ownerId" อยู่เลย
    /// (พบจากรีวิว Task 14 รอบสี่)
    ///
    /// ownerId เป็น String (ไม่ optional) โดยตั้งใจ ตัว decoder ที่ Swift จะ synthesize ให้เฉยๆ จึงถือ
    /// เป็นคีย์บังคับ — เจอ JSON เก่าที่ไม่มีคีย์นี้แล้ว throw DecodingError.keyNotFound ทันที ทำให้
    /// การ decode ทั้งก้อนพัง ไม่ใช่แค่ ownerId เท่านั้น: SOSOutbox.current() (เดิม) ห่อ try? รอบนอกไว้
    /// อีกที ผลคือคืน nil เหมือนกับ "ไม่มีอะไรเก็บไว้เลย" ทุกประการ — เคสฉุกเฉินจริงที่ยังค้างอยู่จาก
    /// ก่อนอัปเดตแอปจะหายไปเงียบๆ ตอนอัปเดต โดยไม่มี crash ไม่มีแบนเนอร์ ไม่มีอะไรฟ้องเลยแม้แต่นิดเดียว
    /// — ขัดกับคอมเมนต์บนสุดของคลาสนี้ตรงๆ ("เคส SOS ที่หายไปคือคนที่รออยู่บนดอยโดยเชื่อว่าส่งไปแล้ว")
    ///
    /// แก้ด้วย decodeIfPresent + fallback เป็น "" แทนที่จะปล่อยให้ throw — ownerId ว่างไม่มีทาง match
    /// currentUserId ของบัญชีจริงคนไหนได้เลย (ดูคอมเมนต์ที่ SOSStore.init) จึงตกไปสาขา "เจ้าของไม่ตรง"
    /// ที่มีอยู่แล้วโดยอัตโนมัติ ล้างช่องทิ้งจริง ไม่ใช่รับมาเป็นของบัญชีที่ล็อกอินอยู่ตอนนั้น — **ห้ามใส่
    /// currentUserId เป็นค่า fallback ตรงนี้เด็ดขาด** จะเป็นการรับ draft เก่าที่ไม่รู้เจ้าของมาเป็นของ
    /// บัญชีไหนก็ได้ที่บังเอิญล็อกอินอยู่ตอนนั้น เปิดช่องโหว่ข้ามบัญชีแบบเดียวกับที่เพิ่งปิดไปในรอบสาม
    /// กลับมาใหม่
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientId = try c.decode(String.self, forKey: .clientId)
        deviceTime = try c.decode(String.self, forKey: .deviceTime)
        forOther = try c.decode(Bool.self, forKey: .forOther)
        lat = try c.decodeIfPresent(Double.self, forKey: .lat)
        lng = try c.decodeIfPresent(Double.self, forKey: .lng)
        accuracyM = try c.decodeIfPresent(Double.self, forKey: .accuracyM)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        serverId = try c.decodeIfPresent(Int64.self, forKey: .serverId)
        ownerId = try c.decodeIfPresent(String.self, forKey: .ownerId) ?? ""
    }
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

/// สิ่งที่เจ้าหน้าที่สรุปว่าพบเมื่อไปถึงเคส — ยกมาจาก `SosOutcome` ของ Android (`6a213ee`)
///
/// **สี่คำตอบนี้ตอบคำถามคนละข้อกับปุ่มปิดเคส** — อันนี้บอกว่า *พบอะไร* ส่วนการปิดบอกว่า
/// *จบแล้ว* · สองในสี่ (`false_alarm`/`minor`) ปิดเคสไปในตัวเพราะไม่มีอะไรให้ทำต่อ
/// ส่วนอีกสอง (`major`/`urgent`) **ยกระดับให้ทั้งงานเห็นแล้วเปิดค้างไว้** — เคสที่มีคนกำลัง
/// เดินไปหาต้องไม่หายไปจากจอของคนอื่น
enum SOSOutcome: String, CaseIterable, Identifiable {
    case falseAlarm, minor, major, urgent

    var id: String { rawValue }

    /// ค่าที่เซิร์ฟเวอร์รู้จัก — ตรงกับฝั่ง Android ตัวต่อตัว
    var wire: String {
        switch self {
        case .falseAlarm: return "false_alarm"
        case .minor: return "minor"
        case .major: return "major"
        case .urgent: return "urgent"
        }
    }

    /// ยกระดับให้ทั้งงานเห็นไหม
    var escalates: Bool {
        switch self {
        case .falseAlarm, .minor: return false
        case .major, .urgent: return true
        }
    }

    var labelKey: String {
        switch self {
        case .falseAlarm: return "sos_staff_outcome_false"
        case .minor: return "sos_staff_outcome_minor"
        case .major: return "sos_staff_outcome_major"
        case .urgent: return "sos_staff_outcome_urgent"
        }
    }

    /// ป้าย "ยังเห็นเฉพาะเจ้าหน้าที่ประจำกลุ่ม" ควรขึ้นไหม
    ///
    /// ขึ้นเฉพาะตอนเคสยังเปิดและยังไม่ถูกยกระดับ — ขึ้นผิดเวลาแปลว่าเจ้าหน้าที่ที่ถือเคสอยู่
    /// จะรอคนที่ไม่มีวันมา หรือคิดว่าไม่มีใครเห็นทั้งที่ทั้งงานเห็นแล้ว
    static func showsStageOneBadge(escalated: Bool, resolved: Bool) -> Bool {
        !escalated && !resolved
    }
}
