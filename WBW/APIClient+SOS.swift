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

    /// decode ที่ไม่ปล่อย DecodingError ดิบออกไปให้ผู้เรียกเจอ — เจอจากรีวิว Task 10: 200/201
    /// ที่ body ไม่ตรงรูปที่คาดไว้ (ส่งไม่จบ, proxy แทรกกลาง, backend เปลี่ยน schema) ไม่ต่างจาก
    /// 503 ในแง่ที่ว่า "ลองใหม่มีโอกาสผ่าน" จึงจัดเป็น retryable เหมือนกัน ไม่ใช่ปล่อยชนิด error
    /// ที่ไม่มีใครดักไว้หลุดออกไป — จุดนี้คือสิ่งที่ทำให้คอมเมนต์ของ raiseSOS ข้างล่างที่บอกว่า
    /// "ไม่มีทางออกอื่น" เป็นจริง แทนที่จะเป็นแค่ความตั้งใจ
    private static func decodeSOS<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try dec.decode(T.self, from: data)
        } catch {
            throw AppError.retryable("อ่านข้อมูลที่เซิร์ฟเวอร์ตอบไม่สำเร็จ")
        }
    }

    /// เปิดหรืออัปเดตเคส SOS — idempotent ด้วย clientId
    ///
    /// ทุก error ออกทาง AppError.retryable หรือ .offline เท่านั้น ไม่มีทางออกอื่น
    /// ผู้เรียก (SOSStore) จึงไม่มีเส้นทางไหนเลยที่จะลบเคสทิ้ง
    func raiseSOS(token: String, draft: SOSDraft) async throws -> SOSCase {
        // โหมดเดโม่ห้ามแตะเน็ต — token ปลอมจะได้ 401 แล้วเตะผู้ใช้ออกทั้งเซสชัน (ดู DemoSOS)
        if DemoMode.active { return await MainActor.run { DemoSOS.raise(draft) } }
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
        // **ห้ามลบบรรทัดนี้** — body ที่ประกอบไว้ข้างบนต้องถูกแนบจริง ไม่งั้น request ออกไปแบบตัวเปล่า
        // เซิร์ฟเวอร์ decode ได้ io.EOF ตอบ 400 ทุกครั้ง แล้วเคสไม่มีวันถูกสร้างเลยสักแถว: ไม่มีในฟีด
        // เจ้าหน้าที่ ไม่มี push ไม่มีแจ้งเตือนกลุ่ม ส่วนแอปค้างที่ .queued แล้ว retry ยิง 400 รัวไป
        // เรื่อยๆ (เคยหายไปจริงมาแล้วรอบหนึ่ง — ถูกเขียนทับด้วย timeoutInterval บรรทัดล่างนี้เอง)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        // ตั้งเพดานเวลาเอง ไม่ปล่อยให้ใช้ค่าเริ่มต้น 60 วิของ URLSession (แก้จากรีวิวรอบสุดท้าย) —
        // นี่คือ request ที่ทั้งเคสรออยู่ ในจุดอับสัญญาณมันค้างได้เต็มเพดานโดยไม่มีใครรู้ 60 วิยาว
        // กว่าหน้าต่างที่ปุ่ม "โทรหาทีมกลาง" จะโผล่ (20 วิ) เสียอีก · 20 วิผูกกับหน้าต่างนั้นโดยตั้งใจ:
        // ถ้าเส้นนี้ยังไม่ได้คำตอบภายในเวลาที่เราเริ่มบอกให้คนโทรแล้ว มันหมดประโยชน์ในรอบนี้ ปล่อยให้
        // retry loop (2/5/10/20/30/60 วิ — ตอนนี้เริ่มขนานไปตั้งแต่ก่อน await ครั้งแรก) ยิงรอบใหม่แทน
        req.timeoutInterval = 20

        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.offline }

        guard let http = resp as? HTTPURLResponse else { throw AppError.retryable("การตอบกลับผิดพลาด") }
        guard Self.sosIsSuccess(status: http.statusCode) else {
            let b = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw AppError.retryable(b?.error ?? "ส่งไม่สำเร็จ กำลังลองใหม่")
        }
        return try Self.decodeSOS(SOSCase.self, from: data)
    }

    enum SOSCancelOutcome: Equatable { case canceled, alreadyAcked, tooLate }

    func cancelSOS(token: String, id: Int64) async throws -> SOSCancelOutcome {
        // โหมดเดโม่ห้ามแตะเน็ต — token ปลอมจะได้ 401 แล้วเตะผู้ใช้ออกทั้งเซสชัน (ดู DemoSOS)
        if DemoMode.active { return await MainActor.run { DemoSOS.cancel() } }
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
        // โหมดเดโม่ห้ามแตะเน็ต — token ปลอมจะได้ 401 แล้วเตะผู้ใช้ออกทั้งเซสชัน (ดู DemoSOS)
        if DemoMode.active { return await MainActor.run { DemoSOS.active() } }
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
        // เจอจากรีวิว: เคยเทียบ String(data:) == "null" ตรงๆ ซึ่งพลาดกรณีจริงที่สุด —
        // json.NewEncoder(w).Encode(nil) ฝั่ง Go (middleware.WriteJSON) ต่อ "\n" ท้ายเสมอ
        // ตอนไม่มีเคสเปิดอยู่ (คือกรณีส่วนใหญ่ของทุก poll) body จริงคือ "null\n" (5 ไบต์)
        // ไม่ใช่ "null" (4 ไบต์) เทียบ string ตรงๆ จึงพลาดทุกครั้ง ไม่ใช่บางครั้ง แล้วร่วงไป
        // decode ต่อจน throw DecodingError ดิบ · แก้โดย decode เข้า Optional โดยตรง ซึ่งเรียก
        // decodeNil() ก่อนและไม่แคร์ byte ท้ายๆ อยู่แล้วโดยธรรมชาติ
        if data.isEmpty { return nil }
        return try Self.decodeSOS(SOSCase?.self, from: data)
    }

    /// เคสหนึ่งอัน สำหรับเพื่อนในกลุ่ม · 404 = ไม่ใช่กลุ่มเรา
    func sosCase(token: String, id: Int64) async throws -> SOSCase {
        // โหมดเดโม่ห้ามแตะเน็ต — token ปลอมจะได้ 401 แล้วเตะผู้ใช้ออกทั้งเซสชัน (ดู DemoSOS)
        if DemoMode.active {
            guard let c = await MainActor.run(body: { DemoSOS.active() }), c.id == id else {
                throw AppError.retryable(Loc.t("error_network_short"))
            }
            return c
        }
        return try await getSOSDecoded("/me/sos/\(id)", token: token, SOSCase.self)
    }

    /// อักขระที่ปลอดภัยจริงในค่าของ query parameter หนึ่งตัว
    ///
    /// **ไม่ใช่ `.urlQueryAllowed`** — ชุดนั้นคืออักขระที่ถูกกฎหมายใน query "ทั้งก้อน" จึงปล่อย
    /// `&`, `=`, `+`, `;` ผ่านออกไปดิบๆ ทั้งที่สามตัวแรกเป็นตัวคั่น/ตัวเข้ารหัสของ query เอง
    /// ตัวที่กัดจริงคือ `+`: ฝั่งรับ (net/url ของ Go และเกือบทุก framework) ถอดกลับเป็นช่องว่างตาม
    /// กติกา form-urlencoded ค่าที่ส่งไปกับที่อ่านได้จึงไม่ใช่ค่าเดียวกัน
    ///
    /// เซิร์ฟเวอร์เลิกใส่ `+` ลงใน cursor แล้ว (updated_at เป็น RFC3339 UTC — ดูคอมเมนต์ที่
    /// sosUpdatedAtExpr ฝั่ง Go) จุดนี้จึงเป็นชั้นที่สอง ไม่ใช่ทางแก้หลัก: ค่าที่ยังไม่รู้ที่มา
    /// ไม่ควรถูกส่งออกไปโดยไว้ใจว่าไม่มีอักขระพิเศษ
    private static let sosQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    func staffSOSFeed(token: String, since: String?, wait: Int) async throws -> [SOSStaffCase] {
        // โหมดเดโม่ห้ามแตะเน็ต — token ปลอมจะได้ 401 แล้วเตะผู้ใช้ออกทั้งเซสชัน (ดู DemoSOS)
        // เจ้าหน้าที่ไม่มีในโหมดเดโม่ (DemoMode เป็น participant เสมอ) — ฟีดว่างคือคำตอบที่ถูก
        if DemoMode.active { return [] }
        var path = "/staff/sos?wait=\(wait)"
        if let since,
           let esc = since.addingPercentEncoding(withAllowedCharacters: Self.sosQueryValueAllowed) {
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
        return try Self.decodeSOS([SOSStaffCase].self, from: data)
    }

    @discardableResult
    func ackSOS(token: String, id: Int64) async throws -> Bool {
        // โหมดเดโม่ห้ามแตะเน็ต — token ปลอมจะได้ 401 แล้วเตะผู้ใช้ออกทั้งเซสชัน (ดู DemoSOS)
        if DemoMode.active { return true }
        return try await postSOSAction("/staff/sos/\(id)/ack", token: token, body: nil)
    }

    @discardableResult
    func resolveSOS(token: String, id: Int64, reason: String) async throws -> Bool {
        // โหมดเดโม่ห้ามแตะเน็ต — token ปลอมจะได้ 401 แล้วเตะผู้ใช้ออกทั้งเซสชัน (ดู DemoSOS)
        if DemoMode.active { return true }
        return try await postSOSAction("/staff/sos/\(id)/resolve", token: token, body: ["reason": reason])
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
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
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
        return try Self.decodeSOS(T.self, from: data)
    }
}
