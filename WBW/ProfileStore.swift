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

    // ตัว optimistic update ของการเปลี่ยนรูปถูกถอดออกพร้อมกับ `APIClient.updatePhoto`
    // (2026-08-24) — ไม่มีจอไหนเรียก ดูเหตุผลเต็มที่ `APIClient` · `photoUrl` ยังอยู่
    // เพราะมันคือรูปที่ **อ่าน** มาจากโปรไฟล์ ไม่ใช่รูปที่เขียนขึ้นไป

    func clear() { me = nil; photoUrl = nil }
}
