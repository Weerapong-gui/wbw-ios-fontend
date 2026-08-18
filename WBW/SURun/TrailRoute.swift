import CoreLocation
import Foundation
import MapKit

/// เส้นทางเดินของงาน — อ่านจากไฟล์ที่ bake ไว้ในแอป ไม่ได้ขอจาก routing service ตอนรัน
///
/// `WBW/Resources/route_wbw.json` เป็น **ไฟล์เดียวกัน** กับที่แอป Android ใช้
/// (`app/src/main/res/raw/route_wbw.json`) — ต้นทางคือ `route.gpx` ที่ผู้จัดงาน export จาก
/// Google Maps · ก๊อปข้ามมาแทนที่จะแปลง GPX เองในแอป เพราะสองแอปต้องลากเส้นเดียวกันเป๊ะ
/// ถ้าเส้นทางเปลี่ยน ให้ regenerate ฝั่ง Android แล้วก๊อปทับที่นี่ อย่าแก้ทีละฝั่ง
struct TrailRoute {
    let points: [CLLocationCoordinate2D]
    /// ระยะรวมตามเส้นทาง หน่วยเมตร — มาจากไฟล์ ไม่ได้คำนวณใหม่ จะได้ตรงกับที่ Android โชว์
    let distanceMetres: Int

    var start: CLLocationCoordinate2D? { points.first }
    var finish: CLLocationCoordinate2D? { points.last }

    /// กรอบที่พอดีทั้งเส้น + ขอบเผื่อ — ใช้ตั้งกล้องตอนเปิดจอ
    var region: MKCoordinateRegion {
        guard let first = points.first else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 20.0466, longitude: 99.9014),
                                      span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLng = first.longitude, maxLng = first.longitude
        for p in points {
            minLat = min(minLat, p.latitude);  maxLat = max(maxLat, p.latitude)
            minLng = min(minLng, p.longitude); maxLng = max(maxLng, p.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLng + maxLng) / 2),
            // คูณ 1.35 กันเส้นชนขอบจอพอดีจนดูเหมือนถูกตัด
            span: MKCoordinateSpan(latitudeDelta: max(maxLat - minLat, 0.002) * 1.35,
                                   longitudeDelta: max(maxLng - minLng, 0.002) * 1.35))
    }

    // MARK: - อ่านไฟล์

    private struct File: Decodable {
        let polyline: String
        let distanceMetres: Int
        enum CodingKeys: String, CodingKey {
            case polyline
            case distanceMetres = "distanceMetres"
        }
    }

    static func decode(_ data: Data) -> TrailRoute? {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        return TrailRoute(points: decodePolyline(file.polyline), distanceMetres: file.distanceMetres)
    }

    private final class BundleMarker {}

    /// อ่านครั้งเดียวแล้วถือไว้ — ~2.6 KB กับการ decode ไม่กี่พันจำนวนเต็ม แต่จอ SU RUN
    /// recompose ทุกครั้งที่ตัวเลขบน HUD ขยับ ปล่อยให้อ่านซ้ำคือ decode วินาทีละหลายรอบ
    ///
    /// ต้องลอง `Bundle(for:)` ก่อน `Bundle.main` เพราะตอนรันในชุดเทส `Bundle.main` คือตัวรันเทส
    /// ไม่ใช่ตัวแอป — หาไฟล์ไม่เจอแล้วเทสจะแดงด้วยเหตุผลที่ไม่เกี่ยวกับเนื้อหาที่ทดสอบเลย
    static let bundled: TrailRoute? = {
        for bundle in [Bundle(for: BundleMarker.self), Bundle.main] {
            if let url = bundle.url(forResource: "route_wbw", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let route = decode(data) {
                return route
            }
        }
        return nil
    }()

    // MARK: - Encoded Polyline Algorithm (precision 5)

    /// ถอดรหัสเส้นแบบเดียวกับ `decodePolyline` ใน `ui/map/TrailRoute.kt` ของ Android
    ///
    /// ผิดตรงไหนนิดเดียวจะได้เส้นที่ยัง "ลากได้" แต่ไปโผล่คนละซีกโลก ไม่มี error ให้เห็นเลย
    /// มีแต่แผนที่ว่างเปล่าเพราะกล้องไปจ่ออยู่กลางทะเล — จึงตรึงไว้ด้วยเวกเตอร์ตัวอย่างของ Google
    static func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        var points: [CLLocationCoordinate2D] = []
        let chars = Array(encoded.utf8)
        var index = 0, lat = 0, lng = 0

        func nextDelta() -> Int? {
            var shift = 0, result = 0
            while index < chars.count {
                let byte = Int(chars[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20 {
                    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
                }
            }
            return nil   // สตริงขาดกลางคัน — หยุด ไม่ใช่คืนจุดครึ่ง ๆ กลาง ๆ
        }

        while index < chars.count {
            guard let dLat = nextDelta(), let dLng = nextDelta() else { break }
            lat += dLat
            lng += dLng
            points.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e5,
                                                 longitude: Double(lng) / 1e5))
        }
        return points
    }
}
