import Foundation

extension APIClient {

    /// **ไม่มีสถานะปลายทางสำหรับเคส SOS เลย** — ฟังก์ชันนี้คืน false เสมอ โดยตั้งใจ
    ///
    /// มีอยู่เป็นฟังก์ชันแทนที่จะไม่มีอะไรเลย เพราะรูปร่างของ submitFeedback ชวนให้
    /// คนแก้โค้ดคนถัดไปเติม "รายชื่อ terminal" เข้ามาโดยอัตโนมัติ · ที่นี่คือที่ที่
    /// การตัดสินใจนั้นถูกเขียนไว้ชัดๆ พร้อมเทสที่ไล่ status 100-599 ค้ำอยู่
    ///
    /// ทำไมถึงต่างจาก feedback ที่ยอมทิ้งเมื่อเจอ 400/401: ความเห็นต่อฐานที่หายไป
    /// คือข้อมูลหนึ่งแถวที่ไม่มีใครเดือดร้อน เคส SOS ที่หายไปคือคนที่รอความช่วยเหลือ
    /// อยู่บนดอยโดยเชื่อว่าส่งไปแล้ว · 401 เองก็ไม่ทิ้ง — ค้างไว้แล้วขอให้ล็อกอินใหม่
    static func sosIsTerminal(status: Int, data: Data) -> Bool { false }

    static func sosIsSuccess(status: Int) -> Bool { status == 200 || status == 201 }

    /// body เป็น error envelope ของ origin เราเองไหม — ใช้แยก 409 ที่มีความหมายจริง
    /// ออกจาก 409/403 ของ Cloudflare ที่ขวางหน้าอยู่ (เหตุผลเดียวกับใน submitFeedback)
    static func sosIsOriginEnvelope(_ data: Data) -> Bool {
        guard let b = try? JSONDecoder().decode(APIErrorBody.self, from: data),
              let e = b.error, !e.isEmpty else { return false }
        return true
    }

    /// เปิดหรืออัปเดตเคส SOS — idempotent ด้วย clientId
    ///
    /// ทุก error ออกทาง AppError.retryable หรือ .offline เท่านั้น ไม่มีทางออกอื่น
    /// ผู้เรียก (SOSStore) จึงไม่มีเส้นทางไหนเลยที่จะลบเคสทิ้ง
    func raiseSOS(token: String, draft: SOSDraft) async throws -> SOSCase {
        guard let url = URL(string: "\(Config.apiBase)/me/sos") else {
            throw AppError.retryable("URL ไม่ถูกต้อง")
        }
        var body: [String: Any] = [
            "client_id": draft.clientId,
            "device_time": draft.deviceTime,
            "for_other": draft.forOther,
        ]
        if let v = draft.lat { body["lat"] = v }
        if let v = draft.lng { body["lng"] = v }
        if let v = draft.accuracyM { body["accuracy_m"] = v }
        if let v = draft.message { body["message"] = v }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.offline }

        guard let http = resp as? HTTPURLResponse else { throw AppError.retryable("การตอบกลับผิดพลาด") }
        guard Self.sosIsSuccess(status: http.statusCode) else {
            let b = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw AppError.retryable(b?.error ?? "ส่งไม่สำเร็จ กำลังลองใหม่")
        }
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(SOSCase.self, from: data)
    }

    enum SOSCancelOutcome: Equatable { case canceled, alreadyAcked, tooLate }

    func cancelSOS(token: String, id: Int64) async throws -> SOSCancelOutcome {
        guard let url = URL(string: "\(Config.apiBase)/me/sos/\(id)/cancel") else {
            throw AppError.retryable("URL ไม่ถูกต้อง")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.offline }

        guard let http = resp as? HTTPURLResponse else { throw AppError.retryable("การตอบกลับผิดพลาด") }
        switch http.statusCode {
        case 200:
            return .canceled
        case 409 where Self.sosIsOriginEnvelope(data):
            // แยกสองเหตุผลจากข้อความ — ทั้งคู่จบเหมือนกันในสายตาผู้ใช้ (ต้องโทรแทน)
            let b = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            return (b?.error ?? "").contains("เลยเวลา") ? .tooLate : .alreadyAcked
        default:
            throw AppError.retryable("ยกเลิกไม่สำเร็จ")
        }
    }
}

