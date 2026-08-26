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
    /// สิทธิ์ออกจากกลุ่มคงเหลือ · optional เพราะ backend ที่ยังไม่ได้ deploy โควตาไม่ส่ง key นี้มา
    /// ผู้ใช้ค่านี้ต้องอ่านเป็น `?? 0` เสมอ — พลาดไปทาง "ไม่มีสิทธิ์" ปลอดภัยกว่าทาง "แจกฟรี"
    let leaveQuota: Int?
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
    /// ชี้ไปวัตถุที่แจ้งเตือนนี้พูดถึง · สองชนิดที่ใช้ตอนนี้: type == "checkin_feedback" = checkpoint_id,
    /// type == "sos" = sos_event id (ดู feedbackCheckpointId/sosId ด้านล่าง ซึ่งเป็นสองทางอ่านค่านี้)
    let refId: String?
    let createdAt: String?
    var readAt: String?

    var isUnread: Bool { readAt == nil }

    /// เลขฐานที่แจ้งเตือนนี้ขอความเห็น · nil = ไม่ใช่แจ้งเตือนชนิดนี้
    var feedbackCheckpointId: Int? {
        guard type == "checkin_feedback", let refId else { return nil }
        return Int(refId)
    }

    /// เลขเคส SOS ที่แจ้งเตือนนี้พูดถึง · nil = ไม่ใช่แจ้งเตือนชนิดนี้
    var sosId: Int64? {
        guard type == "sos", let refId else { return nil }
        return Int64(refId)
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
    /// คีย์ฝั่งเครื่องที่ใช้ dedupe — **ไม่มีวันว่าง** ถึงจะไม่มีในคำตอบก็ตาม (ดู init(from:))
    let clientId: String
    let body: String
    let deviceTime: String?
    let createdAt: String?
    let firstName: String?
    let lastName: String?

    /// memberwise init — เขียนเองเพราะ `init(from:)` ข้างล่างกลบตัวที่ Swift สังเคราะห์ให้
    /// (เทสหลายไฟล์ประกอบ DTO ตรง ๆ ไม่ผ่าน JSON)
    init(id: String, groupId: Int, senderId: String, clientId: String, body: String,
         deviceTime: String?, createdAt: String?, firstName: String?, lastName: String?) {
        self.id = id
        self.groupId = groupId
        self.senderId = senderId
        self.clientId = clientId
        self.body = body
        self.deviceTime = deviceTime
        self.createdAt = createdAt
        self.firstName = firstName
        self.lastName = lastName
    }

    /// เขียน init เองเพื่อ **ไม่ให้แถวเดียวฆ่าทั้งห้องแชท**
    ///
    /// `client_id` เป็นคอลัมน์ที่แอปเป็นคนตั้งตอน POST (ดู docs/backend-contract.md §8) แถวที่
    /// ไม่ได้เกิดจากแอป — แอดมิน insert เอง, migration, สคริปต์ทดสอบ — จึงมี `null` หรือ `""` ได้
    /// จริง · ปล่อยให้ synthesized init throw แล้ว `chatSync` จะล้มทั้งก้อน syncLoop เข้า backoff
    /// วนตลอดไป **โดยไม่มี error บนจอเลย** (แคชเก่ายังโชว์ครบ) = แชทเงียบไปเฉย ๆ ทั้งห้อง
    ///
    /// คีย์แทนต้องอิง `id` ของเซิร์ฟเวอร์ ซึ่งไม่ซ้ำกันแน่นอน — ถ้าใช้ค่าคงที่หรือ `""`
    /// `@Attribute(.unique)` ของ `ChatMessage.clientId` จะ **ยุบทุกแถวแบบนั้นรวมเป็นแถวเดียว**
    /// และ `ForEach` ในจอแชทจะมี id ซ้ำ
    ///
    /// ที่ยังปล่อยให้ throw ไว้เหมือนเดิมคือ `id`/`group_id`/`sender_id`/`body` — ขาดตัวใดตัวหนึ่ง
    /// แปลว่าแถวนี้ประกอบเป็นข้อความไม่ได้จริง ๆ ให้ `ChatSyncResponse` ทิ้งทั้งแถวไปแทน
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // เก็บลงตัวแปรก่อนแล้วค่อยใช้ — อ่าน `self.id` ตอนที่ยังตั้งค่าไม่ครบทุก property ไม่ได้
        let serverId = try c.decode(FlexibleString.self, forKey: .id)
        _id = serverId
        groupId = try c.decode(Int.self, forKey: .groupId)
        senderId = try c.decode(String.self, forKey: .senderId)
        body = try c.decode(String.self, forKey: .body)
        deviceTime = try c.decodeIfPresent(String.self, forKey: .deviceTime)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        let raw = try c.decodeIfPresent(String.self, forKey: .clientId)
        if let raw, !raw.isEmpty {
            clientId = raw
        } else {
            clientId = "srv-\(serverId.wrappedValue)"
        }
    }

    var senderName: String {
        [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum AppError: LocalizedError {
    case message(String)
    case groupFull(String)
    case offline
    /// ไปถึงปลายทางแล้ว แต่ได้คำตอบว่า "ตอนนี้ยังไม่ได้" — **ค่าเริ่มต้นของทุก status ที่ไม่ได้อยู่ใน
    /// รายชื่อ terminal** ไม่ใช่แค่ 429/5xx (ดูตารางเต็มที่ APIClient.submitFeedback)
    ///
    /// ต่างจาก .message ตรงที่ **ส่ง payload เดิมซ้ำมีโอกาสสำเร็จ** จึงเป็น error ที่ต้องเก็บของ
    /// ไว้ retry ไม่ใช่ทิ้ง · แยกออกมาเพราะเดิมทุก status ที่ไม่ใช่ทางสำเร็จถูกยัดรวมเป็น
    /// .message หมด ผู้เรียกจึงแยกไม่ออกว่า "rating ผิด 400" (ส่งซ้ำก็ไม่มีวันผ่าน) กับ "origin
    /// ล้นชั่วคราว 503 / Cloudflare 502-524 หน้า api.studentunion.social" (เดี๋ยวก็ผ่าน)
    /// ต่างกันอย่างไร แล้วทิ้งคำตอบของผู้ใช้ไปพร้อมกันทั้งสองแบบ
    case retryable(String)
    case notInGroup
    var errorDescription: String? {
        switch self {
        case let .message(m): return m
        case let .groupFull(m): return m
        case .offline: return Loc.t("error_network_short")
        case let .retryable(m): return m
        case .notInGroup: return Loc.t("error_not_in_group")
        }
    }
}

/// ฐานหนึ่งใบในงาน (จาก GET /wbw/checkpoints)
///
/// ต่างจาก `CheckinProgressItem` ตรงที่มีครบทุกฐานไม่ใช่เฉพาะที่เช็คอินแล้ว และมีชื่อสองภาษา —
/// `/me/progress` ไม่มีฟิลด์ `_en` เลย คนที่ตั้งแอปเป็นอังกฤษจึงเห็นชื่อฐานเป็นไทยมาตลอด
///
/// ทุกฟิลด์ยกเว้น `id` กับ `name` ถอดแบบยอมให้หายได้ (ดู `init(from:)`) — บทเรียนจาก
/// `CheckinProgressItem.answered`: แคชที่เขียนไว้ก่อนฟิลด์ใหม่จะ decode พัง**ทั้งก้อน**
/// แล้วชื่อฐานหายหมดทั้งแผนที่พร้อมกัน ไม่ใช่หายทีละแถว
struct Checkpoint: Codable, Equatable {
    let id: Int
    /// ลำดับเช็คอิน 1…8 · **nil ได้จริง** — จุดบริการสี่จุด (ห้องน้ำ/สวัสดิการ/สันทนาการ) ไม่มีลำดับ
    let sequence: Int?
    let name: String
    let nameEn: String?
    let activityName: String?
    let activityNameEn: String?
    /// `activity` / `restroom` / `welfare` / `recreation` / `service`
    let type: String
    let requiresCheckin: Bool

    /// พิกัดของฐาน — ใช้บอกว่า "ห่างจากคุณเท่าไร" บนการ์ดฐาน (ยกมาจากฝั่ง Android `405c63d`)
    ///
    /// `var` ไม่ใช่ `let` เพื่อให้ memberwise init มีค่าเริ่มต้นเป็น nil — จุดเรียกเก่าที่สร้าง
    /// `Checkpoint` เองในเทสจะได้ไม่พังทั้งชุดเพราะฟิลด์ที่เซิร์ฟเวอร์เพิ่งเริ่มส่ง
    var lat: Double?
    var lng: Double?

    /// มีคนเช็คอินฐานนี้ไปแล้วกี่คน — **ไม่มีค่ามาแปลว่าศูนย์ ไม่ใช่ซ่อนบรรทัดทิ้ง**
    /// (ตัดสินแบบเดียวกับฝั่ง Android ที่ `7211c6f` · ดู `Map3DPins.checkinCount`)
    var checkinCount: Int?

    /// ชื่อที่โชว์ตามภาษาที่ผู้ใช้เลือก**ในแอป** ไม่ใช่ภาษาของเครื่อง
    var displayName: String { Self.pick(name, nameEn) }
    var displayActivity: String? {
        guard let activityName, !activityName.isEmpty else { return nil }
        return Self.pick(activityName, activityNameEn)
    }

    /// เลือกภาษาผ่านคีย์ `lang_code` ที่อยู่ในชุดคีย์เดียวกับข้อความอื่นทั้งแอป
    ///
    /// ใช้ `AppSettings.language` ตรง ๆ ไม่ได้ เพราะค่า `.system` แปลว่า "ตามเครื่อง" ซึ่งยัง
    /// ไม่บอกว่าสุดท้ายแล้วจอกำลังเป็นภาษาอะไร · ผ่าน `Loc` แทนแล้วชื่อฐานกับข้อความรอบ ๆ
    /// จะชี้ไป `.lproj` เดียวกันเสมอ ขัดกันไม่ได้
    private static func pick(_ thai: String, _ english: String?) -> String {
        guard Loc.t("lang_code") == "en", let english, !english.isEmpty else { return thai }
        return english
    }
}

extension Checkpoint {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        sequence = try c.decodeIfPresent(Int.self, forKey: .sequence)
        name = try c.decode(String.self, forKey: .name)
        nameEn = try c.decodeIfPresent(String.self, forKey: .nameEn)
        activityName = try c.decodeIfPresent(String.self, forKey: .activityName)
        activityNameEn = try c.decodeIfPresent(String.self, forKey: .activityNameEn)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "activity"
        requiresCheckin = try c.decodeIfPresent(Bool.self, forKey: .requiresCheckin) ?? true
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
    /// ตอบความเห็นทั้งงานไปแล้วหรือยัง — server เป็นคนจำ (หลักเดียวกับ answered ต่อฐาน:
    /// เครื่องไม่จำเอง กันลบแอป/เครื่องที่สองแล้วถามคนที่ตอบแล้วซ้ำ) · SUS ยังไม่ส่งฟิลด์นี้
    /// = false ไปก่อน ฟอร์มถามซ้ำได้แต่แอปห้ามเปิดไม่ขึ้น
    let eventFeedbackAnswered: Bool

    init(total: Int, checkedIn: [CheckinProgressItem], eventFeedbackAnswered: Bool = false) {
        self.total = total
        self.checkedIn = checkedIn
        self.eventFeedbackAnswered = eventFeedbackAnswered
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = try c.decode(Int.self, forKey: .total)
        checkedIn = try c.decode([CheckinProgressItem].self, forKey: .checkedIn)
        eventFeedbackAnswered = try c.decodeIfPresent(Bool.self, forKey: .eventFeedbackAnswered) ?? false
    }

    /// ขั้นของต้นไม้ = จำนวนฐานที่เช็คอินแล้ว
    var stage: Int { checkedIn.count }

    /// ครบทุกฐานแล้วจริง — สูตรเดียวกับ Android (ProgressDto.complete)
    var complete: Bool { total > 0 && checkedIn.count >= total }

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
