import Foundation

/// กติกาการนับระยะ/ความเร็ว และการจัดรูปตัวเลขของแท็บ SU RUN — ฟังก์ชันบริสุทธิ์ล้วน
///
/// แยกออกมาจาก `SURunTracker` เพราะตัว tracker ต้องมี `CLLocationManager` กับ `CMPedometer` จริง
/// ถึงจะรันได้ เทสจึงแตะไม่ถึง · เกณฑ์ทุกตัวยกมาจาก `walk/WalkTrackingService.kt` ของแอป Android
/// ที่ผ่านการเดินจริงบนเส้นทางนี้มาแล้ว ไม่ใช่ค่าที่ตั้งขึ้นใหม่
enum SURunMath {
    /// fix ที่คลาดเกินนี้ทิ้ง — ใต้ร่มไม้บนดอย GPS เด้งได้ทีละหลายสิบเมตร ปล่อยเข้ามาแล้วระยะรวมพองทันที
    static let maxAccuracyMetres: Double = 25

    /// ต้องขยับจากหมุดอ้างอิงเกินนี้ถึงนับ — ยืนนิ่งแล้ว GPS แกว่งอยู่กับที่คือแหล่งระยะปลอมที่ใหญ่ที่สุด
    static let minMoveMetres: Double = 2.5

    /// น้ำหนักของตัวอย่างใหม่ตอนปรับความเร็วให้นิ่ง — สูงกว่านี้ pace บนจอจะกระตุกทุกวินาที
    static let speedSmoothing: Double = 0.3

    /// ช้ากว่านี้ไม่แสดง pace — 1000/ความเร็ว จะพุ่งเป็นเลขมหาศาลที่ไม่มีความหมายตอนยืนอยู่กับที่
    static let minPaceSpeed: Double = 0.35

    /// CoreLocation ใช้ค่าติดลบแทน "ไม่รู้ความแม่น" — ต้องทิ้ง ไม่ใช่ตีความว่าแม่นมาก
    static func accepts(accuracy: Double) -> Bool {
        accuracy >= 0 && accuracy <= maxAccuracyMetres
    }

    /// คืนระยะที่ควรบวกเข้าระยะรวม · 0 = ยังขยับไม่พอ ผู้เรียกต้องคงหมุดอ้างอิงเดิมไว้
    static func advance(movedFromAnchor metres: Double) -> Double {
        metres >= minMoveMetres ? metres : 0
    }

    /// ตัวอย่างแรกไม่มีของเก่าให้ผสม ต้องใช้ค่าดิบ — ผสมกับ 0 จะได้ความเร็วต่ำกว่าจริงไปหลายวินาที
    static func smooth(speed: Double, previous: Double?) -> Double {
        guard let previous else { return speed }
        return speedSmoothing * speed + (1 - speedSmoothing) * previous
    }

    static func paceText(metresPerSecond: Double) -> String {
        guard metresPerSecond.isFinite, metresPerSecond >= minPaceSpeed else { return "—" }
        let secondsPerKm = Int((1000 / metresPerSecond).rounded())
        return String(format: "%d:%02d", secondsPerKm / 60, secondsPerKm % 60)
    }

    static func distanceText(metres: Double) -> String {
        guard metres.isFinite else { return "—" }
        if metres < 1000 { return "\(Int(metres.rounded())) ม." }
        // ทศนิยม 2 ตำแหน่ง — ตำแหน่งเดียวทำให้เลขนิ่งอยู่นานถึง 100 ม. จนดูเหมือนแอปค้าง
        return String(format: "%.2f กม.", metres / 1000)
    }

    static func elapsedText(seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    /// nil = เครื่องไม่มีตัวนับก้าว/ไม่ให้สิทธิ์ · ต้องเป็น "—" ไม่ใช่ 0 ซึ่งอ่านว่า "เดินแล้วได้ศูนย์ก้าว"
    static func stepsText(_ steps: Int?) -> String {
        guard let steps else { return "—" }
        return Self.stepFormatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }

    /// ตั้ง separator เองแทนการพึ่ง locale ของเครื่อง — เทสต้องได้ผลเดิมไม่ว่าเครื่องตั้งภาษาอะไร
    private static let stepFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.groupingSize = 3
        f.usesGroupingSeparator = true
        return f
    }()
}
