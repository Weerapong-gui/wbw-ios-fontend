import Foundation

extension Notification.Name {
    /// โพสต์เมื่อเจอ 401 (token หมดอายุ/เปลี่ยน secret) → Session logout อัตโนมัติ
    static let wbwUnauthorized = Notification.Name("wbwUnauthorized")
}

struct APIClient {
    static let shared = APIClient()

    /// เพดานเวลารอของคำขอที่ไม่ได้ตั้งเอง
    ///
    /// ค่าปริยายของ `URLSession` คือ 60 วินาที ซึ่งนานเกินกว่าที่คนจะรอโดยไม่คิดว่าแอปค้าง —
    /// กด "เข้าสู่ระบบ" ตอนเน็ตหลุดแล้วเห็นตัวหมุนนิ่งหนึ่งนาทีก่อนขึ้น error อ่านเหมือนแอปพัง
    /// ไม่ใช่เหมือนแอปกำลังรอ · 15 วินาทีพอสำหรับเน็ตมือถือบนดอยที่ช้าแต่ยังเดินอยู่
    static let defaultTimeout: TimeInterval = 15

    /// เวลารอที่จะใช้จริงกับคำขอนี้
    ///
    /// long-poll ของแชทกับ SOS ตั้ง `timeoutInterval` ของตัวเองไว้ยาวกว่านี้โดยตั้งใจ (ต้องมากกว่า
    /// `wait` ที่ส่งไป ไม่งั้น client ตัดเองก่อนเซิร์ฟเวอร์ตอบ) ค่าพวกนั้นต้องรอด — เพดานกลาง
    /// ใช้เฉพาะกับคำขอที่ **ไม่ได้เลือกอะไรเลย** ซึ่ง `URLRequest` แทนด้วยค่า 60 พอดี
    static func timeout(for req: URLRequest) -> TimeInterval {
        req.timeoutInterval == 60 ? defaultTimeout : req.timeoutInterval
    }

    /// เรียก network + ตรวจ 401 → โพสต์ให้ logout (แทนจอว่างเงียบๆ)
    static func send(_ req: URLRequest) async throws -> (Data, URLResponse) {
        var req = req
        req.timeoutInterval = timeout(for: req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
            NotificationCenter.default.post(name: .wbwUnauthorized, object: nil)
        }
        return (data, resp)
    }

    func login(studentId: String, password: String) async throws -> LoginResponse {
        // โหมดเดโม่เข้าทาง Session.startDemo() ไม่ได้ผ่านฟอร์มนี้ — กันไว้เผื่อมีใครเรียกซ้ำ
        if DemoMode.active { return LoginResponse(user: DemoMode.user, token: DemoMode.token) }
        guard let url = URL(string: "\(Config.apiBase)/auth/login") else {
            throw AppError.message(Loc.t("error_bad_url"))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: ["username": studentId, "password": password]
        )

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await Self.send(req)
        } catch {
            throw AppError.message(Loc.t("error_network"))
        }

