import RealityKit
import Foundation

/// โหลด `map.usdz` ไว้ล่วงหน้า แล้วเก็บไว้ใช้ตลอดอายุแอป
///
/// วัดจริงบน simulator: ตั้งแต่ log แรกของแอปถึงบรรทัดที่โมเดลโหลดเสร็จกินไป 7.5 วินาที และ
/// ระหว่างนั้นแท็บแผนที่ไม่มีอะไรให้ดูเลย · ต้นเหตุอยู่ที่ตัวไฟล์: 10.1 MB แบ่งเป็นเรขาคณิต 3.8 MB
/// กับ texture พื้นดิน 6.2 MB (1872×2161) และข้างในมี mesh แยกกันถึง 1,906 ก้อน (1,777 ก้อน
/// มีจุดไม่เกิน 50) RealityKit จึงต้องสร้าง entity กับ material แยกกันเกือบสองพันชุด
///
/// ตัวนี้ไม่ได้ทำให้โหลดเร็วขึ้น — ย้ายเวลานั้นไปอยู่ช่วงที่ผู้ใช้ยังดูจออื่นอยู่เท่านั้น
/// ลดเวลาจริงต้องแก้ที่ตัวไฟล์ (รวม mesh ตาม material + บีบ texture) ซึ่งต้อง export ใหม่จาก Blender
@MainActor
final class MapModelLoader {
    static let shared = MapModelLoader()

    private var loaded: Entity?
    private var loading: Task<Void, Never>?

    private init() {}

    /// เริ่มโหลดถ้ายังไม่เริ่ม · เรียกซ้ำได้ ไม่เริ่มงานซ้อน
    ///
    /// เรียกจาก Home ไม่ใช่ตอนแอป launch — ระหว่าง launch แอปแย่งทรัพยากรกับฉากป่า/โหลดโปรไฟล์/
    /// แชท sync อยู่แล้ว ยัดงานถอด 10 MB เข้าไปด้วยจะไปทำให้จอแรกช้าลงแทน
    func preload() {
        guard loaded == nil, loading == nil else { return }
        loading = Task { [weak self] in
            let started = CFAbsoluteTimeGetCurrent()
            let entity = try? await Entity(named: "map")
            let elapsed = CFAbsoluteTimeGetCurrent() - started
            if entity == nil {
                // NSLog ไม่ใช่ print — print() ไม่โผล่ใน unified log ของ simulator
                NSLog("[Map3DScreen] โหลด map.usdz ไม่สำเร็จ (ใช้เวลา %.2f วิ)", elapsed)
            } else {
                NSLog("[Map3DScreen] โหลด map.usdz เสร็จใน %.2f วิ", elapsed)
            }
            self?.loaded = entity
            self?.loading = nil
        }
    }

    /// ของที่โหลดแล้ว · ยังโหลดไม่เสร็จ = รอรอบเดิม ไม่เริ่มใหม่ซ้อน · nil = โหลดไม่สำเร็จ
    ///
    /// คืน entity ตัวเดียวกันทุกครั้ง ไม่ clone — โคลนโครงสร้าง 1,906 ก้อนแพงพอ ๆ กับโหลดใหม่
    /// ผู้เรียกต้อง `removeFromParent()` ก่อนเอาไปแขวนที่ใหม่ (ดู Map3DScreen)
    func model() async -> Entity? {
        if let loaded { return loaded }
        preload()
        await loading?.value
        return loaded
    }
}
