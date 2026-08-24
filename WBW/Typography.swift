import SwiftUI

/// ตัวอักษรของแอป — **Anuphan หน้าเดียวทั้งแอป** (เปลี่ยนจาก Sarabun + Kanit เมื่อ 2026-08-25)
///
/// เจ้าของงานขอฟอนต์ทรง Sukhumvit Set · **Sukhumvit Set ใช้ไม่ได้** — มันไม่ได้อยู่บน iOS
/// (ยืนยันด้วยการลิสต์ `UIFont.familyNames` บนเครื่องจริง: มีแค่ฟอนต์ที่แอป bundle เอง
/// กับ Thonburi ของระบบ) และไฟล์ที่อยู่บน macOS เป็นของที่ Apple ซื้อสิทธิ์มาจาก
/// Cadson Demak สำหรับเครื่อง Apple เอง ก๊อปเข้า bundle แอปแล้วส่ง App Store ไม่ได้
///
/// **Anuphan เป็นฟอนต์ของ Cadson Demak เจ้าเดียวกับที่ออกแบบ Sukhumvit Set** และเป็น
/// SIL Open Font License 1.1 จึง bundle ไปกับแอปได้ถูกกฎหมาย (ไฟล์สัญญาอนุญาตอยู่ที่
/// `WBW/Resources/Fonts/Anuphan-OFL.txt` — OFL บังคับให้แนบไปด้วย ห้ามลบ)
///
/// **หน้าเดียวทั้งแอป รวมตัวเลข** — เดิมตัวเลขใช้ Kanit เพราะเลขของมันเหลี่ยมและแยกออกจากกัน
/// ในพริบตา · เจ้าของงานเลือกเสียงเดียว ยอมแลกความต่างของหลักเลขไปกับความกลมกลืน
///
/// **ลำดับชั้นมาจากน้ำหนักกับขนาด ไม่ใช่การสลับหน้าตัวอักษร** — กฎเดียวกับที่บัตรใช้
/// (สีเดียว ตระกูลเดียว ต่างกันด้วยน้ำหนัก) และเป็นเหตุผลที่บัตรอ่านเหมือนถูกออกแบบ
/// ไม่ใช่ถูกประกอบ
///
/// ใช้ `relativeTo:` ทุกตัว — `Font.custom(_:size:relativeTo:)` ยังโตตาม Dynamic Type
/// ต่างจาก `Font.custom(_:fixedSize:)` ที่ตรึงตายและทำให้ผู้ใช้ที่ตั้งตัวอักษรใหญ่อ่านไม่ได้
/// นี่คือสิ่งที่ยกมาจาก Android ไม่ได้ตรง ๆ เพราะฝั่งนั้นไม่มีกลไกนี้
extension Font {
    /// **ชื่อ PostScript ของ Anuphan ไม่ได้เรียงตามที่คาด** — มันเป็น variable font ไฟล์เดียว
    /// iOS จึงตั้งชื่อ instance ว่า `Anuphan-Regular_SemiBold` ไม่ใช่ `Anuphan-SemiBold`
    /// (น้ำหนักปกติเป็น `Anuphan-Regular` เฉย ๆ ไม่มีหาง) · ชื่อชุดนี้ได้จากการ log
    /// `UIFont.fontNames(forFamilyName:)` บนเครื่องจริง ไม่ใช่การเดาจากชื่อไฟล์ —
    /// เดาผิดแล้ว `Font.custom` จะตกกลับไปใช้ฟอนต์ระบบเงียบ ๆ ทั้งแอปโดยไม่มี error
    /// (`FontAudit` ข้างล่างมีไว้จับกรณีนี้)
    /// `internal` ไม่ใช่ `private` เพื่อให้ `TypographyTests` ตรวจด้วย **กฎเดียวกับที่โค้ดจริงใช้**
    /// ไม่ใช่ก๊อปกฎไปเขียนซ้ำในเทส ซึ่งจะเพี้ยนจากกันวันที่มีคนแก้ข้างเดียว
    static func face(_ weight: String) -> String {
        weight == "Regular" ? "Anuphan-Regular" : "Anuphan-Regular_\(weight)"
    }

    static let wbwDisplaySmall = custom(face("Bold"), size: 34, relativeTo: .largeTitle)
    static let wbwHeadlineMedium = custom(face("Bold"), size: 27, relativeTo: .title)
    static let wbwHeadlineSmall = custom(face("Bold"), size: 23, relativeTo: .title2)
    static let wbwTitleLarge = custom(face("SemiBold"), size: 19, relativeTo: .title3)
    static let wbwTitleMedium = custom(face("SemiBold"), size: 15, relativeTo: .headline)
    static let wbwTitleSmall = custom(face("SemiBold"), size: 13, relativeTo: .subheadline)
    static let wbwBodyLarge = custom(face("Regular"), size: 15, relativeTo: .body)
    static let wbwBodyMedium = custom(face("Regular"), size: 13, relativeTo: .callout)
    static let wbwBodySmall = custom(face("Regular"), size: 11.5, relativeTo: .footnote)
    static let wbwLabelLarge = custom(face("SemiBold"), size: 13, relativeTo: .subheadline)
    static let wbwLabelMedium = custom(face("SemiBold"), size: 11, relativeTo: .caption)
    static let wbwLabelSmall = custom(face("SemiBold"), size: 10, relativeTo: .caption2)

    /// ป้ายจิ๋วพิมพ์ใหญ่ถ่างตัวอักษรที่บัตรกับหัวข้อหมวดใช้ — เล็กกว่า labelSmall อีกขั้น
    static let wbwKicker = custom(face("SemiBold"), size: 8.5, relativeTo: .caption2)

    static func wbwNumeral(_ size: CGFloat, weight: NumeralWeight = .semibold,
                           relativeTo style: TextStyle = .body) -> Font {
        custom(face(weight.rawValue), size: size, relativeTo: style)
    }

    enum NumeralWeight: String {
        case medium = "Medium", semibold = "SemiBold", bold = "Bold"
    }

    /// ขนาดนอกสเกล — มีไว้ให้บัตรผู้เข้าร่วมโดยเฉพาะ
    ///
    /// บัตรตั้งขนาดของมันเองมาตั้งแต่ต้น (28 / 12.5 / 8.5) เพราะมันไม่ใช่หน้าจอ มันเป็นแผ่นพิมพ์
    /// ที่ทุกระยะสัมพันธ์กันเอง — บังคับให้ใช้สเกลของแอปจะทำให้ทุกอย่างบนแผ่นขยับพร้อมกันหมด
    /// ตัวช่วยนี้จึงเปลี่ยนแค่ *หน้าตัวอักษร* จาก SF เป็นฟอนต์ของแอป ไม่ได้เปลี่ยนสัดส่วนของแผ่น
    static func wbwText(_ size: CGFloat, weight: TextWeight = .regular,
                        relativeTo style: TextStyle = .body) -> Font {
        custom(face(weight.rawValue), size: size, relativeTo: style)
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
    static let expected = ["Anuphan-Regular", "Anuphan-Regular_Medium",
                           "Anuphan-Regular_SemiBold", "Anuphan-Regular_Bold"]

    static var missing: [String] {
        expected.filter { UIFont(name: $0, size: 12) == nil }
    }
}
#endif
