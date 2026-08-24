import CoreLocation
import MapKit
import SwiftUI

/// แผนที่ 2 มิติของเส้นทางเดิน — **ยกทรงมาจาก `ui/map/MapScreen.kt` ของ Android**
/// แต่ใช้ MapKit ของ Apple แทน Google Maps SDK
///
/// ทำไมไม่ใช้ Google Maps SDK ทั้งที่ต้นทางใช้: ฝั่ง iOS จะต้องมี API key ของตัวเอง เปิด billing
/// และรับ dependency ตัวที่สองต่อจาก Firebase เข้ามาในแอปที่ตอนนี้แทบไม่มีของนอกเลย · แลกกับการ
/// ที่สไตล์ป่าเข้มของต้นทาง (`map_style_forest.json`) ใช้ไม่ได้ เพราะ MapKit ปรับสไตล์ไม่ได้ —
/// เลือก `.hybrid` (ภาพถ่ายดาวเทียม + ชื่อสถานที่) แทน ซึ่งอ่านเป็นป่าเข้มจริง ๆ อยู่แล้วและ
/// เข้ากับธีมมืดของทั้งแอป ต่างจาก `.standard` ที่เป็นแผนที่สีอ่อนสว่างกลางแอปมืด
///
/// **จุดตำแหน่งผู้ใช้วาดเอง ไม่ใช้ `UserAnnotation` ของ MapKit** — ตัวนั้นคุยกับ CoreLocation
/// ของมันเอง ซึ่งเป็นเส้นทางที่ประตูกันโหมดเดโม่ใน `Map3DLocation` เอื้อมไม่ถึง · กล่องขอสิทธิ์
/// ที่เด้งในโหมดเดโม่เคยบังสกรีนช็อตชุดส่ง store ไป 9 ใบจาก 10 (ดู `DemoPermissionTests`)
struct Map2DView: View {
    /// ฐานที่เลือกอยู่ — ใช้ binding ตัวเดียวกับแผนที่ 3 มิติ การ์ดจึงเป็นใบเดียวกันจริง ๆ
    @Binding var selectedSequence: Int?
    /// พิกัดผู้ใช้จาก `Map3DLocation` ที่ `Map3DScreen` เป็นเจ้าของ — ผ่านประตูกันโหมดเดโม่มาแล้ว
    let userCoordinate: CLLocationCoordinate2D?

    @EnvironmentObject private var progress: CheckinProgressStore

    @State private var camera: MapCameraPosition = .automatic

    private let route = TrailRoute.bundled
    private let pins = Map3DConfig.current.pins

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
            if let route {
                // เส้นทางวาดสองชั้น ตามเหตุผลที่ต้นทางเขียนไว้: เส้นเดี่ยวหายไปกับสิ่งที่มันพาดผ่าน
                // ชั้นล่างคือเส้นขอบเกือบดำที่แยกเส้นทางออกจากพื้นหลัง ชั้นบนคือเส้นทางจริง —
                // บนภาพดาวเทียมป่าเขียวเข้ม เส้นเขียวเดี่ยว ๆ จะกลืนหายไปทั้งเส้น
                MapPolyline(coordinates: route.coordinates)
                    .stroke(Color.wbwForestVoid, style: StrokeStyle(lineWidth: 9,
                                                                    lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: route.coordinates)
                    .stroke(Color.wbwGreen, style: StrokeStyle(lineWidth: 5,
                                                               lineCap: .round, lineJoin: .round))

                // จุดเริ่มทึบ จุดจบเป็นวง — การอ่านแบบที่ใช้กันทั่วไป และยังอ่านออกตอนไม่มีป้ายกำกับ
                Annotation(Loc.t("map_route_start"), coordinate: route.start) {
                    Circle().fill(Color.wbwGreen)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
                Annotation(Loc.t("map_route_finish"), coordinate: route.end) {
                    Circle().fill(.white.opacity(0.15))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                }
            }

            // หมุดฐาน — **Android ไม่มีอันนี้** เป็นของที่ผู้ใช้ iOS มีอยู่แล้วในโหมด 3 มิติ
            // ถอดออกในโหมดใหม่จะเป็นการถอยหลัง
            ForEach(pins, id: \.sequence) { pin in
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: pin.latitude,
                                                                  longitude: pin.longitude)) {
                    baseBadge(sequence: pin.sequence)
                }
            }

