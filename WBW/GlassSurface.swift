import SwiftUI

extension View {
    /// พื้นผิว Liquid Glass เนทีฟ (iOS 26) · fallback .ultraThinMaterial สำหรับ < 26
    /// อ้างอิงแพทเทิร์นเดียวกับ GlassRing ใน HomeView
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.stroke(.white.opacity(0.6), lineWidth: 1))
        }
    }
}
