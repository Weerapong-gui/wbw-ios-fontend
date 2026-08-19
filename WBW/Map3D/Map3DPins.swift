import Foundation

/// หมุดฐานบนโมเดลแผนที่ — แท่งทรงกระบอกแดง 8 แท่งที่มากับ map.usdz อยู่แล้ว
///
/// โมเดลตั้งชื่อ prim ว่า Cylinder, Cylinder_001 … Cylinder_007 ซึ่งไม่ได้บอกว่าแท่งไหนคือฐานไหน
/// ลำดับในตารางข้างล่างจึงเป็นการจับคู่ที่ **ต้องยืนยันด้วยสกรีนช็อตกับ Park** ไม่ใช่ค่าที่พิสูจน์
/// จากตัวไฟล์ได้ — จับผิดคู่แปลว่าคนเดินผิดฐานจริง
enum Map3DPins {
    /// ชื่อ prim ของแท่งแดง เรียงตามลำดับฐาน — มาจาก `WBW/Resources/map_config.json`
    ///
    /// **ย้ายออกจากโค้ดเพราะโมเดลจะถูกเปลี่ยนใบ** ชื่อ prim ชุดใหม่จะไม่เหมือนชุดนี้แน่นอน
    static var entityNames: [String] { Map3DConfig.current.pins.map(\.entityName) }

    /// prim นี้เป็นฐานลำดับที่เท่าไร — nil = ไม่ใช่หมุด (อาคาร ถนน ฯลฯ)
    static func sequence(forEntityNamed name: String) -> Int? {
        Map3DConfig.current.pins.first { $0.entityName == name }?.sequence
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
