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

/// สีธีม — **ยกมาจาก `ui/theme/Color.kt` ของแอป Android ทั้งชุด (2026-08-20)**
///
/// Android เขียนไว้ตรง ๆ ว่าชุดนี้มาแทนของ iOS: *"the iOS palette assumed a bright cream
/// photograph (`wbwBg` #FAF7F0)… their mustard gold went muddy"* — พื้นของแอปเป็นภาพป่าเขียวเข้ม
/// สีครีม/ทองที่เคยออกแบบไว้กับพื้นสว่างจึงกลายเป็นเทากับโคลนบนพื้นนี้
///
/// **ไม่มีสีเน้นแล้ว** (`"There is no accent hue."`) ทองแล้วเขียวใบไม้ถูกลองทั้งคู่และแพ้ด้วย
/// เหตุผลเดียวกัน — จอมีภาพถ่ายกับกระจกทำงานอยู่แล้ว สีเน้นบนนั้นคือของชิ้นที่สี่ที่แย่งความสนใจ
/// ลำดับชั้นจึงมาจาก **น้ำหนัก ขนาด และ letterspacing บน ink สีเดียว** แบบเดียวกับบัตรผู้เข้าร่วม
///
/// กฎสองข้อที่ยึดชุดนี้ไว้ (ยกมาจากคอมเมนต์ต้นทาง):
/// 1. **พื้นเดียวทั้งสองธีม** — ภาพพื้นหลังไม่ถูกย้อมใหม่ตามธีม ของที่เปลี่ยนคือสิ่งที่วาง *บน* พื้น
///    ตัวอักษรที่วางลงบนภาพตรง ๆ จึงต้องใช้ `wbwOnBackdrop` ไม่ใช่ `wbwInk`
/// 2. **accent ปรับแสง ไม่พลิกสี** — คงเฉดเดิมทั้งสองธีม เปลี่ยนแค่ความสว่าง
import SwiftUI
import UIKit   // UIColor(dynamicProvider:) — SwiftUI ไม่ได้ re-export UIKit ให้
extension Color {

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    private static func hex(_ value: UInt32, alpha: Double = 1) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255,
              opacity: alpha)
    }

    private static func ui(_ value: UInt32) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    // ===== ตัวอักษรบนพื้นภาพ — สว่างทั้งสองธีม =====
    //
    // พื้นหลังเป็นภาพเดียวและมืดเสมอไม่ว่าผู้ใช้เลือกธีมไหน ตัวอักษรที่วางลงบนภาพจึงตามธีมไม่ได้
    // ใช้ `wbwInk` ตรงนี้เมื่อไหร่ หัวข้อจะหายไปในโหมดสว่าง
    static let wbwOnBackdrop = hex(0xE9EEE0)
    static let wbwOnBackdropMuted = hex(0xA2AF98)

    // ===== accent — คือ ink ไม่ใช่สีอื่น =====
    //
    // โทเคนยังอยู่เพื่อให้จุดเรียกคงความหมาย ("ตรงนี้คือส่วนที่เน้น") และเผื่อวันหลังอยากเอาเฉดสี
    // กลับมาจะได้แก้ที่เดียว
    static let wbwAccent = adaptive(light: ui(0x1B2A1B), dark: ui(0xE9EEE0))
    /// เวอร์ชันลดน้ำหนัก สำหรับ eyebrow กับเครื่องหมายรอง
    static let wbwAccentSoft = adaptive(light: ui(0x58684F), dark: ui(0xA2AF98))

    /// เขียวสถานะ — "เปิด", เช็คอินแล้ว, ความคืบหน้า
    ///
    /// ตั้งใจให้ลึกกว่า accent หนึ่งขั้นแทนที่จะเป็นคนละเฉด: อยู่ตระกูลเดียวกัน ตัวควบคุมที่ถูกเลือก
    /// กับของที่ทำเสร็จแล้วจึงอ่านว่าเกี่ยวข้องกัน และ accent ยังลอยอยู่ข้างบนเพราะสว่างกว่า
    static let wbwGreen = adaptive(light: ui(0x35784F), dark: ui(0x63B283))

    /// พื้นฉากตายตัวสำหรับของที่ต้องอยู่หลังตัวภาพเอง
    static let wbwForestVoid = hex(0x0B140E)

    /// แดงเลือดหมูของปุ่ม Medical ID — ใช้เป็น tint ของกระจก
    static let wbwMedical = hex(0x421717)

    static let wbwDanger = adaptive(light: ui(0xC0503A), dark: ui(0xE88B7A))

    // ===== พื้นผิว — ปรับตามโหมดมืด =====
    //
    // โหมดสว่างเป็นออฟไวท์อุ่นที่ยังมีเขียวปนอยู่ ไม่ใช่ขาวล้วน — ขาวล้วนบนพื้นป่าอ่านเป็น
    // "รูที่เจาะทะลุหน้ากระดาษ"
    static let wbwBg = adaptive(light: ui(0xEDF0E5), dark: ui(0x0F1610))
    static let wbwSurface = adaptive(light: ui(0xF5F4E9), dark: ui(0x1A2318))
    static let wbwInk = adaptive(light: ui(0x1B2A1B), dark: ui(0xE9EEE0))
    static let wbwMuted = adaptive(light: ui(0x58684F), dark: ui(0xA2AF98))
    static let wbwLine = adaptive(light: ui(0xDBDFCB), dark: ui(0x2F3B2B))

    // ===== กระจก =====
    //
    // แผ่นบางที่สุดเท่าที่ยังปิดรูปทรงได้ · **เหมือนกันทั้งสองธีมโดยตั้งใจ** — การ์ดสีอ่อนในโหมดสว่าง
    // แปลว่าทึบเกือบเต็มบนพื้นที่มีแต่ภาพมืด ที่ไหนที่ตัวกระจกคือประเด็น การแลกแบบนั้นผิดทาง
    //
    // เคยลองแผ่นย้อมเขียว (TicketGreen 30% แล้ว DeepForest) ผิดทั้งคู่ด้วยเหตุผลเดียวกัน:
    // **พื้นเขียวอยู่แล้ว** ย้อมแผ่นเป็นเขียวบนพื้นเขียวได้แค่สว่างขึ้น (มรกต ดังที่สุดบนจอ)
    // หรือมืดลง (กลายเป็นรู) ซึ่งไม่ใช่สิ่งที่กระจกทำ — กระจกรับสีจากสิ่งที่อยู่ข้างหลังมัน
    // ขาว 12% บนอาร์ตใบนี้ออกมาเป็นเขียวเอง นั่นคือกลของแถบแท็บมาตลอด
    // เขียนเป็นเศษส่วนของ 255 ไม่ใช่ 0.12/0.13 — ต้นทางเขียน alpha เป็นเลขฐานสิบหก
    // (`0x1FFFFFFF` / `0x21FFFFFF`) การปัดเป็นทศนิยมสองตำแหน่งเลื่อนค่าไปพอที่จะเห็นได้
    // ตอนวางสองแอปเทียบกัน และไม่มีอะไรจับได้นอกจากตาคน
    static let glassSheer = Color.white.opacity(31.0 / 255)        // GlassSheer / PassSurface
    static let glassSheerBorder = Color.white.opacity(33.0 / 255)  // GlassSheerBorder

    /// แผ่นสำหรับของที่แบก **ย่อหน้า** — เข้ม ตรงข้ามกับ `glassSheer` ที่เป็นแค่ฝ้าจาง
    ///
    /// มีเพราะบั๊กที่เลือกสีตัวอักษรยังไงก็แก้ไม่ได้ และตัวเลขที่วัดได้คุ้มที่จะเก็บไว้: บนจอประกาศ
    /// ของ Android พื้น *ข้างใน* การ์ด `GlassSheer` มีความสว่างไล่ตั้งแต่ 0.06 ถึง **0.36**
    /// เพราะแผ่นเป็นขาว 12% ทับภาพถ่ายที่มีช่วงสว่างอยู่ในนั้น · ตัวอักษรสีอ่อนต้องการความสว่าง
    /// ราว 1.8 จึงจะผ่าน WCAG AA บนพื้น 0.36 — และขาวคือ 1.0 ไม่มีหมึกสีไหนผ่านได้เลย
    ///
    /// ฝ้าจาง ๆ แก้ไม่ได้เพราะปัญหาคือ **ความแปรปรวน** ไม่ใช่ระดับ · แผ่นต้องกลบอาร์ตทิ้ง
    /// ไม่ใช่ย้อมมัน ตัวอักษรบรรทัดเดียวกันถึงจะเจอโทนเท่ากันทั้งสองปลาย · นั่นคือสิ่งที่แลก —
    /// การ์ดที่มีย่อหน้ายอมไม่โชว์ป่าผ่านตัวเอง เพื่อให้ได้พื้นที่ตัวอักษรนั่งได้จริง
    /// ส่วนของประดับจอ (ชิป HUD แถบแท็บ) เก็บ `glassSheer` ไว้ เพราะสองสามคำที่ขนาดและน้ำหนัก
    /// ระดับนั้นรอดได้ไม่ว่าข้างหลังจะเป็นอะไร
    ///
    /// เข้มแบบ "เกือบดำของพื้นภาพ" ไม่ใช่ดำสนิท มันจะได้ยังอ่านเป็นวัสดุเดียวกัน
    /// ที่ alpha ต่ำพอให้การหักเหยังบิดแสงตรงขอบได้อยู่ (`GlassPanel = 0xD10D170F`)
    static let glassPanel = hex(0x0D170F).opacity(209.0 / 255)

    // ===== บัตรผู้เข้าร่วม =====
    //
    // ชุดของบัตรเอง: ขาวสี่ระดับ เส้นผม และแผ่นหนึ่งใบ · ตายตัวทั้งสองธีมเพราะบัตรคือของที่ยกให้
    // เจ้าหน้าที่ดู ไม่ใช่พื้นผิวที่เดินตามการตั้งค่ารูปลักษณ์
    static let passInk = Color.white
    static let passMuted = Color.white.opacity(0.80)
    static let passFaint = Color.white.opacity(0.54)
    static let passHairline = Color.white.opacity(0.10)
    static let passWell = Color.white.opacity(0.06)
    static let passSurface = Color.white.opacity(0.12)
    /// ink ของของทึบชิ้นเดียวบนบัตร: บล็อก QR, ปุ่มหลัก
    static let passDeepInk = hex(0x16241A)

    static let ticketDeep = hex(0x14301F)
    static let ticketGreen = hex(0x2D6A4F)
    static let ticketCreamPaper = hex(0xFBF8EF)

    // ===== สภาพอากาศ =====
    //
    // ที่เดียวในแอปที่ใช้เฉดสีเพื่อ "บอกความหมาย" และข้อยกเว้นนี้แคบโดยตั้งใจ: ย้อมแค่ไอคอนสองตัว
    // บนแถวสภาพเส้นทางของ Home เท่านั้น — พระอาทิตย์ที่เทาเท่าเมฆฝนคือพระอาทิตย์ที่ไม่ได้ทำงาน
    //
    // ทุกตัวลดความอิ่มสีลงหนักจนอยู่ราวระดับเดียวกับตัวภาพพื้นหลังเอง (15–25%) เหลืองจัดหรือฟ้าจัด
    // คือหน้าตา "วิดเจ็ตอากาศขององค์กร" ที่ทั้ง palette นี้ตั้งใจหลบ และจะเอาพิกเซลสว่างที่สุดบนจอ
    // ไปวางข้างประโยคที่สำคัญน้อยที่สุด · **ตายตัวทั้งสองธีม** เพราะนั่งอยู่บนภาพพื้นหลังโดยตรง
    static let skySunTint = hex(0xDEC183)
    static let skyCloudTint = hex(0xAEB8AC)
    static let skyFogTint = hex(0xB4BEBD)
    static let skyRainTint = hex(0x93B2C2)
    static let skySnowTint = hex(0xC4D5DA)
    static let skyStormTint = hex(0xD2A264)

    /// คุณภาพอากาศ — ไล่ เขียว-เหลือง-แดง ตามที่คนคุ้นอยู่แล้ว แต่หรี่ความอิ่มสีลงมาเท่าไฟล์นี้
    static let airGoodTint = hex(0x8CC29B)
    static let airModerateTint = skySunTint
    static let airSensitiveTint = hex(0xDFA671)
    static let airUnhealthyTint = hex(0xE88B7A)

    // ===== ชื่อเดิม =====
    //
    // จอนอกไฟล์นี้ยังอ้างชื่อพวกนี้อยู่ เก็บไว้เป็น alias ชี้ไปชุดใหม่เพื่อให้การเปลี่ยนสีแพร่ไปทั้งแอป
    // โดยไม่ต้องแตะจุดเรียกพร้อมกันทีเดียว — **โค้ดใหม่ห้ามใช้** ให้ใช้ `wbwAccent`/`wbwOnBackdrop`
    // (ทำแบบเดียวกับ `// ===== Legacy names =====` ใน Color.kt ของ Android)
    static let wbwGold = wbwAccent
    static let wbwCream = wbwBg
    static let wbwTicketBG = ticketDeep
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
