import RealityKit
import Foundation
import UIKit

/// โหลด `map.usdz` ไว้ล่วงหน้า แล้วเก็บไว้ใช้ตลอดอายุแอป
///
/// วัดจริงบน simulator กับโมเดลใบเก่า: ตั้งแต่ log แรกของแอปถึงบรรทัดที่โมเดลโหลดเสร็จกินไป
/// 7.5 วินาที และระหว่างนั้นแท็บแผนที่ไม่มีอะไรให้ดูเลย · ต้นเหตุอยู่ที่ตัวไฟล์
///
/// ใบปัจจุบัน (Map2.0 เข้ามาแทนใบเดิมเมื่อ 2026-08-20): 9.8 MB แบ่งเป็นเรขาคณิต 3.9 MB กับ
/// texture 4 ใบรวม 5.9 MB (พื้นดิน 3.1, คลื่นน้ำ 1.2, วงปีไม้ 1.2, เปลือกไม้ 0.4) ข้างในมี mesh
/// แยกกัน 2,201 ก้อน RealityKit จึงต้องสร้าง entity กับ material แยกกันสองพันกว่าชุด
/// (ใบเดิม 11 MB / 1,906 mesh / texture 6.2 MB — mesh มากขึ้น 15% แต่ texture เล็กลงครึ่ง
/// สุทธิแล้ว **ช้าลง** ไม่ใช่เร็วขึ้น: วัดจริงได้ 8.18 วิ เทียบ 7.5 วิของใบเดิม
/// ดู `docs/map-2-0-verification.md` แถว 8)
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

    /// สั่ง `playAnimation` ให้ก้อนเมฆในโมเดลไปแล้วหรือยัง — ครั้งเดียวต่อโมเดลที่โหลดอยู่ในมือ
    /// (ไม่ใช่ครั้งเดียวต่อการเปิดแอป เพราะโมเดลอาจถูกปล่อยแล้วโหลดใหม่กลางอายุแอป ดู
    /// `releaseIfPossible()`) เก็บที่นี่ด้วยเหตุผลเดียวกับ `hasPlayedIntro`/`hasShownPinHint`
    ///
    /// **จอถูก mount ใหม่ตอนไหนกันแน่:** ไม่ใช่ตอนสลับแท็บ — `TabView` ของ iOS 18 ถือ view ของ
    /// ทุกแท็บไว้ สลับออกแล้วกลับมา `Map3DScreen.make` ไม่ถูกเรียกซ้ำ · ทางที่เกิดจริงคือ
    /// **ล็อกเอาต์แล้วล็อกอินใหม่โดยไม่ปิดแอป**: `RootView` แขวน `MainTabView` ไว้เฉพาะตอน
    /// session อยู่ที่ `.home` จอแผนที่จึงถูกทำลายและสร้างใหม่ทั้งใบ ขณะที่ singleton ตัวนี้อายุ
    /// เท่าแอปและไม่มีอะไรในเส้นทาง logout ล้างมันเลย · `model()` ก็คืน entity ตัวเดิมที่ไม่ clone
    /// ถ้าไม่กันไว้ การไล่ต้นแล้วสั่ง `playAnimation` ซ้ำจะรีเซ็ตแอนิเมชันที่กำลังเล่นอยู่กลับไป
    /// เฟรม 0 (เมฆกระตุกเห็นชัด) และซ้อน playback controller ตัวใหม่ทับตัวเดิมที่ไม่มีใครหยุด
    var hasStartedCloudAnimations = false

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
        // โมเดลรอบหน้าคือ entity ใหม่ที่ยังไม่เคยสั่งแอนิเมชันเลย ถ้าไม่รีเซ็ตตรงนี้ ธง
        // จะค้าง true ข้ามไปจากโมเดลใบเก่า แล้ว Map3DScreen จะไม่สั่ง playAnimation ให้ใบใหม่
        // เลยตลอดไป — เมฆแข็งค้างถาวรทันทีที่เจอ memory warning หนึ่งครั้ง โดยไม่มีอะไร log แจ้ง
        hasStartedCloudAnimations = false
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
    /// คืน entity ตัวเดียวกันทุกครั้ง ไม่ clone — โคลนโครงสร้าง 2,201 ก้อนแพงพอ ๆ กับโหลดใหม่
    /// ผู้เรียกต้อง `removeFromParent()` ก่อนเอาไปแขวนที่ใหม่ และต้องล้าง scale/position ที่ตัวเอง
    /// เขียนไว้รอบก่อนก่อนวัดขนาดใหม่ด้วย (ดู Map3DScreen — ไม่ล้างแล้วรอบสองสเกลเพี้ยน 2,584 เท่า)
    func model() async -> Entity? {
        if let loaded { return loaded }
        preload()
        await loading?.value
        return loaded
    }
}
