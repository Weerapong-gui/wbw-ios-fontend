import SwiftUI

extension View {
    /// พื้นผิวกระจกของแอป — **สูตรเดียวกับ `Modifier.glass` ของ Android เป๊ะ**
    ///
    /// ต้นทางวาดสามชั้น: การหักเหจากไลบรารี + **แผ่นสีของตัวเอง** (`GlassSheer` ขาว 12%)
    /// + เส้นผม 1dp (`GlassSheerBorder` ขาว 13%) · แถบแท็บ บัตรผู้เข้าร่วม การ์ดกิจกรรม
    /// และแผงตั้งค่า ใช้สามชั้นนี้ชุดเดียวกันหมด ซึ่งเป็นเหตุผลที่ทั้งแอปอ่านเป็นวัสดุเดียว
    ///
    /// **เดิมฝั่ง iOS ใช้ `.regular` ซึ่งเป็นวัสดุของ Apple เอง** — มันมีทั้งแผ่นสีและขอบของตัวเอง
    /// ที่สว่างและเทากว่าขาว 12% ของต้นทางมาก ผลคือการ์ดบน iOS ออกมาคนละสีกับการ์ดบน Android
    /// ทั้งที่โทเคนสีสองฝั่งเท่ากันเป๊ะ (เทสยืนยันแล้วใน `GlassPaletteTests`) เพราะโทเคนไม่เคย
    /// ถูกเอามาใช้เลย · `.clear` คือกระจกที่ **หักเหอย่างเดียว ไม่ทาอะไรทับ** ซึ่งตรงกับสิ่งที่
    /// `liquidGlass(backdrop, shape, surface = tint, highlight = null)` ของต้นทางทำ
    ///
    /// `tint` = แผ่นสีของพื้นผิว (ค่าปริยาย `glassSheer`) — ตรงกับพารามิเตอร์ `fill` ของต้นทาง
    /// ส่งสีอื่นมาได้สำหรับปุ่มที่ต้องย้อม (ปุ่มหยุดเดิน ชิปข้อมูลการแพทย์)
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.clear.tint(tint ?? .glassSheer).interactive(interactive), in: shape)
                // ขอบมาจากเรา ไม่ใช่จากระบบ — ต้นทางวาดเส้นผมขาว 13% รอบทุกแผ่น และเป็นสิ่งเดียว
                // ที่กำหนดรูปทรงของแผ่นตอนแผ่นแทบไม่มีสีของตัวเอง
                .overlay(shape.stroke(Color.glassSheerBorder, lineWidth: 1))
        } else {
            // ไม่มีการหักเหให้ใช้ — ทาแผ่นสีเดียวกันลงบน material บาง ๆ แทน ได้ทรงเดียวกัน
            // ต่างกันแค่ไม่มีการบิดแสง (ทางเดียวกับที่ต้นทาง fallback ตอนไม่มี backdrop layer)
            self
                .background(shape.fill(.ultraThinMaterial))
                .background(shape.fill(tint ?? .glassSheer))
                .overlay(shape.stroke(Color.glassSheerBorder, lineWidth: 1))
        }
    }
}
