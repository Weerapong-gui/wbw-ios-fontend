import Foundation
import simd

/// ท่ากล้องหนึ่งท่า — เดิม `Map3DScreen` ถือ yaw/pitch/distance แยกกันสามตัวและมองที่ `.zero` ตายตัว
/// พอกล้องต้องไปหมุนรอบหมุด จุดที่มองก็กลายเป็นค่าที่เปลี่ยนได้ ทั้งสี่ตัวจึงต้องเดินทางไปด้วยกัน
struct Map3DPose: Equatable {
    var yaw: Float
    var pitch: Float
    var distance: Float
    var target: SIMD3<Float>
}

/// กล้องบินเข้าไปจ้องหมุดแล้วหมุนวนรอบฐาน
///
/// แยกเส้นโค้งออกมาเป็นค่าล้วนไม่ผูกกับ View ด้วยเหตุผลเดียวกับ `Map3DIntro` — ที่ต้องจับให้ได้
/// ก่อนถึงจอคือ **ทุกเฟรมต้องอยู่ในช่วงที่ `Map3DCamera.clamp*` ยอมรับอยู่แล้ว** ถ้าเส้นโค้งพา
/// ออกนอกช่วง clamp จะไปตัดกลางแอนิเมชัน บนจอเห็นเป็นภาพค้างแป๊บนึงแล้วกระตุก หาสาเหตุยากมาก
enum Map3DFocus {
    /// ยาวพอให้อ่านว่า "กล้องกำลังเคลื่อนเข้าไป" ไม่ใช่ตัดภาพ แต่ไม่นานจนคนที่กดหาฐานรู้สึกว่าถูกขัง
    static let flyDuration: TimeInterval = 1.4
    /// ขากลับเร็วกว่าขาไป — กดปิดแล้วผู้ใช้อยากได้จอคืน ไม่ได้อยากดูแอนิเมชันซ้ำ
    static let returnDuration: TimeInterval = 0.8

    /// ท่าปลายทางตอนจ้องหมุด
    ///
    /// **คงมุมกวาดเดิมไว้** ไม่คำนวณมุมใหม่จากตำแหน่งหมุด — เหวี่ยงกล้องข้ามฝั่งจอทำให้ผู้ใช้
    /// ไม่รู้ว่าตัวเองอยู่ทิศไหนของแผนที่แล้ว ทั้งที่เพิ่งกดหมุดที่เห็นอยู่ตรงหน้าเฉย ๆ ·
    /// สิ่งที่เปลี่ยนคือ "มองอะไร" กับ "อยู่ใกล้แค่ไหน" ไม่ใช่ "มองจากทิศไหน"
    static func pose(forPinAt position: SIMD3<Float>, currentYaw: Float) -> Map3DPose {
        Map3DPose(yaw: Map3DCamera.wrapYaw(currentYaw),
                  pitch: Map3DCamera.clampPitch(Map3DCamera.focusPitch),
                  distance: Map3DCamera.clampDistance(Map3DCamera.focusDistance,
                                                      floor: Map3DCamera.focusDistance),
                  target: position)
    }

    /// ท่ากล้องที่ progress 0…1 · นอกช่วงถูกบีบเข้าขอบ (SwiftUI ส่งค่าเลยขอบมาได้บางเส้นโค้ง)
    ///
    /// ease-out กำลังสาม เหมือน `Map3DIntro.frame` — เร็วตอนต้นแล้วค่อย ๆ นิ่งเข้าที่
    static func frame(at progress: Float, from: Map3DPose, to: Map3DPose) -> Map3DPose {
        let t = min(max(progress, 0), 1)
        // คืนของเดิม/ของปลายทางตรง ๆ ที่ปลายทั้งสอง ไม่ผ่านการคำนวณ — `a + (b - a) * 1` ใน
        // floating point ไม่ได้เท่ากับ `b` เป๊ะเสมอไป เศษที่เหลือแปลว่ากล้องไม่เคยถึงท่าปลายทางจริง
        if t <= 0 { return from }
        if t >= 1 { return to }
        let eased = ease(t)
        // กวาดทางสั้นเสมอ — ตั้งแต่ปลดล็อกให้หมุนรอบตัว 170° กับ -170° ห่างกันแค่ 20°
        // interpolate ตรง ๆ จะวิ่งย้อน 340° ผ่าน 0° ซึ่งบนจอคือกล้องหมุนควงกลับทั้งรอบ
        let delta = Map3DCamera.wrapYaw(to.yaw - from.yaw)
        return Map3DPose(
            yaw: Map3DCamera.wrapYaw(from.yaw + delta * eased),
            pitch: Map3DCamera.clampPitch(from.pitch + (to.pitch - from.pitch) * eased),
            // floor = ระยะที่ใกล้กว่าของสองปลาย — ปลายทั้งสองถูกตรวจมาแล้วว่าใช้ได้ ค่าระหว่างทาง
            // จึงใช้ได้ทั้งหมด · ใช้ minDistance ตรง ๆ จะไปตัดกลางแอนิเมชันตอนบินเข้าหาหมุด
            // (ระยะโฟกัสใกล้กว่าที่ผู้ใช้ลากเองได้ โดยตั้งใจ ดู Map3DCamera.clampDistance)
            distance: Map3DCamera.clampDistance(from.distance + (to.distance - from.distance) * eased,
                                                floor: min(from.distance, to.distance)),
            target: from.target + (to.target - from.target) * eased)
    }

