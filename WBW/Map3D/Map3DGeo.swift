import Foundation
import simd

/// แปลงพิกัดโลกจริง → พิกัดบนโมเดลแผนที่
///
/// โมเดลถูกย่อให้พอดีกรอบ 2 หน่วยตอนโหลด (ดู Map3DScreen) พิกัดที่คืนจึงอยู่ในช่วง -1…1
/// ทั้งสองแกน โดย x = ตะวันออก-ตะวันตก, y = เหนือ-ใต้ ผู้เรียกเป็นคนแปลงเป็นแกนของ RealityKit เอง
enum Map3DGeo {
    /// กรอบพิกัดสี่เหลี่ยมของพื้นที่งาน หน่วยเป็นองศา
    struct Bounds: Equatable, Decodable {
        let south: Double
        let west: Double
        let north: Double
        let east: Double
    }

    /// กรอบจริงของโมเดล — **ย้ายไปอยู่ `WBW/Resources/map_config.json` แล้ว** (ดู `Map3DConfig`)
    /// เพราะโมเดลจะถูกเปลี่ยนใบ กรอบนี้ต้องเปลี่ยนตามเสมอ ปล่อยไว้ในโค้ดแล้วมีโอกาสลืม
    ///
    /// ที่มาของตัวเลขชุดปัจจุบัน: metadata ของไฟล์ export รอบ 2026-07-18 · ยืนยันซ้ำด้วยวิธีอิสระ
    /// (2026-08-07) โดยเอาพิกัดจริงของจุดตรวจ 7 จุดไป fit แบบ Procrustes ลงบนแท่งแดง 8 อันใน
    /// map.usdz — ลองทุกวิธีจับคู่ ผลที่ดีที่สุดเสถียรทั้งสามแบบของการ fit และชนะอันดับสองอยู่
    /// 35 ม. RMS · ย้อนกลับไปหากรอบพิกัดจากผล fit ได้กรอบที่ห่างจากค่านี้ไม่เกินราว 100 ม. ทุกขอบ
    ///
    /// ข้อจำกัดความแม่นยำ: scatter ต่อจุดราว 110 ม. — มาจากความหยาบของการปักหมุดในตัวโมเดลเอง
    /// ไม่ใช่ความคลาดของ GPS · จุดตำแหน่งผู้ใช้บนแผนที่จึงแม่นได้ระดับนี้เป็นอย่างดีที่สุด
    static var eventArea: Bounds { Map3DConfig.current.bounds }

    /// nil = อยู่นอกพื้นที่งาน (ไม่ต้องวาดจุด)
    ///
    /// ใช้การแมปเชิงเส้นตรงๆ ไม่แปลงเป็น EPSG:3857 ก่อน — ที่ละติจูด 20° กรอบกว้างราว 4 กม.
    /// ความบิดของ Mercator ในช่วงแคบขนาดนี้เล็กกว่าความคลาดของ GPS มือถือเอง
    static func modelPoint(latitude: Double, longitude: Double, in bounds: Bounds) -> SIMD2<Float>? {
        guard latitude >= bounds.south, latitude <= bounds.north,
              longitude >= bounds.west, longitude <= bounds.east else { return nil }
        let x = (longitude - bounds.west) / (bounds.east - bounds.west) * 2 - 1
        let y = (latitude - bounds.south) / (bounds.north - bounds.south) * 2 - 1
        return SIMD2<Float>(Float(x), Float(y))
    }

    /// พิกัดจริง → พิกัดในหน่วยของโมเดล · x = ตะวันออกบวก, y = เหนือบวก, หน่วยเดียวกับไฟล์ usdz
    /// (`metersPerUnit = 1`, เมตร Web Mercator) · nil = อยู่นอกพื้นที่งาน ไม่ต้องวาดจุด
    ///
    /// แมปเชิงเส้นตรง ๆ ไม่กางสูตร Mercator เต็ม — พื้นที่งานกว้างราว 4.5 กม. ที่ละติจูด 20°
    /// ความบิดของ Mercator ในช่วงแคบขนาดนี้เล็กกว่าความคลาดของ GPS มือถือเองหลายเท่า
    static func modelUnits(latitude: Double, longitude: Double,
                           in anchor: Map3DConfig.Anchor) -> SIMD2<Float>? {
        let x = (longitude - anchor.originLongitude) * anchor.unitsPerDegreeLongitude
        let y = (latitude - anchor.originLatitude) * anchor.unitsPerDegreeLatitude
        guard abs(x) <= anchor.halfSpanUnitsEastWest,
              abs(y) <= anchor.halfSpanUnitsNorthSouth else { return nil }
        return SIMD2<Float>(Float(x), Float(y))
    }
}
