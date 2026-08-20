import XCTest
@testable import WBW

/// ค่าที่ผูกกับ `map.usdz` ทั้งหมดถูกย้ายมาอยู่ใน `WBW/Resources/map_config.json` ไฟล์เดียว
/// เพราะโมเดลจะถูกเปลี่ยนใบ — เดิมค่าพวกนี้กระจายอยู่ 4 ไฟล์ (ชื่อ prim ของหมุด, กรอบ lat/lng,
/// มุมหันพื้นที่งาน, ขอบเขตกล้อง) เปลี่ยนโมเดลทีต้องไล่แก้ทีละที่โดยไม่มีอะไรฟ้องว่าลืมที่ไหน
///
/// เทสชุดนี้คุมสองเรื่องที่ผิดแล้ว "แอปยังรันได้" จนกว่าจะมีคนเปิดแท็บแผนที่แล้วเจอเอง:
/// ไฟล์ถูก bundle ไปจริงไหม และ JSON ที่พิมพ์ผิดถูกปฏิเสธจนตกไปใช้ค่า fallback ไหม
final class Map3DConfigFileTests: XCTestCase {

    // MARK: - ไฟล์จริงที่ไปกับแอป

    /// ไฟล์ต้องอยู่ใน bundle จริง ไม่ใช่แค่มีอยู่ใน repo — XcodeGen เก็บของที่ไม่ใช่ `.swift`
    /// ใน `WBW/` เป็น resource ให้เอง แต่ถ้าวันหลังมีคนย้ายไฟล์ออกนอกโฟลเดอร์นั้น
    /// แอปจะเงียบ ๆ ตกไปใช้ fallback แทน ซึ่งอ่านจากจอไม่ออกเลยว่าเกิดอะไรขึ้น
    func testShippedConfigIsInTheAppBundleAndDecodes() {
        XCTAssertNotNil(Map3DConfig.bundled,
                        "ไม่เจอ map_config.json ใน bundle — แอปจะใช้ fallback โดยไม่มีอะไรฟ้อง")
    }

    func testShippedConfigNamesPinsForEveryBaseInOrder() throws {
        let config = try XCTUnwrap(Map3DConfig.bundled)
        XCTAssertEqual(config.pins.map(\.sequence), Array(1...config.pins.count),
                       "ลำดับฐานต้องเรียง 1…N ไม่ขาดไม่ซ้ำ — ซ้ำแล้วคนเดินผิดฐานจริง")
        let names = config.pins.flatMap(\.entityNames)
        XCTAssertEqual(Set(names).count, names.count,
                       "ชื่อ prim ซ้ำกัน แปลว่าสองฐานชี้ prim เดียวกัน")
    }

    /// ชื่อ prim ต้องลงท้ายด้วยเลขเดียวกับ `sequence` — โมเดล Map2.0 ปั้นเลขฐานติดหมุดมาแล้ว
    /// (`marker_5` คู่กับเลข 5 ที่คนเดินเห็นอยู่บนแผนที่) พิมพ์สลับตัวเดียวคือคนเดินผิดฐานจริง
    /// และไม่มีอะไรฟ้องเลยนอกจากมีคนเปิดแท็บแล้วแตะเทียบทีละอัน
    func testShippedConfigPinNamesEndWithTheirOwnSequence() throws {
        let config = try XCTUnwrap(Map3DConfig.bundled)
        for pin in config.pins {
            for name in pin.entityNames {
                XCTAssertTrue(name.hasSuffix("_\(pin.sequence)"),
                              "\(name) อยู่ในฐานที่ \(pin.sequence) แต่ชื่อไม่ได้ลงท้ายด้วยเลขนั้น")
            }
        }
    }

    /// ค่าที่ส่งไปกับแอปต้องเป็นค่าเดียวกับที่ fallback ถืออยู่ ไม่งั้นการทดสอบทั้งหมดที่รันโดยไม่มี
    /// bundle (เช่นเทสอื่นที่เรียก Map3DCamera ตรง ๆ) จะวัดคนละชุดค่ากับที่ผู้ใช้เห็นจริง
    func testShippedConfigMatchesTheCompiledFallback() throws {
        XCTAssertEqual(try XCTUnwrap(Map3DConfig.bundled), Map3DConfig.fallback)
    }

    // MARK: - JSON ที่พิมพ์ผิดต้องถูกปฏิเสธ

    private func decode(_ json: String) -> Map3DConfig? {
        Map3DConfig.decode(Data(json.utf8))
    }

    private func anchorJSON(unitsPerDegreeLatitude: String = "118498.01",
                            unitsPerDegreeLongitude: String = "111319.49",
                            halfSpanUnitsEastWest: String = "2230.0",
                            halfSpanUnitsNorthSouth: String = "2230.0",
                            userDotHeightUnits: String = "320.0") -> String {
        """
        {"originLatitude":20.04549,"originLongitude":99.90280,
         "unitsPerDegreeLatitude":\(unitsPerDegreeLatitude),
         "unitsPerDegreeLongitude":\(unitsPerDegreeLongitude),
         "halfSpanUnitsEastWest":\(halfSpanUnitsEastWest),
         "halfSpanUnitsNorthSouth":\(halfSpanUnitsNorthSouth),
         "userDotHeightUnits":\(userDotHeightUnits)}
        """
    }

