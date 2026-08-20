import Foundation
import simd

/// แปลงพิกัดโลกจริง → พิกัดบนโมเดลแผนที่ (หน่วยเดียวกับไฟล์ usdz)
///
/// ที่มาของค่า anchor และข้อจำกัดความแม่นยำอยู่ที่ `Map3DConfig.Anchor` — อ่านที่นั่นก่อนแก้ตัวเลข
enum Map3DGeo {
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
