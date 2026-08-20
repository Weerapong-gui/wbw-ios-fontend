import Foundation

/// หมุดฐานบนโมเดลแผนที่ — `marker_1`…`marker_8` ที่มากับ Map2.0
///
/// ต่างจากใบก่อนตรงที่ **โมเดลบอกลำดับฐานเอง**: ชื่อ prim มีเลขอยู่ในตัว และมีเลขปั้นเป็น mesh
/// (`markerNum_N`) ให้คนเดินเห็นบนแผนที่ตรงกัน · ใบเก่าชื่อ prim เป็น `Cylinder_00N` ที่ไม่ได้
/// บอกอะไรเลย ต้องเดาคู่แล้วยืนยันด้วยสกรีนช็อต — และตอนเทียบกับใบใหม่พบว่าเดาผิด 6 จาก 8
enum Map3DPins {
    /// ชื่อ prim ทุกตัวที่ต้องติด collision ให้ — รวมทั้งแท่งและเลขที่ปั้นติดหมุด
    static var entityNames: [String] { Map3DConfig.current.pins.flatMap(\.entityNames) }

    /// ชื่อแท่งหลักของฐานนั้น (ชื่อแรกในตาราง) — กล้องต้องบินไปจ้องแท่ง ไม่ใช่เลขที่ลอยสูงกว่า
    /// ไม่งั้นเฟรมสุดท้ายของแอนิเมชันโฟกัสเป็นภาพกลางอากาศเหนือฐาน
    static func primaryEntityName(for sequence: Int) -> String? {
        Map3DConfig.current.pins.first { $0.sequence == sequence }?.entityNames.first
    }

    /// prim นี้เป็นฐานลำดับที่เท่าไร — nil = ไม่ใช่หมุด (อาคาร ถนน ต้นไม้ ฯลฯ)
    static func sequence(forEntityNamed name: String) -> Int? {
        Map3DConfig.current.pins.first { $0.entityNames.contains(name) }?.sequence
    }

    /// ข้อความบนการ์ดตอนแตะหมุด
    ///
    /// ชื่อจริงมีให้เฉพาะฐานที่เช็คอินไปแล้ว (GET /wbw/me/progress คืนแค่ checked_in)
    /// ฐานที่ยังไม่ไปถึงไม่มีทางรู้ชื่อจากฝั่ง participant — คืน "ฐานที่ N" แทน ห้ามเดาชื่อ
    static func label(sequence: Int, checkedIn: [CheckinProgressItem]) -> String {
        if let match = checkedIn.first(where: { $0.sequence == sequence }) {
            return match.name
        }
        return String(format: Loc.t("map_base_number"), sequence)
    }
}
