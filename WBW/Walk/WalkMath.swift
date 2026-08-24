import CoreLocation
import Foundation

/// คณิตของการเดิน — `static func` บริสุทธิ์ล้วน รับค่าเข้า คืนค่าออก ไม่มี state ของ View ติดมา
///
/// แยกออกจาก `WalkTracker` เพื่อให้เทสเรียกตรงได้โดยไม่ต้อง mount View หรือรอ GPS จริง
/// (ทรงเดียวกับ `Map3DCamera.clampPitch`) — พฤติกรรมที่สำคัญที่สุดสองข้อของฟีเจอร์นี้
/// คือ "ยืนอยู่กับที่แล้วระยะต้องไม่วิ่ง" กับ "เดินช้ามากแล้วเพซต้องไม่เป็นเลขบ้า ๆ"
/// ซึ่งทดสอบด้วยตาบนเครื่องจริงได้ยากมาก แต่เทสตรงนี้จับได้ทันที
///
/// ค่าคงที่ทุกตัวยกมาจาก `walk/WalkTrackingService.kt` ของ Android ตรง ๆ เพื่อให้สองแอป
/// ให้ตัวเลขใกล้กันเมื่อเดินเส้นเดียวกัน — ไม่ใช่ค่าที่ตั้งขึ้นใหม่เอง
enum WalkMath {

    /// ทิ้ง fix ที่ความแม่นยำแย่กว่านี้ (เมตร) — ใต้ร่มไม้หนา ๆ GPS ให้ค่าที่กระโดดเป็นสิบเมตร
    static let maxAccuracyMetres: Double = 25

    /// ต้องขยับเกินนี้ถึงจะนับเป็นการเคลื่อนที่ (เมตร)
    ///
    /// **นี่คือตัวกันอาการ "ยืนเฉย ๆ แล้วระยะวิ่งขึ้นเอง"** ซึ่งเป็นอาการที่ผู้ใช้เห็นแล้ว
    /// เลิกเชื่อตัวเลขทั้งจอ · GPS นิ่ง ๆ ยังส่งพิกัดที่ต่างกันหลักเมตรตลอดเวลา
    static let minMoveMetres: Double = 2.5

    /// น้ำหนักของค่าใหม่ตอนไล่เฉลี่ยความเร็ว — ต่ำ = นิ่งแต่ตามช้า
    static let speedAlpha: Double = 0.3

    /// ช้ากว่านี้ถือว่า "ไม่ได้เดิน" แล้วเพซโชว์ `—` (เมตร/วินาที)
    ///
    /// ไม่มีเพดานนี้ เพซตอนยืนนิ่งจะพุ่งเป็นหลักชั่วโมงต่อกิโลเมตร ซึ่งเป็นตัวเลขที่ถูก
    /// ทางคณิตแต่ไร้ความหมายกับคนอ่าน
    static let minPaceSpeedMps: Double = 0.35

    /// fix นี้เชื่อได้ไหม — `horizontalAccuracy` ติดลบแปลว่าพิกัดใช้ไม่ได้เลย
    static func isTrustworthy(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= maxAccuracyMetres
    }

    /// ระยะที่สะสมได้จากหมุดอ้างอิงมายังจุดใหม่
    ///
    /// คืน `nil` เมื่อขยับไม่ถึงเกณฑ์ = **ยังไม่ต้องขยับหมุดอ้างอิง** ซึ่งเป็นหัวใจของวิธีนี้:
    /// ถ้าเลื่อนหมุดตามทุก fix แล้วค่อยตัดสินทีหลัง ระยะจะสะสมจากการสั่นทีละ 1-2 เมตร
    /// ไปเรื่อย ๆ จนได้กิโลเมตรจากการยืนอยู่กับที่
    static func advance(from anchor: CLLocation, to next: CLLocation) -> Double? {
        let moved = next.distance(from: anchor)
        return moved >= minMoveMetres ? moved : nil
    }

    /// ไล่เฉลี่ยความเร็วแบบ exponential — ค่าดิบจาก GPS กระโดดจนอ่านไม่ทัน
    static func smoothSpeed(previous: Double, sample: Double) -> Double {
        let clean = max(sample, 0)   // GPS คืน -1 ตอนวัดความเร็วไม่ได้
        return previous + speedAlpha * (clean - previous)
    }

    /// `450 ม.` ต่ำกว่า 1 กม. · `1.20 กม.` ตั้งแต่ 1 กม. ขึ้นไป (ทรงเดียวกับ Android)
    static func distanceText(_ metres: Double) -> String {
        metres < 1000
            ? String(format: "%d %@", Int(metres.rounded()), Loc.t("walk_unit_metre"))
            : String(format: "%.2f %@", metres / 1000, Loc.t("walk_unit_km"))
    }

    /// `6'30"` ต่อกิโลเมตร · ช้ากว่าเกณฑ์คืน `—`
    static func paceText(speedMps: Double) -> String {
        guard speedMps >= minPaceSpeedMps else { return "—" }
        let secondsPerKm = 1000 / speedMps
        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm) % 60
        return String(format: "%d'%02d\"", minutes, seconds)
    }

    /// จำนวนก้าว — nil แปลว่านับไม่ได้ ไม่ใช่ศูนย์ (ดูคอมเมนต์ที่ `WalkStats.steps`)
    static func stepsText(_ steps: Int?) -> String {
        steps.map(String.init) ?? "—"
    }
}
