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
    /// ภาษาที่ `use(_:)` เลือกไว้จริง — เก็บแยกจาก `bundle` เพราะ **ถาม bundle ไม่ได้**
    ///
    /// `Bundle(path: ".../th.lproj")` ไม่มี localization อยู่ข้างในตัวเอง `preferredLocalizations`
    /// ของมันจึงตอบเป็นภาษาของ *เครื่อง* ไม่ใช่ `th` · `t(_:_:)` เคยถาม bundle แบบนั้นเพื่อหา
    /// locale ไปจัดรูปตัวเลข = ได้ locale ผิดมาตลอดโดยไม่มีใครเห็น (ตัวคั่นหลักพันของไทยกับ
    /// อังกฤษเหมือนกันพอดี อาการเลยไม่โผล่) — พบตอนย้ายป้ายวันในแชทมาใช้ทางเดียวกัน
    nonisolated(unsafe) private static var current: AppLanguage = .system

    /// เลือก bundle ตามภาษาที่ผู้ใช้ตั้งไว้ · `.system` = กลับไปใช้ของเครื่อง
    static func use(_ language: AppLanguage) {
        guard let code = language.locale?.identifier,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let localised = Bundle(path: path)
        else {
            bundle = .main
            current = .system
            return
        }
        bundle = localised
        current = language
    }

    /// Locale ของภาษาที่กำลังใช้อยู่ — แหล่งเดียวสำหรับโค้ดที่จัดรูป **เอง** ไม่ได้ผ่านชุดคีย์
    ///
    /// มีเพราะ `ChatFormat.dayFormatter` เคยตั้ง `Locale(identifier: "th_TH")` ตายตัว คนที่เลือก
    /// English ในหน้าตั้งค่าจึงได้แอปอังกฤษทั้งใบ **ยกเว้นป้ายคั่นวันในแชทที่เป็นไทย** — อาการ
    /// เดียวกับที่ `Loc` ถูกสร้างขึ้นมาแก้ตั้งแต่แรก แค่ย้ายที่ไปอยู่ในตัวจัดรูปวันที่แทน
    ///
    /// `DateFormatter`/`NumberFormatter` ที่ต้องเดินตามภาษาในแอปให้ถามที่นี่ ห้ามฮาร์ดโค้ดเอง
    static var locale: Locale {
        if let chosen = current.locale { return chosen }
        // `.system` = ตามเครื่อง แต่ต้องเป็นภาษาที่ **แอปมีจริง** ไม่ใช่ภาษาเครื่องดิบ ๆ —
        // เครื่องที่ตั้งภาษาญี่ปุ่นได้ข้อความจาก en.lproj (fallback) ป้ายวันต้องเป็นอังกฤษตาม
        // ไม่ใช่ญี่ปุ่นอยู่จุดเดียว · `Bundle.main` ตอบคำถามนี้ได้จริง ต่างจาก bundle ของ .lproj
        return Bundle.main.preferredLocalizations.first.map(Locale.init(identifier:)) ?? .current
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
        String(format: t(key), locale: locale, arguments: arguments)
    }
}
