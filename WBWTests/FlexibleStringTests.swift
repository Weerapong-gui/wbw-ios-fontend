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

    func testDecodesFromIntegralDouble() throws {
        let data = #"{"id": 123.0}"#.data(using: .utf8)!
        let box = try JSONDecoder().decode(Box.self, from: data)
        XCTAssertEqual(box.id, "123")
    }

    func testThrowsOnUnrepresentableValue() throws {
        let data = #"{"id": true}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(Box.self, from: data))
    }
}
