import SwiftUI
import MapKit

/// ลิงก์เปิด Apple Maps ที่จุดเกิดเหตุ
///
/// เดิมสตริงนี้ถูกเขียนซ้ำสองที่ (`StaffSOSView` กับ `SOSFriendView`) ด้วยมือทั้งคู่ —
/// แก้ที่เดียวลืมอีกที่คือสิ่งที่เกิดแน่นอนกับโค้ดรูปนี้ ยิ่งเป็นทางที่ใช้ตอนฉุกเฉิน
enum SOSMapLink {
    static func appleMaps(lat: Double, lng: Double) -> URL? {
        // `q=` เป็นป้ายกำกับหมุด ไม่ใช่คำค้น — Apple Maps โชว์มันใต้หมุดที่พิกัด `ll=`
        // ตรวจแล้วว่า `URL(string:)` เข้ารหัสตัวอักษรไทยให้เองบน Foundation ปัจจุบัน
        // แต่เข้ารหัสเองไว้ชัดกว่า ไม่ต้องพึ่งความใจดีของ parser
        let label = Loc.t("sos_map_pin_label")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "maps://?ll=\(lat),\(lng)&q=\(label)")
    }
}

/// กรอบแผนที่ของเคสหนึ่งใบ — **ฟังก์ชันบริสุทธิ์ ไม่แตะ MapKit runtime**
///
/// เจ้าหน้าที่อ่านแผนที่นี้ตอนกำลังจะวิ่งไปหาผู้บาดเจ็บ ซูมผิดทางไหนก็ใช้ไม่ได้ทั้งคู่ —
/// แน่นเกินไปเห็นแค่ทางเท้าโดยไม่รู้ว่าอยู่ตรงไหนของเส้นทาง กว้างเกินไปหมุดกลายเป็นจุดเดียว
enum SOSCaseMap {
    /// เล็กที่สุดที่ยังเห็นบริบทรอบตัว (ม. ต่อด้าน)
    ///
    /// **วัดจากจอจริง ไม่ใช่เดา** — ตั้งไว้ 180 ม. ตอนแรกแล้วถ่ายดู ได้พื้นเขียวเปล่าทั้งกรอบ
    /// เพราะพื้นที่งานเป็นป่าบนดอย ที่ระยะนั้นไม่มีถนน ไม่มีชื่อสถานที่ ไม่มีอะไรให้เทียบเลย
    /// แผนที่ที่ไม่มีที่หมายไม่ได้บอกอะไรมากกว่าตัวเลขพิกัดที่อยู่บรรทัดบน · 500 ม. เริ่มเห็น
    /// เส้นทางกับอาคาร ซึ่งเป็นสิ่งที่คนกำลังจะวิ่งไปหาต้องใช้จริง
    static let minSpanMetres: Double = 500
    /// ใหญ่ที่สุดที่แผนที่ยังบอกอะไรได้ — เลยนี้ไปข้อความ "พิกัดหยาบ" บนการ์ดทำหน้าที่แทน
    static let maxSpanMetres: Double = 3_000
    /// ระยะที่หนึ่งองศาละติจูดกินจริง คงที่ทั้งโลก (ต่างจากลองจิจูดที่หดตามละติจูด)
    static let metresPerDegreeLatitude: Double = 111_320

    static func region(lat: Double, lng: Double, accuracyM: Double?) -> MKCoordinateRegion {
        // กรอบต้องกว้างกว่า**เส้นผ่านศูนย์กลาง**ของวง (รัศมี × 2) แล้วเผื่อขอบอีก 1.6 เท่า
        // ไม่งั้นวงที่วาดจะล้นจอ แล้วเจ้าหน้าที่เห็นแค่ส่วนหนึ่งของมัน ซึ่งอ่านผิดเป็น
        // "อยู่ในบริเวณแค่นี้" ทั้งที่จริงกว้างกว่าที่เห็น
        let wanted = (accuracyM ?? 0) * 2 * 1.6
        let span = min(max(wanted, minSpanMetres), maxSpanMetres)

        let latDelta = span / metresPerDegreeLatitude
        // หนึ่งองศาลองจิจูดสั้นกว่าหนึ่งองศาละติจูดตาม cos(lat) — ที่ 20°N ราว 6%
        // ลืมหารแล้วกรอบจะแคบไปตามแนวตะวันออก-ตะวันตก (หลักการเดียวกับ `Map3DGeo`)
        let shrink = max(cos(lat * .pi / 180), 0.01)   // กันหารศูนย์ที่ขั้วโลก
        let lngDelta = latDelta / shrink

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta))
    }
}

/// แผนที่นิ่งในการ์ดเคส · แตะแล้วออกไปนำทางต่อที่ Apple Maps
///
/// **ห้ามใส่ `UserAnnotation()` เด็ดขาด** — บันทึกไว้ตั้งแต่จอ SU RUN (ถอดออกแล้ว) ว่า MapKit ขอสิทธิ์ตำแหน่งเอง
/// ทันทีที่เห็นตัวนั้นในฉาก · เจ้าหน้าที่ต้องเห็นตำแหน่ง**ผู้บาดเจ็บ** ไม่ใช่ของตัวเอง
/// การเพิ่มมันได้แค่กล่องขอสิทธิ์ที่ไม่มีเหตุผลจะขอ
struct SOSCaseMapView: View {
    let lat: Double
    let lng: Double
    let accuracyM: Double?
    /// วาดวงความคลาดเคลื่อนไหม — จริงเฉพาะตอน `SOSStaffCase.isCoarse` (แม่นแย่กว่า 200 ม.)
    /// ซึ่งเป็นตอนที่หมุดโกหกได้ · พิกัดแม่นไม่ต้องมีวง วงเล็ก ๆ รอบหมุดอ่านเป็นของประดับ
    let showsAccuracy: Bool

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var body: some View {
        map
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            // แผนที่นิ่งไม่มีอะไรบอกว่ากดได้ — ปุ่ม "เปิดแผนที่" ใต้การ์ดคือป้ายของมัน
            // ตัวแผนที่เป็นทางลัดที่นิ้วเจอก่อนเพราะใหญ่กว่ามาก
            .accessibilityLabel(Loc.t("sos_map_open"))
    }

    @ViewBuilder
    private var map: some View {
        let content = Map(initialPosition: .region(
            SOSCaseMap.region(lat: lat, lng: lng, accuracyM: accuracyM)),
            interactionModes: []) {
                if showsAccuracy, let accuracyM {
                    MapCircle(center: coordinate, radius: accuracyM)
                        .foregroundStyle(.orange.opacity(0.18))
                        .stroke(.orange, lineWidth: 1.5)
                }
                Marker("", systemImage: "sos", coordinate: coordinate)
                    .tint(.red)
            }
            // ป้ายร้านค้าไม่ใช่สิ่งที่ต้องอ่านตอนนี้
            .mapStyle(.standard(pointsOfInterest: .excludingAll))

        if let url = SOSMapLink.appleMaps(lat: lat, lng: lng) {
            Link(destination: url) { content }
        } else {
            content
        }
    }
}
