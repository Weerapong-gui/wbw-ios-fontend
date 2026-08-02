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
struct NotificationItem: Codable, Identifiable {
    @FlexibleString var id: String
    let type: String?
    let title: String
    let body: String?
    let level: String
    let audience: String?
    let audienceId: String?
    let createdAt: String?
    var readAt: String?

    var isUnread: Bool { readAt == nil }

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
    let sequence: Int?
    let at: String
}

/// ความคืบหน้าเช็คอินของตัวเอง
///
/// total มาจาก backend ทุกครั้ง ไม่ใช่ 8 ตายตัว — แอดมินเพิ่ม/ลบฐานได้
struct CheckinProgress: Codable, Equatable {
    let total: Int
    let checkedIn: [CheckinProgressItem]

    /// ขั้นของต้นไม้ = จำนวนฐานที่เช็คอินแล้ว
    var stage: Int { checkedIn.count }
}
