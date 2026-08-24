import Foundation

/// ร่างข้อความในช่องพิมพ์ของจอแชท — **ตัวตัดสิน "ส่งได้ไหม" ตัวเดียวของทั้งแอป**
///
/// มีเพราะเคยมีสองตัวที่ไม่ตรงกัน: ปุ่มส่งใน `GroupChatView` เช็คด้วย `.whitespaces`
/// ส่วน `ChatSession.send` เช็คด้วย `.whitespacesAndNewlines` · ช่องพิมพ์เป็น
/// `axis: .vertical` ปุ่ม Return จึงเป็นการขึ้นบรรทัดใหม่ ร่างที่มีแต่ `\n` เกิดง่ายมาก
/// แล้วมันเปิดปุ่มให้กดได้ทั้งที่ store จะเตะทิ้ง — view ล้างช่องต่อ ข้อความหายเงียบ
/// ไม่มีฟอง ไม่มี error ไม่มีอะไรบอกผู้ใช้ว่าไม่ได้ส่ง (ทรงเดียวกับกับดัก
/// "ดูเหมือนกดได้แต่กดไม่ได้" ที่ `SOSStatusView.noteRow` บันทึกไว้)
///
/// ใครจะเช็คว่าส่งได้ไหม ต้องผ่านที่นี่ที่เดียว ห้ามเขียน trimming ซ้ำที่จุดเรียก
enum ChatDraft {
    /// ตัดหัวท้ายแล้วเหลืออะไรจริงไหม — เว้นวรรค แท็บ และขึ้นบรรทัดใหม่ ไม่นับว่าเป็นข้อความ
    static func canSend(_ draft: String) -> Bool { !trimmed(draft).isEmpty }

    /// ตัวข้อความที่จะถูกส่งจริง — ตัดชุดอักขระ **ชุดเดียวกับ** `canSend` เสมอ
    static func trimmed(_ draft: String) -> String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
