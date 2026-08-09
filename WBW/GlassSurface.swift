import SwiftUI

extension View {
    /// พื้นผิว Liquid Glass เนทีฟ (iOS 26) · fallback .ultraThinMaterial สำหรับ < 26
    /// อ้างอิงแพทเทิร์นเดียวกับ GlassRing ใน HomeView
    ///
    /// tint = ย้อมสีให้กระจก ใช้ `Glass.tint(_:)` ของระบบ ไม่ใช่เอาสีไปแปะเป็นพื้นใต้กระจกเอง —
    /// แบบหลังกระจกจะซ้อนอยู่หลังสีทึบจนไม่เห็นการหักเหอะไรเลย ได้แค่สี่เหลี่ยมสีเดียว
    /// nil = กระจกใสตามเดิม จุดที่เรียกอยู่แล้วจึงไม่ต้องแก้
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .background(shape.fill(tint ?? .clear))
                .overlay(shape.stroke(.white.opacity(0.6), lineWidth: 1))
        }
    }
}
