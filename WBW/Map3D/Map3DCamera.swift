import Foundation
import simd

/// กล้องของแท็บแผนที่ — คุมเองแทน `.realityViewCameraControls(.orbit)`
///
/// `.orbit` ให้ผู้ใช้หมุนได้อิสระรวมถึงมุดลงไปมองใต้โมเดล (เห็นก้นภูมิประเทศเป็นแผ่นแบนๆ)
/// และไม่มี API ให้จำกัดมุมหรือกำหนดทิศเริ่มต้น จึงต้องเขียนเอง ตรรกะทั้งหมดอยู่ในนี้เป็น
/// ฟังก์ชันบริสุทธิ์ให้เทสได้ ตัว `Map3DScreen` แค่เอาค่าที่ได้ไปตั้ง `PerspectiveCamera`
///
/// ทุกมุมเป็นเรเดียน · ระยะเป็นหน่วยของฉากหลังโมเดลถูกย่อให้พอดีกรอบ 2 หน่วยแล้ว
enum Map3DCamera {
    /// มุมกวาดเริ่มต้น — หันด้านหน้ามหาวิทยาลัยเข้าหากล้อง
    ///
    /// ค่านี้หาจากการถ่ายจริงเทียบกับภาพอ้างอิงที่ Park ให้ ไม่ได้คำนวณจากทิศเหนือจริง
    /// (ปรับได้ตอนรันด้วย `-uitestMapHeading <องศา>` เพื่อถ่ายเทียบหลายค่า)
    static let defaultYaw: Float = 0

    /// มุมเงยเริ่มต้น — 68° ให้ภาพใกล้เคียงภาพอ้างอิงที่ Park ส่งมาที่สุดจากที่กวาดมา
    /// (ถ่ายเทียบจริงที่ 8° / 45° / 60° / 68° / 75°)
    ///
    /// ⚠️ ทิศทางของค่านี้ "กลับด้าน" กับที่ชื่อบอก และยืนยันด้วยภาพแล้วทั้งสองทาง:
    /// **ค่ามาก = กล้องต่ำ มองเฉียงเห็นอาคารเป็นทรงสามมิติ · ค่าน้อย = มองจากเกือบบนหัว โมเดลแบน**
    /// (8° ได้ภาพจากบนหัว, 75° ได้ภาพแบนเป็นเส้นแบบมองจากข้าง) เคยลองสลับสูตรให้ Z เป็นแกนความสูง
    /// ตามสมมติฐานว่าฉากเป็น Z-up แล้ว ผลกลับด้านซ้ำอีกรอบ จึงคืนสูตร Y-up เดิมแล้วยึดค่าที่วัดได้จริง
    /// อย่าไป "แก้" ทิศทางนี้โดยไม่ถ่ายภาพเทียบก่อน
    static let defaultPitch: Float = 68 * .pi / 180

    /// กวาดซ้ายขวาได้เท่านี้จากมุมเริ่มต้น — ล็อกเป็นช่วงตามที่ Park สั่ง ไม่ปล่อยหมุนรอบตัว
    static let yawRange: Float = 55 * .pi / 180

    /// ปลายทางฝั่ง "มองจากบนหัว" — ต่ำกว่านี้ไม่มีประโยชน์ ภาพแบนจนไม่เหลือความเป็นสามมิติ
    static let minPitch: Float = 6 * .pi / 180

    /// ปลายทางฝั่ง "กล้องต่ำ" — **นี่คือข้อที่กันไม่ให้มองใต้โมเดล** เกินกว่านี้กล้องจะลอดลงไป
    /// ใต้ระนาบพื้นแล้วเห็นก้นภูมิประเทศซึ่งเป็นแผ่นตัดเปล่า ๆ ไม่มีเนื้อ (ยืนยันด้วยภาพที่ 75°
    /// ภูมิประเทศเริ่มแบนเป็นเส้น) เทส Map3DCameraTests คุมไว้ว่าค่านี้ต้องไม่ถึง 90°
    static let maxPitch: Float = 75 * .pi / 180

    static let minDistance: Float = 0.8
    static let maxDistance: Float = 4.0
    static let defaultDistance: Float = 1.6

    static func clampYaw(_ yaw: Float) -> Float {
        min(max(yaw, defaultYaw - yawRange), defaultYaw + yawRange)
    }

    static func clampPitch(_ pitch: Float) -> Float {
        min(max(pitch, minPitch), maxPitch)
    }

    static func clampDistance(_ distance: Float) -> Float {
        min(max(distance, minDistance), maxDistance)
    }

    /// ตำแหน่งกล้องบนทรงกลมรอบจุดที่มอง
    ///
    /// pitch 0 = ระดับสายตาเดียวกับเป้า · pitch สูงขึ้น = ลอยสูงขึ้นและเข้าใกล้แนวดิ่ง
    static func position(yaw: Float, pitch: Float, distance: Float,
                         target: SIMD3<Float>) -> SIMD3<Float> {
        let horizontal = distance * cos(pitch)
        return SIMD3<Float>(
            target.x + horizontal * sin(yaw),
            target.y + distance * sin(pitch),
            target.z + horizontal * cos(yaw)
        )
    }
}
