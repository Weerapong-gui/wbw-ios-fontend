import Foundation

/// เคส SOS จำลองของโหมดเดโม่ — อยู่ในหน่วยความจำล้วน ไม่แตะเน็ตและไม่แตะดิสก์
///
/// **ทำไมต้องมี** `APIClient+SOS.swift` มาจากสาขา `feat/wbw-sos` ซึ่งเขียนก่อนโหมดเดโม่จะกลาย
/// เป็นทางเข้าหลักของผู้รีวิว App Store จึงไม่มี guard ของโหมดเดโม่เลยสักจุด (ไฟล์ `APIClient.swift`
/// มี 18 จุด) · ผลจริงบนซิม: `SOSStore` poll `/me/sos/active` ด้วย token ปลอมของเดโม่ →
/// backend จริงตอบ 401 → `.wbwUnauthorized` → `Session.logout(automatic:)` → ผู้รีวิวถูกเตะ
/// ออกจากโหมดเดโม่กลับไปหน้าล็อกอิน ซึ่งคือ Guideline 2.1 เต็ม ๆ
///
/// ต่างจาก `DemoData` ตรงที่ของนี่ **มีสถานะ** — กด SOS แล้วต้องมีเคสเปิดอยู่จริงให้จอสถานะอ่าน
/// ไม่ใช่ fixture ตายตัว จึงไม่ได้เขียนเป็น JSON ดิบเหมือนไฟล์นั้น
///
/// `@MainActor` เพราะทุกคนที่เรียก (`SOSStore`) เป็น `@MainActor` อยู่แล้ว ไม่ต้องมีล็อกของตัวเอง
@MainActor
enum DemoSOS {
    private static var openCase: SOSCase?
    /// เลขเคสเดินหน้าอย่างเดียว เพื่อให้เคสที่ยกเลิกแล้วกดใหม่ได้เลขใหม่ ไม่ใช่เลขเดิม
    private static var nextId: Int64 = 9001

    /// เคสที่เปิดอยู่ · nil = ไม่มี ซึ่งเป็นสถานะปกติของทุก poll
    static func active() -> SOSCase? { openCase }

    /// เปิดเคส — **idempotent ตาม `clientId` เหมือน backend จริง** ไม่งั้น `SOSStore` ที่ยิงซ้ำ
    /// จนกว่าจะสำเร็จจะสร้างเคสใหม่ทุกรอบ
    static func raise(_ draft: SOSDraft) -> SOSCase {
        if let existing = openCase, clientIds[existing.id] == draft.clientId { return existing }
        let made = SOSCase(
            id: nextId,
            forOther: draft.forOther,
            lat: draft.lat, lng: draft.lng, accuracyM: draft.accuracyM,
            locSource: draft.lat == nil ? nil : "gps",
            checkpointId: 5, checkpointName: Loc.t("demo_sos_checkpoint"),
            message: draft.message,
            resolved: false, resolveReason: nil,
            ackedAt: nil, ackedByName: nil,
            createdAt: draft.deviceTime,
            emergencyPhone: Config.emergencyPhoneDefault)
        nextId += 1
        openCase = made
        clientIds[made.id] = draft.clientId
        return made
    }

    static func cancel() -> APIClient.SOSCancelOutcome {
        guard openCase != nil else { return .tooLate }
        clear()
        return .canceled
    }

    static func clear() {
        openCase = nil
        clientIds.removeAll()
    }

    /// `SOSCase` ไม่มีฟิลด์ `clientId` (backend ไม่ส่งกลับมา) — เก็บคู่ไว้ข้างนอกเพื่อทำ idempotency
    private static var clientIds: [Int64: String] = [:]
}
