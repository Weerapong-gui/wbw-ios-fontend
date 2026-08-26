import Foundation

/// ข้อมูลจำลองของโหมดเดโม่ — ครบทุกจอที่ reviewer จะกดเข้าไปดู
///
/// เก็บเป็น **JSON ดิบแล้ว decode ด้วยตัวถอดรหัสตัวเดียวกับที่ `APIClient` ใช้จริง** ไม่ใช่สร้าง
/// struct ตรง ๆ ด้วยเหตุผลเดียว: ถ้าฟิลด์ไหนใน `Models.swift` เปลี่ยนชื่อ/เปลี่ยนชนิด ของจำลอง
/// จะพังทันทีที่เทสรัน แทนที่จะยังคอมไพล์ผ่านแล้วไปโผล่เป็นจอว่างบนเครื่อง reviewer
///
/// **ห้ามใส่ข้อมูลของคนจริงลงในนี้** ชื่อ/เบอร์/รหัสนักศึกษาทั้งหมดเป็นของสมมติ
enum DemoData {
    /// วันที่คงที่ ไม่ใช่ `Date()` — สกรีนช็อตกับสิ่งที่ reviewer เห็นต้องเป็นภาพเดียวกันทุกครั้ง
    private static let baseTime = "2026-08-29T09:00:00Z"

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    /// พังตรงนี้แปลว่า fixture ไม่ตรงกับ model แล้ว — ต้องดังตอนเทส ไม่ใช่เงียบแล้วได้จอว่าง
    private static func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) -> T {
        guard let data = json.data(using: .utf8) else {
            preconditionFailure("DemoData: แปลง fixture เป็น UTF-8 ไม่ได้")
        }
        do { return try decoder.decode(T.self, from: data) }
        catch { preconditionFailure("DemoData: decode \(T.self) ไม่ผ่าน — \(error)") }
    }

    // MARK: - โปรไฟล์

    /// `var` เพราะสกรีนช็อตต้องถ่ายจอ "ยังไม่มีกลุ่ม" ด้วย ซึ่งต่างกันแค่ฟิลด์เดียว —
    /// สลับได้เฉพาะจาก launch arg ที่เป็น `#if DEBUG` (ดู `Session.init`) โค้ดที่ส่งขึ้น store
    /// ไม่มีทางเปลี่ยนค่านี้
    static var me: Me = defaultMe

    static let defaultMe: Me = decode("""
    {
      "user_id": "demo-user",
      "username": "demo",
      "role": "participant",
      "student_id": "6930000001",
      "first_name": "ดินดิน",
      "last_name": "เดินดอย",
      "date_of_birth": "2006-05-14",
      "sex": "unspecified",
      "contact_phone": "0800000000",
      "school_name": "School of Applied Digital Technology",
      "major": "Software Engineering",
      "year": 1,
      "group_id": 7,
      "group_number": 7,
      "leave_quota": 1,
      "bib_number": 1042,
      "qr_token": "demoqrtoken0424",
      "photo_url": null,
      "emergency_contact_name": "ผู้ปกครอง ตัวอย่าง",
      "emergency_contact_phone": "0800000001",
      "blood_type": "O+",
      "food_allergies": "อาหารทะเล",
      "chronic_disease": null,
      "medications": null,
      "weight_kg": 58,
      "height_cm": 170
    }
    """, as: Me.self)

    /// ผู้เข้าร่วมที่ยังไม่ได้เข้ากลุ่ม — ใช้ถ่ายจอ "เข้ากลุ่ม" ซึ่งเป็นคนละจอกับแชทกลุ่ม
    static let meWithoutGroup: Me = decode("""
    {
      "user_id": "demo-user",
      "username": "demo",
      "role": "participant",
      "student_id": "6930000001",
      "first_name": "ดินดิน",
      "last_name": "เดินดอย",
      "date_of_birth": "2006-05-14",
      "sex": "unspecified",
      "contact_phone": "0800000000",
      "school_name": "School of Applied Digital Technology",
      "major": "Software Engineering",
      "year": 1,
      "group_id": null,
      "group_number": null,
      "leave_quota": 2,
      "bib_number": 1042,
      "qr_token": "demoqrtoken0424",
      "photo_url": null,
      "emergency_contact_name": "ผู้ปกครอง ตัวอย่าง",
      "emergency_contact_phone": "0800000001",
      "blood_type": "O+",
      "food_allergies": "อาหารทะเล",
      "chronic_disease": null,
      "medications": null,
      "weight_kg": 58,
      "height_cm": 170
    }
    """, as: Me.self)

    // MARK: - ฐานทั้งงาน

    /// ฐานทั้ง 12 ใบตามที่ `GET /wbw/checkpoints` คืนมา
    ///
    /// **ชื่อชุดนี้คือชื่อจริงจากตาราง `checkpoint` ของงาน** ไม่ใช่ชื่อสมมติ — โหมดเดโม่คือสิ่งที่
    /// App Review เห็น มันควรเป็นงานจริง · รอบแรกเคยใช้ชื่อสมมติ (ลานธงชัย, ศาลาต้นจามจุรี ฯลฯ)
    /// เพื่อให้ตรงกับ `progress` ที่มีชื่อสมมติอยู่ก่อน ซึ่งตรงกันก็จริงแต่ตรงกันที่ชื่อผิดทั้งคู่
    ///
    /// **ชื่อฐาน 1–5 ต้องตรงกับ `progress` ข้างล่างเป๊ะ** — การ์ดบนแผนที่อ่านชื่อจากชุดนี้
    /// ส่วน toast ตอนเช็คอินอ่านจาก `progress` สองชุดใช้ชื่อคนละแบบเมื่อไหร่ reviewer จะเห็นฐาน
    /// เดียวกันชื่อไม่ตรงกันในจอเดียว (`DemoModeTests` คุมไว้)
    ///
    /// **12 แถวไม่ได้แปลว่า 12 ฐาน** — 8 แถวแรกคือฐานที่ต้องสแกน (`requires_checkin: true`)
    /// ที่เหลือเป็นจุดบริการซึ่งเดินผ่านเฉย ๆ · `total` ใน `progress` จึงเป็น 8 ไม่ใช่ 12
    /// เพราะ server นับเฉพาะแถวที่ต้องสแกน (ยืนยันกับ production 2026-08-27: 8 ฐานกิจกรรม
    /// + จุดบริการที่ไม่นับ) · เดิมบรรทัดนี้เขียนว่า 12 ตรงกับ total และตรงกับ DB ซึ่งผิดทั้งสองท่อน
    static let checkpoints: [Checkpoint] = decode("""
    [
      {"id": 1, "sequence": 1, "name": "วิหารพระเจ้าล้านทอง", "name_en": "Wihan Phra Chao Lan Thong",
       "activity_name": "ไหว้พระวิหารพระเจ้าล้านทอง", "activity_name_en": "Pay respects at Wihan Phra Chao Lan Thong",
       "type": "activity", "requires_checkin": true},
      {"id": 2, "sequence": 2, "name": "สวนกุหลาบ", "name_en": "Rose Garden",
       "activity_name": "R2L", "activity_name_en": "R2L",
       "type": "activity", "requires_checkin": true},
      {"id": 3, "sequence": 3, "name": "ลานวัฒนธรรม", "name_en": "Culture Plaza",
       "activity_name": "ปลูกป่าข้ามแม่น้ำ", "activity_name_en": "Plant trees across the river",
       "type": "activity", "requires_checkin": true},
      {"id": 4, "sequence": 4, "name": "ลานสวนสน", "name_en": "Pine Grove Plaza",
       "activity_name": "ส่งแป้งข้ามหัว", "activity_name_en": "Pass the flour overhead",
       "type": "activity", "requires_checkin": true},
      {"id": 5, "sequence": 5, "name": "จุดปลูก", "name_en": "Planting Point",
       "activity_name": "ปลูกป่า", "activity_name_en": "Tree planting",
       "type": "activity", "requires_checkin": true},
      {"id": 6, "sequence": 6, "name": "ลานย่อย 3", "name_en": "Sub-area 3",
       "activity_name": "ล้วงไห", "activity_name_en": "Reach into the jar",
       "type": "activity", "requires_checkin": true},
      {"id": 7, "sequence": 7, "name": "ฐานผ้าใบ", "name_en": "Canvas Base",
       "activity_name": "ผ้าใบเขียนความรู้สึก", "activity_name_en": "Canvas: write your feelings",
       "type": "activity", "requires_checkin": true},
      {"id": 8, "sequence": 8, "name": "ฐาน Zero Waste", "name_en": "Zero Waste Base",
       "activity_name": "Zero Waste และ SDGs", "activity_name_en": "Zero Waste & SDGs",
       "type": "activity", "requires_checkin": true},
      {"id": 9, "sequence": null, "name": "MFU Botanical Garden", "name_en": "MFU Botanical Garden",
       "activity_name": "จุดห้องน้ำ", "activity_name_en": "Restroom point",
       "type": "restroom", "requires_checkin": false},
      {"id": 10, "sequence": null, "name": "ลานย่อย 1", "name_en": "Sub-area 1",
       "activity_name": "จุดสวัสดิการ", "activity_name_en": "Welfare point",
       "type": "welfare", "requires_checkin": false},
      {"id": 11, "sequence": null, "name": "ลานย่อย 2", "name_en": "Sub-area 2",
       "activity_name": "สวัสดิการ/สันทนาการ", "activity_name_en": "Welfare / recreation",
       "type": "recreation", "requires_checkin": false},
      {"id": 12, "sequence": null, "name": "ทางออกฐานปลูกป่า", "name_en": "Reforestation Base Exit",
       "activity_name": "สวัสดิการ/รถห้องน้ำ", "activity_name_en": "Welfare / mobile restroom",
       "type": "service", "requires_checkin": false}
    ]
    """, as: [Checkpoint].self)

    // MARK: - ความคืบหน้าเช็คอิน

    /// 5 จาก 8 ฐาน — ตั้งใจให้อยู่กลาง ๆ ดอกไม้บนหน้า Home จะได้บานไปแล้วครึ่งทาง
    /// ไม่ใช่เมล็ด (ดูไม่ออกว่ามีฟีเจอร์) และไม่ใช่บานเต็ม (ไม่เหลืออะไรให้เห็นว่ามันโตได้อีก)
    /// ฐานสุดท้ายยังไม่ตอบความเห็น เพื่อให้ฟอร์มให้คะแนนเปิดได้จริงในโหมดเดโม่
    static let progress: CheckinProgress = decode("""
    {
      "total": 8,
      "checked_in": [
        {"checkpoint_id": 1, "name": "วิหารพระเจ้าล้านทอง", "activity_name": "ไหว้พระวิหารพระเจ้าล้านทอง",
         "sequence": 1, "at": "2026-08-29T07:12:00Z", "answered": true, "rating": 3, "comment": null},
        {"checkpoint_id": 2, "name": "สวนกุหลาบ", "activity_name": "R2L",
         "sequence": 2, "at": "2026-08-29T07:48:00Z", "answered": true, "rating": 3, "comment": null},
        {"checkpoint_id": 3, "name": "ลานวัฒนธรรม", "activity_name": "ปลูกป่าข้ามแม่น้ำ",
         "sequence": 3, "at": "2026-08-29T08:21:00Z", "answered": true, "rating": 2, "comment": null},
        {"checkpoint_id": 4, "name": "ลานสวนสน", "activity_name": "ส่งแป้งข้ามหัว",
         "sequence": 4, "at": "2026-08-29T08:55:00Z", "answered": true, "rating": 3, "comment": null},
        {"checkpoint_id": 5, "name": "จุดปลูก", "activity_name": "ปลูกป่า",
         "sequence": 5, "at": "2026-08-29T09:26:00Z", "answered": false, "rating": null, "comment": null}
      ]
    }
    """, as: CheckinProgress.self)

    // MARK: - ประกาศ

    static let notifications: [NotificationItem] = decode("""
    [
      {"id": "5", "type": "checkin_feedback", "title": "ให้คะแนนฐานจุดปลูก",
       "body": "เช็คอินแล้ว แตะเพื่อบอกทีมงานว่าฐานนี้เป็นยังไงบ้าง",
       "level": "info", "audience": "user", "audience_id": "demo-user", "ref_id": "5",
       "created_at": "2026-08-29T09:26:10Z", "read_at": null},
      {"id": "4", "type": "announcement", "title": "ฝนตกช่วงบ่าย เตรียมเสื้อกันฝน",
       "body": "กรมอุตุฯ แจ้งฝนฟ้าคะนองบริเวณดอยช่วง 13:00-15:00 น. ทีมงานเตรียมจุดหลบฝนไว้ที่ฐาน 6 และ 7",
       "level": "warning", "audience": "all", "audience_id": null, "ref_id": null,
       "created_at": "2026-08-29T08:40:00Z", "read_at": null},
      {"id": "3", "type": "announcement", "title": "จุดเติมน้ำฐานที่ 6 พร้อมแล้ว",
       "body": "นำขวดน้ำส่วนตัวมาเติมได้ ไม่มีแก้วพลาสติกแจกตามนโยบายงานปลอดขยะ",
       "level": "info", "audience": "all", "audience_id": null, "ref_id": null,
       "created_at": "2026-08-29T07:30:00Z", "read_at": "2026-08-29T07:35:00Z"},
      {"id": "2", "type": "announcement", "title": "ทีมพยาบาลประจำลานสวนสน",
       "body": "ถ้ารู้สึกไม่ไหว แจ้งเจ้าหน้าที่เสื้อกั๊กสีส้มได้ทันที ทุกฐานมีชุดปฐมพยาบาล",
       "level": "emergency", "audience": "all", "audience_id": null, "ref_id": null,
       "created_at": "2026-08-29T06:55:00Z", "read_at": "2026-08-29T07:00:00Z"},
      {"id": "1", "type": "announcement", "title": "ยินดีต้อนรับสู่งานเดินรอบดอย",
       "body": "ลงทะเบียนที่วิหารพระเจ้าล้านทองตั้งแต่ 06:30 น. อย่าลืมบัตรผู้เข้าร่วมในแอป",
       "level": "info", "audience": "all", "audience_id": null, "ref_id": null,
       "created_at": "2026-08-29T06:00:00Z", "read_at": "2026-08-29T06:05:00Z"}
    ]
    """, as: [NotificationItem].self)

    // MARK: - กลุ่ม

    static let groups: [GroupSummary] = decode("""
    [
      {"group_id": 5, "group_number": 5, "capacity": 50, "member_count": 50, "seats_left": 0},
      {"group_id": 6, "group_number": 6, "capacity": 50, "member_count": 47, "seats_left": 3},
      {"group_id": 7, "group_number": 7, "capacity": 50, "member_count": 42, "seats_left": 8},
      {"group_id": 8, "group_number": 8, "capacity": 50, "member_count": 31, "seats_left": 19},
      {"group_id": 9, "group_number": 9, "capacity": 50, "member_count": 12, "seats_left": 38},
      {"group_id": 10, "group_number": 10, "capacity": 50, "member_count": 4, "seats_left": 46}
    ]
    """, as: [GroupSummary].self)

    static let membersIndex: [GroupMemberIndex] = decode("""
    [
      {"user_id": "demo-user", "first_name": "ดินดิน", "last_name": "เดินดอย", "group_id": 7, "group_number": 7},
      {"user_id": "demo-2", "first_name": "ปาล์ม", "last_name": "ใจดี", "group_id": 7, "group_number": 7},
      {"user_id": "demo-3", "first_name": "แนน", "last_name": "ศรีวิไล", "group_id": 7, "group_number": 7},
      {"user_id": "demo-4", "first_name": "ตี๋", "last_name": "ภูผา", "group_id": 7, "group_number": 7},
      {"user_id": "demo-5", "first_name": "มายด์", "last_name": "ทองสุข", "group_id": 8, "group_number": 8}
    ]
    """, as: [GroupMemberIndex].self)

    static let groupMembers: GroupMembersResponse = decode("""
    {
      "count": 4,
      "members": [
        {"user_id": "demo-user", "first_name": "ดินดิน", "last_name": "เดินดอย",
         "photo_url": null, "bib": 1042, "school": "Applied Digital Technology"},
        {"user_id": "demo-2", "first_name": "ปาล์ม", "last_name": "ใจดี",
         "photo_url": null, "bib": 1043, "school": "Management"},
        {"user_id": "demo-3", "first_name": "แนน", "last_name": "ศรีวิไล",
         "photo_url": null, "bib": 1044, "school": "Science"},
        {"user_id": "demo-4", "first_name": "ตี๋", "last_name": "ภูผา",
         "photo_url": null, "bib": 1045, "school": "Liberal Arts"}
      ]
    }
    """, as: GroupMembersResponse.self)

    // MARK: - แชทกลุ่ม

    /// id เดินจาก 1 ขึ้นไป · `sinceId` เป็น 0 เพราะไม่มีประวัติที่ต้องตัดทิ้งในโหมดเดโม่
    static let chatMessages: [MessageDTO] = decode("""
    [
      {"id": 1, "group_id": 7, "sender_id": "demo-2", "client_id": "d-1",
       "body": "ถึงวิหารพระเจ้าล้านทองแล้วน้า ใครยังไม่มารีบเลย", "device_time": "2026-08-29T07:05:00Z",
       "created_at": "2026-08-29T07:05:00Z", "first_name": "ปาล์ม", "last_name": "ใจดี"},
      {"id": 2, "group_id": 7, "sender_id": "demo-3", "client_id": "d-2",
       "body": "กำลังไปถึงใน 5 นาที", "device_time": "2026-08-29T07:06:20Z",
       "created_at": "2026-08-29T07:06:20Z", "first_name": "แนน", "last_name": "ศรีวิไล"},
      {"id": 3, "group_id": 7, "sender_id": "demo-user", "client_id": "d-3",
       "body": "เจอกันหน้าซุ้มลงทะเบียนนะ", "device_time": "2026-08-29T07:07:00Z",
       "created_at": "2026-08-29T07:07:00Z", "first_name": "ดินดิน", "last_name": "เดินดอย"},
      {"id": 4, "group_id": 7, "sender_id": "demo-4", "client_id": "d-4",
       "body": "ฐาน 3 คิวยาวมาก เผื่อเวลาด้วย", "device_time": "2026-08-29T08:15:00Z",
       "created_at": "2026-08-29T08:15:00Z", "first_name": "ตี๋", "last_name": "ภูผา"},
      {"id": 5, "group_id": 7, "sender_id": "demo-2", "client_id": "d-5",
       "body": "วิวจากลานสวนสนสวยมาก อย่าลืมถ่ายรูปหมู่", "device_time": "2026-08-29T08:58:00Z",
       "created_at": "2026-08-29T08:58:00Z", "first_name": "ปาล์ม", "last_name": "ใจดี"},
      {"id": 6, "group_id": 7, "sender_id": "demo-user", "client_id": "d-6",
       "body": "ถึงฐาน 5 แล้ว เหลืออีก 3 ฐาน สู้ ๆ", "device_time": "2026-08-29T09:26:30Z",
       "created_at": "2026-08-29T09:26:30Z", "first_name": "ดินดิน", "last_name": "เดินดอย"}
    ]
    """, as: [MessageDTO].self)

    static var chatSync: ChatSyncResponse {
        ChatSyncResponse(sinceId: 0, memberCount: 4, messages: chatMessages,
                         cursors: [ReadCursor(userId: "demo-2", lastReadId: 6),
                                   ReadCursor(userId: "demo-3", lastReadId: 5),
                                   ReadCursor(userId: "demo-4", lastReadId: 6)])
    }

    /// ข้อความที่ผู้ใช้พิมพ์เองในโหมดเดโม่ — echo กลับให้ optimistic send เห็นสถานะ "ส่งแล้ว" จริง
    /// id เดินต่อจากชุด fixture ไม่งั้นข้อความใหม่จะถูกมองว่าเก่ากว่าของที่มีอยู่แล้ว
    static func echo(clientId: String, body: String, deviceTime: String, groupId: Int) -> MessageDTO {
        let nextId = (chatMessages.compactMap { Int64($0.id) }.max() ?? 0) + Int64(sentCount + 1)
        sentCount += 1
        let json = """
        {"id": \(nextId), "group_id": \(groupId), "sender_id": "demo-user",
         "client_id": "\(clientId)", "body": \(quoted(body)),
         "device_time": "\(deviceTime)", "created_at": "\(deviceTime)",
         "first_name": "ดินดิน", "last_name": "เดินดอย"}
        """
        return decode(json, as: MessageDTO.self)
    }

    private static var sentCount = 0

    /// ข้อความผู้ใช้ต้องผ่าน JSON encoder จริง ไม่ใช่แปะลงสตริง — พิมพ์ `"` หรือขึ้นบรรทัดใหม่
    /// แล้ว fixture จะพังทั้งก้อนแล้ว `preconditionFailure` จะทำให้แอปดับคาการรีวิว
    private static func quoted(_ s: String) -> String {
        (try? String(data: JSONEncoder().encode(s), encoding: .utf8)) ?? "\"\""
    }

    // MARK: - สภาพเส้นทาง

    /// ค่าคงที่ ไม่ยิง Open-Meteo — โหมดเดโม่ต้องทำงานได้แม้ไม่มีเน็ตเลย และสกรีนช็อตต้องซ้ำได้
    static let conditions = TrailConditions(
        weather: Weather(temperatureC: 27, feelsLikeC: 30, humidityPercent: 72, code: 2),
        air: AirReading(usAqi: 42))

    // MARK: - ฐานของเจ้าหน้าที่ (เผื่อไว้ — role เดโม่เป็น participant จึงไม่ควรถูกเรียก)

    static let staffCheckpoints: [StaffCheckpoint] = []
}
