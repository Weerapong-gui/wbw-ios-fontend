import XCTest
import SwiftUI
@testable import WBW

/// ทรงตั๋วต้อง "เจาะรู" จริง ไม่ใช่เอาวงกลมสีพื้นแปะทับแบบเดิม
///
/// พื้นหลังจอโปรไฟล์กำลังจะเปลี่ยนเป็นรูปภาพ ท่าแปะทับเนียนเฉพาะตอนพื้นเป็นสีเรียบสีเดียว
/// วางรูปเมื่อไหร่จะเห็นเป็นวงกลมสีทึบกลางรูปทันที · เทสพวกนี้จับว่ารูทะลุจริงหรือไม่
final class TicketShapeTests: XCTestCase {

    private let rect = CGRect(x: 0, y: 0, width: 320, height: 560)
    private let avatarCut: CGFloat = 60
    private let sideCut: CGFloat = 14
    private let tearY: CGFloat = 380

    private func shape() -> TicketShape {
        TicketShape(corner: 34, avatarCut: avatarCut, sideCut: sideCut, tearY: tearY)
    }

    // MARK: - รอยเว้าบน (avatar)

    func testTopCutIsActuallyHollow() {
        let p = shape().path(in: rect)
        XCTAssertFalse(p.contains(CGPoint(x: rect.midX, y: rect.minY + 2)),
                       "กึ่งกลางขอบบนต้องเป็นรู avatar จะได้เห็นพื้นหลังลอดเป็นวงแหวน")
        XCTAssertFalse(p.contains(CGPoint(x: rect.midX, y: rect.minY + avatarCut * 0.5)),
                       "ลึกลงมาครึ่งรัศมีก็ยังต้องอยู่ในรู")
    }

    func testCardStillSolidBesideTopCut() {
        let p = shape().path(in: rect)
        XCTAssertTrue(p.contains(CGPoint(x: rect.midX - avatarCut - 25, y: rect.minY + 4)),
                      "ซ้ายของรอยเว้ายังต้องเป็นเนื้อการ์ด")
        XCTAssertTrue(p.contains(CGPoint(x: rect.midX + avatarCut + 25, y: rect.minY + 4)),
                      "ขวาของรอยเว้ายังต้องเป็นเนื้อการ์ด")
    }

    func testTopCutSitsAtHorizontalCenter() {
        let p = shape().path(in: rect)
        // ยิงตามขอบบนแล้วเก็บช่วงที่เป็นรู — จุดกึ่งกลางของช่วงต้องตรงกับ midX
        let ys = rect.minY + 3
        let hollow = stride(from: rect.minX + 1, to: rect.maxX - 1, by: 1)
            .filter { !p.contains(CGPoint(x: $0, y: ys)) }
        XCTAssertFalse(hollow.isEmpty, "ต้องมีรูบนขอบบน")
        let mid = (hollow.first! + hollow.last!) / 2
        XCTAssertEqual(mid, rect.midX, accuracy: 2, "รอยเว้าต้องอยู่กึ่งกลางแนวนอน")
    }

    // MARK: - รอยเว้าข้าง (แนวฉีก)

    func testSideCutsAreHollowAtTearLine() {
        let p = shape().path(in: rect)
        XCTAssertFalse(p.contains(CGPoint(x: rect.minX + 2, y: tearY)),
                       "ขอบซ้ายที่ระดับเส้นฉีกต้องเว้าเข้าไป")
        XCTAssertFalse(p.contains(CGPoint(x: rect.maxX - 2, y: tearY)),
                       "ขอบขวาที่ระดับเส้นฉีกต้องเว้าเข้าไป")
    }

    func testCardSolidAboveAndBelowSideCuts() {
        let p = shape().path(in: rect)
        for y in [tearY - sideCut - 20, tearY + sideCut + 20] {
            XCTAssertTrue(p.contains(CGPoint(x: rect.minX + 4, y: y)),
                          "เหนือ/ใต้รอยเว้าข้างยังต้องเป็นเนื้อการ์ด (y=\(y))")
        }
    }

    // MARK: - ขอบเขต

    func testPathStaysInsideGivenRect() {
        let b = shape().path(in: rect).boundingRect
        XCTAssertGreaterThanOrEqual(b.minX, rect.minX - 0.5, "รอยเว้าต้องกินเข้าใน ไม่ใช่โป่งออกนอกกรอบ")
        XCTAssertGreaterThanOrEqual(b.minY, rect.minY - 0.5)
        XCTAssertLessThanOrEqual(b.maxX, rect.maxX + 0.5)
        XCTAssertLessThanOrEqual(b.maxY, rect.maxY + 0.5)
    }

    /// ตอนเลย์เอาต์ยังไม่รู้ขนาด avatar ค่าจะเป็น 0 มาก่อน — ห้ามได้ NaN หรือขอบบนแหว่ง
    func testZeroAvatarCutGivesFlatTopEdge() {
        let p = TicketShape(corner: 34, avatarCut: 0, sideCut: sideCut, tearY: tearY).path(in: rect)
        XCTAssertTrue(p.contains(CGPoint(x: rect.midX, y: rect.minY + 2)),
                      "avatarCut = 0 ต้องได้ขอบบนเรียบ ไม่มีรู")
        XCTAssertFalse(p.boundingRect.isNull, "path ต้องใช้ได้ ไม่ใช่ NaN")
    }

    func testZeroSideCutGivesStraightEdges() {
        let p = TicketShape(corner: 34, avatarCut: avatarCut, sideCut: 0, tearY: tearY).path(in: rect)
        XCTAssertTrue(p.contains(CGPoint(x: rect.minX + 2, y: tearY)))
        XCTAssertTrue(p.contains(CGPoint(x: rect.maxX - 2, y: tearY)))
    }
}
