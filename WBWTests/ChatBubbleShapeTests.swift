import XCTest
import SwiftUI
@testable import WBW

/// ทรงฟองแชทหลังตัดหางทิ้ง
///
/// **หางเดิมพังจริง** (`BubbleShape` เดิม): วาดสี่เหลี่ยมมนรัศมี 18 แล้ว `addPath` สามเหลี่ยมทับ
/// โดยฐานสามเหลี่ยมเริ่มที่ `x - dir * 18` ซึ่งอยู่ในเขตที่มุมมนกินไปแล้ว เส้นโค้งของหางจึงไม่ต่อ
/// เนื่องกับเส้นโค้งของมุม ตาอ่านเป็นธงสามเหลี่ยมคม ๆ แปะข้างฟอง ไม่ใช่หางที่งอกออกมา
///
/// พอไม่มีหางแล้ว สิ่งเดียวที่บอกว่าฟองไหนอยู่ชุดเดียวกันคือรัศมีมุม — ไฟล์นี้จึงตรึงกฎนั้นไว้
/// ผิดด้านเมื่อไหร่จะได้กล่องมนเรียงกันเฉย ๆ ที่อ่านไม่ออกว่าใครพูดติดกัน ซึ่งดูไม่ออกว่าผิด
/// จนกว่าจะเอาไปเทียบกับแอปแชทตัวอื่น
final class ChatBubbleShapeTests: XCTestCase {

    private func corners(mine: Bool, first: Bool, last: Bool) -> RectangleCornerRadii {
        ChatBubbleShape.corners(isMine: mine, isFirstInGroup: first, isLastInGroup: last)
    }

    /// ฟองเดี่ยว ๆ (เป็นทั้งฟองแรกและฟองสุดท้ายของชุด) ไม่มีเพื่อนบ้าน มุมจึงมนเต็มทั้งสี่
    func testALoneBubbleIsFullyRoundedOnEveryCorner() {
        for mine in [true, false] {
            let c = corners(mine: mine, first: true, last: true)
            for (radius, name) in [(c.topLeading, "topLeading"), (c.topTrailing, "topTrailing"),
                                   (c.bottomLeading, "bottomLeading"),
                                   (c.bottomTrailing, "bottomTrailing")] {
                XCTAssertEqual(radius, ChatBubbleShape.full, accuracy: 1e-6,
                               "\(name) ของฟองเดี่ยว (isMine: \(mine)) ต้องมนเต็ม")
            }
        }
    }

    /// ฟองกลางชุดของเรา — มุมฝั่งขวาทั้งบนและล่างติดฟองข้างเคียง จึงมนน้อยลงทั้งคู่
    func testMiddleBubbleTightensBothCornersOnTheSpeakersSide() {
        let c = corners(mine: true, first: false, last: false)
        XCTAssertEqual(c.topTrailing, ChatBubbleShape.tight, accuracy: 1e-6)
        XCTAssertEqual(c.bottomTrailing, ChatBubbleShape.tight, accuracy: 1e-6)
        XCTAssertEqual(c.topLeading, ChatBubbleShape.full, accuracy: 1e-6, "มุมฝั่งนอกต้องมนเต็มเสมอ")
        XCTAssertEqual(c.bottomLeading, ChatBubbleShape.full, accuracy: 1e-6)
    }

    /// ฟองแรกของชุด: บนยังมนเต็ม (ไม่มีใครอยู่เหนือ) ล่างมนน้อยลง (มีฟองต่อข้างล่าง)
    func testFirstBubbleKeepsItsTopRoundAndTightensTheBottom() {
        let c = corners(mine: true, first: true, last: false)
        XCTAssertEqual(c.topTrailing, ChatBubbleShape.full, accuracy: 1e-6)
        XCTAssertEqual(c.bottomTrailing, ChatBubbleShape.tight, accuracy: 1e-6)
    }

    func testLastBubbleKeepsItsBottomRoundAndTightensTheTop() {
        let c = corners(mine: true, first: false, last: true)
        XCTAssertEqual(c.topTrailing, ChatBubbleShape.tight, accuracy: 1e-6)
        XCTAssertEqual(c.bottomTrailing, ChatBubbleShape.full, accuracy: 1e-6)
    }

    /// ฝั่งเขาต้องเป็นภาพสะท้อนของฝั่งเราเป๊ะ — ตั้งด้านผิดแล้วมุมจะไปมนน้อยลงที่ฝั่งนอก
    /// ซึ่งอ่านเหมือนฟองถูกตัดขอบมากกว่าฟองที่ต่อกันเป็นชุด
    func testTheirSideIsTheMirrorImageOfOurs() {
        for (first, last) in [(true, false), (false, true), (false, false), (true, true)] {
            let mine = corners(mine: true, first: first, last: last)
            let theirs = corners(mine: false, first: first, last: last)
            XCTAssertEqual(theirs.topLeading, mine.topTrailing, accuracy: 1e-6,
                           "first: \(first) last: \(last)")
            XCTAssertEqual(theirs.bottomLeading, mine.bottomTrailing, accuracy: 1e-6,
                           "first: \(first) last: \(last)")
            XCTAssertEqual(theirs.topTrailing, mine.topLeading, accuracy: 1e-6)
            XCTAssertEqual(theirs.bottomTrailing, mine.bottomLeading, accuracy: 1e-6)
        }
    }

    /// มุมที่ "มนน้อยลง" ต้องยังมนอยู่จริง ไม่ใช่มุมฉาก — ศูนย์เมื่อไหร่ฟองจะดูเป็นกล่องเหลี่ยม
    /// และต้องน้อยกว่ามุมเต็มจริง ไม่งั้นกฎทั้งหมดในไฟล์นี้ไม่มีผลอะไรบนจอเลย
    func testTightCornerIsStillRoundedJustLess() {
        XCTAssertGreaterThan(ChatBubbleShape.tight, 0)
        XCTAssertLessThan(ChatBubbleShape.tight, ChatBubbleShape.full)
    }
}
