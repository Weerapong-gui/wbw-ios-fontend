import XCTest
@testable import WBW

final class FlexibleStringTests: XCTestCase {
    private struct Box: Codable { @FlexibleString var id: String }

    func testDecodesFromNumber() throws {
        let data = #"{"id": 123}"#.data(using: .utf8)!
        let box = try JSONDecoder().decode(Box.self, from: data)
        XCTAssertEqual(box.id, "123")
    }

    func testDecodesFromString() throws {
        let data = #"{"id": "456"}"#.data(using: .utf8)!
        let box = try JSONDecoder().decode(Box.self, from: data)
        XCTAssertEqual(box.id, "456")
    }
}
