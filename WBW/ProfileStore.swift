import Foundation

/// เก็บโปรไฟล์ (me) ร่วมกันทั้งแอป — ทุกหน้าอ่านตัวเดียวกัน
/// รูปโปรไฟล์อัปเดตแบบ optimistic: โชว์ทันทีทุกหน้า, upload เบื้องหลัง
@MainActor
final class ProfileStore: ObservableObject {
    @Published var me: Me?
    @Published var photoUrl: String?   // แหล่งความจริงของ avatar

    func load(token: String) async {
        guard !token.isEmpty else { return }
        if let m = try? await APIClient.shared.me(token: token) {
            me = m
            photoUrl = m.photoUrl
        }
    }

    /// เปลี่ยนรูป — โชว์ทันที (optimistic) แล้ว upload; ล้มเหลว = คืนค่าเดิม
    /// คืน true ถ้าสำเร็จ
    func updatePhoto(dataUrl: String, token: String) async -> Bool {
        let old = photoUrl
        photoUrl = dataUrl                 // ทุกหน้าที่ผูก store เห็นรูปใหม่ทันที
        do {
            try await APIClient.shared.updatePhoto(token: token, photoUrl: dataUrl)
            return true
        } catch {
            photoUrl = old                 // upload พลาด → คืนรูปเดิม
            return false
        }
    }

    func clear() { me = nil; photoUrl = nil }
}
