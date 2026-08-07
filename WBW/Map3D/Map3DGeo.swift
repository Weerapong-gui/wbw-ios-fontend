import Foundation
import simd

/// แปลงพิกัดโลกจริง → พิกัดบนโมเดลแผนที่
///
/// โมเดลถูกย่อให้พอดีกรอบ 2 หน่วยตอนโหลด (ดู Map3DScreen) พิกัดที่คืนจึงอยู่ในช่วง -1…1
/// ทั้งสองแกน โดย x = ตะวันออก-ตะวันตก, y = เหนือ-ใต้ ผู้เรียกเป็นคนแปลงเป็นแกนของ RealityKit เอง
enum Map3DGeo {
    /// กรอบพิกัดสี่เหลี่ยมของพื้นที่งาน หน่วยเป็นองศา
    struct Bounds: Equatable {
        let south: Double
        let west: Double
        let north: Double
        let east: Double
    }

    /// กรอบจริงของ map.usdz — ค่าจาก metadata ของไฟล์ export รอบ 2026-07-18 (สเปกเก่าบันทึกไว้)
    ///
    /// ยืนยันซ้ำด้วยวิธีอิสระแล้ว (2026-08-07): เอาพิกัดจริงของจุดตรวจ 7 จุดที่สำรวจมา
    /// (จาก screenshot Google Maps ที่ Park ให้) ไป fit แบบ Procrustes ลงบนแท่งแดง 8 อันใน
    /// map.usdz — ลองทุกวิธีจับคู่ 7 จุดกับ 8 แท่ง ผลลัพธ์ที่ดีที่สุดเสถียรทั้งสามแบบของการ fit
    /// (เลื่อนอย่างเดียว / เลื่อน+ย่อขยาย / คล้ายเต็มรูป) และชนะอันดับสองอยู่ 35 ม. RMS —
    /// ไม่ใช่เรื่องบังเอิญ ย้อนกลับไปหากรอบพิกัดของโมเดลจากผล fit นี้ได้กรอบที่ห่างจากค่าด้านล่าง
    /// ไม่เกินราว 100 ม. ทุกขอบ สองแหล่งข้อมูลอิสระเห็นตรงกันขนาดนี้แปลว่า export รอบ 2026-08-07
    /// (ไฟล์ที่ใช้จริงตอนนี้) ครอบคลุมพื้นที่เดียวกับรอบ 2026-07-18 ที่ค่านี้มาจาก
    ///
    /// ข้อจำกัดความแม่นยำ: scatter ต่อจุดของผล fit อยู่ที่ราว 110 ม. — มาจากความหยาบของการปักหมุด
    /// ในตัวโมเดลเอง ไม่ใช่ความคลาดของ GPS จุดตำแหน่งผู้ใช้บนแผนที่จึงแม่นยำได้ระดับนี้เป็นอย่างดีที่สุด
    /// ไม่ใช่ระดับความแม่นยำของ GPS มือถือ
    static let eventArea = Bounds(south: 20.02371, west: 99.88272,
                                  north: 20.06727, east: 99.92288)

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
}
