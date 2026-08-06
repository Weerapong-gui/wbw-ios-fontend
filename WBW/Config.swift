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
}

/// สีธีม (DOI-APP)
import SwiftUI
extension Color {
    static let wbwCream = Color(red: 222 / 255, green: 198 / 255, blue: 132 / 255) // #DEC684
    static let wbwInk = Color(red: 43 / 255, green: 43 / 255, blue: 43 / 255)
    static let wbwGold = Color(red: 201 / 255, green: 154 / 255, blue: 31 / 255) // #C99A1F ทอง
    static let wbwGreen = Color(red: 64 / 255, green: 145 / 255, blue: 108 / 255) // #40916C เขียวป่า (toggle on)

    /// พื้นหลังทึบแทนฉากป่าตอน Config.forest3D ปิด — สีเดียวกับ scrim เดิมของ ForestOverlay
    static let wbwForestVoid = Color(red: 10 / 255, green: 22 / 255, blue: 16 / 255) // #0A1610
}
