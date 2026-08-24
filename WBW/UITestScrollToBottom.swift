import SwiftUI

/// เลื่อน `ScrollView` ลงสุดตั้งแต่ตอน launch — **DEBUG เท่านั้น มีไว้ถ่ายรูป**
///
/// จอที่ยาวกว่าหน้าจอมีครึ่งล่างที่ถ่ายไม่ได้เลยด้วยเครื่องมือที่ repo นี้ใช้ (ไม่มี tap tooling
/// ไม่มีตัวสั่งเลื่อน) · ของสำคัญที่อยู่ครึ่งล่างจริง ๆ มีสองอย่างแล้ว: ปุ่ม SOS ใต้บัตรผู้เข้าร่วม
/// (`-uitestPassBottom`) กับปุ่มออกจากระบบท้ายหน้าตั้งค่า (`-uitestSettingsBottom`) ซึ่งเป็นจุดที่
/// Park รายงานว่าโดนบัง — ไม่มีแฟลกก็พิสูจน์ไม่ได้ว่าแก้แล้วหายจริง
///
/// เดิมตัวนี้เป็น `private struct` อยู่ใน `ParticipantPassView.swift` ผูกกับชื่อแฟลกตายตัว
/// ย้ายออกมารับชื่อแฟลกเข้ามาแทนตอนหน้าตั้งค่าต้องใช้ตัวเดียวกัน (2026-08-24)
///
/// **`defaultScrollAnchor(.bottom)` ตัวเดียวไม่พอบนจอที่อยู่ใน `NavigationStack`** — มันยึดตำแหน่ง
/// จากความสูงของเนื้อหา *ตอน layout รอบแรก* แล้ว safe-area ของแถบหัวจอค่อยถูกใส่เข้ามาทีหลัง
/// ดันเนื้อหาลงไปอีกราวความสูงแถบ ผลคือหยุดก่อนถึงก้นจอเท่ากับแถบหัวจอพอดี — ถ่ายหน้าตั้งค่าออกมา
/// ได้ปุ่มออกจากระบบโดนขอบล่างตัดครึ่ง ซึ่งเป็นของชิ้นเดียวที่แฟลกนี้มีไว้ถ่าย · จึงย้ำตำแหน่งซ้ำ
/// ด้วย `ScrollPosition` หลัง layout นิ่งแล้ว
struct UITestScrollToBottom: ViewModifier {
    /// ชื่อคีย์ใน `UserDefaults` ที่ launch argument เขียนไว้ให้ เช่น `uitestPassBottom`
    let flag: String

    #if DEBUG
    @State private var position = ScrollPosition(edge: .bottom)
    #endif

    func body(content: Content) -> some View {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: flag) {
            content
                .defaultScrollAnchor(.bottom)
                .scrollPosition($position)
                .task {
                    // รอให้แถบหัวจอกับการ์ดกระจกวัดตัวเองเสร็จก่อนค่อยย้ำ — ย้ำเร็วกว่านี้
                    // จะได้ตำแหน่งเดียวกับที่ผิดอยู่แล้ว
                    try? await Task.sleep(for: .milliseconds(400))
                    position.scrollTo(edge: .bottom)
                }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
