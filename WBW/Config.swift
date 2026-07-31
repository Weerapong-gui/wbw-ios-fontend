import Foundation

/// backend ปลายทาง — สลับทั้งแอปทีเดียว (JWT คนละ secret ต่อ backend)
enum Backend {
    case prodNode   // Node เดิม (ใช้งานได้จริงตอนนี้)
    case nodeLocal  // Node ตัวเดียวกัน แต่รัน docker stack ในเครื่อง (dev เทส long-poll ฯลฯ)
    case susLocal   // Student-Union-Server รันในเครื่อง
    case susProd    // SUS ที่ deploy แล้ว (รอ URL จากเพื่อน)

    var apiBase: String {
        switch self {
        case .prodNode:  return "https://wbw.sumfu.store"
        case .nodeLocal: return "http://localhost:4000"
        case .susLocal:  return "http://localhost:8080/wbw"
        case .susProd:   return "https://TODO-set-sus-host/wbw"
        }
    }

    /// โปรไฟล์ผู้ใช้ปัจจุบัน — Node อยู่ที่ /auth/me, SUS อยู่ที่ /me
    var mePath: String {
        switch self {
        case .prodNode, .nodeLocal: return "/auth/me"
        case .susLocal, .susProd:   return "/me"
        }
    }
}

enum Config {
    /// เปลี่ยนค่าเดียวนี้เพื่อสลับ backend
    static let backend: Backend = .prodNode
    static var apiBase: String { backend.apiBase }
    static var mePath: String { backend.mePath }
}

/// สีธีม (DOI-APP)
import SwiftUI
extension Color {
    static let wbwCream = Color(red: 222 / 255, green: 198 / 255, blue: 132 / 255) // #DEC684
    static let wbwInk = Color(red: 43 / 255, green: 43 / 255, blue: 43 / 255)
    static let wbwGold = Color(red: 201 / 255, green: 154 / 255, blue: 31 / 255) // #C99A1F ทอง
    static let wbwGreen = Color(red: 64 / 255, green: 145 / 255, blue: 108 / 255) // #40916C เขียวป่า (toggle on)
}
