import XCTest
@testable import WBW

final class QRCodeTests: XCTestCase {
    func testTokenProducesImage() {
        XCTAssertNotNil(QRCode.image(from: "ebbbf619f27d509fd1d880d1"))
    }
    func testEmptyStringReturnsNil() {
        XCTAssertNil(QRCode.image(from: ""))
    }
}
