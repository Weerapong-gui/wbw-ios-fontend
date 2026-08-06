import RealityKit
import SwiftUI

/// แท็บแผนที่ — โมเดล 3D ของพื้นที่งาน (map.usdz) แทน MapLibre เดิม
///
/// ไม่ใช้ ForestSceneHost: ฉากป่าต้องมี host เพราะ 4 จอใช้ฉากเดียวกันและฉากถูกวาดที่ RootView
/// ซึ่งอยู่คนละ hosting context กับจอ — แผนที่อยู่จอเดียว RealityView เกิดและตายไปกับจอนี้ได้เลย
struct Map3DScreen: View {
    /// โหลดโมเดลไม่สำเร็จ — โชว์ข้อความแทนจอเปล่า (ทรงเดียวกับ ForestSceneHost.loadFailed)
    @State private var loadFailed = false

    /// มุมหมุนรอบแกน Y ที่ใส่ให้ `map` เพื่อเลี่ยงมุมกล้องเริ่มต้นของ `.orbit` ที่ก้มต่ำและหันตรงตามแกน
    /// X/Z ของโมเดล (พื้นที่งานเป็นทรงเกือบสี่เหลี่ยม พอกล้องมองตรงแนวขอบ 0°/90° เลยเห็นภูมิประเทศเป็น
    /// เส้นบางแบบมองข้าง หมุนแนวทแยงให้พ้นทั้งสองแนวขอบ — ยืนยันด้วยสกรีนช็อต: 0°/90° บาง, 45° เห็นมุมสูง
    /// ชัดเจนที่สุด) ค่านี้ "ไม่ใช่" ทิศเหนือจริง อย่าตีความเป็นมุม compass/bearing ใด ๆ
    ///
    /// กติกาสำหรับใครมาต่อ: entity ที่วางตำแหน่งจากพิกัดจริง (lat/lng) เช่นจุด GPS ผู้ใช้ใน Task 4
    /// ต้องเป็นลูกของ `map` ไม่ใช่ลูกของ `root` — ให้ transform hierarchy พาการหมุนนี้ไปเองอัตโนมัติ
    /// ถ้าจำเป็นต้องแยกไปเป็นลูกของ entity อื่น ต้องคูณการหมุนนี้เข้าไปเองด้วยมือ ไม่งั้นตำแหน่งจะเพี้ยน
    /// แบบเงียบ ๆ ไม่มี error ไม่มีเทสจับได้ (หมุดจาก Task 3 หาโหนดผ่าน findEntity(named:) บนโมเดลเอง
    /// อยู่แล้ว จึงรับการหมุนนี้ไปฟรี ๆ โดยอัตโนมัติ ไม่ต้องแก้อะไร)
    private static let cameraFramingYaw: Float = .pi / 4

    /// เทสยูนิตรันในโปรเซสเดียวกับแอป (app target เป็น test host) — ทรงเดียวกับ
    /// ForestSceneHost.isRunningUnderXCTest ที่มีเหตุผลยาวเขียนไว้แล้ว
    nonisolated static var isRunningUnderXCTest: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    /// โหลดโมเดลจริงไหม — false = โชว์การ์ดข้อความแทน ไม่แตะ RealityView เลย
    ///
    /// `nonisolated` เพื่อให้เทสยูนิตเรียกได้โดยไม่ต้องอยู่บน main actor (ฟังก์ชันนี้ไม่แตะ state ใด)
    nonisolated static func shouldRender(map3D: Bool, underTest: Bool) -> Bool {
        map3D && !underTest
    }

