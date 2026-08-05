import Foundation

/// สูตรที่แปลง "เช็คอินไปกี่ฐาน" เป็นขนาดต้นไม้กับเวลาของวัน
///
/// เว็บใช้ตารางความสูงตายตัว 5 ค่า [0.7, 1.3, 2.2, 3.4, 5.0] (อัตราส่วนระหว่างขั้นติดกันไม่คงที่ —
/// 1.86, 1.69, 1.55, 1.47 ตามลำดับ ค่าเฉลี่ยเรขาคณิต ≈1.64)
/// ที่นี่ใช้สูตรแทน เพราะ total มาจาก DB — แอดมินเพิ่ม/ลบฐานได้ ตารางตายตัวจะพังทันที
enum ForestMath {
    static let minTreeHeight: Float = 0.7
    static let maxTreeHeight: Float = 5.0

    /// ช่วงเวลาของวันที่ใช้จริง — ปลายทั้งสองข้างของ 0..1 มืดเกินกว่าจะอ่าน UI ที่ลอยทับ
    /// (ค่าเดียวกับ DAY_FROM/DAY_TO ใน ~/su-wbw-website/lib/dayCycle.ts)
    static let dayFrom: Float = 0.14
    static let dayTo: Float = 0.78

    /// เวลากลางวันนิ่งๆ สำหรับหน้าที่ไม่มีความคืบหน้า (Login, QR)
    static let dayStill: Float = 0.46
    /// เช้าตรู่ — หน้า Welcome
    static let dayWelcome: Float = 0.20

    private static func fraction(_ stage: Int, _ total: Int) -> Float {
        guard total > 0 else { return 0 }
        return Float(min(max(stage, 0), total)) / Float(total)
    }

    static func treeHeight(stage: Int, total: Int) -> Float {
        minTreeHeight * pow(maxTreeHeight / minTreeHeight, fraction(stage, total))
    }

    static func day(stage: Int, total: Int) -> Float {
        dayFrom + (dayTo - dayFrom) * fraction(stage, total)
    }
}