        guard let http = resp as? HTTPURLResponse else {
            throw AppError.message(Loc.t("error_bad_response"))
        }
        if http.statusCode != 200 {
            let body = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw AppError.message(body?.error ?? Loc.t("error_login_failed"))
        }
        return try JSONDecoder().decode(LoginResponse.self, from: data)
    }

    /// โปรไฟล์ผู้ใช้ปัจจุบัน (ต้องมี token)
    func me(token: String) async throws -> Me {
        if DemoMode.active { return DemoData.me }
        guard let url = URL(string: "\(Config.apiBase)\(Config.mePath)") else {
            throw AppError.message(Loc.t("error_bad_url"))
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await Self.send(req)
        } catch {
            throw AppError.message(Loc.t("error_network_short"))
        }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.message(Loc.t("error_load_profile"))
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(Me.self, from: data)
    }

    /// ฐานทั้งงาน — ชื่อ/ชื่อกิจกรรมสองภาษา ทั้งฐานที่เช็คอินแล้วและยังไม่ได้ไป
    ///
    /// **ห้ามเลียนแบบ `staffCheckpoints` ข้างล่าง** ตัวนั้นเขียน URLSession เองและ**ไม่ได้ตั้ง
    /// `convertFromSnakeCase`** รอดมาได้เพราะคีย์เป็นคำเดียวหมด (`id`/`name`/`sequence`)
    /// ตัวนี้มี `activity_name_en` จึงต้องผ่าน `getDecoded` ที่ตั้งให้แล้ว
    func checkpoints(token: String) async throws -> [Checkpoint] {
        if DemoMode.active { return DemoData.checkpoints }
        return try await getDecoded("/checkpoints", token: token, [Checkpoint].self,
                                    error: Loc.t("error_load_checkpoints"))
    }

    /// ความคืบหน้าเช็คอินของตัวเอง — คุมขั้นต้นไม้กับเวลาของวันที่หน้า Home
    func progress(token: String) async throws -> CheckinProgress {
        if DemoMode.active { return DemoData.progress }
        return try await getDecoded("/me/progress", token: token, CheckinProgress.self,
                                    error: Loc.t("error_load_progress"))
    }

    // ===== staff =====

    /// ฐานที่เจ้าหน้าที่คนนี้ประจำ
    func staffCheckpoints(token: String) async throws -> [StaffCheckpoint] {
        if DemoMode.active { return DemoData.staffCheckpoints }
        guard let url = URL(string: "\(Config.apiBase)/staff/checkpoints") else {
            throw AppError.message(Loc.t("error_bad_url"))
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await Self.send(req)
        } catch {
            throw AppError.message(Loc.t("error_network_short"))
        }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.message(Loc.t("error_load_bases"))
        }
        return try JSONDecoder().decode([StaffCheckpoint].self, from: data)
    }

    /// เช็คอินผู้เข้าร่วมที่ฐาน (จาก qr หรือ bib)
    func staffCheckin(token: String, checkpointId: Int, qrToken: String?, bib: Int?) async throws -> CheckinResult {
        // จอเจ้าหน้าที่ไปไม่ถึงในโหมดเดโม่ (role เป็น participant) — ถ้าถึงแปลว่ามีอะไรผิด
        // ต้องไม่ปล่อยให้ยิงเช็คอินจริงด้วย token ปลอม
        if DemoMode.active { throw AppError.message(Loc.t("error_demo_no_checkin")) }
        guard let url = URL(string: "\(Config.apiBase)/staff/checkin") else {
            throw AppError.message(Loc.t("error_bad_url"))
        }
        var body: [String: Any] = ["checkpoint_id": checkpointId]
        if let qrToken { body["qr_token"] = qrToken }
        if let bib { body["bib"] = bib }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await Self.send(req)
        } catch {
            throw AppError.message(Loc.t("error_network_short"))
        }
        guard let http = resp as? HTTPURLResponse else { throw AppError.message(Loc.t("error_unknown")) }
        if http.statusCode != 200 {
            let b = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw AppError.message(b?.error ?? Loc.t("error_checkin_failed"))
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(CheckinResult.self, from: data)
    }

    /// อัปเดตรูปโปรไฟล์ตัวเอง (base64 data URL)
    func updatePhoto(token: String, photoUrl: String) async throws {
        if DemoMode.active { return }
        guard let url = URL(string: "\(Config.apiBase)\(Config.mePath)") else { throw AppError.message(Loc.t("error_bad_url")) }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["photo_url": photoUrl])
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.message(Loc.t("error_network_short")) }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let b = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw AppError.message(b?.error ?? Loc.t("error_photo_failed"))
        }
    }

    // ===== ประกาศ / แจ้งเตือน =====

    /// รายการประกาศของฉัน (ตาม audience) + สถานะอ่าน
    func notifications(token: String) async throws -> [NotificationItem] {
        if DemoMode.active { return DemoData.notifications }
        guard let url = URL(string: "\(Config.apiBase)/notifications") else {
            throw AppError.message(Loc.t("error_bad_url"))
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await Self.send(req)
        } catch {
            throw AppError.message(Loc.t("error_network_short"))
        }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.message(Loc.t("error_load_announcements"))
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode([NotificationItem].self, from: data)
    }

    /// ทำเครื่องหมายว่าอ่านแล้ว
    func markRead(token: String, id: String) async throws {
        if DemoMode.active { return }
        guard let url = URL(string: "\(Config.apiBase)/notifications/\(id)/read") else {
            throw AppError.message(Loc.t("error_bad_url"))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await Self.send(req)
    }

    // ===== device token (push) =====

    /// ลงทะเบียน FCM token กับ backend
    func registerDevice(token: String, fcmToken: String, platform: String) async throws {
        if DemoMode.active { return }
        try await deviceCall(path: "/devices/register", token: token, body: ["token": fcmToken, "platform": platform])
    }

    /// ถอน FCM token (ตอน logout)
    func unregisterDevice(token: String, fcmToken: String) async throws {
        if DemoMode.active { return }
        try await deviceCall(path: "/devices/unregister", token: token, body: ["token": fcmToken])
    }

    private func deviceCall(path: String, token: String, body: [String: Any]) async throws {
        guard let url = URL(string: "\(Config.apiBase)\(path)") else { throw AppError.message(Loc.t("error_bad_url")) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try? await Self.send(req)
    }

    // ===== กลุ่ม + แชท =====

    func groups(token: String) async throws -> [GroupSummary] {
        if DemoMode.active { return DemoData.groups }
        return try await getDecoded("/groups", token: token, [GroupSummary].self, error: Loc.t("error_load_groups"))
    }

    func membersIndex(token: String) async throws -> [GroupMemberIndex] {
        if DemoMode.active { return DemoData.membersIndex }
        return try await getDecoded("/groups/members/index", token: token, [GroupMemberIndex].self, error: Loc.t("error_load_members"))
    }

    func groupMembers(token: String, groupId: Int) async throws -> GroupMembersResponse {
        if DemoMode.active { return DemoData.groupMembers }
        return try await getDecoded("/groups/\(groupId)/members", token: token, GroupMembersResponse.self, error: Loc.t("error_load_members"))
    }

    /// เข้ากลุ่ม — 409 = เต็ม → โยน AppError.groupFull
    func joinGroup(token: String, groupId: Int) async throws {
        if DemoMode.active { return }
        guard let url = URL(string: "\(Config.apiBase)/groups/\(groupId)/join") else { throw AppError.message(Loc.t("error_bad_url")) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.message(Loc.t("error_network_short")) }
        guard let http = resp as? HTTPURLResponse else { throw AppError.message(Loc.t("error_unknown")) }
        if http.statusCode == 200 { return }
        let b = try? JSONDecoder().decode(APIErrorBody.self, from: data)
        let msg = b?.error ?? Loc.t("error_join_failed")
        throw http.statusCode == 409 ? AppError.groupFull(msg) : AppError.message(msg)
    }

    /// ออกจากกลุ่ม — ไม่ใช้ deviceCall เพราะตัวนั้น `try?` ทิ้งทุก error ทิ้ง (ตั้งใจสำหรับ device token
    /// ที่ล้มเหลวแล้วไม่มีอะไรให้ผู้ใช้ทำ) · ที่นี่ 409 "สิทธิ์ออกจากกลุ่มหมดแล้ว" คือคำตอบที่ผู้ใช้
    /// ต้องเห็น ไม่ใช่ความเงียบ
    func leaveGroup(token: String) async throws {
        if DemoMode.active { return }
        guard let url = URL(string: "\(Config.apiBase)/groups/leave") else {
            throw AppError.message(Loc.t("error_bad_url"))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.offline }
        guard let http = resp as? HTTPURLResponse else { throw AppError.message(Loc.t("error_unknown")) }
        if http.statusCode == 200 { return }
        let b = try? JSONDecoder().decode(APIErrorBody.self, from: data)
        throw AppError.message(b?.error ?? Loc.t("error_leave_failed"))
    }

    /// status ของ POST ข้อความแชทที่เป็น **ปลายทางจริง** — ยิงซ้ำด้วย payload เดิมไม่มีวันผ่าน
    ///
    /// ทุกตัวคือ error ที่เกิดจากตัว request เอง ซึ่งไม่มีอะไรเปลี่ยนตอน retry: body เดิม
    /// (400 รูปร่างผิด, 413 ยาวเกิน, 422 ผิดความหมาย), header เดิม (401 token หมดอายุ,
    /// 415 content-type), method/URL เดิม (405, 414), สิทธิ์ (403 ไม่ได้อยู่ในกลุ่มแล้ว)
    /// หรือหายถาวร (410)
    ///
    /// **ที่ไม่อยู่ในรายชื่อนี้ retry ได้ทั้งหมด** — 408/425 (Cloudflare: ส่ง body ไม่จบ /
    /// TLS early data), 429 (ล้น), 5xx (origin หรือ gateway ล้ม — 502/503/524 หน้า
    /// api.studentunion.social), 404/407 (ทางผ่านเพี้ยนชั่วคราว) และ status อะไรก็ตามที่
    /// ยังไม่มีใครนึกถึง · ค่าเริ่มต้นต้องคือ "เก็บข้อความของผู้ใช้ไว้ก่อน" ไม่ใช่ยอมแพ้
    ///
    /// แยกเป็น static ไม่ใช่ฝังใน switch — ให้เทสยิงทีละ status ได้ตรง ๆ
    static func isTerminalSendStatus(_ status: Int) -> Bool {
        [400, 401, 403, 405, 410, 413, 414, 415, 422].contains(status)
    }

    /// ส่งข้อความ — idempotent ด้วย clientId
    func sendMessage(token: String, groupId: Int, clientId: String, body: String, deviceTime: String) async throws -> MessageDTO {
        if DemoMode.active {
            return DemoData.echo(clientId: clientId, body: body, deviceTime: deviceTime, groupId: groupId)
        }
        guard let url = URL(string: "\(Config.apiBase)/groups/\(groupId)/messages") else { throw AppError.message(Loc.t("error_bad_url")) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": clientId, "body": body, "device_time": deviceTime])
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.offline }   // เน็ตล่ม → offline (flush จะหยุด retry รอบหน้า)
        guard let http = resp as? HTTPURLResponse else { throw AppError.message(Loc.t("error_unknown")) }
        guard http.statusCode == 201 || http.statusCode == 200 else {
            let b = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            let msg = b?.error ?? Loc.t("error_send_failed")
            // จำแนกกลับหัวเหมือน submitFeedback: terminal คือรายชื่อที่ระบุไว้ชัด ที่เหลือ retry ได้
            // — ราคาของการจำแนกผิดสองทางไม่เท่ากันเหมือนกัน เผลอ retry = POST เปล่ารอบละครั้งต่อ
            // sync loop หนึ่งรอบ (~25 วิ) ส่วนเผลอ terminal = ฟอง "ส่งไม่สำเร็จ" ค้างจนกว่าผู้ใช้
            // จะสังเกตแล้วกดเอง ซึ่งบนดอยคือข้อความที่กลุ่มไม่ได้อ่านทั้งวัน
            throw Self.isTerminalSendStatus(http.statusCode)
                ? AppError.message(msg)
                : AppError.retryable(msg)
        }
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(MessageDTO.self, from: data)
    }

    /// ผลของการส่งความเห็น — แยก 409/403/error จริงออกจากกัน เพราะแต่ละกลุ่ม retry แล้วผลต่างกัน:
    /// 409/403 คือสถานะปลายทางจากเซิร์ฟเวอร์ (ตอบไปแล้ว/ไม่ได้เช็คอิน) ไม่ใช่ความผิดพลาด ส่วน .failed
    /// คือ error อื่นที่ไม่มีทางสำเร็จซ้ำด้วย draft เดิม (rating ผิด 400, token หมดอายุ 401, เซิร์ฟเวอร์
    /// พัง 500 ฯลฯ) — Equatable เพื่อให้ฝั่งเทส/ฟอร์มเทียบค่าตรงๆ ด้วย == ได้
    enum FeedbackSubmitOutcome: Equatable {
        case saved
        case alreadyAnswered
        case notCheckedIn
        case failed
    }

    /// รูปร่างของ body ที่ **origin ของเราเอง** ตอบกลับมา — ใช้แยกจากของที่ Cloudflare หรืออะไรก็ตาม
    /// ที่ขวางหน้า origin ตอบแทน (ดู submitFeedback)
    ///
    /// ทำไมไม่ใช้ APIErrorBody: `error` ของมันเป็น optional จึง decode ผ่านกับ JSON object **ทุกก้อน**
    /// บนโลก รวมถึง `{}` และแถวความเห็นเดิมของ 409 — ใช้เป็นตัวแยกไม่ได้เลย ตัวนี้จึงต้องดูถึงระดับ
    /// "มีคีย์ที่ backend ส่งจริงอยู่ในนั้นไหม"
    private struct OriginBody: Decodable {
        /// middleware.WriteError ฝั่ง Go ตอบ `{"error":"..."}` เสมอ และข้อความไม่เคยว่าง
        let error: String?
        /// 409 ฝั่ง Go ตอบเป็น **แถวความเห็นเดิม** ผ่าน WriteJSON ไม่ใช่ envelope — คีย์นี้คือตัวชี้ว่า
        /// เป็นแถวจริง · JSONDecoder ตรงนี้ไม่ได้เปิด convertFromSnakeCase จึงต้องระบุคีย์เอง
        let checkpointId: Int?

        enum CodingKeys: String, CodingKey {
            case error
            case checkpointId = "checkpoint_id"
        }
    }

    /// body เป็น error envelope ของ backend เราเองไหม (403/401/400 ทุกตัวออกทาง WriteError)
    private static func isOriginErrorEnvelope(_ data: Data) -> Bool {
        guard let b = try? JSONDecoder().decode(OriginBody.self, from: data),
              let e = b.error, !e.isEmpty
        else { return false }
        return true
    }

    /// body เป็น "แถวความเห็นเดิม" ที่ 409 ของ backend เราส่งกลับมาให้ฟอร์มแสดงไหม
    private static func isOriginFeedbackRow(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(OriginBody.self, from: data))?.checkpointId != nil
    }

    /// ส่งความเห็นต่อฐาน — idempotent ด้วย clientId
    ///
    /// **การจำแนกกลับหัวโดยตั้งใจ: terminal คือรายชื่อที่ระบุไว้ชัด ที่เหลือทั้งหมด retry ได้**
    ///
    /// เดิมเขียนกลับกัน (retryable คือ 429/5xx ที่เหลือตกลง default = terminal) ซึ่งแปลว่าทุก status
    /// ที่ไม่ได้นึกถึงตอนเขียนจะลบคำตอบของผู้ใช้ทิ้งเงียบๆ · ที่หลุดไปจริงคือ **408** (Cloudflare ตอบเมื่อ
    /// client ส่ง body ไม่จบในเวลา — เกิดเต็มๆ บนไวไฟภูเขาที่คนสองพันคนแย่งกันใช้) และ **425**
    /// (Too Early จาก TLS early data ที่ Cloudflare เปิดเป็นค่าเริ่มต้น) ทั้งคู่ retry แล้วผ่านได้สบาย
    ///
    /// ราคาของการจำแนกผิดสองทางไม่เท่ากัน: เผลอ retry = เสีย POST เปล่าอย่างมากรอบละหนึ่งครั้งต่อฐาน
    /// (คิวมีเพดาน ~8 ชิ้น เพราะ outbox.add แทนที่ของฐานเดิม และ flush วิ่งแค่ตอน mount/.active/ส่งสำเร็จ)
    /// ส่วนเผลอ terminal = คำตอบของผู้เข้าร่วมหายถาวร ไม่มี error ไม่มี toast ไม่มี badge
    ///
    /// **403/409 ต้องดู body ด้วย ไม่ใช่ดูแค่ status**
    ///
    /// 403 ของแอปแปลว่า "ไม่เคยเช็คอินฐานนี้" ซึ่งเป็นปลายทางจริง แต่ Cloudflare WAF/firewall rule ก็
    /// ตอบ 403 เหมือนกัน — พร้อม HTML ไม่ใช่ envelope ของเรา · status อย่างเดียวแบกการตัดสินใจนี้ไม่ไหว
    /// และผลที่ตามมาหนักกว่าทางอื่นทั้งหมด เพราะ .notCheckedIn ทำให้ FeedbackStore.submit เรียก
    /// outbox.remove(checkpointId:) = ล้างคิว **ทั้งฐาน** ไม่ใช่แค่ draft เดียว
    ///
    /// ทิศทางพังตรงข้ามอันตรายพอกัน (คิวค้างถาวรเพราะของที่จบแล้วถูกมองว่ายัง retry ได้) ตัวจำแนกจึง
    /// ต้องรับ **ทุกรูปที่ backend ส่งจริง**: 403 มาทาง WriteError เป็น envelope ส่วน 409 มาทาง
    /// WriteJSON เป็นแถวความเห็นเดิม (ตรึงไว้ด้วยเทสฝั่ง Go — TestSubmitFeedbackForbiddenBodyIsErrorEnvelope
    /// และ TestSubmitFeedbackConflictBodyIsFeedbackRow)
    func submitFeedback(token: String, draft: FeedbackDraft) async throws -> FeedbackSubmitOutcome {
        if DemoMode.active { return .saved }
        guard let url = URL(string: "\(Config.apiBase)/me/feedback") else {
            throw AppError.message(Loc.t("error_bad_url"))
        }
        var body: [String: Any] = [
            "client_id": draft.clientId,
            "checkpoint_id": draft.checkpointId,
            "rating": draft.rating,
            "device_time": draft.deviceTime,
        ]
        if let c = draft.comment { body["comment"] = c }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.offline }   // เน็ตล่ม → เก็บเข้า outbox รอรอบหน้า

        guard let http = resp as? HTTPURLResponse else { throw AppError.message(Loc.t("error_unknown")) }
        let b = try? JSONDecoder().decode(APIErrorBody.self, from: data)
        switch http.statusCode {
        case 200, 201:
            return .saved

        // สถานะปลายทางของ backend เราเอง — เป็นปลายทางได้ก็ต่อเมื่อ body ยืนยันว่ามาจาก origin จริง
        case 403 where Self.isOriginErrorEnvelope(data):
            return .notCheckedIn
        case 409 where Self.isOriginFeedbackRow(data) || Self.isOriginErrorEnvelope(data):
            return .alreadyAnswered

        // **รายชื่อ terminal ทั้งหมด** — ทุกตัวคือ error ที่เกิดจากตัว request เอง ซึ่งไม่มีอะไรเปลี่ยน
        // ตอน retry: body เดิม (400 rating ผิด, 413 ยาวเกิน, 422 ผิดความหมาย), header เดิม
        // (401 token หมดอายุ, 415 content-type), method/URL เดิม (405, 414) หรือหายถาวร (410)
        //
        // 401 อยู่ตรงนี้แต่แทบไม่มีผลจริง: Self.send โพสต์ .wbwUnauthorized ทุกครั้งที่เจอ 401
        // ซึ่งพา Session.logout() ที่เรียก FeedbackOutbox.clear() อยู่แล้ว
        case 400, 401, 405, 410, 413, 414, 415, 422:
            throw AppError.message(b?.error ?? Loc.t("error_feedback_failed"))

        // **ที่เหลือทั้งหมด retry ได้** — 429/5xx (origin ล้นตอนคนเข้าฐานพร้อมกัน, Cloudflare ตอบ
        // 502/503/524 แทน origin), 408/425 (ยิงไม่จบ/early data ของ Cloudflare), 404/407 (เส้นทาง
        // หรือ proxy ระหว่างทางเพี้ยนชั่วคราว), 403/409 ที่ไม่ได้ออกจาก origin (WAF block page)
        // และ status อะไรก็ตามที่ยังไม่มีใครนึกถึง — ค่าเริ่มต้นต้องคือ "เก็บคำตอบของผู้ใช้ไว้ก่อน"
        default:
            throw AppError.retryable(b?.error ?? Loc.t("error_server_busy"))
        }
    }

    // helper: GET + decode (snake_case)
    private func getDecoded<T: Decodable>(_ path: String, token: String, _ type: T.Type, error: String) async throws -> T {
        guard let url = URL(string: "\(Config.apiBase)\(path)") else { throw AppError.message(Loc.t("error_bad_url")) }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.message(Loc.t("error_network_short")) }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { throw AppError.message(error) }
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(T.self, from: data)
    }
}
