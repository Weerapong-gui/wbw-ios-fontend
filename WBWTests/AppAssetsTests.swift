import XCTest
import SwiftUI
import ImageIO
import CoreGraphics
@testable import WBW

/// คุมไฟล์ภาพสองใบที่ "ผิดแล้วไม่มีอะไรฟ้อง" จนกว่าจะสายเกินแก้
///
/// ไอคอน: ไฟล์ที่มี alpha channel build ผ่านปกติ รันบน simulator ก็สวยดี แต่โดนตีกลับตอน
/// validate ด้วย ITMS-90717 ซึ่งกว่าจะรู้ก็ตอนกำลังจะส่งขึ้น store จริง
///
/// พื้นหลัง: ทุกจอที่ใช้ `AppBackdrop` วางตัวหนังสือกับไอคอน**สีขาวล้วน** ทับลงไปตรง ๆ
/// (คำทักทายที่ Home, หัวข้อกับกรอบมุมที่ QR) ถ้ามีคนสลับภาพเป็นใบที่สว่างโดยไม่แตะ scrim
/// ตัวหนังสือจะจมหายทั้งแอป โดยไม่มี error ให้เห็นเลย — เคยเกิดมาแล้วรอบหนึ่ง
/// (ดู `docs/app-backdrop-open-questions.md` หัวข้อ "ค้าง 3")
///
/// อ่านไฟล์จาก source tree ผ่าน `#filePath` ไม่ใช่จาก bundle เพราะสิ่งที่ต้องคุมคือไฟล์ต้นทางใน
/// asset catalog ส่วนของใน bundle ถูก actool แปลงระหว่างทางแล้ว (แพตเทิร์นเดียวกับ AppStoreConfigTests)
final class AppAssetsTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // WBWTests
        .deletingLastPathComponent()   // repo root

    private static let appIcon = "WBW/Assets.xcassets/AppIcon.appiconset/icon1024.png"
    private static let backdrop = "WBW/Assets.xcassets/bg_backdrop.imageset/bg_backdrop.jpg"

    private func source(_ relativePath: String) throws -> CGImageSource {
        let url = Self.repoRoot.appendingPathComponent(relativePath)
        return try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil),
                             "เปิดไฟล์ \(relativePath) เป็นรูปไม่ได้")
    }

    private func properties(_ relativePath: String) throws -> [CFString: Any] {
        let source = try source(relativePath)
        return try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            "อ่าน metadata ของ \(relativePath) ไม่ได้")
    }

    private func size(_ relativePath: String) throws -> (width: Int, height: Int) {
        let props = try properties(relativePath)
        let width = try XCTUnwrap(props[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(props[kCGImagePropertyPixelHeight] as? Int)
        return (width, height)
    }

    /// ความสว่างเฉลี่ยทั้งใบ 0…1
    ///
    /// ย่อลง grayscale 16×32 แล้วเฉลี่ยไบต์ ไม่ต้องดึงพิกเซลเต็ม 1440×2880 — ที่ต้องการคือ
    /// "ภาพใบนี้โดยรวมมืดหรือสว่าง" ไม่ใช่ค่าเป๊ะ ๆ ของแต่ละจุด
    private func meanLuminance(_ relativePath: String) throws -> Double {
        let source = try source(relativePath)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil),
                                  "decode \(relativePath) ไม่ได้")
        let (width, height) = (16, 32)
        var pixels = [UInt8](repeating: 0, count: width * height)
        let context = try XCTUnwrap(pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress,
                      width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        })
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let total = pixels.reduce(0) { $0 + Int($1) }
        return Double(total) / Double(pixels.count) / 255.0
    }

    // MARK: - ไอคอนแอป

    /// `hasAlpha` ของ PNG ที่ไม่มีช่อง alpha จะเป็น false — ของ JPEG ไม่มีคีย์นี้เลย
    /// ที่นี่เป็น PNG เสมอ จึงถือว่า "ไม่มีคีย์" = ไม่มี alpha ได้
    func testAppIconCarriesNoAlphaChannel() throws {
        let props = try properties(Self.appIcon)
        let hasAlpha = props[kCGImagePropertyHasAlpha] as? Bool ?? false
        XCTAssertFalse(hasAlpha,
                       "ไอคอนมี alpha channel — App Store ตีกลับด้วย ITMS-90717 ตอน validate")
    }

    func testAppIconIsSquare1024() throws {
        let (width, height) = try size(Self.appIcon)
        XCTAssertEqual(width, 1024)
        XCTAssertEqual(height, 1024,
                       "AppIcon.appiconset เป็นแบบ single-size ต้องเป็น 1024×1024 ใบเดียวเป๊ะ")
    }

    // MARK: - พื้นหลังกลางของแอป

    /// ยิ่งสำคัญกว่าเดิมหลังเปลี่ยนภาพ — ฟิล์มที่ทาทับลดจาก 0.35 เหลือ 0.12 ตามกฎของ palette
    /// ฝั่ง Android ("The image is the design; it is shown, not tinted") ตัวภาพเองจึงต้องมืดพอ
    /// ด้วยตัวมันเอง ไม่มีชั้นทึบมาช่วยเหมือนก่อน
    func testBackdropIsDarkEnoughForWhiteTextOnTop() throws {
        let luminance = try meanLuminance(Self.backdrop)
        XCTAssertLessThan(luminance, 0.30,
                          """
                          พื้นหลังสว่างเกินไป (\(luminance)) — ตัวหนังสือขาวบน Home/QR/Ticket จะอ่านไม่ออก
                          ถ้าตั้งใจเปลี่ยนเป็นภาพสว่างจริง ต้องกลับไปเพิ่ม scrim ใน AppBackdrop ก่อน
                          """)
    }

    /// อัตราส่วน 1:2 ไม่ใช่เลขสุ่ม — `AppBackdrop` เลือกมาให้อยู่กึ่งกลางระหว่าง SE (0.562) กับ
    /// Pro Max (0.460) เพื่อให้ `scaledToFill` ตัดขอบหนักสุดราว 11% ด้านเดียว เปลี่ยนสัดส่วน
    /// เมื่อไหร่คำอธิบายในไฟล์นั้นกลายเป็นเท็จทันที และองค์ประกอบกลางภาพจะเลื่อนหลุดกรอบ
    ///
    /// คุมเป็น "อัตราส่วน" ไม่ใช่ขนาดพิกเซลตายตัวแล้ว — ภาพที่ยกมาจากแอป Android เป็น 736×1471
    /// ซึ่งเล็กกว่าใบเดิม (1440×2880) แต่สัดส่วนเท่ากันเป๊ะ · ภาพเบลอทั้งใบจึงไม่มีรายละเอียด
    /// ให้เสียตอนขยาย ขนาดพิกเซลไม่ใช่สิ่งที่ต้องตรึง สัดส่วนต่างหาก
    func testBackdropKeepsTheOneToTwoAspectAppBackdropAssumes() throws {
        let (width, height) = try size(Self.backdrop)
        XCTAssertEqual(Double(height) / Double(width), 2.0, accuracy: 0.01,
                       "สัดส่วนต้องเป็น 1:2 — ได้ \(width)×\(height)")
    }

    /// สีเตือนที่วางบน**ภาพ** ไม่ใช่บนการ์ด ต้องรอดจริงบนภาพใบที่ใช้อยู่จริง
    ///
    /// `wbwDanger` ปรับตามธีม ขาสว่างของมัน (#C0503A) ได้ราว 2.4:1 บนภาพนี้ — ปุ่ม "ออกจากกลุ่ม"
    /// กับข้อความ error ใน `GroupHomeView` วางบนภาพตรง ๆ หลังจากแท็บแชทเลิกทาพื้นทึบของตัวเอง
    /// จึงใช้ตัวนั้นไม่ได้ · เทสนี้วัดกับไฟล์จริง ไม่ใช่กับเลขในคอมเมนต์ เปลี่ยนภาพเมื่อไหร่มันจะดัง
    func testOnBackdropDangerSurvivesTheRealBackdrop() throws {
        // ค่าที่ `meanLuminance` คืนคือค่าเทาที่ยังผ่าน gamma อยู่ ต้อง linearise ก่อนเข้าสูตร WCAG
        // แล้วคูณ scrim ดำ 12% ที่ `AppBackdrop.wash` ทาทับ (สีดำ = คูณ 0.88 ในสเปซเชิงเส้น)
        let gray = try meanLuminance(Self.backdrop)
        let linear = gray <= 0.03928 ? gray / 12.92 : pow((gray + 0.055) / 1.055, 2.4)
        let backdrop = linear * 0.88

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(Color.wbwOnBackdropDanger).getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let danger = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)

        let ratio = (max(danger, backdrop) + 0.05) / (min(danger, backdrop) + 0.05)
        XCTAssertGreaterThan(ratio, 4.0,
                             "wbwOnBackdropDanger บนภาพพื้นหลังได้ \(String(format: "%.2f", ratio)):1 "
                             + "— ปุ่มออกจากกลุ่มกับข้อความ error จะจมหายไปกับภาพ")
    }
}
