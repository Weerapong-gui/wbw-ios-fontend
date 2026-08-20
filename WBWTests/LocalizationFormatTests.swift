import XCTest
@testable import WBW

/// คีย์ที่ถูกป้อนด้วยตัวเลขต้องไม่ใช้ตัวระบุของ object
///
/// **นี่คือคลาสของบั๊กที่ทำให้หน้าบัตร (แท็บ QR) crash จริง** — `"group_number_str" = "Group %1$@"`
/// ถูกเรียกด้วย `me?.groupNumber` ซึ่งเป็น `Int` · `String(format:)` เอา 7 ไปตีความเป็นตัวชี้ object
/// แล้วส่งข้อความ `description` ไปที่แอดเดรส 0x7 → `EXC_BAD_ACCESS` ทันทีที่เปิดแท็บ
///
/// คอมไพเลอร์ไม่เห็นเลย: `String(format:)` รับ `CVarArg` ทุกชนิด และคีย์เป็นสตริง เทสนี้กับ
/// `scripts/check-localization.sh` (ที่เทียบตัวระบุระหว่าง en/th) คือสองด่านที่มีจริง
final class LocalizationFormatTests: XCTestCase {

    /// ทุกคีย์ที่จุดเรียกส่ง `Int` เข้าไป — ดูรายการจริงได้จาก `grep 'String(format: Loc.t('`
    private let integerKeys = [
        "group_number", "group_join_confirm", "group_leave_confirm",
        "group_quota_join_left", "group_quota_join_none", "group_quota_leave_none",
        "group_quota_leave_last", "group_quota_leave_left", "group_quota_remaining",
        "chat_members_count", "chat_new_messages_count", "chat_read_by", "chat_read_by_all",
        "home_checked_in", "home_weather_feels", "home_air_aqi",
        "map_base_number", "walk_distance_m_short", "checkin_toast_more",
    ]

    func testIntegerKeysNeverUseTheObjectSpecifier() {
        for key in integerKeys {
            let value = Loc.t(key)
            XCTAssertNotEqual(value, key, "ไม่มีคีย์ \(key) ในชุดข้อความ")
            XCTAssertFalse(value.contains("%@") || value.contains("$@"),
                           "\(key) = \"\(value)\" ใช้ `%@` กับค่าที่เป็น Int — จะ crash ตอนวาดจอ")
        }
    }

    /// คีย์ที่รับ String ต้องใช้ `%@` ไม่ใช่ `%lld` — ทางกลับกันของบั๊กเดียวกัน
    func testStringKeysUseTheObjectSpecifier() {
        for key in ["home_greeting", "group_number_str", "checkin_toast_title", "profile_hw_value"] {
            let value = Loc.t(key)
            XCTAssertTrue(value.contains("%@") || value.contains("$@"),
                          "\(key) = \"\(value)\" รับ String แต่ไม่มี `%@`")
        }
    }

    /// `Loc` ต้องเปลี่ยน bundle ตามภาษาที่เลือกจริง ไม่ใช่ตามภาษาของเครื่อง
    ///
    /// ถ้าข้อนี้พัง แปลว่าผู้ใช้ที่เลือก "ไทย" บนเครื่องภาษาอังกฤษจะได้แอปครึ่งไทยครึ่งอังกฤษ:
    /// ปุ่มใน View แปลตาม (`Text` อ่าน `\.locale`) ส่วนข้อความ error กับป้ายบนบัตรไม่แปล
    func testLocFollowsTheInAppLanguageChoice() {
        defer { Loc.use(.system) }
        Loc.use(.th)
        let thai = Loc.t("action_back")
        Loc.use(.en)
        let english = Loc.t("action_back")
        XCTAssertNotEqual(thai, english, "สลับภาษาแล้วข้อความต้องเปลี่ยน (ได้ \"\(thai)\" ทั้งสองรอบ)")
        XCTAssertEqual(english, "Back")
    }
}
