import Foundation

/// แอนิเมชันตอนเข้าแท็บแผนที่ครั้งแรก — กล้องไต่ลงมาจากเหนือเมฆ
///
/// แยกเส้นโค้งออกมาเป็นค่าล้วนไม่ผูกกับ View เพื่อให้เทสจับได้ก่อนถึงจอ · ที่ต้องจับเป็นพิเศษคือ
/// ทุกเฟรมต้องอยู่ในช่วงที่ `Map3DCamera.clamp*` ยอมรับอยู่แล้ว — ถ้าเส้นโค้งพาออกนอกช่วง
/// clamp จะไปตัดกลางแอนิเมชัน บนจอเห็นเป็นภาพค้างแป๊บนึงแล้วกระตุก หาสาเหตุยากมาก
enum Map3DIntro {
    /// ยาวพอให้เห็นเมฆผ่าน แต่ไม่นานจนคนที่เปิดมาหาฐานรู้สึกว่าถูกขัง
    static let duration: TimeInterval = 2.2

    /// มุมเริ่ม — ค่าสูงคือมองเกือบจากบนหัว (ยืนยันด้วยภาพ: 75° โมเดลเต็มจอราบ, 8° มองเอียงต่ำ)
    /// เริ่มจากบนหัวเพราะกำลังจะ "ตกลงมา" ผ่านชั้นเมฆที่วางราบอยู่
    static let startPitch = Map3DCamera.maxPitch

    /// ระยะเริ่ม — ต้องสูงกว่าชั้นเมฆบนสุดของ Map3DSky ไม่งั้นกล้องเริ่มใต้เมฆ ไม่ได้ทะลุอะไรเลย
    /// ใช้ maxDistance ตรง ๆ เพื่อไม่ให้เกินช่วงที่กล้องยอมรับ (เทสคุมข้อนี้ไว้)
    static let startDistance = Map3DCamera.maxDistance

    /// ค่ากล้องที่ progress 0…1 · นอกช่วงถูกบีบเข้าขอบ (SwiftUI ส่งค่าเลยขอบมาได้บางเส้นโค้ง)
    ///
    /// ease-out กำลังสาม: เร็วตอนต้นแล้วค่อย ๆ นิ่งเข้าที่ ให้ความรู้สึก "ร่อนลงจอด" ไม่ใช่ "ตกกระแทก"
    static func frame(at progress: Float) -> (pitch: Float, distance: Float) {
        let t = min(max(progress, 0), 1)
        let eased = 1 - pow(1 - t, 3)
        return (
            pitch: startPitch + (Map3DCamera.defaultPitch - startPitch) * eased,
            distance: startDistance + (Map3DCamera.defaultDistance - startDistance) * eased
        )
    }
}
