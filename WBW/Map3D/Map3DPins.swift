import Foundation

/// หมุดฐานบนโมเดลแผนที่ — แท่งทรงกระบอกแดง 8 แท่งที่มากับ map.usdz อยู่แล้ว
///
/// โมเดลตั้งชื่อ prim ว่า Cylinder, Cylinder_001 … Cylinder_007 ซึ่งไม่ได้บอกว่าแท่งไหนคือฐานไหน
/// ลำดับในตารางข้างล่างจึงเป็นการจับคู่ที่ **ต้องยืนยันด้วยสกรีนช็อตกับ Park** ไม่ใช่ค่าที่พิสูจน์
/// จากตัวไฟล์ได้ — จับผิดคู่แปลว่าคนเดินผิดฐานจริง
enum Map3DPins {
    /// เรียงตามลำดับฐาน 1-8 · ลำดับนี้คือสิ่งที่ต้องยืนยันด้วยตา
    static let entityNames = [
        "Cylinder",
        "Cylinder_001",
        "Cylinder_002",
        "Cylinder_003",
        "Cylinder_004",
        "Cylinder_005",
        "Cylinder_006",
        "Cylinder_007",
    ]

    /// prim นี้เป็นฐานลำดับที่เท่าไร — nil = ไม่ใช่หมุด (อาคาร ถนน ฯลฯ)
    static func sequence(forEntityNamed name: String) -> Int? {
        guard let index = entityNames.firstIndex(of: name) else { return nil }
        return index + 1
    }

    /// ข้อความบนการ์ดตอนแตะหมุด
    ///
    /// ชื่อจริงมีให้เฉพาะฐานที่เช็คอินไปแล้ว (GET /wbw/me/progress คืนแค่ checked_in)
    /// ฐานที่ยังไม่ไปถึงไม่มีทางรู้ชื่อจากฝั่ง participant — คืน "ฐานที่ N" แทน ห้ามเดาชื่อ
    static func label(sequence: Int, checkedIn: [CheckinProgressItem]) -> String {
        if let match = checkedIn.first(where: { $0.sequence == sequence }) {
            return match.name
        }
        return "ฐานที่ \(sequence)"
    }
}
