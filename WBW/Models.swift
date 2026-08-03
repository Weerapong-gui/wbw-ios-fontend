import Foundation

/// รับค่าตัวเลขที่อาจมาเป็น number หรือ string (PG numeric → node ส่ง string)
struct LossyNumber: Codable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else { value = nil }
    }
    /// แสดงแบบไม่มีทศนิยมถ้าเป็นจำนวนเต็ม
    var display: String? {
        guard let v = value else { return nil }
        return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

struct AuthUser: Codable, Equatable {
    let userId: String
    let username: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case role
    }
}

struct LoginResponse: Codable {
    let user: AuthUser
    let token: String
}

/// โปรไฟล์เต็มจาก /auth/me (snake_case → decode ด้วย convertFromSnakeCase)
struct Me: Codable {
    let userId: String
    let username: String
    let role: String
    let studentId: String?
    let firstName: String?
    let lastName: String?
    let dateOfBirth: String?
    let sex: String?
    let contactPhone: String?
    let schoolName: String?
    let major: String?
    let year: Int?
    let groupId: Int?
    let groupNumber: Int?
    let bibNumber: Int?
    let qrToken: String?
    let photoUrl: String?
    let emergencyContactName: String?
    let emergencyContactPhone: String?
    let bloodType: String?
    let foodAllergies: String?
    let chronicDisease: String?
    let medications: String?
    let weightKg: LossyNumber?
    let heightCm: LossyNumber?

    /// ชื่อที่โชว์ (first_name ถ้ามี ไม่งั้น username)
    var displayName: String {
        if let f = firstName?.trimmingCharacters(in: .whitespaces), !f.isEmpty { return f }
        return username
    }

