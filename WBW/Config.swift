import Foundation

enum Config {
    /// backend ที่ deploy จริง (public ผ่าน Cloudflare tunnel บน archlinux) — ทุก client เข้าได้ทุกที่
    /// dev local: เปลี่ยนเป็น http://localhost:4000 (sim) หรือ LAN IP (เครื่องจริง)
    static let apiBase = "https://wbw.sumfu.store"
}

/// สีธีม (DOI-APP)
import SwiftUI
extension Color {
    static let wbwCream = Color(red: 222 / 255, green: 198 / 255, blue: 132 / 255) // #DEC684
    static let wbwInk = Color(red: 43 / 255, green: 43 / 255, blue: 43 / 255)
    static let wbwGold = Color(red: 201 / 255, green: 154 / 255, blue: 31 / 255) // #C99A1F ทอง
    static let wbwGreen = Color(red: 64 / 255, green: 145 / 255, blue: 108 / 255) // #40916C เขียวป่า (toggle on)
}
