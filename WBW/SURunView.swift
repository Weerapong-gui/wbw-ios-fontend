import CoreLocation
import MapKit
import SwiftUI

/// SU RUN — แผนที่เส้นทางเดินรอบดอย พร้อมจับระยะ/ก้าว/pace ระหว่างเดินจริง
///
/// **ประวัติของจอนี้ อ่านก่อนแก้:** ของเดิมเป็นแดชบอร์ดที่ทุกตัวเลขมาจาก `SURunMock`
/// (ก้าว/ระยะ/เวลา/แคลอรี/อันดับ) บล็อก MAP เป็นสี่เหลี่ยมเขียวเขียนคำว่า MAP และปุ่ม "Start now!"
/// เป็น `Button { }` เปล่า — ถูกล้างทิ้งทั้งหมดเพราะตัวเลขปลอมบนแอปที่กำลังจะใช้จริงทำให้คน
/// เข้าใจว่าระบบนับก้าวให้อยู่ · จากนั้นเป็นจอว่าง แล้วเป็นการ์ด "เร็ว ๆ นี้" ชั่วคราว
///
/// **รอบนี้เป็นของจริงแล้ว ตัวเลขทุกตัวมาจากเซ็นเซอร์ของเครื่อง** ไม่มี mock เหลืออยู่เลย —
/// ระยะจาก CoreLocation, ก้าวจาก CMPedometer, เส้นทางจากไฟล์ที่ bake มากับแอป
/// รอบส่ง 1.0 (7) โดน App Review ตีกลับด้วย 2.1 กับ 2.3.3 · แท็บที่เปิดมาแล้วไม่มีอะไรคือ
/// ใบตีกลับใบต่อไปที่รออยู่ (4.2 minimum functionality) — **ห้ามถอยกลับไปเป็นจอว่าง**
///
/// ตัวเลขไม่ถูกส่งขึ้น backend เพราะยังไม่มี endpoint รับ (แอป Android ก็ไม่ส่งเหมือนกัน)
/// จอนี้จึงไม่โฆษณาว่าเก็บสถิติให้ — พูดแค่ว่ากำลังจับอยู่ตอนนี้
struct SURunView: View {
    /// แยกเป็นค่าคงที่ให้เทสจับได้ — ตัว View ทั้งใบ render ในเทสไม่ได้
    static let title = "เส้นทางเดินรอบดอย"

    /// แท็บนี้ถูกเลือกอยู่จริงหรือเปล่า — **จำเป็น ไม่ใช่ของเผื่อ**
    ///
    /// `TabView` แบบ `Tab(value:)` ของ iOS 18+ สร้างเนื้อของทุกแท็บตั้งแต่ตอน mount และ
    /// `MapKit.Map` **ขอสิทธิ์ตำแหน่งด้วยตัวเองทันทีที่ถูกสร้าง** (ยืนยันแล้วว่าไม่ใช่โค้ดของเรา:
    /// ใส่ NSLog ที่ทุกจุดที่เรียก `requestWhenInUseAuthorization` แล้ว log ว่างเปล่า แต่ dialog
    /// ยังเด้ง) ผลคือแอปขอสิทธิ์ตำแหน่งทับหน้า Home ทันทีที่ล็อกอินเสร็จ โดยที่ผู้ใช้ยังไม่ได้
    /// แตะอะไรเลย — เป็นสิ่งที่ App Review ตีกลับได้ตรง ๆ
    var isActive: Bool = true

    @StateObject private var tracker = SURunTracker()
    @State private var camera: MapCameraPosition = .automatic
    /// จริงแล้วไม่กลับเป็นเท็จอีก — สลับออกจากแท็บแล้วถอดแผนที่ทิ้งจะเสียตำแหน่งกล้องกับรอยที่เดินมา
    @State private var mapReady = false

    private let route = TrailRoute.bundled

    var body: some View {
        ZStack(alignment: .top) {
            if mapReady {
                map
            } else {
                Color.clear
            }
            hud
        }
        .safeAreaInset(edge: .bottom) { startStop }
        .onAppear {
            if isActive { mapReady = true }
            #if DEBUG
            // ถ่ายรูปตอน "กำลังเดินอยู่จริง" — คู่กับ `xcrun simctl location start` ที่ป้อนพิกัด
            // ตามเส้นทางจริงเข้ามา ตัวเลขบน HUD จึงมาจากการคำนวณจริงทั้งหมด ไม่ใช่ค่าที่ยัดไว้
            if UserDefaults.standard.bool(forKey: "uitestRunStart") { tracker.start() }
            #endif
        }
        .onChange(of: isActive) { _, nowActive in if nowActive { mapReady = true } }
        // root ของแท็บต้องมี modifier ตัวนี้เสมอ ไม่ใช่ AppBackdrop() ตรง ๆ — มันพก
        // TabRootOpaqueBackgroundRemover มาด้วย ซึ่งเจาะพื้นทึบขาวของ per-tab UIHostingController
        // ทิ้ง ไม่มีแล้วจะเห็นเป็นแถบขาวข้างจอ (เคยเจอจริงที่แท็บ QR ดู docs/forest-3d-off-verification.md)
        .forestBackground(day: ForestMath.dayStill)
    }

