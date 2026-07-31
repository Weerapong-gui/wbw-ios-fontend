import Foundation

extension APIClient {
    /// long-poll ข้อความ — wait = วินาทีที่ยอมให้ server ค้าง request ไว้ (0 = ตอบทันที)
    /// คืน messages ว่าง = หมดเวลา ไม่ใช่ error
    func chatSync(token: String, groupId: Int, after: Int64, wait: Int) async throws -> ChatSyncResponse {
        var path = "\(Config.apiBase)/groups/\(groupId)/chat/sync?wait=\(wait)"
        if after > 0 { path += "&after=\(after)" }
        guard let url = URL(string: path) else { throw AppError.message("URL ไม่ถูกต้อง") }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = TimeInterval(wait) + 10   // ต้องมากกว่า wait ไม่งั้น client ตัดเอง
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Self.send(req) }
        catch { throw AppError.offline }
        guard let http = resp as? HTTPURLResponse else { throw AppError.message("ผิดพลาด") }
        if http.statusCode == 403 { throw AppError.notInGroup }
        guard http.statusCode == 200 else { throw AppError.message("โหลดข้อความไม่สำเร็จ") }
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(ChatSyncResponse.self, from: data)
    }

    /// อ่านถึง id ไหน — ใช้เป็น heartbeat "กำลังดูจอแชทอยู่" ด้วย จึงยิงซ้ำค่าเดิมได้
    func chatRead(token: String, groupId: Int, lastReadId: Int64) async throws {
        guard let url = URL(string: "\(Config.apiBase)/groups/\(groupId)/chat/read") else {
            throw AppError.message("URL ไม่ถูกต้อง")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["last_read_id": Int(lastReadId)])
        _ = try? await Self.send(req)
    }
}
