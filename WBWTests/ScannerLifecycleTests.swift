import XCTest

/// วงจรชีวิตของกล้องสแกน — **เทสสแกนซอร์ส ไม่ได้รันกล้องจริง**
///
/// รันกล้องในเทสไม่ได้: ซิมูเลเตอร์ไม่มีกล้อง (`AVCaptureDevice.default` คืน nil) และ
/// `viewWillAppear`/`viewWillDisappear` เป็น callback ของ UIKit ที่ต้องมีจอจริงถึงจะยิง
/// · สิ่งที่จับได้จากที่นี่คือ "โครงสร้างยังถูกอยู่ไหม" ซึ่งพอสำหรับบั๊กคลาสนี้
/// (ทรงเดียวกับ `Map3DScreenLifecycleTests` ที่สแกนซอร์สด้วยเหตุผลเดียวกัน)
///
/// **บั๊กที่เทสนี้มีไว้กัน**: ของเดิม `startRunning()` อยู่ใน `viewDidLoad` ที่เดียว ส่วน
/// `viewWillDisappear` สั่ง `stopRunning()` — ไม่มีใครสั่งเริ่มใหม่เลย · เจ้าหน้าที่สลับไป
/// แท็บ SOS แล้วกลับมา หรือโดนจอเคสใหม่ทับ (ซึ่งเป็นสถานการณ์ที่ออกแบบไว้ตั้งใจ
/// ดู `RootView` `.fullScreenCover(item: $sosStaff.newCase)`) จะได้ช่องมองดำถาวร
/// จนกว่าจะปิดแอปเปิดใหม่ · ไม่มี error ไม่มีข้อความ อ่านเหมือนกล้องเสีย และช่องกรอก BIB
/// ยังใช้ได้อยู่ ทำให้ดูเหมือน "QR ของผู้เข้าร่วมมีปัญหา" แทนที่จะดูเหมือนแอปพัง
final class ScannerLifecycleTests: XCTestCase {

    private static let source: String = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("WBW/StaffScanView.swift")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    private var code: String {
        Self.source.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    func testTheScannerHasAWayToStartAgainNotJustToStop() {
        XCTAssertFalse(code.isEmpty, "อ่าน WBW/StaffScanView.swift ไม่ได้")
        XCTAssertTrue(code.contains("override func viewWillDisappear"),
                      "ต้องยังหยุดกล้องตอนจอหาย — ไม่งั้นเผาแบตให้สิ่งที่ไม่มีใครดู")
        XCTAssertTrue(code.contains("override func viewWillAppear"), """
            มีแต่ทางหยุด ไม่มีทางเริ่ม — สลับแท็บแล้วกลับมาจะได้ช่องมองดำถาวร
            """)
    }

    /// `updateUIViewController` ว่างเปล่า = SwiftUI สั่งอะไรกล้องที่สร้างไปแล้วไม่ได้เลย
    /// ซึ่งเป็นทั้งเหตุของบั๊กข้างบนและเหตุที่ปุ่มเปิด/ปิดทำไม่ได้
    func testSwiftUICanStillTalkToARunningScanner() {
        XCTAssertTrue(code.contains("func updateUIViewController"),
                      "ไม่มี updateUIViewController")
        XCTAssertTrue(code.contains("vc.setRunning("), """
            `updateUIViewController` ต้องส่งความตั้งใจล่าสุดลงไปหา VC ทุกรอบ
            ปล่อยว่างเมื่อไหร่ ปุ่มเปิด/ปิดจะกลายเป็นปุ่มที่กดแล้วไม่มีอะไรเกิดขึ้น
            """)
    }

    /// กรอบเล็งต้องเป็นของจริง — วาดกรอบไว้แล้วอ่านทั้งเฟรมคือการโกหกผู้ใช้
    ///
    /// ไม่ตั้ง `rectOfInterest` แล้วคนที่ยืนต่อคิวข้างหลังซึ่งถือบัตรของตัวเองอยู่ อาจถูก
    /// เช็คอินแทนคนที่เจ้าหน้าที่เล็ง โดยการ์ดผลขึ้นชื่อคนนั้นจริง ๆ ไม่มีอะไรให้สงสัยเลย
    func testTheAimingBoxActuallyLimitsWhatIsScanned() {
        XCTAssertTrue(code.contains("rectOfInterest"), """
            มีกรอบเล็งบนจอแต่ไม่ได้จำกัดพื้นที่อ่านจริง — กรอบกลายเป็นของประดับที่ชวนเข้าใจผิด
            """)
    }

    /// ระบบยึดกล้องไปแล้วต้องมีคนรับรู้ — เพิ่งเป็นเรื่องจริงตอนเปิด iPad (Split View)
    func testSomethingListensWhenTheSystemTakesTheCameraAway() {
        XCTAssertTrue(code.contains("wasInterruptedNotification"),
                      "ไม่มีใครรับรู้ตอนกล้องถูกยึด — ได้ช่องมองดำเงียบ ๆ")
        XCTAssertTrue(code.contains("interruptionEndedNotification"),
                      "รู้ตอนถูกยึดแต่ไม่รู้ตอนได้คืน = ดำค้างต่อทั้งที่กล้องว่างแล้ว")
    }
}