            if let userCoordinate {
                Annotation("", coordinate: userCoordinate) {
                    Circle().fill(Color.wbwGreen)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .shadow(radius: 3)
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
        // ซ่อนตอนการ์ดฐานเปิดอยู่ ด้วยเหตุผลเดียวกับปุ่มสลับโหมดใน `Map3DScreen` —
        // ปุ่มลอยทับการ์ดอ่านเป็นปุ่มของการ์ด
        .overlay(alignment: .bottomTrailing) {
            if selectedSequence == nil { recenterButton }
        }
        .onAppear {
            // กรอบเริ่มต้นคือเส้นทางทั้งเส้น ไม่ใช่ตำแหน่งผู้ใช้ — คนเปิดแอปจากบ้านก่อนวันงาน
            // เป็นเรื่องปกติ และแผนที่ที่เปิดมาที่บ้านตัวเองไม่ได้บอกอะไรเลยเกี่ยวกับงาน
            if let route { camera = .region(route.region) }
        }
    }

    /// ปุ่มกลับมาที่ตัวเอง — ถ้ายังไม่มีพิกัด (ไม่ให้สิทธิ์ / โหมดเดโม่ / อยู่บ้าน) ให้กลับไป
    /// กรอบเส้นทางทั้งเส้นแทน ไม่ใช่ปุ่มที่กดแล้วเงียบ
    ///
    /// วางเหนือปุ่มสลับโหมดที่ `Map3DScreen` วาดทับอยู่ — คอลัมน์เดียวกับที่ Android เรียงไว้
    /// (สลับโหมดอยู่บน กลับมาที่ตัวเองอยู่ล่าง เพราะอันล่างคือปุ่มที่ใช้ระหว่างเดินจริง)
    private var recenterButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.35)) {
                if let userCoordinate {
                    camera = .region(MKCoordinateRegion(center: userCoordinate,
                                                        latitudinalMeters: 700,
                                                        longitudinalMeters: 700))
                } else if let route {
                    camera = .region(route.region)
                }
            }
        } label: {
            Image(systemName: userCoordinate == nil ? "arrow.up.left.and.arrow.down.right" : "location.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .glassSurface(Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("map_recenter")
        .padding(.horizontal, 20)
        .tabBarClearance(extra: 68)
    }

    /// หมุดฐานหนึ่งใบ — เลขฐานในวงกลม ทองเมื่อเช็คอินแล้ว
    ///
    /// ทองคือสีเดียวกับที่การ์ดฐานใช้บอกว่าเช็คอินแล้ว (`Color.wbwGold` ใน `MapBaseCard`)
    /// ความหมายของสีจึงมีชุดเดียวทั้งแท็บ
    private func baseBadge(sequence: Int) -> some View {
        let checkedIn = progress.progress?.checkedIn.contains { $0.sequence == sequence } ?? false
        return Button {
            selectedSequence = sequence
        } label: {
            Text("\(sequence)")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(checkedIn ? Color.wbwOnGreen : .white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(checkedIn ? Color.wbwGold : Color.wbwForestVoid))
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                // วงกลม 28pt เล็กกว่าเป้านิ้วขั้นต่ำ — ขยายพื้นที่รับนิ้วโดยไม่ขยายกราฟิก
                // ไม่งั้นแตะพลาดกลายเป็นการลากแผนที่ ซึ่งดูเหมือนหมุดกดไม่ได้
                .frame(width: Config.Tap.minTarget, height: Config.Tap.minTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: Loc.t("map_base_number"), sequence))
    }
}
