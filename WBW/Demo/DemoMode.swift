import Foundation

/// โหมดเดโม่ — เดินดูแอปได้ครบทุกจอโดยไม่ต้องมีบัญชีและไม่ยิงเน็ตเลยสักครั้ง
///
/// **ทำไมถึงต้องมี:** build 1.0 (7) โดน App Review ตีกลับด้วย Guideline 2.1 เพราะบัญชีเดโม่ที่ให้ไป
/// ล็อกอินไม่ผ่าน (ยิงจริงยืนยันแล้วว่า prod ตอบ 401) และงานปิดรับสมัครไปแล้วที่ 2000/2000 ที่นั่ง
/// สมัครบัญชีใหม่ไม่ได้อีก · Apple เขียนไว้ในใบตีกลับเองว่ารับ *"a demonstration mode that shows all
/// of the features and functionality available in the app"* แทนบัญชีจริงได้
///
/// **ต้องคอมไพล์ติดใน Release** — ต่างจาก `-uitest*` ทั้ง 14 ตัวที่อยู่ใน `#if DEBUG` และหายไปจาก
/// build ที่ส่งขึ้น store · ปุ่มนี้เป็นของที่ reviewer ต้องกดได้จริงบน build ที่ส่งไป
///
/// **สถานะอ่านจาก token ที่เก็บไว้ ไม่ใช่ตัวแปรแยก** — เปิดแอปใหม่แล้ว `Session.init` กู้ token เดิม
/// กลับมา ถ้าเก็บสถานะไว้คนละที่ สองอย่างจะไม่ตรงกันทันทีที่แอปถูกฆ่าคาโหมดเดโม่: มี session อยู่
/// แต่ `active` เป็น false แล้วทุกจอจะยิงเน็ตด้วย token ปลอมแล้วได้ 401 รัว ๆ
enum DemoMode {
    /// token แทนของจริง — ไม่ใช่ JWT จึงไม่มีวันชนกับ token จริงของใคร
    static let token = "wbw-demo-session"

    /// ทับค่าได้เฉพาะในเทส — โค้ดแอปไม่ควรตั้งค่านี้เอง
    static var forcedActive: Bool?

    static var active: Bool {
        if let forcedActive { return forcedActive }
        return TokenStore.read() == token
    }

    /// ผู้ใช้ปลอมของโหมดเดโม่ · role เป็น `participant` เสมอ — เข้าโหมดเดโม่แล้วต้องไม่หลุดไปจอ
    /// เจ้าหน้าที่ (`StaffScanView`) ซึ่งเปิดกล้องสแกน QR ของจริง
    static var user: AuthUser {
        AuthUser(userId: "demo-user", username: "demo", role: "participant")
    }
}
