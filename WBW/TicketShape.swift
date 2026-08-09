import SwiftUI

/// ตำแหน่งแนวฉีกที่วัดได้จาก layout จริง ส่งขึ้นไปให้ TicketShape เจาะรอยเว้าข้างให้ตรงเส้นประ
/// ฮาร์ดโค้ดไม่ได้ — ชื่อยาวขึ้นอีกบรรทัดเมื่อไหร่ เส้นประกับรอยเว้าจะเลื่อนออกจากกันทันที
struct TearYKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

/// เส้นแนวนอนกลางกรอบ — ใช้เป็นเส้นประแนวฉีก
///
/// ต้องเป็น Shape ไม่ใช่ Path ที่ลากยาว ๆ แล้วครอบ .frame() เอา — Path วาดทะลุกรอบออกไปได้
/// (frame คุมแค่พื้นที่ layout ไม่ได้คลิปการวาด) เส้นประจะพาดออกนอกการ์ดไปจนสุดขอบจอ
struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// เส้นขอบตั๋วประจำตัว — มุมมน + รอยเว้าครึ่งวงกลมสามจุด (บนกลางสำหรับ avatar, ซ้าย/ขวาที่แนวฉีก)
///
/// ทำไมต้องเป็น Shape ไม่ใช่เอาวงกลมสีพื้นแปะทับแบบเดิม: ท่าแปะทับเนียนเฉพาะตอนพื้นหลังเป็นสี
/// เรียบสีเดียว พอจอนี้เปลี่ยนไปใช้รูปภาพเป็นพื้นหลัง วงกลมสีทึบจะโผล่กลางรูปทันที
///
/// วาดเป็นเส้นรอบรูป "เส้นเดียวที่ไม่ตัดตัวเอง" โดยใช้ addArc โค้งกลับเข้าใน — ไม่ใช่วาดสี่เหลี่ยม
/// แล้ว addEllipse ทับหวังให้หักลบกัน เพราะแบบหลังต้องพึ่ง FillStyle(eoFill: true) ซึ่ง .clipShape
/// กับ .background(_:in:) ไม่รับ ใช้ได้แค่ .fill อย่างเดียว พอจะเอาไปคลิปเนื้อหาหรือทำเงาตามทรง
/// จะพังทันทีโดยไม่มีอะไรเตือน
struct TicketShape: Shape {
    var corner: CGFloat = 34
    /// รัศมีรอยเว้าบน = รัศมี avatar + ช่องไฟที่อยากให้เห็นพื้นหลังลอด · 0 = ขอบบนเรียบ
    /// (เลย์เอาต์รอบแรกยังไม่รู้ขนาด avatar ค่าจะเป็น 0 มาก่อน ห้ามพังหรือได้ NaN)
    var avatarCut: CGFloat = 0
    /// รัศมีรอยเว้าซ้าย/ขวาตรงแนวฉีก · 0 = ขอบข้างตรง
    var sideCut: CGFloat = 14
    /// ระยะจากขอบบนถึงแนวฉีก (จุดกึ่งกลางของรอยเว้าข้าง)
    var tearY: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var p = Path()

        // บีบค่าให้อยู่ในกรอบเสมอ — ค่าที่ใหญ่เกินจะทำให้ arc ทับกันจนเส้นตัดตัวเอง แล้ว contains()
        // ให้ผลกลับด้านเป็นบางจุดแบบเดาไม่ถูก
        let r = min(corner, min(rect.width, rect.height) / 2)
        let aCut = max(0, min(avatarCut, (rect.width / 2) - r - 1))
        let sCut = max(0, min(sideCut, (rect.height / 2) - r - 1))
        let tear = min(max(tearY, rect.minY + r + sCut), rect.maxY - r - sCut)
        let hasTear = sCut > 0 && tearY > 0

        // ขอบบน: ซ้ายไปขวา เว้ารอยครึ่งวงกลมกลางทางถ้ามี
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        if aCut > 0 {
            p.addLine(to: CGPoint(x: rect.midX - aCut, y: rect.minY))
            // clockwise: true = โค้งลงมาในเนื้อการ์ด (เว้าเข้า) ไม่ใช่โป่งขึ้นไปนอกกรอบ
            p.addArc(center: CGPoint(x: rect.midX, y: rect.minY), radius: aCut,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        }
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)

        // ขอบขวา: ลงล่าง เว้าที่แนวฉีก
        if hasTear {
            p.addLine(to: CGPoint(x: rect.maxX, y: tear - sCut))
            p.addArc(center: CGPoint(x: rect.maxX, y: tear), radius: sCut,
                     startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)

        // ขอบล่าง: ขวาไปซ้าย
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)

        // ขอบซ้าย: ขึ้นบน เว้าที่แนวฉีก
        if hasTear {
            p.addLine(to: CGPoint(x: rect.minX, y: tear + sCut))
            p.addArc(center: CGPoint(x: rect.minX, y: tear), radius: sCut,
                     startAngle: .degrees(90), endAngle: .degrees(270), clockwise: true)
        }
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        p.closeSubpath()
        return p
    }
}