    var fullName: String {
        [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// อายุจาก date_of_birth (ISO) — nil ถ้าไม่มี/ผิด
    func age(asOf now: Date) -> Int? {
        guard let dob = dateOfBirth,
              let d = ISO8601DateFormatter().date(from: dob.contains("T") ? dob : dob + "T00:00:00Z")
                ?? DateFormatter.ymd.date(from: String(dob.prefix(10)))
        else { return nil }
        let a = Calendar.current.dateComponents([.year], from: d, to: now).year
        if let a, a >= 0, a < 130 { return a }
        return nil
    }
}

extension DateFormatter {
    static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

struct APIErrorBody: Codable {
    let error: String?
}

// ===== staff (เจ้าหน้าที่ประจำฐาน) =====
struct StaffCheckpoint: Codable, Identifiable {
    let id: Int
    let name: String
    let sequence: Int?
}

struct CheckinResult: Codable {
    let firstName: String?
    let lastName: String?
    let bib: Int?
    let hasMedicalFlag: Bool
    let alreadyCheckedIn: Bool

    var fullName: String {
        [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

// ===== ประกาศ / แจ้งเตือน =====
// หมายเหตุ: id มาเป็น string (PG bigint → node ส่ง string)
// Equatable เพื่อให้ .onChange(of: noti.items) ใน MainTabView จับ "รายการเปลี่ยน" ได้ตรงๆ — ใช้ retry
// การมาร์คว่าอ่านแล้วของ push ที่พาเข้าฟอร์มก่อนรายการจะโหลดทัน (ดู markFeedbackNotiRead)
struct NotificationItem: Codable, Identifiable, Equatable {
    @FlexibleString var id: String
    let type: String?
    let title: String
    let body: String?
    let level: String
    let audience: String?
    let audienceId: String?
    /// ชี้ไปวัตถุที่แจ้งเตือนนี้พูดถึง · ตอนนี้ใช้เฉพาะ type == "checkin_feedback" = checkpoint_id
    let refId: String?
    let createdAt: String?
    var readAt: String?

    var isUnread: Bool { readAt == nil }

    /// เลขฐานที่แจ้งเตือนนี้ขอความเห็น · nil = ไม่ใช่แจ้งเตือนชนิดนี้
    var feedbackCheckpointId: Int? {
        guard type == "checkin_feedback", let refId else { return nil }
        return Int(refId)
    }

    /// เวลาแบบไทยสั้นๆ (16 ก.ค. 09:02)
    var timeText: String {
        guard let createdAt else { return "" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = iso.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt)
        guard let d else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "th_TH")
        f.dateFormat = "d MMM HH:mm"
        return f.string(from: d)
    }
}

// ===== กลุ่ม + แชท =====
struct GroupSummary: Codable, Identifiable {
    let groupId: Int
    let groupNumber: Int
    let capacity: Int
    let memberCount: Int
    let seatsLeft: Int
    var id: Int { groupId }
    var isFull: Bool { seatsLeft <= 0 }
}

/// ดัชนีสมาชิกเบา (ไม่มีรูป) — ใช้ค้นหาคนข้ามกลุ่ม + avatar ตัวอักษร
struct GroupMemberIndex: Codable, Identifiable {
    let userId: String
    let firstName: String?
    let lastName: String?
    let groupId: Int
    let groupNumber: Int
    var id: String { userId }
    var fullName: String {
        [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// สมาชิกเต็ม (มีรูป) — โหลดตอนเปิดกลุ่ม
struct GroupMember: Codable, Identifiable {
    let userId: String
    let firstName: String?
    let lastName: String?
    let photoUrl: String?
    let bib: Int?
    let school: String?
    var id: String { userId }
    var fullName: String {
        [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct GroupMembersResponse: Codable {
    let members: [GroupMember]
    let count: Int
}

/// ข้อความจาก server (id เป็น string เพราะ PG bigint)
struct MessageDTO: Codable {
    @FlexibleString var id: String
    let groupId: Int
    let senderId: String
    let clientId: String
    let body: String
    let deviceTime: String?
    let createdAt: String?
    let firstName: String?
    let lastName: String?

    var senderName: String {
        [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum AppError: LocalizedError {
    case message(String)
    case groupFull(String)
    case offline
    case notInGroup
    var errorDescription: String? {
        switch self {
        case let .message(m): return m
        case let .groupFull(m): return m
        case .offline: return "เชื่อมต่อเซิร์ฟเวอร์ไม่ได้"
        case .notInGroup: return "ไม่ได้อยู่ในกลุ่มนี้แล้ว"
        }
    }
}

/// ฐานหนึ่งที่เช็คอินไปแล้ว (จาก GET /wbw/me/progress)
struct CheckinProgressItem: Codable, Equatable {
    let checkpointId: Int
    let name: String
    let activityName: String?
    let sequence: Int?
    let at: String
    /// ตอบความเห็นฐานนี้แล้วหรือยัง — backend คำนวณจาก LEFT JOIN ไม่ได้เก็บสถานะไว้
    ///
    /// decode แบบ tolerant (ดู init(from:) ด้านล่าง): ไม่มีคีย์นี้ในเน็ต = ถือว่า false ไว้ก่อน
    /// เผื่อ cache เก่าที่เขียนไว้ก่อนฟีเจอร์นี้ขึ้น (ยังไม่มีคีย์นี้เลย) — ถ้า decode พังทั้งก้อนแทน
    /// progress จะหาย ต้นไม้หน้า Home เหลือ 0 ทั้งที่เดินมาแล้วหลายฐาน (offline คือเรื่องปกติกลางเขา)
    /// เคสเลวร้ายสุดของ false ผิดคือชวนตอบฐานที่ตอบไปแล้วซ้ำ ซึ่ง backend เด้ง 409 พร้อมคำตอบเดิม
    /// ให้ฟอร์มโชว์แบบอ่านอย่างเดียว ไม่ใช่ error — ปลอดภัยกว่าเสีย progress ทั้งก้อนเยอะ
    let answered: Bool
    let rating: Int?
    let comment: String?
}

// เขียน init(from:) แยกไว้ใน extension โดยตั้งใจ — ถ้าย้ายเข้าไปในตัว struct ตรงๆ Swift จะเลิก
// synthesize memberwise init ให้ (test หลายจุดสร้าง CheckinProgressItem(...) ตรงๆ พึ่งตัวนั้นอยู่)
// แยกไว้ใน extension แบบนี้ยังได้ทั้งคู่ — CodingKeys ก็ยังปล่อยให้ compiler synthesize ให้เหมือนเดิม
extension CheckinProgressItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checkpointId = try c.decode(Int.self, forKey: .checkpointId)
        name = try c.decode(String.self, forKey: .name)
        activityName = try c.decodeIfPresent(String.self, forKey: .activityName)
        sequence = try c.decodeIfPresent(Int.self, forKey: .sequence)
        at = try c.decode(String.self, forKey: .at)
        answered = try c.decodeIfPresent(Bool.self, forKey: .answered) ?? false
        rating = try c.decodeIfPresent(Int.self, forKey: .rating)
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
    }
}

/// ความคืบหน้าเช็คอินของตัวเอง
///
/// total มาจาก backend ทุกครั้ง ไม่ใช่ 8 ตายตัว — แอดมินเพิ่ม/ลบฐานได้
struct CheckinProgress: Codable, Equatable {
    let total: Int
    let checkedIn: [CheckinProgressItem]

    /// ขั้นของต้นไม้ = จำนวนฐานที่เช็คอินแล้ว
    var stage: Int { checkedIn.count }

    /// ฐานที่เช็คอินแล้วแต่ยังไม่ได้ให้ความเห็น · ใหม่สุดก่อน (toast เด้งของฐานล่าสุด)
    ///
    /// เรียงด้วยการเทียบ string `at` ตรงๆ ไม่ parse เป็น Date — ใช้ได้เพราะ backend ฟอร์แมตด้วย
    /// at.UTC().Format(time.RFC3339) เสมอ: ความกว้างคงที่ ไม่มีเศษวินาที ลงท้าย "Z" ตายตัว
    /// lexicographic order เลยตรงกับเวลาจริงพอดี ถือเป็นสัญญากับ backend ไม่ใช่เรื่องบังเอิญ —
    /// ถ้า backend เปลี่ยนฟอร์แมต (เติมเศษวินาที, ใช้ offset แทน Z, ความกว้างไม่คงที่) ลำดับนี้จะผิด
    /// ทันทีโดยไม่มี error ให้เห็น
    var pending: [CheckinProgressItem] {
        checkedIn.filter { !$0.answered }.sorted { $0.at > $1.at }
    }
}
