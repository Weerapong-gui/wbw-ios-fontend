import Foundation

/// การแปลข้อความสำหรับโค้ดที่ไม่ใช่ View
///
/// **มีเพราะ `String(localized:)` ไม่ฟังตัวเลือกภาษาในแอป** — มันอ่านจาก bundle ซึ่งเลือก
/// `.lproj` จากภาษาของ *เครื่อง* ส่วน `Text("key")` ใน SwiftUI อ่านจาก `\.locale` ใน environment
/// ซึ่ง `WBWApp` ตั้งตามตัวเลือกในหน้าตั้งค่า · ปล่อยไว้แบบนั้นแล้วผู้ใช้ที่เลือก "ไทย" บนเครื่อง
/// ภาษาอังกฤษจะได้แอปครึ่งไทยครึ่งอังกฤษ: ปุ่มเป็นไทย ข้อความ error เป็นอังกฤษ
/// (เจอจากการถ่ายจอจริง ไม่ใช่จากการอ่านโค้ด — ทั้งสองทางคอมไพล์ผ่านเหมือนกัน)
///
/// ตัวนี้จึงเลือก bundle ของภาษาที่ผู้ใช้เลือกไว้เอง แล้วอ่านคีย์จาก bundle นั้นตรง ๆ
/// ทั้งสองทางจึงชี้ไปที่ `.lproj` เดียวกันเสมอ
///
/// `Text("key")` ใน View ยังใช้ทางเดิมได้ (environment locale) — ไม่ต้องแก้ทุกจอ
enum Loc {
    /// เขียนจาก main thread ตอนตั้งค่าเปลี่ยน อ่านได้จากทุก thread — เป็นตัวชี้ bundle เฉย ๆ
    nonisolated(unsafe) private static var bundle = Bundle.main

    /// เลือก bundle ตามภาษาที่ผู้ใช้ตั้งไว้ · `.system` = กลับไปใช้ของเครื่อง
    static func use(_ language: AppLanguage) {
        guard let code = language.locale?.identifier,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let localised = Bundle(path: path)
        else {
            bundle = .main
            return
        }
        bundle = localised
    }

    /// ข้อความของคีย์นี้ในภาษาที่กำลังใช้ · คีย์ที่ไม่มีจะคืนชื่อคีย์กลับมา (เหมือน iOS ปกติ)
    /// ซึ่ง `scripts/check-localization.sh` มีไว้จับก่อนถึงมือผู้ใช้
    static func t(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// เหมือน `t(_:)` แต่เติมค่าลงตัวระบุรูปแบบให้ด้วย
    ///
    /// **ต้องใช้ตัวนี้ ไม่ใช่ `String(format: Loc.t(key), ...)` ที่เขียนเอง** — `String(format:)`
    /// แบบไม่ระบุ locale ใช้ locale ของ *เครื่อง* จัดรูปตัวเลข คนที่เลือกไทยบนเครื่องภาษาอื่น
    /// จะได้ตัวคั่นหลักพันคนละแบบกับที่เหลือทั้งแอป · ที่นี่ผูก locale ให้ตรงกับ bundle ที่
    /// `use(_:)` เลือกไว้แล้ว
    ///
    /// ตัวระบุรูปแบบต้องเป็นแบบมีลำดับ (`%1$@`, `%1$lld`) เสมอ เพราะภาษาต่างกันสลับลำดับคำได้
    /// — `scripts/check-localization.sh` ตรวจว่าทั้งสองภาษามีชุดเดียวกัน และคู่ `%@` กับ `Int`
    /// ที่ไม่ตรงกันเคย **crash** จริงมาแล้วที่บัตรผู้เข้าร่วม
    static func t(_ key: String, _ arguments: CVarArg...) -> String {
        let locale = bundle.preferredLocalizations.first.map(Locale.init(identifier:))
        return String(format: t(key), locale: locale, arguments: arguments)
    }
}
