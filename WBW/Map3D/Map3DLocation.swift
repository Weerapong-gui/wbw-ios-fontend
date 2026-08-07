import CoreLocation
import Foundation

/// ตำแหน่งผู้ใช้สำหรับจุดบนแผนที่ — บางที่สุดเท่าที่พอใช้ ไม่มี background, ไม่มี heading
///
/// ไม่ให้สิทธิ์หรือหาไม่เจอ = coordinate เป็น nil เงียบๆ จอที่เหลือใช้งานได้ปกติ
/// (คนเปิดแอปจากบ้านก่อนวันงานเป็นเรื่องปกติ ไม่ใช่ความผิดพลาดที่ต้องแจ้ง)
@MainActor
final class Map3DLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // 10 เมตร: จุดบนโมเดลกว้าง ~4 กม. ขยับถี่กว่านี้ตาไม่เห็นความต่าง แต่กินแบตเพิ่ม
        manager.distanceFilter = 10
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.coordinate = last.coordinate }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in self.coordinate = nil }
    }
}