    var body: some View {
        ZStack {
            Color.wbwForestVoid.ignoresSafeArea()

            if !Self.shouldRender(map3D: Config.map3D, underTest: Self.isRunningUnderXCTest) {
                // ปิดสวิตช์อยู่ — ต้องเหลือของที่อ่านรู้เรื่อง ไม่ใช่จอว่าง
                VStack(spacing: 12) {
                    Image(systemName: "map")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("แผนที่ 3D ปิดชั่วคราว")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            } else if loadFailed {
                VStack(spacing: 12) {
                    Text("เปิดแผนที่ไม่ได้")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("ลองเข้าใหม่อีกครั้ง")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                mapView
            }

            if Self.shouldRender(map3D: Config.map3D, underTest: Self.isRunningUnderXCTest) {
                VStack {
                    Spacer()
                    HStack {
                        Text("Satlas · Allen AI · © OpenStreetMap contributors")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    // พ้นแท็บบาร์ลอย — ค่าเดียวกับที่ฉากป่าใช้ วัดจากเครื่องจริงสองรุ่นมาแล้ว
                    .padding(.bottom, ForestSceneHost.tabBarClearance)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private var mapView: some View {
        RealityView { content in
            let root = Entity()
            content.add(root)

            let map: Entity
            do {
                map = try await Entity(named: "map")
            } catch {
                // NSLog ไม่ใช่ print — print() ไม่โผล่ใน unified log ของ simulator
                // (ยืนยันมาแล้วตอน debug จอขาวของฉากป่า) ต้องใช้ NSLog ถึงจะ grep เจอผ่าน
                // `xcrun simctl spawn booted log stream`
                NSLog("[Map3DScreen] Entity(named: \"map\") threw: %@", String(describing: error))
                await MainActor.run { loadFailed = true }
                return
            }
            map.name = "Map"

            // โมเดลเป็นเมตรจริง รัศมีราว 1.9 กม. — ย่อให้ทั้งก้อนพอดีกรอบ 2 หน่วย
            // ก่อนค่อยให้ camera controls จัดการระยะ ไม่งั้นกล้องเริ่มต้นจะอยู่ในเนื้อโมเดล
            let bounds = map.visualBounds(relativeTo: nil)
            let widest = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
            if widest > 0 { map.scale = SIMD3<Float>(repeating: 2 / widest) }
            map.position = -bounds.center * map.scale.x

            // usdz นี้ประกาศ upAxis = "Z" จริง (ตรวจด้วย usdcat) แต่ Entity(named:) ของ
            // RealityKit แปลงให้เป็น Y-up ให้เองตั้งแต่โหลด — วัดจาก visualBounds ก่อนตัวโค้ด
            // นี้แตะต้องอะไรเลย: แกน Y (สูง 664 ม.) เตี้ยกว่า X/Z (กว้าง 4470×5162 ม.) มาก
            // ตรงกับความสูงภูมิประเทศจริง ไม่ใช่ด้านกว้างของพื้นที่ จึงไม่ต้องหมุนแก้ Z-up/Y-up
            // ที่ต้องหมุนจริงคือ cameraFramingYaw — เหตุผลเต็มอยู่ที่คอมเมนต์ของตัวแปรด้านบน
            map.orientation = simd_quatf(angle: Self.cameraFramingYaw, axis: SIMD3<Float>(0, 1, 0))

            root.addChild(map)

            #if DEBUG
            NSLog("[Map3DScreen] map.visualBounds = %@", String(describing: bounds))
            NSLog("[Map3DScreen] map.children.count = %d", map.children.count)
            #endif

            let sun = DirectionalLight()
            sun.light.intensity = 4000
            sun.look(at: .zero, from: SIMD3<Float>(2, 4, 2), relativeTo: nil)
            root.addChild(sun)

            // ไฟเติมจากฝั่งตรงข้าม — ด้านเงาของอาคารไม่ดำสนิท (ทรงเดียวกับ ForestSceneView)
            let fill = DirectionalLight()
            fill.light.intensity = 1200
            fill.look(at: .zero, from: SIMD3<Float>(-3, 2, -3), relativeTo: nil)
            root.addChild(fill)
        }
        .realityViewCameraControls(.orbit)
        .ignoresSafeArea()
    }
}
