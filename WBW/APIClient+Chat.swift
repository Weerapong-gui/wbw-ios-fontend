import Foundation

extension APIClient {
    /// long-poll ข้อความ — wait = วินาทีที่ยอมให้ server ค้าง request ไว้ (0 = ตอบทันที)
    /// คืน messages ว่าง = หมดเวลา ไม่ใช่ error
    func chatSync(token: String, groupId: Int, after: Int64, wait: Int) async throws -> ChatSyncResponse {
        if DemoMode.active {
            // ชุดแรกครั้งเดียว จากนั้นจอดรอเงียบ ๆ — long-poll ตัวจริงค้างที่ server ฝั่งนี้ไม่มี
            // server ให้ค้าง ถ้าคืนลิสต์ว่างทันทีทุกครั้ง ลูปใน ChatSession จะหมุนเต็มสปีดไม่หยุด
            if after > 0 {
                try? await Task.sleep(nanoseconds: UInt64(max(wait, 1)) * 1_000_000_000)
                return ChatSyncResponse(sinceId: 0, memberCount: DemoData.chatSync.memberCount,
                                        messages: [], cursors: DemoData.chatSync.cursors)
            }
            return DemoData.chatSync
        }
        var path = "\(Config.apiBase)/groups/\(groupId)/chat/sync?wait=\(wait)"
        if after > 0 { path += "&after=\(after)" }
        guard let url = URL(string: path) else { throw AppError.message(Loc.t("error_bad_url")) }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = TimeInterval(wait) + 10   // ต้องมากกว่า wait ไม่งั้น client ตัดเอง
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.offline }
        guard let http = resp as? HTTPURLResponse else { throw AppError.message(Loc.t("error_unknown")) }
        if http.statusCode == 403 { throw AppError.notInGroup }
        guard http.statusCode == 200 else { throw AppError.message(Loc.t("error_load_messages")) }
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(ChatSyncResponse.self, from: data)
    }

    /// อ่านถึง id ไหน — ใช้เป็น heartbeat "กำลังดูจอแชทอยู่" ด้วย จึงยิงซ้ำค่าเดิมได้
    /// ไม่ throw — ผู้เรียกทำอะไรกับความล้มเหลวไม่ได้อยู่แล้ว (ตัวถัดไปจะยิงซ้ำค่าเดิม/ค่าใหม่กว่าเอง)
    /// พังแล้ว log ไว้เฉยๆ ให้ตามรอยได้ ไม่ใช่หายเงียบ
    func chatRead(token: String, groupId: Int, lastReadId: Int64) async {
        if DemoMode.active { return }
        guard let url = URL(string: "\(Config.apiBase)/groups/\(groupId)/chat/read") else {
            NSLog("[chat] chatRead: URL ไม่ถูกต้อง (group \(groupId))")
            return
        }
        guard let body = try? JSONSerialization.data(withJSONObject: ["last_read_id": Int(lastReadId)]) else {
            NSLog("[chat] chatRead: เตรียม body ไม่สำเร็จ (group \(groupId))")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        do {
            let (_, resp) = try await Self.send(req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            if status != 200 {
                NSLog("[chat] chatRead: server ตอบ \(status) (group \(groupId))")
            }
        } catch {
            NSLog("[chat] chatRead: ส่งไม่สำเร็จ (group \(groupId)): \(error)")
        }
    }
}
