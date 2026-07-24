import Foundation

extension Notification.Name {
    /// โพสต์เมื่อเจอ 401 (token หมดอายุ/เปลี่ยน secret) → Session logout อัตโนมัติ
    static let wbwUnauthorized = Notification.Name("wbwUnauthorized")
}

struct APIClient {
    static let shared = APIClient()

    /// เรียก network + ตรวจ 401 → โพสต์ให้ logout (แทนจอว่างเงียบๆ)
    static func send(_ req: URLRequest) async throws -> (Data, URLResponse) {
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
            NotificationCenter.default.post(name: .wbwUnauthorized, object: nil)
        }
        return (data, resp)
    }

    func login(studentId: String, password: String) async throws -> LoginResponse {
        guard let url = URL(string: "\(Config.apiBase)/auth/login") else {
            throw AppError.message("URL ไม่ถูกต้อง")
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
            throw AppError.message("เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ — ตรวจสัญญาณอินเทอร์เน็ต")
        }

        guard let http = resp as? HTTPURLResponse else {
            throw AppError.message("การตอบกลับผิดพลาด")
        }
        if http.statusCode != 200 {
            let body = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw AppError.message(body?.error ?? "เข้าสู่ระบบไม่สำเร็จ")
        }
        return try JSONDecoder().decode(LoginResponse.self, from: data)
    }

    /// โปรไฟล์ผู้ใช้ปัจจุบัน (ต้องมี token)
    func me(token: String) async throws -> Me {
        guard let url = URL(string: "\(Config.apiBase)/auth/me") else {
            throw AppError.message("URL ไม่ถูกต้อง")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await Self.send(req)
        } catch {
            throw AppError.message("เชื่อมต่อเซิร์ฟเวอร์ไม่ได้")
        }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.message("โหลดโปรไฟล์ไม่สำเร็จ")
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(Me.self, from: data)
    }

    // ===== staff =====

    /// ฐานที่เจ้าหน้าที่คนนี้ประจำ
    func staffCheckpoints(token: String) async throws -> [StaffCheckpoint] {
        guard let url = URL(string: "\(Config.apiBase)/staff/checkpoints") else {
            throw AppError.message("URL ไม่ถูกต้อง")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await Self.send(req)
        } catch {
            throw AppError.message("เชื่อมต่อเซิร์ฟเวอร์ไม่ได้")
        }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.message("โหลดฐานไม่สำเร็จ")
        }
        return try JSONDecoder().decode([StaffCheckpoint].self, from: data)
    }

    /// เช็คอินผู้เข้าร่วมที่ฐาน (จาก qr หรือ bib)
    func staffCheckin(token: String, checkpointId: Int, qrToken: String?, bib: Int?) async throws -> CheckinResult {
        guard let url = URL(string: "\(Config.apiBase)/staff/checkin") else {
            throw AppError.message("URL ไม่ถูกต้อง")
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
            throw AppError.message("เชื่อมต่อเซิร์ฟเวอร์ไม่ได้")
        }
        guard let http = resp as? HTTPURLResponse else { throw AppError.message("ผิดพลาด") }
        if http.statusCode != 200 {
            let b = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw AppError.message(b?.error ?? "เช็คอินไม่สำเร็จ")
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(CheckinResult.self, from: data)
    }

    /// อัปเดตรูปโปรไฟล์ตัวเอง (base64 data URL)
    func updatePhoto(token: String, photoUrl: String) async throws {
        guard let url = URL(string: "\(Config.apiBase)/auth/me") else { throw AppError.message("URL ไม่ถูกต้อง") }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["photo_url": photoUrl])
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.message("เชื่อมต่อเซิร์ฟเวอร์ไม่ได้") }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let b = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw AppError.message(b?.error ?? "อัปเดตรูปไม่สำเร็จ")
        }
    }

    // ===== ประกาศ / แจ้งเตือน =====

    /// รายการประกาศของฉัน (ตาม audience) + สถานะอ่าน
    func notifications(token: String) async throws -> [NotificationItem] {
        guard let url = URL(string: "\(Config.apiBase)/notifications") else {
            throw AppError.message("URL ไม่ถูกต้อง")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await Self.send(req)
        } catch {
            throw AppError.message("เชื่อมต่อเซิร์ฟเวอร์ไม่ได้")
        }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.message("โหลดประกาศไม่สำเร็จ")
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode([NotificationItem].self, from: data)
    }

    /// ทำเครื่องหมายว่าอ่านแล้ว
    func markRead(token: String, id: String) async throws {
        guard let url = URL(string: "\(Config.apiBase)/notifications/\(id)/read") else {
            throw AppError.message("URL ไม่ถูกต้อง")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await Self.send(req)
    }

    // ===== device token (push) =====

    /// ลงทะเบียน FCM token กับ backend
    func registerDevice(token: String, fcmToken: String, platform: String) async throws {
        try await deviceCall(path: "/devices/register", token: token, body: ["token": fcmToken, "platform": platform])
    }

    /// ถอน FCM token (ตอน logout)
    func unregisterDevice(token: String, fcmToken: String) async throws {
        try await deviceCall(path: "/devices/unregister", token: token, body: ["token": fcmToken])
    }

    private func deviceCall(path: String, token: String, body: [String: Any]) async throws {
        guard let url = URL(string: "\(Config.apiBase)\(path)") else { throw AppError.message("URL ไม่ถูกต้อง") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try? await Self.send(req)
    }

    // ===== กลุ่ม + แชท =====

    func groups(token: String) async throws -> [GroupSummary] {
        try await getDecoded("/groups", token: token, [GroupSummary].self, error: "โหลดกลุ่มไม่สำเร็จ")
    }

    func membersIndex(token: String) async throws -> [GroupMemberIndex] {
        try await getDecoded("/groups/members/index", token: token, [GroupMemberIndex].self, error: "โหลดสมาชิกไม่สำเร็จ")
    }

    func groupMembers(token: String, groupId: Int) async throws -> GroupMembersResponse {
        try await getDecoded("/groups/\(groupId)/members", token: token, GroupMembersResponse.self, error: "โหลดสมาชิกไม่สำเร็จ")
    }

    /// เข้ากลุ่ม — 409 = เต็ม → โยน AppError.groupFull
    func joinGroup(token: String, groupId: Int) async throws {
        guard let url = URL(string: "\(Config.apiBase)/groups/\(groupId)/join") else { throw AppError.message("URL ไม่ถูกต้อง") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.message("เชื่อมต่อเซิร์ฟเวอร์ไม่ได้") }
        guard let http = resp as? HTTPURLResponse else { throw AppError.message("ผิดพลาด") }
        if http.statusCode == 200 { return }
        let b = try? JSONDecoder().decode(APIErrorBody.self, from: data)
        let msg = b?.error ?? "เข้ากลุ่มไม่สำเร็จ"
        throw http.statusCode == 409 ? AppError.groupFull(msg) : AppError.message(msg)
    }

    func leaveGroup(token: String) async throws {
        try await deviceCall(path: "/groups/leave", token: token, body: [:])
    }

    /// ดึงข้อความ (poll) — after = id ล่าสุดที่มี
    func messages(token: String, groupId: Int, after: String?, limit: Int = 50) async throws -> [MessageDTO] {
        var path = "/groups/\(groupId)/messages?limit=\(limit)"
        if let after, !after.isEmpty { path += "&after=\(after)" }
        return try await getDecoded(path, token: token, [MessageDTO].self, error: "โหลดข้อความไม่สำเร็จ")
    }

    /// ส่งข้อความ — idempotent ด้วย clientId
    func sendMessage(token: String, groupId: Int, clientId: String, body: String, deviceTime: String) async throws -> MessageDTO {
        guard let url = URL(string: "\(Config.apiBase)/groups/\(groupId)/messages") else { throw AppError.message("URL ไม่ถูกต้อง") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": clientId, "body": body, "device_time": deviceTime])
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.offline }   // เน็ตล่ม → offline (flush จะหยุด retry รอบหน้า)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 201 || http.statusCode == 200 else {
            let b = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw AppError.message(b?.error ?? "ส่งข้อความไม่สำเร็จ")  // 4xx = mark failed
        }
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(MessageDTO.self, from: data)
    }

    // helper: GET + decode (snake_case)
    private func getDecoded<T: Decodable>(_ path: String, token: String, _ type: T.Type, error: String) async throws -> T {
        guard let url = URL(string: "\(Config.apiBase)\(path)") else { throw AppError.message("URL ไม่ถูกต้อง") }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.message("เชื่อมต่อเซิร์ฟเวอร์ไม่ได้") }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { throw AppError.message(error) }
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(T.self, from: data)
    }
}
