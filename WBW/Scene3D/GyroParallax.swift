import CoreMotion
import SwiftUI
import simd

/// เอียงเครื่องแล้วฉากขยับ — เวอร์ชันมือถือของ pointer parallax ที่เว็บทำใน CameraRig
///
/// เลื่อน "ตำแหน่ง" กล้องแล้ว lookAt จุดเดิม ไม่ใช่หมุนกล้อง — ของใกล้กับของไกลจึง
/// ขยับไม่เท่ากัน ได้ความรู้สึกเป็นหน้าต่างจริง ถ้าหมุนกล้องเฉยๆ ทุกอย่างจะเลื่อนพร้อมกัน
@MainActor
final class GyroParallax: ObservableObject {
    /// ขอบที่สคริปต์ bake เผื่อไว้ (GYRO_MARGIN = 1.25) — เกินกว่านี้เห็นขอบฉาก
    ///
    /// nonisolated เหมือน mapAttitude ด้านล่าง — ทั้งสองตัวเป็นค่าคงที่ล้วนๆ ไม่มีเหตุผลต้องอยู่หลัง
    /// @MainActor ของ class เลย ถ้าไม่ประกาศตรงนี้ mapAttitude (nonisolated) จะอ่านค่าทั้งคู่ไม่ได้ —
    /// เจอจริงเป็น warning ตอน build เต็ม ("main actor-isolated static property ... can not be
    /// referenced from a nonisolated context; this is an error in the Swift 6 language mode")
    nonisolated static let maxOffsetX: Float = 1.1
    nonisolated static let maxOffsetY: Float = 0.4

    @Published private(set) var offset = SIMD2<Float>(0, 0)

    private let motion = CMMotionManager()
    private var running = false

    /// true ถ้าเครื่องนี้มีฮาร์ดแวร์ที่ device motion ใช้ได้ (ในซิมูเลเตอร์เป็น false เสมอ — ไม่มี
    /// motion hardware จริง) เป็นข้อเท็จจริงของฮาร์ดแวร์ ไม่เปลี่ยนตลอดอายุ process รู้ได้ทันทีตั้งแต่
    /// เฟรมแรกโดยไม่ต้องรอ start()/callback แรกมาถึงก่อน — ForestSceneView ใช้ค่านี้ (ไม่ใช่ `running`)
    /// ตัดสินใจว่า TimelineView schedule ต้อง tick ต่อเฟรมไหมตอนยังไม่มีต้นไม้ในฉาก (ดูคอมเมนต์ที่
    /// sceneShouldTick) เหตุผลที่ไม่ใช้ `running`: `running` เปลี่ยนค่า "หลัง" start() ถูกเรียกเท่านั้น
    /// (เป็น side effect ของ onAppear/onChange ที่รันทีหลัง body) ถ้า SwiftUI ประเมิน body รอบแรกไปแล้ว
    /// เห็น running=false เลยตัดสินใจ pause จะไม่มีอะไรมาปลุกให้ประเมินใหม่อีกเลย (`running` เป็น
    /// private var ธรรมดา ไม่ publish) — isAvailable เลี่ยงปัญหานี้เพราะเป็นค่าที่ถูกต้องตั้งแต่แรกอยู่แล้ว
    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    /// map มุมเอียงเป็นระยะเลื่อน · ล้วนๆ ไม่มี side effect เทสได้
    ///
    /// nonisolated ตรงๆ — ทั้ง class เป็น @MainActor แต่ฟังก์ชันนี้ล้วน (ไม่แตะ motion/running/offset
    /// เลย) เทสเรียกแบบ sync ไม่มี await ตามที่บรีฟกำหนด ถ้าไม่ประกาศ nonisolated จะ compile ไม่ผ่าน
    /// ("main actor-isolated static method ... in a synchronous nonisolated context" — เจอจริงตอน
    /// รันเทสรอบแรก) เหมือน pattern ที่ ChatSession.cacheKey(for:) ใช้อยู่แล้ว 2 ที่ในโปรเจกต์นี้
    nonisolated static func mapAttitude(roll: Double, pitch: Double) -> SIMD2<Float> {
        // tanh ให้เอียงน้อยๆ ตอบไว เอียงมากอิ่มตัว ไม่กระชากตอนพลิกเครื่อง
        let x = Float(tanh(roll * 1.6)) * maxOffsetX
        let y = Float(tanh(pitch * 1.2)) * maxOffsetY
        return SIMD2<Float>(min(max(x, -maxOffsetX), maxOffsetX),
                            min(max(y, -maxOffsetY), maxOffsetY))
    }

    func start() {
        guard !running, motion.isDeviceMotionAvailable else { return }
        running = true
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.attitude else { return }
            let raw = Self.mapAttitude(roll: a.roll, pitch: a.pitch)
            // low-pass — เซนเซอร์ดิบสั่นตลอด ถ้าไม่กรองฉากจะสั่นตาม
            self.offset += (raw - self.offset) * 0.12
        }
    }

    /// หยุดตอนฉากถูกซ่อนหรือแอปลงหลัง — เซนเซอร์ที่วิ่งอยู่เฉยๆ กินแบต
    func stop() {
        guard running else { return }
        running = false
        motion.stopDeviceMotionUpdates()
        offset = .zero
    }
}
