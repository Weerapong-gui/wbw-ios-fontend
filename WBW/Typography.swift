import SwiftUI

/// ตัวอักษรของแอป — **ยกมาจาก `ui/theme/Type.kt` ของแอป Android**
///
/// สองหน้าตัวอักษรเท่านั้นทั้งแอป: **Sarabun** สำหรับข้อความ **Kanit** สำหรับตัวเลข
///
/// ต้นทางเคยใช้สองเสียงพร้อมกัน — หัวข้อเป็น Itim (ลายมือ) ส่วนเนื้อกับ UI เป็น Sarabun
/// บัตรผู้เข้าร่วมไม่เคยเลือกเสียงลายมือ (มันตั้งขนาดกับน้ำหนักเอง เลยตกมาที่ Sarabun)
/// พอเห็นสองอันข้างกันจึงชัดว่าแอปดูเหมือนสองผลิตภัณฑ์
///
/// **ลำดับชั้นมาจากน้ำหนักกับขนาด ไม่ใช่การสลับหน้าตัวอักษร** — กฎเดียวกับที่บัตรใช้
/// (สีเดียว ตระกูลเดียว ต่างกันด้วยน้ำหนัก) และเป็นเหตุผลที่บัตรอ่านเหมือนถูกออกแบบ
/// ไม่ใช่ถูกประกอบ
///
/// ใช้ `relativeTo:` ทุกตัว — `Font.custom(_:size:relativeTo:)` ยังโตตาม Dynamic Type
/// ต่างจาก `Font.custom(_:fixedSize:)` ที่ตรึงตายและทำให้ผู้ใช้ที่ตั้งตัวอักษรใหญ่อ่านไม่ได้
/// นี่คือสิ่งที่ยกมาจาก Android ไม่ได้ตรง ๆ เพราะฝั่งนั้นไม่มีกลไกนี้
extension Font {
    private static let text = "Sarabun"
    /// ตัวเลขกับตัวเลขเด่น — บิบ จำนวนใหญ่ · ตัวเลขของ Kanit เหลี่ยมกว่าและแยกออกจากกันในพริบตา
    private static let numeral = "Kanit"

    static let wbwDisplaySmall = custom("\(text)-Bold", size: 34, relativeTo: .largeTitle)
    static let wbwHeadlineMedium = custom("\(text)-Bold", size: 27, relativeTo: .title)
    static let wbwHeadlineSmall = custom("\(text)-Bold", size: 23, relativeTo: .title2)
    static let wbwTitleLarge = custom("\(text)-SemiBold", size: 19, relativeTo: .title3)
    static let wbwTitleMedium = custom("\(text)-SemiBold", size: 15, relativeTo: .headline)
    static let wbwTitleSmall = custom("\(text)-SemiBold", size: 13, relativeTo: .subheadline)
    static let wbwBodyLarge = custom("\(text)-Regular", size: 15, relativeTo: .body)
    static let wbwBodyMedium = custom("\(text)-Regular", size: 13, relativeTo: .callout)
    static let wbwBodySmall = custom("\(text)-Regular", size: 11.5, relativeTo: .footnote)
    static let wbwLabelLarge = custom("\(text)-SemiBold", size: 13, relativeTo: .subheadline)
    static let wbwLabelMedium = custom("\(text)-SemiBold", size: 11, relativeTo: .caption)
    static let wbwLabelSmall = custom("\(text)-SemiBold", size: 10, relativeTo: .caption2)

    /// ป้ายจิ๋วพิมพ์ใหญ่ถ่างตัวอักษรที่บัตรกับหัวข้อหมวดใช้ — เล็กกว่า labelSmall อีกขั้น
    static let wbwKicker = custom("\(text)-SemiBold", size: 8.5, relativeTo: .caption2)

    static func wbwNumeral(_ size: CGFloat, weight: NumeralWeight = .semibold,
                           relativeTo style: TextStyle = .body) -> Font {
        custom("\(numeral)-\(weight.rawValue)", size: size, relativeTo: style)
    }

    enum NumeralWeight: String {
        case medium = "Medium", semibold = "SemiBold", bold = "Bold"
    }

    /// ขนาดนอกสเกล — มีไว้ให้บัตรผู้เข้าร่วมโดยเฉพาะ
    ///
    /// บัตรตั้งขนาดของมันเองมาตั้งแต่ต้น (28 / 12.5 / 8.5) เพราะมันไม่ใช่หน้าจอ มันเป็นแผ่นพิมพ์
    /// ที่ทุกระยะสัมพันธ์กันเอง — บังคับให้ใช้สเกลของแอปจะทำให้ทุกอย่างบนแผ่นขยับพร้อมกันหมด
    /// ตัวช่วยนี้จึงเปลี่ยนแค่ *หน้าตัวอักษร* จาก SF เป็น Sarabun ไม่ได้เปลี่ยนสัดส่วนของแผ่น
    static func wbwText(_ size: CGFloat, weight: TextWeight = .regular,
                        relativeTo style: TextStyle = .body) -> Font {
        custom("\(text)-\(weight.rawValue)", size: size, relativeTo: style)
    }

    enum TextWeight: String {
        case regular = "Regular", semibold = "SemiBold", bold = "Bold"
    }
}

#if DEBUG
/// ตรวจว่าไฟล์ฟอนต์ถูก bundle ไปจริงและชื่อ PostScript ตรงกับที่โค้ดเรียก
///
/// จำเป็นเพราะ **ชื่อผิดไม่ทำให้ build พัง** — `Font.custom` ที่หาไม่เจอจะตกกลับไปใช้ฟอนต์ระบบ
/// เงียบ ๆ ทั้งแอป ซึ่งดูเหมือน "ยังไม่ได้เปลี่ยนฟอนต์" มากกว่าดูเหมือนบั๊ก
enum FontAudit {
    static let expected = ["Sarabun-Regular", "Sarabun-SemiBold", "Sarabun-Bold",
                           "Kanit-Medium", "Kanit-SemiBold", "Kanit-Bold"]

    static var missing: [String] {
        expected.filter { UIFont(name: $0, size: 12) == nil }
    }
}
#endif
