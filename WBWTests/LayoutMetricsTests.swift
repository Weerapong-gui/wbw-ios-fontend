import XCTest
import SwiftUI
@testable import WBW

/// ระยะเลย์เอาต์ที่ตอบต่างกันตามขนาดจอ — `WBW/Layout.swift`
///
/// **มีเทสนี้เพราะค่าเดิมเป็นค่าคงที่ตัวเดียวที่ตอบเหมือนกันทุกที่**
/// (`ForestSceneHost.tabBarClearance = 89`) ซึ่งถูกบน iPhone และผิด 89pt บน iPad
/// โดยไม่มี build/test ตัวไหนฟ้อง — แถบแท็บของ `Tab(value:)` บน iPadOS 18+ อยู่ **ข้างบน**
/// ไม่ใช่ข้างล่าง เว้นระยะก้นจอไว้จึงเป็นที่ว่างตายเปล่า ๆ ขณะที่ขอบที่ต้องการระยะจริงคือขอบบน
/// `@MainActor` เพราะ `ForestSceneHost.tabBarClearance` เป็นสมาชิกของคลาสที่ผูก main actor —
/// อ้างจาก autoclosure ของ `XCTAssert*` ที่ไม่ผูก actor เป็น warning วันนี้และเป็น error ใน Swift 6
@MainActor
final class LayoutMetricsTests: XCTestCase {

    // MARK: - ระยะพ้นแถบแท็บ

    func testCompactKeepsTheMeasuredPhoneClearance() {
        // เลข 89 มาจากการสแกนพิกเซลบนสกรีนช็อตจริงสองเครื่อง (ดูคอมเมนต์ที่
        // ForestSceneHost.tabBarClearance) — ของใหม่ต้องไม่ทิ้งงานวัดนั้น
        XCTAssertEqual(WBWLayout.tabBarClearance(.compact), ForestSceneHost.tabBarClearance,
                       "iPhone ยังต้องได้ระยะเดิมเป๊ะ ไม่งั้นทุกจอขยับพร้อมกันโดยไม่ตั้งใจ")
    }

    func testRegularGetsNoBottomClearanceBecauseTheBarIsOnTop() {
        XCTAssertEqual(WBWLayout.tabBarClearance(.regular), 0,
                       "บน iPad แถบแท็บอยู่ข้างบน เว้นก้นจอ 89pt คือที่ว่างตายที่ไม่มีอะไรอยู่")
    }

    /// **ข้อที่สำคัญที่สุดในไฟล์นี้**
    ///
    /// จะมีคนมา "ทำให้สั้นลง" เป็น `h == .compact ? 89 : 0` ซึ่งอ่านแล้วดูเหมือนกัน
    /// แต่ตอบ 0 ให้ค่า nil — และ nil คือสิ่งที่ SwiftUI ให้มาในเฟรมแรกก่อน resolve size class
    /// ผลคือเนื้อหากระพริบไปอยู่ใต้แถบแท็บหนึ่งเฟรมทุกครั้งที่เข้าจอ บน iPhone ทุกเครื่อง
    func testUnknownSizeClassAnswersLikeAPhoneNotLikeAnIPad() {
        XCTAssertEqual(WBWLayout.tabBarClearance(nil), ForestSceneHost.tabBarClearance,
                       "เฟรมแรกยังไม่รู้ size class — เดาเป็น iPad แล้วเนื้อหาจะโผล่ใต้แถบแท็บ")
    }

    // MARK: - ความกว้างคอลัมน์

    func testPhonesAreNeverNarrowedByTheColumnCap() {
        // จอ iPhone SE กว้าง 375pt อยู่แล้ว หนีบเข้าไปอีกคือทำให้จอที่แคบอยู่แล้วแคบลง
        // · นี่คือข้อที่ทำให้ commit ของ .contentColumn() เป็น no-op บน iPhone แบบพิสูจน์ได้
        for column in WBWLayout.Column.allCases {
            XCTAssertNil(WBWLayout.columnWidth(column, .compact),
                         "\(column) หนีบความกว้างบน iPhone — สกรีนช็อตที่ส่ง ASC ไปแล้วจะขยับ")
            XCTAssertNil(WBWLayout.columnWidth(column, nil),
                         "\(column) หนีบตั้งแต่เฟรมแรกที่ยังไม่รู้ size class")
        }
    }

    func testRegularGetsTheDeclaredWidth() {
        for column in WBWLayout.Column.allCases {
            XCTAssertEqual(WBWLayout.columnWidth(column, .regular), column.rawValue)
        }
    }

    /// เทสค้ำ **ลำดับ** ไม่ใช่ตัวเลข — 560 เป็นดุลพินิจที่เปลี่ยนได้
    /// แต่ "บัตรต้องแคบกว่าการ์ด" กับ "แชทต้องกว้างที่สุด" เป็นเหตุผลของการมีหลายค่า
    func testColumnsAreOrderedFromMostConstrainedToLeast() {
        let order: [WBWLayout.Column] = [.dialog, .pass, .form, .card, .transcript]
        for (narrow, wide) in zip(order, order.dropFirst()) {
            XCTAssertLessThan(narrow.rawValue, wide.rawValue,
                              "\(narrow) ต้องแคบกว่า \(wide)")
        }
        XCTAssertEqual(Set(order), Set(WBWLayout.Column.allCases),
                       "มี case ใหม่ที่ยังไม่ถูกจัดลำดับ — เพิ่มเข้า order ด้วย")
    }

    func testTheWorkhorseColumnIsWiderThanTheNarrowestPhone() {
        // iPhone SE = 375pt · การ์ดที่แคบกว่าจอมือถือแปลว่าพิมพ์เลขผิดหลัก (56 หรือ 5600)
        XCTAssertGreaterThanOrEqual(WBWLayout.Column.card.rawValue, 375)
    }
}
