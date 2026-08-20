import Foundation
import SwiftUI

/// ขั้นการบานของดอกไม้บนหน้า Home — 6 ขั้นตามจำนวนฐานที่เช็คอินแล้ว
///
/// ยกเกณฑ์มาจาก `stageFor` ใน `ui/home/Bloom.kt` ของแอป Android ตรง ๆ เพื่อให้สองแอปขึ้นขั้น
/// พร้อมกันเป๊ะ — คนละเกณฑ์แปลว่าเพื่อนสองคนที่เช็คอินเท่ากันเห็นดอกไม้คนละขั้น ซึ่งอ่านว่าแอปพัง
///
/// **ขั้น 0 เป็นเมล็ด ไม่ใช่จอว่าง** — คนที่ยังไม่ได้เช็คอินที่ไหนเลยก็ต้องเห็นสิ่งที่ตัวเองกำลังปลูก
enum BloomStages {
    static let count = 6

    static func stage(checkedIn: Int, total: Int) -> Int {
        guard total > 0, checkedIn > 0 else { return 0 }
        let fraction = min(max(Double(checkedIn) / Double(total), 0), 1)
        switch fraction {
        case ..<0.2: return 1
        case ..<0.4: return 2
        case ..<0.65: return 3
        case ..<0.9: return 4
        default: return 5
        }
    }

    /// ชื่อขั้น — ผ่านชุดคีย์ `bloom_stage_0..5` ร่วมกับ Android
    ///
    /// ขึ้นจอจริง (บรรทัดใต้แถบขั้นตอนพรีวิว) และถูก VoiceOver อ่านทุกชิป จึงต้องแปล
    static func label(_ stage: Int) -> String {
        switch min(max(stage, 0), 5) {
        case 0: return String(localized: "bloom_stage_0")
        case 1: return String(localized: "bloom_stage_1")
        case 2: return String(localized: "bloom_stage_2")
        case 3: return String(localized: "bloom_stage_3")
        case 4: return String(localized: "bloom_stage_4")
        default: return String(localized: "bloom_stage_5")
        }
    }
}
