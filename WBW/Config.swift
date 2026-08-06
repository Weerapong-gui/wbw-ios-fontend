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

    /// ต้นฉบับของสามตัวนี้คือ Task 13 (ดู task-13-brief.md ขั้นที่ 5: plist สิทธิ์ตำแหน่ง +
    /// เบอร์กลางงาน) แต่ต้องยกมานิยามที่นี่ก่อน เพราะ SOSStore.send (Task 12) เรียก
    /// cacheEmergencyPhone(_:) ทันทีที่ยิงสำเร็จครั้งแรก — ไฟล์ SOSStore.swift จึงคอมไพล์ไม่ผ่าน
    /// ถ้าไม่มีฟังก์ชันนี้อยู่ก่อน (พบตอนทำ Task 12 — เหมือนกับ SOSStaffCase ที่ Task 10 เจอกับ
    /// Task 15 มาก่อนแล้ว) เมื่อทำ Task 13 ควรเช็คว่าสามตัวนี้ตรงกับที่ตัวเองจะเพิ่มอยู่แล้วก่อนเพิ่มซ้ำ
    ///
    /// เบอร์กลางงาน — ค่าเริ่มต้นที่ฝังมากับแอป เผื่อยังไม่เคยคุยกับเซิร์ฟเวอร์สำเร็จเลย
    /// ค่าจริงมาจาก emergency_phone ใน /me/progress และคำตอบของ /me/sos แล้ว cache ทับ
    static let emergencyPhoneDefault = "053-916-000"

    static var emergencyPhone: String {
        UserDefaults.standard.string(forKey: "wbw.emergencyPhone.\(backend.cacheNamespace)")
            ?? emergencyPhoneDefault
    }

    static func cacheEmergencyPhone(_ phone: String) {
        guard !phone.isEmpty else { return }
        UserDefaults.standard.set(phone, forKey: "wbw.emergencyPhone.\(backend.cacheNamespace)")
    }
}

/// สีธีม (DOI-APP)
import SwiftUI
extension Color {
    static let wbwCream = Color(red: 222 / 255, green: 198 / 255, blue: 132 / 255) // #DEC684
    static let wbwInk = Color(red: 43 / 255, green: 43 / 255, blue: 43 / 255)
    static let wbwGold = Color(red: 201 / 255, green: 154 / 255, blue: 31 / 255) // #C99A1F ทอง
    static let wbwGreen = Color(red: 64 / 255, green: 145 / 255, blue: 108 / 255) // #40916C เขียวป่า (toggle on)
}