    private func valid(pins: String = #"[{"sequence":1,"entityNames":["marker_1"]}]"#,
                       anchor: String? = nil,
                       domeRadius: String = "9.0",
                       minPitch: String = "12",
                       maxPitch: String = "75") -> String {
        """
        {"modelName":"map","framingYawDegrees":90,
         "anchor":\(anchor ?? anchorJSON()),
         "camera":{"defaultPitchDegrees":68,"minPitchDegrees":\(minPitch),"maxPitchDegrees":\(maxPitch),
                   "minDistance":0.8,"maxDistance":4.0,"defaultDistance":1.6,
                   "focusPitchDegrees":34,"focusDistance":0.55,"orbitDegreesPerSecond":8},
         "sky":{"domeRadius":\(domeRadius),"apronSpanMultiplier":4.0},
         "pins":\(pins)}
        """
    }

    func testAcceptsAWellFormedConfig() {
        XCTAssertNotNil(decode(valid()))
    }

    func testRejectsJunk() {
        XCTAssertNil(decode("ไม่ใช่ JSON เลย"))
        XCTAssertNil(decode(#"{"modelName":"map"}"#), "คีย์ไม่ครบต้องไม่ผ่าน")
    }

    /// หมุดว่าง = แท็บเปิดได้ โมเดลขึ้นครบ แต่แตะแท่งแดงแล้วไม่มีอะไรเกิดขึ้นสักอัน
    /// เป็นความล้มเหลวที่เงียบที่สุดที่จะเกิดจากการพิมพ์ JSON ผิด
    func testRejectsAnEmptyPinList() {
        XCTAssertNil(decode(valid(pins: "[]")))
    }

    /// ฐานที่ไม่มีชื่อ prim สักตัว = แท่งนั้นแตะไม่ติด แต่แท่งอื่นยังติด อ่านจากจอไม่ออกว่าพัง
    func testRejectsAPinWithNoEntityNames() {
        XCTAssertNil(decode(valid(pins: #"[{"sequence":1,"entityNames":[]}]"#)))
    }

    func testRejectsTheSameEntityNameOnTwoBases() {
        XCTAssertNil(decode(valid(pins: #"""
        [{"sequence":1,"entityNames":["marker_1"]},{"sequence":2,"entityNames":["marker_1"]}]
        """#)))
    }

    /// สเกลเป็นศูนย์หรือติดลบ = ทุกพิกัดยุบไปกองที่จุดเดียวหรือกลับด้านทั้งแผนที่
    func testRejectsAnAnchorScaleThatIsNotPositive() {
        XCTAssertNil(decode(valid(anchor: anchorJSON(unitsPerDegreeLatitude: "0"))))
        XCTAssertNil(decode(valid(anchor: anchorJSON(unitsPerDegreeLongitude: "-111319.49"))))
    }

    /// ครึ่งความกว้างเป็นศูนย์ = จุดตำแหน่งผู้ใช้ถูกตัดว่า "นอกพื้นที่" ทุกครั้ง ไม่เคยโผล่เลย
    func testRejectsAZeroSizedEventArea() {
        XCTAssertNil(decode(valid(anchor: anchorJSON(halfSpanUnitsEastWest: "0"))))
        XCTAssertNil(decode(valid(anchor: anchorJSON(halfSpanUnitsNorthSouth: "0"))))
    }

    /// ความสูงศูนย์/ติดลบ = จุดจมอยู่ใต้ภูมิประเทศ หายไปเงียบ ๆ โดยไม่มีอะไรฟ้อง
    func testRejectsAUserDotBuriedUnderTheTerrain() {
        XCTAssertNil(decode(valid(anchor: anchorJSON(userDotHeightUnits: "0"))))
    }

    /// ค่าที่ส่งไปกับแอปต้องเป็นค่าที่ถอดจากโมเดลจริง ไม่ใช่ค่าที่พิมพ์มั่ว — ตรวจด้วยหมุดฐานที่ 5
    /// ที่รู้พิกัดในไฟล์โมเดลอยู่แล้ว (751.2, −112) ผิดเมื่อไหร่จุด GPS เพี้ยนทั้งแผนที่
    func testShippedAnchorPutsBaseFiveWhereTheModelPutsIt() throws {
        let anchor = try XCTUnwrap(Map3DConfig.bundled).anchor
        let p = try XCTUnwrap(Map3DGeo.modelUnits(latitude: 20.04454, longitude: 99.90955,
                                                  in: anchor))
        XCTAssertEqual(p.x, 751.2, accuracy: 6)
        XCTAssertEqual(p.y, -112.0, accuracy: 6)
    }

    func testRejectsAPitchRangeThatIsInverted() {
        XCTAssertNil(decode(valid(minPitch: "80", maxPitch: "20")))
    }

    /// โดมเล็กกว่าระยะกล้องสูงสุด = ซูมออกสุดแล้วกล้องทะลุออกไปนอกโดม เห็นพื้นดำรอบโมเดล
    /// (อาการเดิมที่โดมถูกใส่เข้ามาเพื่อแก้ตั้งแต่แรก)
    func testRejectsADomeSmallerThanTheFarthestTheCameraCanGo() {
        XCTAssertNil(decode(valid(domeRadius: "3.0")), "domeRadius ต้องมากกว่า maxDistance (4.0)")
    }

    // MARK: - ตัวที่ระบบใช้จริง

    func testCurrentAlwaysHasUsablePinsEvenIfTheFileIsMissing() {
        XCTAssertFalse(Map3DConfig.current.pins.isEmpty,
                       "ไม่ว่าไฟล์จะหายหรือพัง ต้องยังมีหมุดให้กดเสมอ")
        XCTAssertFalse(Map3DConfig.fallback.pins.isEmpty)
    }

    func testFramingYawIsExposedInRadians() {
        XCTAssertEqual(Map3DConfig.fallback.framingYaw,
                       Map3DConfig.fallback.framingYawDegrees * .pi / 180, accuracy: 1e-6)
    }
}
