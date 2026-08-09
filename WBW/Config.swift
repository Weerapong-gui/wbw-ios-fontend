import Foundation

/// backend ปลายทาง — สลับทั้งแอปทีเดียว (JWT คนละ secret ต่อ backend)
enum Backend {
    case prodNode   // Node เดิม (ใช้งานได้จริงตอนนี้)
    case nodeLocal  // Node ตัวเดียวกัน แต่รัน docker stack ในเครื่อง (dev เทส long-poll ฯลฯ)
    case susLocal   // Student-Union-Server รัน docker stack ในเครื่อง — เซิร์ฟเวอร์ทดสอบหลัก
    case susProd    // SUS ที่ deploy แล้ว (named Cloudflare tunnel → backend:8080)
    /// สำหรับรันบนเครื่องจริงเท่านั้น — localhost บนมือถือคือตัวมือถือเอง ต้องใช้ IP ของ Mac ในวง LAN
    ///
    /// **ตัว case ต้องอยู่ในนี้เสมอ** ห้ามลบออกเวลา commit — BackendCacheKey กับเทสอีกสองไฟล์
    /// switch ครบทุก case ถ้าไม่มีตัวนี้ repo จะ build ไม่ผ่านเลยตอน clone ใหม่ (เคยพลาดมาแล้ว)
    /// สิ่งที่แก้เฉพาะเครื่องคือ **เลข IP ข้างล่าง** ไม่ใช่ตัว case
    case susLan

    var apiBase: String {
        switch self {
        case .prodNode:  return "https://wbw.sumfu.store"
        case .nodeLocal: return "http://localhost:4000"
        case .susLocal:  return "http://localhost:8080/wbw"
        case .susProd:   return "https://api.studentunion.social/wbw"
        // IP เปลี่ยนทุกครั้งที่ย้ายเน็ต: `ipconfig getifaddr en0` แล้วแก้ตรงนี้
        // และ container publish แค่ 127.0.0.1 ต้อง forward ออก LAN ก่อน (ดู docs/sus-test-backend.md)
        case .susLan:    return "http://172.25.32.8:8081/wbw"
        }
    }

    /// โปรไฟล์ผู้ใช้ปัจจุบัน — Node อยู่ที่ /auth/me, SUS อยู่ที่ /me
    var mePath: String {
        switch self {
        case .prodNode, .nodeLocal: return "/auth/me"
        case .susLocal, .susProd, .susLan: return "/me"
        }
    }
}

enum Config {
    /// เปลี่ยนค่าเดียวนี้เพื่อสลับ backend
    ///
    /// สลับแล้ว **ต้องล้างข้อมูลแอป** ทุกครั้ง — cache แชท (SwiftData) กับ cursor ใน UserDefaults
    /// ไม่ได้ผูกกับ backend ที่มันมาจาก แต่ละ backend เดิน `group_message.id` แยกกัน พอสลับแล้ว
    /// แอปจะขอข้อความ "หลัง id" ที่ backend ใหม่ไม่เคยออกให้ ได้ 200 พร้อมลิสต์ว่างตลอด
    /// แชทดูเหมือนค้างโดยไม่มี error ไม่มี log อะไรเลย · ดู docs/sus-test-backend.md
    static let backend: Backend = .susProd   // ค่าที่ส่งขึ้น store
    static var apiBase: String { backend.apiBase }
    static var mePath: String { backend.mePath }

    /// ฉากป่า 3D — ปิดชั่วคราว (เครื่องทำงานหนัก) เปิดกลับได้ที่ค่านี้ค่าเดียว
    ///
    /// ปิด = ทุกจอที่เรียก .forestBackground() ได้พื้นทึบ Color.wbwForestVoid แทน และ
    /// ForestSceneView/ForestOverlay ไม่ถูก mount เลยสักครั้ง (ดู ForestSceneHost.shouldClaim)
    /// โค้ดและ asset ของฉากยังอยู่ครบ ไม่ได้ถูกลบ
    static let forest3D = false

    /// โมเดลแผนที่ 3D ที่แท็บ Map — ปิดได้ด้วยค่าเดียวนี้ถ้าเครื่องรับไม่ไหว
    ///
    /// ปิด = แท็บ Map โชว์การ์ดข้อความแทน ไม่โหลด map.usdz เลยสักครั้ง (ดู Map3DScreen.shouldRender)
    /// ตั้ง true ไว้ต่างจาก forest3D โดยตั้งใจ — ฉากป่าถูกปิดเพราะอาการที่ยังไม่พิสูจน์
    /// (docs/forest-3d-off-verification.md §7) แผนที่ยังไม่ถูกวัด จึงเปิดไว้ก่อนแล้ววัด (Task 5)
    static let map3D = true
}

/// สีธีม (DOI-APP)
import SwiftUI
import UIKit   // UIColor(dynamicProvider:) — SwiftUI ไม่ได้ re-export UIKit ให้
extension Color {
    // ===== สีแบรนด์ — คงที่ทั้งสองธีม =====
    //
    // ทองกับเขียวเป็นเอกลักษณ์ของงาน ไม่ใช่สีพื้นผิว พลิกตามธีมเมื่อไหร่แอปจะดูเป็นคนละงาน
    static let wbwCream = Color(red: 222 / 255, green: 198 / 255, blue: 132 / 255) // #DEC684
    static let wbwGold = Color(red: 201 / 255, green: 154 / 255, blue: 31 / 255) // #C99A1F ทอง
    static let wbwGreen = Color(red: 64 / 255, green: 145 / 255, blue: 108 / 255) // #40916C เขียวป่า (toggle on)

