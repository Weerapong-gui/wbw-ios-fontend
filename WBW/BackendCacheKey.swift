import Foundation

/// ชื่อสั้นๆ ของแต่ละ backend ไว้ทำ key ของ cache
///
/// อยู่แยกไฟล์จาก Config.swift ตั้งใจ — Config.swift มีบรรทัด Config.backend ที่
/// เปลี่ยนไปมาระหว่างทดสอบและห้าม commit การแยกไว้ทำให้แก้ไฟล์นี้แล้ว stage ได้เลย
///
/// cache ทุกตัวในแอปต้องแยกตาม backend: id ของ checkpoint/message เดินคนละชุดต่อ
/// backend ถ้าใช้ key เดียวกัน สลับ backend แล้วได้ข้อมูลผิดโดยไม่มี error ไม่มี log
/// (ดู docs/sus-test-backend.md)
extension Backend {
    var cacheNamespace: String {
        switch self {
        case .prodNode:  return "prodNode"
        case .nodeLocal: return "nodeLocal"
        case .susLocal:  return "susLocal"
        case .susProd:   return "susProd"
        case .susLan:    return "susLan"
        }
    }
}

/// ขอบเขตของ cache ที่ซ้อนอยู่บน `Backend.cacheNamespace` อีกชั้น
///
/// โหมดเดโม่ใช้ข้อมูลจำลองที่ไม่ได้มาจาก backend ตัวไหนเลย ถ้าเขียนทับคีย์เดียวกับของจริง
/// reviewer ที่กดเข้าโหมดเดโม่แล้วออกมาล็อกอินด้วยบัญชีจริงจะเห็นความคืบหน้ากับความเห็นของ
/// ข้อมูลจำลองค้างอยู่ — เป็นอาการเดียวกับกับดัก "สลับ backend แล้วไม่ล้างข้อมูล" ที่เคยกินเวลา
/// มาแล้ว คือได้ 200 พร้อมข้อมูลผิด ไม่มี error ไม่มี log ให้เห็นเลย
///
/// **cache/persisted key ใหม่ทุกตัวต้องต่อทั้ง `cacheNamespace` และ `CacheScope.suffix`**
enum CacheScope {
    static let demoSuffix = ".demo"

    static var suffix: String { DemoMode.active ? demoSuffix : "" }
}