    /// มุมกวาดของการหมุนวนหลังบินถึง — วนไปเรื่อย ๆ จนผู้ใช้สั่งหยุด
    ///
    /// wrap ทุกครั้ง ไม่ปล่อยให้ค่าสะสมโต: จอนี้เปิดค้างได้เป็นนาที ๆ ที่ 8°/วิ ครึ่งชั่วโมงก็เกิน
    /// 80 รอบแล้ว ซึ่งเริ่มกินความละเอียดของ Float ไปกับส่วนที่ไม่มีความหมายทางสายตาเลย
    static func orbitYaw(base: Float, elapsed: TimeInterval) -> Float {
        Map3DCamera.wrapYaw(base + Map3DCamera.orbitSpeed * Float(elapsed))
    }

    // MARK: - ม่านมืดตอนโฟกัสหมุด

    /// ease-out กำลังสาม — เร็วตอนต้นแล้วค่อย ๆ นิ่งเข้าที่
    ///
    /// ดึงออกมาเป็นฟังก์ชันเพราะกล้องกับม่านมืดต้องเดินเส้นโค้งเดียวกันจริง ๆ ไม่ใช่ "เส้นโค้ง
    /// หน้าตาเหมือนกันสองที่" — ลอกสูตรไปเขียนซ้ำแล้ววันหลังมีคนแก้ที่เดียว ทั้งสองจะเดินคนละ
    /// จังหวะโดยไม่มีอะไรฟ้อง (เทส `testDimRidesTheSameEasingCurveAsTheCamera` คุมข้อนี้ไว้)
    static func ease(_ t: Float) -> Float {
        1 - pow(1 - t, 3)
    }

    /// ความเข้มสูงสุดของม่านมืดตอนจ้องหมุด
    ///
    /// ไม่ใช่ 1 โดยตั้งใจ — ม่านทึบเต็มแปลว่าแผนที่หายไปทั้งจอเหลือแต่การ์ด ซึ่งไม่ใช่การ "โฟกัส"
    /// แต่คือการปิดแผนที่ · หน้าที่ของมันคือลดสิ่งรบกวนรอบ ๆ ให้หมุดที่เลือกเด่นขึ้น ไม่ใช่ลบฉากทิ้ง
    static let maxDim: Double = 0.55

    /// ค่าม่านที่ progress 0…1 · นอกช่วงถูกบีบเข้าขอบ
    ///
    /// ขับจากลูปเดียวกับที่เดินกล้อง (`Map3DScreen.run(to:over:dimTo:)`) ไม่ได้สร้างตัวขับใหม่ —
    /// จอนี้เดินค่ากล้องด้วยมือทุกเฟรมอยู่แล้วเพราะพึ่ง SwiftUI ให้รัน `RealityView.update`
    /// ตามค่าที่อนิเมตอยู่ไม่ได้ (เหตุผลยาวอยู่ที่ `Map3DScreen.run`) ม่านจึงเกาะไปกับลูปนั้น
    static func dim(at progress: Float, from: Float, to: Float) -> Float {
        let t = min(max(progress, 0), 1)
        // คืนค่าปลายเป๊ะ ไม่ผ่านการคำนวณ — เหตุผลเดียวกับ `frame(at:from:to:)` เศษทศนิยมที่เหลือ
        // แปลว่าม่านไม่เคยใสสนิทจริง ซึ่งบนจอคือคราบจาง ๆ ที่ไม่มีวันหายไป
        if t <= 0 { return from }
        if t >= 1 { return to }
        return from + (to - from) * ease(t)
    }

    /// ค่าม่าน 0…1 → ความทึบจริงของชั้นบนจอ
    static func dimOpacity(_ dim: Float) -> Double {
        maxDim * Double(min(max(dim, 0), 1))
    }
}
