import RealityKit
import simd

/// ต้นไม้ประจำผู้เข้าร่วม — โตหนึ่งขั้นต่อหนึ่งฐานที่เช็คอิน
///
/// ใช้ tree.glb ต้นเดียวกับป่ารอบๆ แล้วไล่ขนาดเอา (เว็บเคยลองสลับเป็นโมเดลคนละตัว
/// ต่อระยะแล้ว สไตล์ไม่เข้ากับฉาก เลยกลับมาใช้วิธีนี้) · tree.usdz ถูก bake ให้สูง
/// 1.0 หน่วยพอดี จึงคูณ scale ด้วยความสูงเป้าหมายได้ตรงๆ
final class GrowingTree {
    /// ตำแหน่งที่ถางไว้ในสคริปต์ bake — กลางจอ ระยะ 6 หน่วยหน้ากล้อง
    static let position = SIMD3<Float>(0, 0, -6)

    private let node: Entity
    private var height: Float = ForestMath.minTreeHeight
    private var target: Float = ForestMath.minTreeHeight

    init?(target parent: Entity) {
        guard let tree = try? Entity.load(named: "tree") else { return nil }
        let holder = Entity()
        holder.name = "GrowingTree"
        holder.position = Self.position
        holder.addChild(tree)
        parent.addChild(holder)
        node = holder
        node.scale = .init(repeating: height)
    }

    func setStage(_ stage: Int, total: Int) {
        target = ForestMath.treeHeight(stage: stage, total: total)
    }

    /// เรียกทุกเฟรม — ค่อยๆ โตเข้าหาเป้าหมาย ไม่กระโดดทันทีที่ข้อมูลมาถึง
    func tick(deltaTime: Float, elapsed: Float, reduceMotion: Bool) {
        if reduceMotion {
            height = target
        } else {
            height += (target - height) * min(1, deltaTime * 1.7)   // อัตราเดียวกับเว็บ
        }
        node.scale = .init(repeating: height)

        guard !reduceMotion else {
            node.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            return
        }
        // ไหวตามลม — ต้นเล็กไหวมาก ต้นใหญ่แทบไม่ไหว (สูตรเดียวกับ GrowingPlant.tsx)
        let amp = 0.05 / (1 + height * 0.8)
        let z = sin(elapsed * 0.90) * amp
        let x = sin(elapsed * 0.72 + 1.3) * amp * 0.6
        node.orientation = simd_quatf(angle: z, axis: [0, 0, 1]) * simd_quatf(angle: x, axis: [1, 0, 0])
    }

    func removeFromScene() { node.removeFromParent() }
}
