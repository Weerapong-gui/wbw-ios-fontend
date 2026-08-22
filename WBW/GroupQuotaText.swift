import Foundation

// ประโยคทั้งหมดในไฟล์นี้ผ่านชุดคีย์ `group_quota_*` — มันคือข้อความที่บอกผู้ใช้ว่าการกดครั้งนี้
// จะทำอะไรกับสิทธิ์ที่เหลือ ซึ่งเป็นข้อมูลที่ผิดภาษาแล้วอ่านไม่ออกเลย ไม่ใช่แค่ดูแปลก

/// ข้อความทั้งหมดที่พูดถึงสิทธิ์ออกจากกลุ่ม — ฟังก์ชันบริสุทธิ์ ไม่มี view/state
///
/// `quota` ของทุกฟังก์ชันคือสิทธิ์ **ก่อน** ทำรายการเสมอ (ค่าที่อ่านได้จากโปรไฟล์ ณ ตอนนั้น)
/// การเข้ากลุ่มไม่หักสิทธิ์ ส่วนการออกหัก 1 — ตัวข้อความคำนวณผลลัพธ์ให้เอง ผู้เรียกไม่ต้องลบเอง
/// ไม่งั้นจุดเรียกแต่ละที่จะลบกันคนละแบบจนเลขไม่ตรงกัน
enum GroupQuotaText {

    static func joinWarning(groupNumber: Int, quota: Int) -> String {
        quota > 0
            ? String(format: Loc.t("group_quota_join_left"), groupNumber, quota)
            : String(format: Loc.t("group_quota_join_none"), groupNumber)
    }

    static func leaveWarning(groupNumber: Int, quota: Int) -> String {
        // quota <= 0 ต้องแยกเป็นเคสของตัวเอง — ถ้าใช้ max(quota - 1, 0) เหมือนเดิม
        // ทั้ง quota=0 (ไม่มีสิทธิ์ตั้งแต่ต้น) กับ quota=1 (นี่คือครั้งสุดท้ายที่ยังออกได้) จะ clamp
        // เหลือ 0 เท่ากัน แล้วได้ประโยค "เลือกกลุ่มใหม่ได้อีกครั้งเดียว" เหมือนกันทั้งคู่
        // ซึ่งหลอกคนที่สิทธิ์หมดแล้วว่ายังมีสิทธิ์เหลืออีกหนึ่งครั้ง — คนละความจริงกัน ห้ามใช้ประโยคเดียวกัน
        guard quota > 0 else {
            return String(format: Loc.t("group_quota_leave_none"), groupNumber)
        }
        let after = quota - 1
        return after == 0
            ? String(format: Loc.t("group_quota_leave_last"), groupNumber)
            : String(format: Loc.t("group_quota_leave_left"), groupNumber, after)
    }

    static func remaining(quota: Int) -> String {
        // ใช้คำว่า "สิทธิ์ออกจากกลุ่ม" ให้ตรงกับข้อความอื่นในไฟล์นี้ทุกจุด — เดิมเคสหมดสิทธิ์ใช้คำว่า
        // "เปลี่ยนกลุ่ม" ซึ่งเป็นคนละคำ อ่านแล้วเหมือนพูดถึงสิทธิ์คนละตัวกัน
        quota > 0
            ? String(format: Loc.t("group_quota_remaining"), quota)
            : Loc.t("group_quota_none")
    }
}
