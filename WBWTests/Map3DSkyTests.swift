import XCTest
import CoreGraphics
@testable import WBW

/// texture เมฆที่วาดเองในโค้ด (ไม่มี asset เมฆในโปรเจกต์ และโมเดลแผนที่ก็ 10 MB อยู่แล้ว)
///
/// เทสตัววาดภาพ ไม่ใช่ตัวที่แปลงเป็น TextureResource — ขั้นแปลงต้องมี RealityKit context
/// ส่วนตัววาดเป็นฟังก์ชันบริสุทธิ์ เรียกตรงได้
final class Map3DSkyTests: XCTestCase {

    func testCloudImageHasRequestedSize() {
        let image = Map3DSky.cloudImage(size: 256)
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.width, 256)
        XCTAssertEqual(image?.height, 256)
    }

    /// หัวใจของเทสนี้ — ต้องมีทั้งส่วนโปร่งและส่วนทึบ
    ///
    /// ถ้าทึบทั้งผืนแปลว่าได้สี่เหลี่ยมขาว ไม่ใช่ก้อนเมฆ · ถ้าโปร่งทั้งผืนแปลว่าวาดไม่ติด
    /// ทั้งสองแบบขึ้นจอแล้ว "ดูไม่ออกว่าผิด" จนกว่าจะเทียบภาพอ้างอิง
    func testCloudImageHasBothTransparentAndOpaquePixels() throws {
        let image = try XCTUnwrap(Map3DSky.cloudImage(size: 128))
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &pixels, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let alphas = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
        XCTAssertTrue(alphas.contains { $0 < 10 }, "ไม่มีพิกเซลโปร่งเลย — ได้สี่เหลี่ยมทึบ ไม่ใช่เมฆ")
        XCTAssertTrue(alphas.contains { $0 > 200 }, "ไม่มีพิกเซลทึบเลย — เมฆจางจนมองไม่เห็น")
    }

    /// สีต้องขาวล้วนทุกพิกเซล ความจางอยู่ที่ช่อง alpha อย่างเดียว (straight alpha)
    ///
    /// เคยพังจริง: `UIGraphicsImageRenderer` คืน bitmap แบบ **premultiplied** — ขาว alpha 0.5
    /// ถูกเก็บเป็น RGB 128 · RealityKit อ่านค่านั้นเป็น straight alpha ก็ได้ "เทา 50%" แทน
    /// "ขาวจาง 50%" บนจอเห็นเมฆกลายเป็นหมอกเทาทั้งผืน
    ///
    /// ต้องอ่าน buffer ดิบผ่าน data provider — วาดลง CGContext เพื่อตรวจไม่ได้ เพราะ context
    /// จะ premultiply ให้เองระหว่างทาง เทสจะผ่านทั้งที่ของจริงพัง
    func testImagesUseStraightAlphaNotPremultiplied() throws {
        let image = try XCTUnwrap(Map3DSky.cloudImage(size: 64))
        XCTAssertEqual(image.alphaInfo, .last, "ต้องประกาศเป็น straight alpha")
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        let bytesPerRow = image.bytesPerRow
        var checked = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * bytesPerRow + x * 4
                let alpha = data[offset + 3]
                guard alpha > 20, alpha < 235 else { continue }   // เฉพาะพิกเซลกึ่งโปร่ง
                checked += 1
                XCTAssertEqual(data[offset], 255,
                               "พิกเซลกึ่งโปร่งต้องยังขาวเต็ม — ได้ \(data[offset]) ที่ alpha \(alpha)")
            }
        }
        XCTAssertGreaterThan(checked, 0, "ไม่มีพิกเซลกึ่งโปร่งเลย ตรวจอะไรไม่ได้")
    }

    // MARK: - เรขาคณิตที่กันไม่ให้เห็นขอบโมเดล

    /// โดมต้องใหญ่กว่าระยะที่กล้องถอยได้ไกลสุด ไม่งั้นซูมออกสุดแล้วกล้องทะลุออกนอกโดม
    /// เห็นพื้นดำรอบโมเดล ซึ่งเป็นอาการเดิมที่โดมถูกใส่เข้ามาแก้ตั้งแต่แรก
    func testDomeIsBigEnoughToKeepTheCameraInside() {
        XCTAssertGreaterThan(Map3DSky.domeRadius, Map3DCamera.maxDistance,
                             "ซูมออกสุดแล้วกล้องจะหลุดออกนอกโดม")
    }

}
