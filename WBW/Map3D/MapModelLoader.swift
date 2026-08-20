import RealityKit
import Foundation
import UIKit

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

    /// แอนิเมชันบินทะลุเมฆเล่นไปแล้วหรือยัง — ครั้งเดียวต่อการเปิดแอป
    /// เก็บไว้ที่นี่เพราะเป็น singleton ที่มีอายุเท่าแอปอยู่แล้ว ไม่ต้องสร้างที่เก็บสถานะใหม่
    var hasPlayedIntro = false

    /// คำใบ้ "แตะหมุดสีแดงเพื่อดูฐาน" โผล่ไปแล้วหรือยัง — ครั้งเดียวต่อการเปิดแอป
    /// เก็บที่เดียวกับ hasPlayedIntro ด้วยเหตุผลเดียวกัน (singleton ที่อายุเท่าแอปอยู่แล้ว)
    var hasShownPinHint = false

    /// มีจอไหนกำลังใช้โมเดลอยู่ไหม — `Map3DScreen` เขียนค่านี้ตาม `isActive` ของแท็บ
    ///
    /// จำเป็นเพราะการคืนหน่วยความจำเป็นเรื่องของ "จังหวะ" ล้วน ๆ: entity ตัวเดียวกันนี้แขวนอยู่ใน
    /// ฉากที่ RealityView กำลังเรนเดอร์ ปล่อยตอนนั้นแผนที่จะหายไปเฉย ๆ ไม่มี error ให้เห็น
    var isInUse = false

    private var loaded: Entity?
    private var loading: Task<Void, Never>?

    /// มีโมเดลอยู่ในมือหรือกำลังโหลดอยู่ไหม — เผยไว้ให้เทสพิสูจน์ได้ว่า `preload()` ไม่ได้เริ่ม
    /// งานจริงตอนรันเทส (ดู MapModelLoaderTests)
    var isBusy: Bool { loaded != nil || loading != nil }

    private init() {
        // คืนของ 10 MB ตอนระบบขอ ไม่ใช่ตอนออกจากแท็บ — ออกจากแท็บแล้วปล่อยทุกครั้งแปลว่า
        // กลับเข้ามาทีไรก็รอโหลดใหม่ 7.5 วิทุกรอบ ซึ่งแย่กว่าการถือ 10 MB ไว้บนเครื่องยุคนี้
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main) { _ in
                Task { @MainActor in MapModelLoader.shared.releaseIfPossible() }
            }
    }

    /// ปล่อยได้ไหม — แยกเป็นฟังก์ชันบริสุทธิ์เพื่อให้เทสจับกฎนี้ได้โดยไม่ต้องแตะ Entity จริง
    nonisolated static func shouldRelease(inUse: Bool) -> Bool { !inUse }

    /// คืนโมเดลให้ระบบถ้าตอนนี้ไม่มีใครใช้ · รอบหน้าที่มีคนขอจะโหลดใหม่เอง (ดู `model()`)
    func releaseIfPossible() {
        guard Self.shouldRelease(inUse: isInUse) else {
            NSLog("[Map3DScreen] ระบบเตือนความจำ แต่แท็บแผนที่เปิดอยู่ — ไม่ปล่อยโมเดล")
            return
        }
        loading?.cancel()
        loading = nil
        loaded = nil
        NSLog("[Map3DScreen] คืนโมเดลแผนที่ให้ระบบตอนความจำเหลือน้อย")
    }

    /// เริ่มโหลดถ้ายังไม่เริ่ม · เรียกซ้ำได้ ไม่เริ่มงานซ้อน
    ///
    /// **เรียกจาก `RootView` ตอนล็อกอินสำเร็จ** (ย้ายมาจาก `HomeView.task` เมื่อ 2026-08-20)
    /// ไม่ยิงตอนแอป launch เพราะช่วงนั้นยังมีสแปลช/ฉากป่า/ฟอร์มล็อกอินแย่งทรัพยากรกันอยู่
    /// และคนที่ยังไม่ล็อกอินก็ไม่มีทางไปถึงแท็บแผนที่ · ยิงหลังล็อกอินได้เวลาเพิ่มหลายวินาที
    /// ก่อนผู้ใช้จะกดแท็บแผนที่จริง โดยไม่กวนจอไหนเลย
    ///
    /// เจ้าหน้าที่ (`StaffScanView`) ไม่ถูกเรียกให้โหลด — เขาไม่มีแท็บแผนที่ให้เปิด
    func preload() {
        // **ห้ามโหลดตอนรันเทส** — เทสยูนิตรันในโปรเซสเดียวกับแอป พอเทสจบโปรเซส exit() ทันที
        // ขณะที่คิว `com.apple.realityio.live-scene-update-queue` ของ RealityKit ยังไล่ USD stage
        // ของ map.usdz อยู่ → EXC_BAD_ACCESS ใน `TfToken` (มี crash report จริง 2026-08-20)
        //
        // `Map3DScreen.shouldRender` guard ไว้แค่ "เรนเดอร์ไหม" ตัวโหลดเคยหลุดกฎนี้มาตลอด
        // เพิ่งโผล่ตอนย้ายจุดเรียกไป RootView (ยิงทันทีที่ข้ามสแปลช) — เทสจบใน ~1 วิ
        // แต่โมเดลใช้ 6-7 วิ ช่วงที่ทับกันเลยกลายเป็นเกือบทุกรอบแทนที่จะเป็นนาน ๆ ครั้ง
        guard Map3DScreen.shouldRender(map3D: Config.map3D,
                                       underTest: Map3DScreen.isRunningUnderXCTest) else { return }
        guard loaded == nil, loading == nil else { return }
        loading = Task { [weak self] in
            let started = CFAbsoluteTimeGetCurrent()
            let entity = try? await Entity(named: Map3DConfig.current.modelName)
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
