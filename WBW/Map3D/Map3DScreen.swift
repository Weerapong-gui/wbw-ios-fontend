import RealityKit
import SwiftUI

/// แท็บแผนที่ — โมเดล 3D ของพื้นที่งาน (map.usdz) แทน MapLibre เดิม
///
/// ไม่ใช้ ForestSceneHost: ฉากป่าต้องมี host เพราะ 4 จอใช้ฉากเดียวกันและฉากถูกวาดที่ RootView
/// ซึ่งอยู่คนละ hosting context กับจอ — แผนที่อยู่จอเดียว RealityView เกิดและตายไปกับจอนี้ได้เลย
struct Map3DScreen: View {
    /// โหลดโมเดลไม่สำเร็จ — โชว์ข้อความแทนจอเปล่า (ทรงเดียวกับ ForestSceneHost.loadFailed)
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            Color.wbwForestVoid.ignoresSafeArea()

            if loadFailed {
                VStack(spacing: 12) {
                    Text("เปิดแผนที่ไม่ได้")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("ลองเข้าใหม่อีกครั้ง")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
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
                    //
                    // ปัญหาจริงคือกล้อง .orbit เริ่มต้นที่มุมก้ม (elevation) ต่ำและหันตามแกน X/Z ของ
                    // เนื้อโมเดลตรง ๆ — พื้นที่งานเป็นทรงเกือบสี่เหลี่ยม พอกล้องมองตรงแนวขอบ (0° หรือ 90°)
                    // เลยเห็นภูมิประเทศเป็นเส้นบางแบบมองข้าง หมุนแนวทแยง 45° รอบแกน Y ให้พ้นทั้งสองแนวขอบ
                    // (ยืนยันด้วยสกรีนช็อต: 0°/90° บาง, 45° เห็นมุมสูงชัดเจนที่สุด)
                    map.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 1, 0))

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
