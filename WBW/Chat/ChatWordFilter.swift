import Foundation

/// ตัวกรองคำหยาบก่อนข้อความจะถูกส่งขึ้นแชทกลุ่ม
///
/// **มีเพราะ Guideline 1.2 บังคับสี่อย่าง** สำหรับแอปที่มี user-generated content:
/// *"A method for filtering objectionable material from being posted to the app"* ·
/// รายงานเนื้อหา · บล็อกผู้ใช้ · ช่องทางติดต่อที่เผยแพร่ไว้ — สามข้อหลังแอปมีมาตั้งแต่แรก
/// (`ChatModeration` กับหน้า `/support`) แต่ข้อแรกไม่เคยมีเลยทั้งฝั่งแอปและฝั่ง SUS
/// ขาดข้อเดียวก็นับว่าไม่ครบ และเป็นเหตุตีกลับได้โดยไม่ต้องรอให้มีใครก่อกวนจริงก่อน
///
/// **ไทยเทียบแบบ substring · อังกฤษเทียบขอบคำ** — ภาษาไทยไม่มีช่องว่างระหว่างคำ จะหาขอบคำ
/// แบบ regex ไม่ได้ ลิสต์ฝั่งไทยจึงต้องมีแต่คำที่ยาวพอจะไม่ไปโผล่กลางคำสุภาพ (เช่นไม่ใส่
/// "หี" ซึ่งเป็นส่วนหนึ่งของ "หีบ") ส่วนฝั่งอังกฤษถ้าใช้ `contains` จะเจอกับดัก Scunthorpe
/// ทันที — "assassin", "classic" จะถูกกันทั้งที่ไม่มีอะไรผิด
///
/// **ตั้งใจให้กรองหยาบ ๆ ไม่ใช่สมบูรณ์แบบ** — คนตั้งใจเลี่ยงด้วยการเว้นวรรคกลางคำหรือสลับ
/// ตัวอักษรยังผ่านได้ ทางจัดการของจริงคือปุ่มรายงาน (`ChatModeration.reportMailURL`) ที่ส่ง
/// ข้อความถึงทีมงาน · ตัวกรองมีไว้กันข้อความหยาบที่ "หลุดปาก" ซึ่งเป็นก้อนใหญ่ที่สุดในงานจริง
enum ChatWordFilter {

    /// ฝั่งไทย — เทียบตรง ๆ ว่ามีอยู่ในข้อความไหม
    static let thai = ["ควย", "เย็ด", "เหี้ย", "สัส", "แตด", "อีดอก", "ระยำ", "แม่ง", "ไอ้เวร"]

    /// ฝั่งอังกฤษ — เทียบทั้งคำเท่านั้น
    static let english = ["fuck", "fucking", "shit", "bitch", "cunt", "asshole",
                          "whore", "slut", "bastard", "dickhead", "motherfucker"]

    static func isObjectionable(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if thai.contains(where: lowered.contains) { return true }
        return english.contains { word in
            lowered.range(of: "\\b\(word)\\b", options: [.regularExpression]) != nil
        }
    }
}
