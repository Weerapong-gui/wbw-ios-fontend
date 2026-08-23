import CoreLocation
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

    /// ทางกลับ: หน่วยของโมเดล → พิกัดจริง
    ///
    /// ใช้ตอนเอาตำแหน่งที่ปักไว้ในโมเดลไปวางบนแผนที่ 2 มิติ ซึ่งไม่มีโมเดลให้อ้างอิง —
    /// เขียนคู่ไว้ในไฟล์เดียวกับขาไปโดยตั้งใจ แก้สูตรข้างบนแล้วต้องเห็นตัวนี้อยู่ตรงหน้าด้วย
    ///
    /// **ไม่มี guard กรอบพื้นที่งานที่นี่** ต่างจากขาไป: ค่าที่ป้อนเข้ามาคือตำแหน่งที่มีอยู่จริงใน
    /// โมเดลอยู่แล้ว การปฏิเสธมันทิ้งจะกลายเป็นหมุดที่หายไปเงียบ ๆ ส่วนขาไปรับพิกัด GPS ของผู้ใช้
    /// ซึ่งอยู่นอกงานได้จริงและต้องไม่ถูกวาด
    static func coordinate(x: Float, y: Float,
                           in anchor: Map3DConfig.Anchor) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: anchor.originLatitude + Double(y) / anchor.unitsPerDegreeLatitude,
            longitude: anchor.originLongitude + Double(x) / anchor.unitsPerDegreeLongitude)
    }
}
