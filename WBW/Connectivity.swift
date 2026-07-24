import Foundation
import Network

/// เฝ้าสถานะเน็ต — แจ้ง reconnect (offline→online) ให้ ChatStore flush คิว
@MainActor
final class Connectivity: ObservableObject {
    @Published var online = true
    var onReconnect: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "wbw.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let was = self.online
                self.online = up
                if !was && up { self.onReconnect?() }   // กลับมามีเน็ต → flush
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