    // MARK: - แผนที่

    private var map: some View {
        Map(position: $camera) {
            if let route {
                // เส้นทึบเข้มรองใต้เส้นเขียว — เส้นเดี่ยวบนภาพดาวเทียม/ป่าเขียวจะกลืนหายไปเลย
                MapPolyline(coordinates: route.points)
                    .stroke(Color.black.opacity(0.55), style: .init(lineWidth: 9, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: route.points)
                    .stroke(Color.wbwGreen, style: .init(lineWidth: 5, lineCap: .round, lineJoin: .round))

                if let start = route.start {
                    Annotation("เริ่ม", coordinate: start) { endpoint(filled: true) }
                }
                if let finish = route.finish {
                    Annotation("สิ้นสุด", coordinate: finish) { endpoint(filled: false) }
                }
            }
            // รอยที่เดินมาจริงรอบนี้ วาดทับเส้นทางด้วยสีทองให้แยกออกจากกันได้ทันที
            if tracker.track.count > 1 {
                MapPolyline(coordinates: tracker.track)
                    .stroke(Color.wbwGold, style: .init(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            // ใส่เมื่อได้สิทธิ์แล้วเท่านั้น — MapKit ขอสิทธิ์เองทันทีที่เห็นตัวนี้ในฉาก
            // ซึ่งจะเด้ง dialog ตั้งแต่ยังไม่ได้กด "เริ่มเดิน" (แถมแท็บถูกสร้างล่วงหน้าตั้งแต่ล็อกอิน
            // ด้วย — ดูคอมเมนต์ `isActive` ที่ Map3DScreen)
            if tracker.locationAuthorized { UserAnnotation() }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .ignoresSafeArea()
        .onAppear {
            if let route { camera = .region(route.region) }
        }
    }

    private func endpoint(filled: Bool) -> some View {
        Circle()
            .fill(filled ? Color.wbwGold : Color.clear)
            .overlay(Circle().stroke(filled ? Color.black.opacity(0.6) : Color.wbwGold, lineWidth: 3))
            .frame(width: 16, height: 16)
    }

    // MARK: - HUD

    private var hud: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                stat("ระยะ", SURunMath.distanceText(metres: tracker.distanceMetres))
                divider
                stat("ก้าว", SURunMath.stepsText(tracker.steps))
                divider
                stat("นาที/กม.", SURunMath.paceText(metresPerSecond: tracker.smoothedSpeed))
                divider
                stat("เวลา", SURunMath.elapsedText(seconds: tracker.elapsedSeconds))
            }
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // ต้องย้อมเข้ม ไม่ใช่กระจกใส — ตัวหนังสือบน HUD เป็นสีขาว ส่วนแผนที่ของ MapKit เป็นพื้นสว่าง
        // ถ่ายจริงแล้วขาวบนขาวหายไปทั้งแถบ · ใช้ tint ของ Glass ไม่ใช่แปะสีทึบใต้กระจก
        // (แบบหลังกระจกจะไปอยู่หลังสีทึบจนไม่เหลือการหักเหอะไรเลย)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous),
                      tint: Color.wbwForestVoid)
        .padding(.horizontal, 14)
    }

    private var subtitle: String {
        if tracker.locationDenied {
            return "ยังไม่ได้ให้สิทธิ์ตำแหน่ง — ดูเส้นทางได้ แต่จับระยะไม่ได้"
        }
        if tracker.isRunning {
            return "กำลังจับระยะ · นับเฉพาะตอนเปิดแอปอยู่"
        }
        guard let route else { return Self.title }
        return "\(Self.title) · \(SURunMath.distanceText(metres: Double(route.distanceMetres)))"
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 26)
    }

    // MARK: - ปุ่ม

    private var startStop: some View {
        Button {
            tracker.isRunning ? tracker.stop() : tracker.start()
        } label: {
            Label(tracker.isRunning ? "หยุด" : "เริ่มเดิน",
                  systemImage: tracker.isRunning ? "stop.fill" : "figure.walk")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 14)
                .glassSurface(Capsule(), tint: tracker.isRunning ? Color.wbwMedical : Color.wbwGreen,
                              interactive: true)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }
}

#Preview { SURunView() }
