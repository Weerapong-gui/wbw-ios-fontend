import XCTest
@testable import WBW

/// ตรึงลิงก์สมัครบัญชีไว้
///
/// เดิมข้อความ "Sign up" ที่หน้า login เป็น Text เฉยๆ กดไม่ได้ ไม่มี action — เป็นเหตุให้
/// App Review ตีกลับได้ตรงๆ ด้วย Guideline 2.1 เพราะ reviewer กดทุกอย่างบนจอแล้วสมัครไม่ได้
/// ตอนนี้เป็น Link จริง เทสนี้กันสองอย่าง: URL พิมพ์ผิดจนพัง และมีคนเผลอย้ายไป path อื่น
final class LoginViewTests: XCTestCase {

    func testRegisterURLIsWellFormedAndSecure() {
        let url = LoginView.registerURL
        XCTAssertEqual(url.scheme, "https", "ลิงก์ที่พาผู้ใช้ออกจากแอปต้องเป็น https")
        XCTAssertEqual(url.host, "walkbeyondthewild.studentunion.social")
        XCTAssertEqual(url.path, "/auth/participant/register")
    }

    func testRegisterURLPointsAtParticipantSignupNotStaff() {
        // เจ้าหน้าที่สมัครคนละหน้ากัน (/auth/staff/...) — หน้า login นี้เป็นของผู้เข้าร่วม
        XCTAssertFalse(LoginView.registerURL.absoluteString.contains("staff"),
                       "หน้า login ผู้เข้าร่วมต้องไม่พาไปหน้าสมัครเจ้าหน้าที่")
    }
}