    /// พื้นหลังทึบแทนฉากป่าตอน Config.forest3D ปิด — สีเดียวกับ scrim เดิมของ ForestOverlay
    /// มืดโดยตั้งใจทั้งสองธีม เป็นพื้นฉาก ไม่ใช่พื้นจอ
    static let wbwForestVoid = Color(red: 10 / 255, green: 22 / 255, blue: 16 / 255) // #0A1610

    /// พื้นจอตั๋วประจำตัว — ที่พักไว้ก่อน ของจริงจะเป็นรูปภาพ (ดู TicketView.background)
    /// คงที่ทั้งสองธีม จอนี้เป็นดีไซน์ตายตัว ไม่ใช่พื้นผิวที่ปรับตามโหมด
    static let wbwTicketBG = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255) // #1A1A1A
    /// แดงเลือดหมูของปุ่ม Medical ID — ใช้เป็น tint ของกระจก
    static let wbwMedical = Color(red: 66 / 255, green: 23 / 255, blue: 23 / 255) // #421717

    // ===== สีพื้นผิว — ปรับตามโหมดมืด =====
    //
    // ใช้ UIColor(dynamicProvider:) ไม่ใช่ .colorset ใน Assets เพราะโปรเจกต์สร้างจาก XcodeGen
    // การเพิ่ม colorset ต้องแตะหลายไฟล์ใน Assets.xcassets แล้ว `xcodegen generate` ทุกครั้ง
    // ส่วนแบบนี้อยู่ไฟล์เดียว รีวิวจบในที่เดียว · ตัวขับคือ .preferredColorScheme ที่ WBWApp
    // ตั้งไว้จาก AppSettings.isDark ซึ่ง resolve ให้ถูกต้องอยู่แล้ว
    //
    // ค่าโหมดสว่างต้องเท่าของเดิมเป๊ะ — งานนี้เพิ่มโหมดมืด ไม่ได้เปลี่ยนหน้าตาโหมดสว่าง
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// พื้นหลังจอ — เดิมแต่ละจอประกาศ `private let bg = Color(red: 250/255, ...)` ของตัวเอง 6 ที่
    static let wbwBg = adaptive(
        light: UIColor(red: 250 / 255, green: 247 / 255, blue: 240 / 255, alpha: 1), // #FAF7F0 ครีมอ่อน
        dark: UIColor(red: 20 / 255, green: 18 / 255, blue: 15 / 255, alpha: 1))     // #14120F
    /// การ์ด/ฟองแชท/ช่องพิมพ์ — เดิมเป็น Color.white ตรง ๆ
    static let wbwSurface = adaptive(
        light: .white,
        dark: UIColor(red: 33 / 255, green: 31 / 255, blue: 27 / 255, alpha: 1))     // #211F1B
    /// ตัวอักษร/เส้นเข้ม — ตัวที่ได้ผลกว้างสุด ถูกใช้อยู่ 41 จุดใน 16 ไฟล์
    static let wbwInk = adaptive(
        light: UIColor(red: 43 / 255, green: 43 / 255, blue: 43 / 255, alpha: 1),    // #2B2B2B
        dark: UIColor(red: 239 / 255, green: 235 / 255, blue: 227 / 255, alpha: 1))  // #EFEBE3
    /// ข้อความรอง — เดิมหว่าน Color(0xFF8F8A80)/.secondary ปนกัน
    static let wbwMuted = adaptive(
        light: UIColor(red: 143 / 255, green: 138 / 255, blue: 128 / 255, alpha: 1), // #8F8A80
        dark: UIColor(red: 168 / 255, green: 161 / 255, blue: 150 / 255, alpha: 1))  // #A8A196
    /// เส้นคั่น
    static let wbwLine = adaptive(
        light: UIColor(red: 236 / 255, green: 230 / 255, blue: 218 / 255, alpha: 1), // #ECE6DA
        dark: UIColor(red: 51 / 255, green: 47 / 255, blue: 41 / 255, alpha: 1))     // #332F29
}

/// ข้อเท็จจริงของงาน — ไม่มีมาจาก backend เลย ฝังมากับแอป
///
/// เดิมช่อง Date บนตั๋วเป็น string `"29 AUG 2026"` ฮาร์ดโค้ดกลางไฟล์จอ ย้ายมาที่นี่เพื่อให้แก้ที่เดียว
/// และให้รูปแบบที่โชว์คำนวณจากวันจริง ไม่ใช่สตริงคนละชุดที่ต้องมาไล่แก้ให้ตรงกันเอง
enum WBWEvent {
    /// วันเดินรอบดอย — ค.ศ. 2026 = พ.ศ. 2569
    static let day = DateComponents(year: 2026, month: 8, day: 29)

    /// ข้อความช่อง Date บนตั๋ว เช่น "29 AUG 2026"
    ///
    /// deviceLocale รับเข้ามาเพื่อ "ประกาศว่าจงใจไม่ใช้" — ตัวจัดรูปแบบบังคับ en_US_POSIX กับ
    /// ปฏิทินเกรกอเรียนเสมอ เพราะบัตรออกแบบมาเป็นรูปแบบนี้แบบเดียว ถ้าปล่อยให้ตาม locale เครื่อง
    /// มือถือที่ตั้งภาษาไทยจะได้ "29 ส.ค. 2569" (พุทธศักราช) ซึ่งเดฟที่ simulator เป็น en_US
    /// จะไม่มีวันเห็น · พารามิเตอร์นี้ทำให้เทสพิสูจน์ได้ และกันคนหวังดีเปลี่ยนไปใช้ .current ทีหลัง
    static func ticketDate(deviceLocale: Locale = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let date = cal.date(from: day) else { return "" }

        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: date).uppercased()
    }
}
