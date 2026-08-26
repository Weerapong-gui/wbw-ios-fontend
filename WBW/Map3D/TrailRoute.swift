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

    // MARK: - ความคืบหน้าบนเส้น (ยกจาก TrailRoute.kt ของ Android — สัญญาเดียวกันสองแอป)

    /// เส้นในหน่วยเมตรระนาบ local: ตะวันออก/เหนือจากจุดกลางเส้น (equirectangular ล้วน ๆ)
    /// กล่องกว้างสองกิโล error เทียบ geodesic จริงอยู่ระดับเซนติเมตร — คำถามที่ถามมัน
    /// ("เส้นวิ่งไปทางไหนตรงนี้") ตอบเป็นองศาอยู่แล้ว
    private let originLat: Double
    private let originLng: Double
    private let metresPerDegLng: Double
    private let east: [Double]
    private let north: [Double]
    /// ระยะสะสมตามเส้นที่แต่ละจุด — วัดจาก projection เดียวกัน ไม่ใช่ `distanceMetres`
    /// จากไฟล์ ไม่งั้นตำแหน่งบน segment i แปลงกลับเป็น "เดินมาแล้วกี่เมตร" ไม่ได้ และการเดิน
    /// จะจบที่ 99.8% เพราะเลขสองแหล่งไม่ตรงกันไม่กี่เมตร
    private let cumulative: [Double]

    init(coordinates: [CLLocationCoordinate2D], distanceMetres: Int) {
        self.coordinates = coordinates
        self.distanceMetres = distanceMetres

        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)
        let oLat = ((lats.min() ?? 0) + (lats.max() ?? 0)) / 2
        let oLng = ((lngs.min() ?? 0) + (lngs.max() ?? 0)) / 2
        originLat = oLat
        originLng = oLng
        let mLng = Self.metresPerDegree * cos(oLat * .pi / 180)
        metresPerDegLng = mLng
        east = coordinates.map { ($0.longitude - oLng) * mLng }
        north = coordinates.map { ($0.latitude - oLat) * Self.metresPerDegree }
        var c = [Double](repeating: 0, count: coordinates.count)
        for i in 1..<max(coordinates.count, 1) {
            c[i] = c[i - 1] + hypot(east[i] - east[i - 1], north[i] - north[i - 1])
        }
        cumulative = c
    }

    /// ความยาวเส้นในหน่วยเดียวกับที่วัดความคืบหน้า
    var lengthMetres: Double { cumulative.last ?? 0 }

    private static let metresPerDegree = 111_320.0
    /// ห่างเส้นเกินนี้ = ไม่อยู่บนเส้น — คืน nil ให้ผู้เรียกถือค่าเดิม ไม่ใช่เดามั่ว
    private static let offRouteMetres = 120.0
    /// หน้าต่างไปข้างหน้า — กว้าง เพราะเครื่องที่สัญญาณหายในหุบอาจโผล่ขึ้นมาไกลหลายร้อยเมตรจริง
    private static let forwardWindowMetres = 400.0
    /// หน้าต่างถอยหลัง — แคบ เพราะ GPS สั่นระดับเมตรและคนเดินย้อนจริงหายาก กว้างไป noise
    /// จะลากความคืบหน้าถอยลง
    private static let backWindowMetres = 30.0

    /// เดินมาแล้วกี่เมตร จากตำแหน่งปัจจุบัน + ค่าครั้งก่อน
    ///
    /// **ทำไมต้องมีค่าครั้งก่อน** — เส้นช่วง ~4.2 กม. เฉียดช่วง ~4.6 กม. ในระยะ ~120 ม.
    /// ซึ่งอยู่ในช่วง error ของมือถือใต้ร่มไม้ nearest-point ล้วน ๆ จึงกำกวมตรงจุดที่พลาด
    /// แล้วเจ็บสุดพอดี — fix เพี้ยนครั้งเดียวคนถูกบอกว่าเหลืออีก 900 ม. ที่เดินไปแล้ว
    /// การค้นต่อจากที่อยู่เดิมแก้แบบเดียวกับที่คนแก้: มาถึงตรงนี้ได้เพราะเดินมา ก็ต้องอยู่แถวเดิม
    ///
    /// ส่ง [fromMetres] ติดลบสำหรับ fix แรก — ค้นทั้งเส้น (ไม่มีที่เดิมให้ใกล้ และคนมา join
    /// กลางทางได้จริง) · คืน nil เมื่อห่างเส้นเกิน `offRouteMetres` — ผู้เรียกถือค่าเดิม
    /// ไม่ใช่ "กลับไปเริ่มต้น" · ไม่มีวันคืนค่าน้อยกว่าที่มี — เส้นบนจอห้ามกระตุกถอยเพราะ noise
    func progressFrom(_ fromMetres: Double, coordinate: CLLocationCoordinate2D) -> Double? {
        guard coordinates.count >= 2 else { return nil }
        let px = (coordinate.longitude - originLng) * metresPerDegLng
        let py = (coordinate.latitude - originLat) * Self.metresPerDegree

        let acquiring = fromMetres < 0
        let lo = acquiring ? -Double.infinity : fromMetres - Self.backWindowMetres
        let hi = acquiring ? Double.infinity : fromMetres + Self.forwardWindowMetres

        var bestAlong = -1.0
        var bestDistSq = Double.greatestFiniteMagnitude
        for i in 0..<(coordinates.count - 1) {
            // segment ที่อยู่นอกหน้าต่างทั้งท่อน ข้ามก่อนทำงานใด ๆ กับมัน
            if cumulative[i + 1] < lo || cumulative[i] > hi { continue }

            let ax = east[i], ay = north[i]
            let dx = east[i + 1] - ax, dy = north[i + 1] - ay
            let lenSq = dx * dx + dy * dy
            let t = lenSq <= 0 ? 0 : min(max(((px - ax) * dx + (py - ay) * dy) / lenSq, 0), 1)
            let qx = ax + t * dx - px
            let qy = ay + t * dy - py
            let distSq = qx * qx + qy * qy
            if distSq < bestDistSq {
                bestDistSq = distSq
                bestAlong = cumulative[i] + t * hypot(dx, dy)
            }
        }

        if bestAlong < 0 || bestDistSq > Self.offRouteMetres * Self.offRouteMetres { return nil }
        return acquiring ? bestAlong : max(fromMetres, bestAlong)
    }

    /// ตัดเส้นเป็นสองท่อนที่ [metres]: เดินแล้ว กับ ที่เหลือ
    ///
    /// จุดตัด interpolate ใน segment ที่มันตก และเป็น**จุดท้ายของท่อนแรกพร้อมกับจุดหัวของ
    /// ท่อนหลัง** — สองเส้นที่วาดจึงชนกันพอดี ไม่ใช่ช่องว่างที่กว้างตามความยาว segment ·
    /// ท่อนไหนว่างได้ (เพิ่งเริ่ม = ยังไม่เดิน, จบแล้ว = ไม่เหลือ) — ผู้วาดต้องข้าม polyline
    /// ที่มีน้อยกว่าสองจุด ไม่ใช่ยัดเส้นพิการให้ MapKit
    func splitAt(_ metres: Double) -> (walked: [CLLocationCoordinate2D], remaining: [CLLocationCoordinate2D]) {
        guard coordinates.count >= 2 else { return ([], coordinates) }
        let d = min(max(metres, 0), lengthMetres)

        var seg = 0
        while seg < coordinates.count - 2 && cumulative[seg + 1] < d { seg += 1 }

        let segLen = cumulative[seg + 1] - cumulative[seg]
        let t = segLen <= 0 ? 0 : min(max((d - cumulative[seg]) / segLen, 0), 1)
        let a = coordinates[seg]
        let b = coordinates[seg + 1]
        let cut = CLLocationCoordinate2D(latitude: a.latitude + t * (b.latitude - a.latitude),
                                         longitude: a.longitude + t * (b.longitude - a.longitude))

        let walked = Array(coordinates[0...seg]) + [cut]
        let remaining = [cut] + Array(coordinates[(seg + 1)...])
        return (walked, remaining)
    }

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