/// เคสหนึ่งอันในสายตาเจ้าหน้าที่ ข้อมูลมากกว่าที่คนกดเห็น — ต้นฉบับของชนิดนี้คือ Task 15
/// แต่ต้องยกมานิยามที่นี่ก่อน เพราะ staffSOSFeed ด้านล่างคืนค่าเป็น [SOSStaffCase] ตรงๆ
/// ไฟล์นี้จึงคอมไพล์ไม่ผ่านถ้าไม่มีชนิดนี้อยู่ก่อน (พบตอนทำ Task 10 — ดู fix(plan) ที่แก้จุดนี้)
///
/// field ตรงกับ model.SOSStaffCase ฝั่ง Go (Task 2) แบบ 1:1 ผ่าน convertFromSnakeCase —
/// Go embed SOSCase แบบไม่มี json tag จึง flatten เป็นก้อนเดียวกับ struct นี้พอดี
struct SOSStaffCase: Codable, Identifiable, Equatable {
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
    let updatedAt: String
    let participantId: String
    let firstName: String
    let lastName: String
    let bib: Int?
    let groupNumber: Int?
    let contactPhone: String?
    let emergencyContactName: String?
    let emergencyContactPhone: String?
    let bloodType: String?
    let healthNotes: String?

    var fullName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// ความแม่นแย่กว่า 200 ม. = ฐานที่เซิร์ฟเวอร์คำนวณมาเชื่อไม่ได้
    /// ฐานห่างกัน 300-500 ม. พิกัด ±500 ม. ชี้ผิดฐานได้ง่ายๆ
    var isCoarse: Bool { (accuracyM ?? 0) > 200 }

    var accuracyLabel: String {
        guard let a = accuracyM else { return "ไม่ทราบความแม่น" }
        return "±\(Int(a)) ม."
    }

    var positionLabel: String {
        guard let lat, let lng else { return "ไม่ทราบตำแหน่ง" }
        return String(format: "%.5f, %.5f", lat, lng)
    }
}

extension APIClient {

    /// long-poll สถานะเคสของตัวเอง · nil = ไม่มีเคสเปิดและไม่มีเคสที่เพิ่งปิด
    ///
    /// timeoutInterval ตั้งเป็น wait + 10 — ค่าเริ่มต้น 60 วิของ URLSession ยาวกว่า
    /// long-poll 25 วิอยู่แล้วก็จริง แต่ผูกไว้ให้ชัดกันคนเพิ่ม wait แล้วลืมแก้ฝั่งนี้
    func activeSOS(token: String, wait: Int) async throws -> SOSCase? {
        guard let url = URL(string: "\(Config.apiBase)/me/sos/active?wait=\(wait)") else {
            throw AppError.retryable("URL ไม่ถูกต้อง")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = TimeInterval(wait + 10)

        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.offline }

        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.retryable("อ่านสถานะไม่สำเร็จ")
        }
        if data.isEmpty || String(data: data, encoding: .utf8) == "null" { return nil }
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(SOSCase.self, from: data)
    }

    /// เคสหนึ่งอัน สำหรับเพื่อนในกลุ่ม · 404 = ไม่ใช่กลุ่มเรา
    func sosCase(token: String, id: Int64) async throws -> SOSCase {
        try await getSOSDecoded("/me/sos/\(id)", token: token, SOSCase.self)
    }

    func staffSOSFeed(token: String, since: String?, wait: Int) async throws -> [SOSStaffCase] {
        var path = "/staff/sos?wait=\(wait)"
        if let since, let esc = since.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&since=\(esc)"
        }
        guard let url = URL(string: "\(Config.apiBase)\(path)") else {
            throw AppError.retryable("URL ไม่ถูกต้อง")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = TimeInterval(wait + 10)

        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.offline }

        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.retryable("โหลดรายการเคสไม่สำเร็จ")
        }
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode([SOSStaffCase].self, from: data)
    }

    @discardableResult
    func ackSOS(token: String, id: Int64) async throws -> Bool {
        try await postSOSAction("/staff/sos/\(id)/ack", token: token, body: nil)
    }

    @discardableResult
    func resolveSOS(token: String, id: Int64, reason: String) async throws -> Bool {
        try await postSOSAction("/staff/sos/\(id)/resolve", token: token, body: ["reason": reason])
    }

    private func postSOSAction(_ path: String, token: String, body: [String: Any]?) async throws -> Bool {
        guard let url = URL(string: "\(Config.apiBase)\(path)") else {
            throw AppError.retryable("URL ไม่ถูกต้อง")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        let (_, resp): (Data, URLResponse)
        do { (_, resp) = try await Self.send(req) }
        catch { throw AppError.offline }
        guard let http = resp as? HTTPURLResponse, Self.sosIsSuccess(status: http.statusCode) else {
            throw AppError.retryable("ทำรายการไม่สำเร็จ")
        }
        return true
    }

    private func getSOSDecoded<T: Decodable>(_ path: String, token: String, _ type: T.Type) async throws -> T {
        guard let url = URL(string: "\(Config.apiBase)\(path)") else {
            throw AppError.retryable("URL ไม่ถูกต้อง")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.offline }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.retryable("โหลดข้อมูลไม่สำเร็จ")
        }
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(T.self, from: data)
    }
}
