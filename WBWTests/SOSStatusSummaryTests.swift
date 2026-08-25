import XCTest
@testable import WBW

/// สองอย่างบนจอสถานะ SOS ที่ยกมาจากฝั่ง Android (`ui/map/SosButton.kt`)
///
/// 1. **บรรทัดบอกว่าเจ้าหน้าที่เห็นตำแหน่งเราแบบไหน** — เซิร์ฟเวอร์ส่ง `loc_source` มาอยู่แล้ว
///    (`gps` / `last_checkin` / `none`) แต่จอ iOS ไม่เคยพูดถึงมันเลย พูดแค่ตอนสิทธิ์ตำแหน่งขาด
///    · "เรารู้พิกัดคุณ" กับ "เราเดาจากฐานที่คุณเช็คอินล่าสุด ซึ่งอาจอยู่ห่างไปหนึ่งชั่วโมงเดิน"
///    เป็นคนละคำสัญญากัน คนที่กำลังรอความช่วยเหลือควรรู้ว่าได้อันไหน
/// 2. **การ์ดข้อมูลให้คนที่มาถึงอ่าน** — คนที่กดค้าง 3 วิเพราะเจ็บ มีโอกาสสูงที่จะยื่นเครื่อง
///    ให้เจ้าหน้าที่หรือคนแปลกหน้า · ของที่มีค่าตอนนั้นคือกรุ๊ปเลือดกับเบอร์ญาติ ไม่ใช่บรรทัดสถานะ
///
/// ทั้งคู่เป็นตรรกะล้วนเพื่อให้เทสได้โดยไม่ต้องมีจอ — ทรงเดียวกับ `LocationPrimer.shouldShow`
final class SOSStatusSummaryTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func me(_ json: String) throws -> Me {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(Me.self, from: Data(json.utf8))
    }

    // MARK: - เจ้าหน้าที่เห็นตำแหน่งเราแบบไหน

    func testGPSFixIsReportedAsAKnownPosition() {
        XCTAssertEqual(SOSWhere.from(locSource: "gps", checkpointName: "จุดปลูก"), .gps)
    }

    /// `last_checkin` **ไม่ใช่** ตำแหน่งจริง — เป็นฐานที่เช็คอินล่าสุด ซึ่งอาจอยู่ไกลไปแล้ว
    /// มีชื่อฐานก็บอกชื่อ เพราะ "ใกล้จุดปลูก" ใช้ตัดสินใจได้ ส่วน "ฐานล่าสุด" เฉย ๆ ใช้ไม่ได้
    func testLastCheckinNamesTheCheckpointWhenTheServerSentOne() {
        XCTAssertEqual(SOSWhere.from(locSource: "last_checkin", checkpointName: "จุดปลูก"),
                       .nearCheckpoint("จุดปลูก"))
    }

    func testLastCheckinWithoutANameStillSaysItIsOnlyTheLastCheckpoint() {
        XCTAssertEqual(SOSWhere.from(locSource: "last_checkin", checkpointName: nil), .lastCheckin)
        XCTAssertEqual(SOSWhere.from(locSource: "last_checkin", checkpointName: "  "), .lastCheckin)
    }

    /// **เดาไม่ออกต้องพูดว่าไม่รู้** — ค่าที่ไม่รู้จักหรือหายไปแปลว่าเซิร์ฟเวอร์ไม่มีตำแหน่งให้
    /// เจ้าหน้าที่เลย · ตกไปทาง "รู้" คือการโกหกคนที่กำลังรออยู่ว่ามีคนรู้ว่าเขาอยู่ไหน
    func testAnythingElseIsReportedAsNoPositionAtAll() {
        for raw in [nil, "none", "", "somethingNew"] {
            XCTAssertEqual(SOSWhere.from(locSource: raw, checkpointName: "จุดปลูก"), .unknown,
                           "loc_source \(raw ?? "nil") ไม่ควรถูกอ่านว่ารู้ตำแหน่ง")
        }
    }

    // MARK: - การ์ดข้อมูลให้คนที่มาถึงอ่าน

    /// **สี่แถวเสมอ ไม่ว่าโปรไฟล์จะมีอะไรบ้าง** — แถวที่หายไปทำให้การ์ดดูครบทั้งที่ไม่ครบ
    /// คนที่กวาดตาหากรุ๊ปเลือดต้องได้คำตอบว่า "ไม่มีในระบบ" ไม่ใช่สงสัยว่าตัวเองมองข้าม
    func testTheCardAlwaysHasFourRowsEvenForAnEmptyProfile() throws {
        let bare = try me(#"{"user_id":"u1","username":"6931900011","role":"participant"}"#)
        let rows = SOSVitals.rows(for: bare)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.map(\.labelKey),
                       ["sos_vitals_blood", "sos_vitals_contact", "sos_vitals_bib", "sos_vitals_group"])
        XCTAssertTrue(rows.allSatisfy { $0.value == nil }, "ค่าที่ไม่มีต้องเป็น nil ให้จอพิมพ์ว่าไม่ได้ระบุ")
    }

    func testTheCardReadsWhatTheProfileActuallyHas() throws {
        let full = try me(#"""
        {"user_id":"u1","username":"6931900011","role":"participant","blood_type":"O+",
         "emergency_contact_name":"ผู้ปกครอง ตัวอย่าง","emergency_contact_phone":"0800000001",
         "bib_number":1042,"group_number":7}
        """#)
        let rows = SOSVitals.rows(for: full)
        XCTAssertEqual(rows[0].value, "O+")
        XCTAssertEqual(rows[1].value, "ผู้ปกครอง ตัวอย่าง · 0800000001")
        XCTAssertEqual(rows[2].value, "1042")
        XCTAssertEqual(rows[3].value, "7")
    }

    /// มีแต่เบอร์ ไม่มีชื่อ ก็ยังใช้ได้ — คนที่มาถึงกดโทรได้โดยไม่ต้องรู้ว่าโทรหาใคร
    func testTheContactRowWorksWithOnlyANumber() throws {
        let phoneOnly = try me(#"""
        {"user_id":"u1","username":"x","role":"participant","emergency_contact_phone":"0800000001"}
        """#)
        XCTAssertEqual(SOSVitals.rows(for: phoneOnly)[1].value, "0800000001")
    }

    /// ไม่มีโปรไฟล์ในมือเลย (ยังโหลดไม่เสร็จ/ล็อกอินค้างจากบิลด์เก่า) — การ์ดยังต้องขึ้นครบสี่แถว
    /// ว่าง ๆ ไม่ใช่หายไปทั้งใบ จอนี้ห้ามรอเน็ตเพื่อจะบอกกรุ๊ปเลือดใคร
    func testTheCardSurvivesHavingNoProfileAtAll() {
        XCTAssertEqual(SOSVitals.rows(for: nil).count, 4)
    }

    /// เบอร์ที่มีขีด/ช่องว่างต้องโทรออกได้ — `URL(string:)` กับ `tel://080-000-0001` คืน nil
    func testTheDialableNumberStripsWhateverIsNotADigit() {
        XCTAssertEqual(SOSVitals.dialable("080-000 0001"), "0800000001")
        XCTAssertEqual(SOSVitals.dialable("+66 80 000 0001"), "+66800000001")
        XCTAssertNil(SOSVitals.dialable("ไม่มีเบอร์"))
        XCTAssertNil(SOSVitals.dialable(nil))
    }

    // MARK: - เคสที่กดแทนคนอื่น

    /// **การ์ดต้องไม่ขึ้นเมื่อเคสเป็นของคนอื่น** — คนเจ็บไม่ใช่เจ้าของเครื่อง กรุ๊ปเลือดบนจอ
    /// จึงเป็นข้อมูลผิดคนในมือคนที่มาช่วย · ฝั่งเซิร์ฟเวอร์กันเรื่องเดียวกันด้วยเงื่อนไข
    /// `NOT s.for_other` ตอนเปิดข้อมูลสุขภาพให้เจ้าหน้าที่ (ดู `SOSStore.markForOther`)
    ///
    /// กวาดซอร์สแบบเดียวกับ `PermissionCopyTests` เพราะเงื่อนไขนี้อยู่ในตัว View ซึ่งไม่มี API
    /// ให้ assert และถอด guard ออกแล้วไม่มีอะไรฟ้องเลยจนกว่าจะมีเคสจริง
    func testTheCardIsGatedOnTheCaseNotBeingForSomebodyElse() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("WBW/SOS/SOSStatusView.swift"),
            encoding: .utf8)
        let card = source.components(separatedBy: "vitalsCard").dropFirst().first ?? ""
        XCTAssertTrue(card.contains("isForOther") || source.contains("!isForOther"),
                      "การ์ดข้อมูลไม่ได้กันเคสที่กดแทนคนอื่น — ข้อมูลผิดคนในมือคนที่มาช่วย")
    }
}
