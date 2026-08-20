import XCTest
import SwiftUI
@testable import WBW

/// พื้นผิวกระจกต้องเป็นค่าเดียวกับ Android เป๊ะ — **ไม่ใช่ค่าที่ปัดเอาเอง**
///
/// ค่าพวกนี้เป็น alpha ของขาวที่ต้นทางเขียนเป็นเลขฐานสิบหก (`0x1FFFFFFF`) ปัดเป็นทศนิยมสองตำแหน่ง
/// แล้วมันเลื่อนไปพอที่จะเห็นได้เมื่อสองแอปวางเทียบกัน · และเพราะเป็นแค่ตัวเลข ไม่มีอะไรจับได้เลย
/// นอกจากตาคนที่เอาสองเครื่องมาวางข้างกัน
final class GlassPaletteTests: XCTestCase {

    private func alphaOfWhite(_ color: Color) -> CGFloat {
        var w: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getWhite(&w, alpha: &a)
        XCTAssertEqual(w, 1, accuracy: 0.001, "ต้องเป็นขาวล้วน ต่างกันแค่ alpha")
        return a
    }

    /// `GlassSheer = Color(0x1FFFFFFF)` — 31/255
    func testGlassSheerMatchesAndroid() {
        XCTAssertEqual(alphaOfWhite(.glassSheer), 31.0 / 255, accuracy: 0.002)
    }

    /// `GlassSheerBorder = Color(0x21FFFFFF)` — 33/255
    func testGlassSheerBorderMatchesAndroid() {
        XCTAssertEqual(alphaOfWhite(.glassSheerBorder), 33.0 / 255, accuracy: 0.002)
    }

    /// บัตรผู้เข้าร่วมใช้พื้นผิวเดียวกับแถบแท็บ — `PassSurface` กับ `GlassSheer` เป็นเลขเดียวกัน
    /// ในต้นทาง และคอมเมนต์ของต้นทางบอกเหตุผลไว้ว่า "การ์ดกับแถบต้องเป็นวัสดุเดียวกัน"
    func testPassSurfaceIsTheSameMaterialAsTheBar() {
        XCTAssertEqual(alphaOfWhite(.passSurface), alphaOfWhite(.glassSheer), accuracy: 0.002,
                       "บัตรกับแถบแท็บต้องเป็นวัสดุเดียวกัน ไม่ใช่สองค่าที่ใกล้กัน")
    }

    /// ที่เหลือของชุดบัตร — ตัวเลขจาก `Color.kt` ตรง ๆ
    func testPassInkRampMatchesAndroid() {
        XCTAssertEqual(alphaOfWhite(.passMuted), 0xCC / 255.0, accuracy: 0.002)
        XCTAssertEqual(alphaOfWhite(.passFaint), 0x8A / 255.0, accuracy: 0.002)
        XCTAssertEqual(alphaOfWhite(.passHairline), 0x1A / 255.0, accuracy: 0.002)
        XCTAssertEqual(alphaOfWhite(.passWell), 0x0F / 255.0, accuracy: 0.002)
    }
}
