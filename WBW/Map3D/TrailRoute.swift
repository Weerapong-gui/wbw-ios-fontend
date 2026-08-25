import CoreLocation
import Foundation
import MapKit

/// เส้นทางเดินของงาน อบมากับแอป — ยกไฟล์มาจาก Android
/// (`app/src/main/res/raw/route_wbw.json` ของ repo Student-Union-WBW-Andriod)
///
/// **ตอนนี้สองแอปใช้เส้นเดียวกันแล้ว (2026-08-25)** — ยกไฟล์จาก branch `work` ของ Android
/// ซึ่งเปลี่ยนไปใช้ `newroute.gpx` ของผู้จัดงาน (คนละลิงก์ Google Maps กับ `route.gpx` เดิม)
/// · 504 จุด 5,126 ม. เริ่มที่วัดพระเจ้าล้านทอง จบทางตะวันออกเฉียงเหนือที่ (20.05671, 99.90875)
/// · หัวท้ายตรงกับชุดเดิมของ iOS พอดี ต่างกันที่ทางช่วงกลาง — หมุดฐานทั้งแปดจึงยังอยู่ห่างจาก
/// เส้นเท่าเดิมทุกหมุด (ตรวจแล้วตอนเปลี่ยน: ไกลสุด 47.9 ม. ที่ฐาน 1 เท่ากันทั้งเส้นเก่าและใหม่)
/// · ที่มาของตัวเลขทั้งหมดอยู่ใน `_comment` ของไฟล์ JSON — **regenerate จาก `newroute.gpx`
/// ไม่ใช่ `route.gpx` ที่ตายไปแล้ว**
///
/// เป็นค่าคงที่ ไม่ใช่ของที่ยิงมาจากเซิร์ฟเวอร์ ตามเหตุผลที่ต้นทางเขียนไว้: เส้นทางไม่เปลี่ยน
/// ระหว่างงาน การถาม routing service ทุกครั้งที่เปิดแอปคือการจ่ายโควตาเพื่อให้ได้เส้นเดิมกลับมา
/// — และที่สำคัญกว่านั้น เส้นต้องวาดได้บนเครื่องที่ไม่มีสัญญาณกลางดอย ซึ่งเป็นสภาพที่แอปนี้ถูกใช้จริง
///
/// เก็บเป็นไฟล์ไม่ใช่ค่าคงที่ในโค้ดด้วยเหตุผลเดียวกับ `map_config.json`: มันคือข้อมูลที่ถูก
/// **สร้าง**ขึ้นจาก GPX ของผู้จัดงาน ไม่ใช่ค่าที่คนพิมพ์ เปลี่ยนเส้นทางคือเปลี่ยนไฟล์ไฟล์เดียว
struct TrailRoute {
    /// ทุกจุดบนเส้นทาง เรียงตามลำดับการเดิน
    let coordinates: [CLLocationCoordinate2D]
    /// ระยะทางตามพื้น หน่วยเมตร — มาจากไฟล์ ไม่ได้คำนวณใหม่ตอนรัน
    let distanceMetres: Int

    var start: CLLocationCoordinate2D { coordinates.first ?? kCLLocationCoordinate2DInvalid }
    var end: CLLocationCoordinate2D { coordinates.last ?? kCLLocationCoordinate2DInvalid }

    /// กรอบกล้องตอนเปิดแผนที่ — ครอบเส้นทั้งเส้นแล้วเผื่อขอบอีก 15%
    ///
    /// เผื่อขอบเพราะกรอบที่พอดีเป๊ะจะวางหมุด START/FINISH ไว้ชิดขอบจอ ซึ่งเป็นสองจุดที่คน
    /// มองหาก่อนอย่างอื่น · ไม่เผื่อมากกว่านี้เพราะทุกเปอร์เซ็นต์ที่เผื่อคือเส้นทางที่เล็กลงบนจอ
    var region: MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(center: kCLLocationCoordinate2DInvalid,
                                      span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0))
        }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLat = latitudes.min()!, maxLat = latitudes.max()!
        let minLon = longitudes.min()!, maxLon = longitudes.max()!

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.15,
                                   longitudeDelta: (maxLon - minLon) * 1.15))
    }

    // MARK: - อ่านไฟล์

    private struct File: Decodable {
        let distanceMetres: Int
        let polyline: String
    }

    static func decode(_ data: Data) -> TrailRoute? {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        let points = decodePolyline(file.polyline)
        // เส้นที่เหลือจุดเดียวไม่ใช่เส้น — ปฏิเสธตั้งแต่ตรงนี้ดีกว่าปล่อยให้จอวาด polyline ว่าง
        // แล้วดูเหมือนแผนที่ที่ "ไม่มีเส้นทางของงานนี้"
        guard points.count > 1, file.distanceMetres > 0 else { return nil }
        return TrailRoute(coordinates: points, distanceMetres: file.distanceMetres)
    }

    private final class BundleMarker {}

    /// ต้องลอง `Bundle(for:)` ก่อน `Bundle.main` เพราะตอนรันในชุดเทส `Bundle.main` คือตัวรันเทส
    /// ไม่ใช่ตัวแอป (แพทเทิร์นเดียวกับ `Map3DConfig.bundled`)
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

    // MARK: - ตัวถอดรหัส polyline ของ Google

    /// ถอด Encoded Polyline Algorithm Format — รูปแบบเดียวกับที่ Maps SDK ฝั่ง Android ถอดให้เอง
    ///
    /// ต้องเขียนเองเพราะ MapKit ไม่มีตัวถอดให้ (Google เก็บของตัวเองไว้ใน SDK ของตัวเอง) ·
    /// สามขั้นตามสเปก: อ่านทีละ 5 บิตจนเจอไบต์ที่ไม่มีบิตต่อ (0x20) → เลื่อนกลับ →
    /// คลาย zigzag (บิตท้ายคือเครื่องหมาย) · ค่าที่ได้เป็นผลต่างจากจุดก่อนหน้า หน่วย 1e-5 องศา
    ///
    /// **ไม่ throw และไม่ตัดจบกลางคัน** ข้อมูลที่พังจะได้จุดเพี้ยนออกมา ซึ่งถูกจับด้วยกรอบ
    /// พื้นที่งานใน `TrailRouteTests` แทน — ตัวถอดที่ยอมคืนของครึ่ง ๆ กลาง ๆ อ่านง่ายกว่า
    /// ตัวถอดที่มีทางล้มเหลวหลายทางให้ผู้เรียกต้องแยกแยะ
    static func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        var points: [CLLocationCoordinate2D] = []
        var index = encoded.startIndex
        var latitudeE5 = 0, longitudeE5 = 0

        func nextValue() -> Int? {
            var result = 0
            var shift = 0
            while index < encoded.endIndex {
                guard let ascii = encoded[index].asciiValue else { return nil }
                index = encoded.index(after: index)
                let chunk = Int(ascii) - 63
                result |= (chunk & 0x1F) << shift
                shift += 5
                if chunk < 0x20 {
                    // บิตท้ายคือเครื่องหมาย (zigzag) — เลขคี่คือค่าลบ
                    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
                }
            }
            return nil
        }

        while index < encoded.endIndex {
            guard let deltaLatitude = nextValue(), let deltaLongitude = nextValue() else { break }
            latitudeE5 += deltaLatitude
            longitudeE5 += deltaLongitude
            points.append(CLLocationCoordinate2D(latitude: Double(latitudeE5) / 1e5,
                                                 longitude: Double(longitudeE5) / 1e5))
        }
        return points
    }
}
