import XCTest
import AVFoundation
@testable import WBW

/// สิทธิ์กล้องของจอเจ้าหน้าที่ — **เคยไม่มีการเช็คเลย**
///
/// `ScannerVC.viewDidLoad` เดิมเป็น `guard let device = ..., let input = try? ... else { return }`
/// ล้วน ๆ · ผู้ใช้กด "ไม่อนุญาต" แล้วได้สี่เหลี่ยมดำ 300pt ค้างถาวร ไม่มีข้อความ ไม่มีปุ่ม
/// ไม่มีทางแก้ในแอป ซึ่งเป็นรูปแบบที่ App Store Guideline 5.1.1 ตีกลับตรง ๆ
///
/// แยกเป็นฟังก์ชันบริสุทธิ์เพราะ `AVAuthorizationStatus` จริงตั้งค่าในเทสไม่ได้ — ตัวที่ต้อง
/// พิสูจน์คือ "สถานะไหนแปลว่าอะไร" ไม่ใช่ตัว AVFoundation
final class StaffScanPermissionTests: XCTestCase {

    func testAuthorisedIsTheOnlyStateThatOpensTheCamera() {
        XCTAssertEqual(CameraPermission.from(.authorized), .ready)
    }

    /// `.notDetermined` ต้องถามก่อน ไม่ใช่เหมาเป็นถูกปฏิเสธ — เหมาแล้วผู้ใช้จะไม่มีวันได้เห็น
    /// กล่องขอสิทธิ์ของระบบเลยสักครั้ง แล้วจอสแกนจะพังตั้งแต่เปิดครั้งแรก
    func testNotDeterminedAsksInsteadOfGivingUp() {
        XCTAssertEqual(CameraPermission.from(.notDetermined), .ask)
    }

    /// `.restricted` (เครื่องถูกล็อกด้วย MDM หรือ Screen Time) ต้องเดินทางเดียวกับ `.denied`
    /// — ผู้ใช้เปิดเองไม่ได้ทั้งคู่ ต้องได้ข้อความบอกและช่องกรอก BIB สำรอง
    func testDeniedAndRestrictedBothLandOnTheExplanation() {
        XCTAssertEqual(CameraPermission.from(.denied), .denied)
        XCTAssertEqual(CameraPermission.from(.restricted), .denied)
    }

    /// สถานะใหม่ที่ Apple อาจเพิ่มมาในอนาคตต้องตกไปทางที่ปลอดภัย (มีข้อความอธิบาย)
    /// ไม่ใช่ `.ready` ที่จะพากลับไปเป็นจอดำเงียบแบบเดิม
    func testUnknownFutureStatusFallsBackToTheExplanation() {
        XCTAssertEqual(CameraPermission.from(AVAuthorizationStatus(rawValue: 99) ?? .denied), .denied)
    }
}
