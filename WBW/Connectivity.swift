import Foundation
import Network

/// เฝ้าสถานะเน็ต — แจ้ง reconnect (offline→online) ให้ ChatSession flush คิว
@MainActor
final class Connectivity: ObservableObject {
    /// **เขียนผ่าน `apply(online:)` เท่านั้น** — ไม่งั้น callback สองตัวข้างล่างจะไม่ถูกยิง
    @Published private(set) var online = true
    var onReconnect: (() -> Void)?
    /// สถานะเปลี่ยนทิศไหนก็แจ้ง — `ChatSession` ใช้สะท้อนค่าต่อให้ view (ดู `ChatSession.online`)
    /// ต่างจาก `onReconnect` ที่ยิงเฉพาะขา offline→online
    var onChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "wbw.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor in self?.apply(online: up) }
        }
        monitor.start(queue: queue)
    }

    /// ประตูเดียวที่เขียน `online` — แยกออกมาจาก `pathUpdateHandler` เพื่อให้เทสหน่วยยิง
    /// สถานะเน็ตได้ตรง ๆ โดยไม่ต้องมี `NWPathMonitor` จริง (เทสตัดเน็ตของซิมจากข้างนอกไม่ได้
    /// — ปัญหาเดียวกับที่ `-uitestNotiLoadFailed` มีอยู่แล้ว)
    ///
    /// ค่าเดิมซ้ำ = ไม่แจ้งใครเลย · `NWPathMonitor` ยิงค่าเดิมซ้ำได้ตอนเส้นทางเปลี่ยนแต่ยัง
    /// ออกเน็ตได้เหมือนเดิม (ไวไฟ → มือถือ) ปล่อยผ่านจะกลายเป็น flush คิวรัวโดยไม่มีเหตุ
    func apply(online up: Bool) {
        let was = online
        guard was != up else { return }
        online = up
        onChange?(up)
        if !was && up { onReconnect?() }   // กลับมามีเน็ต → flush
    }

    deinit { monitor.cancel() }
}
