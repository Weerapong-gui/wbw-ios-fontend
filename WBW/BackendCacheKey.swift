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
