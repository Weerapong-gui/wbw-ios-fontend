import XCTest
@testable import WBW

/// จังหวะของจออินโทร — **ยกมาจาก `ui/intro/IntroScreen.kt` ของ Android**
///
/// ทำไมต้องแยกออกมาเป็น `static func` แล้วเทสตรงนี้: ตัวเลขพวกนี้ผิดแล้วไม่มีอะไรฟ้อง แอปยัง
/// คอมไพล์ผ่าน จออินโทรยังขึ้น แต่ดอกไม้จะกระตุกหรือข้ามขั้นแบบที่ต้องนั่งดูซ้ำหลายรอบถึงจะจับได้
/// · ที่สำคัญที่สุดคือ **ช่วงเปลี่ยนขั้น (450ms) ต้องสั้นกว่า animation ของ `BloomView` (900ms)**
/// ไม่งั้นการเคลื่อนจะขาดเป็นท่อน ๆ แทนที่จะต่อเนื่อง — ต้นทางอธิบายไว้ตรง ๆ ว่าที่มันลื่นเพราะ
/// ทุกขั้นถูกเปลี่ยนเป้ากลางทาง ไม่ใช่รอให้ขั้นก่อนหน้าจบ
final class IntroViewTests: XCTestCase {

    /// ขั้นที่ควรเห็น ณ เวลาหนึ่ง ๆ — เริ่มที่ดอกตูม (ขั้น 1) ไม่ใช่ขั้น 0
    ///
    /// ขั้น 0 คือก้านเปล่า ๆ ซึ่งแปลว่าเปิดแอปมาเจอจอว่างอยู่พักหนึ่งก่อนจะมีอะไรเกิดขึ้น
    func testStageStartsAtBudAndStepsEveryInterval() {
        XCTAssertEqual(IntroTimeline.stage(atMillis: 0), 1, "เปิดมาต้องเป็นดอกตูม ไม่ใช่ก้านเปล่า")
        XCTAssertEqual(IntroTimeline.stage(atMillis: 259), 1, "ต้องนิ่งให้เห็นว่าเป็นตูมก่อนขั้นแรกจะขยับ")
        XCTAssertEqual(IntroTimeline.stage(atMillis: 260), 2)
        XCTAssertEqual(IntroTimeline.stage(atMillis: 709), 2)
        XCTAssertEqual(IntroTimeline.stage(atMillis: 710), 3)
        XCTAssertEqual(IntroTimeline.stage(atMillis: 1160), 4)
        XCTAssertEqual(IntroTimeline.stage(atMillis: 1609), 4)
        XCTAssertEqual(IntroTimeline.stage(atMillis: 1610), 5, "ขั้นสุดท้ายต้องมาถึงก่อนช่วงค้าง")
    }

    /// หลังบานเต็มแล้วต้องไม่ไปต่อ — `BloomStages.count` มี 6 ขั้น (0–5) ขั้น 5 คือสุดทาง
    func testStageNeverGoesPastFullBloom() {
        XCTAssertEqual(IntroTimeline.stage(atMillis: 2810), IntroTimeline.finalStage)
        XCTAssertEqual(IntroTimeline.stage(atMillis: 60_000), IntroTimeline.finalStage,
                       "ค้างนานแค่ไหนก็ต้องหยุดที่ขั้นสุดท้าย ไม่วิ่งเลยไปเป็นขั้นที่ไม่มีจริง")
    }

    /// ช่วงเปลี่ยนขั้นต้องสั้นกว่า animation ของ `BloomView` — เหตุผลอยู่ที่หัวไฟล์
    func testStageStepIsShorterThanTheBloomAnimationSoMotionStaysContinuous() {
        XCTAssertLessThan(IntroTimeline.stageStepMillis, 900,
                          "ยาวกว่า 900ms เมื่อไหร่ ดอกไม้จะบานทีละท่อนแทนที่จะบานต่อเนื่อง")
    }

    /// ความยาวรวมของจอ — 260 หน่วงแรก + 4 ขั้น × 450 + 750 ค้างบานเต็ม
    ///
    /// ตัวเลขนี้คือเวลาที่ผู้ใช้ต้องรอทุกครั้งที่เปิดแอป ยาวขึ้นเมื่อไหร่ต้องเป็นการตัดสินใจ
    /// ไม่ใช่ผลข้างเคียงของการแก้จังหวะขั้นใดขั้นหนึ่ง
    func testTotalDurationStaysUnderThreeSeconds() {
        XCTAssertEqual(IntroTimeline.totalMillis, 2810)
        XCTAssertLessThan(IntroTimeline.totalMillis, 3000, "จอเปิดแอปยาวเกิน 3 วิ คือการรอ ไม่ใช่การต้อนรับ")
    }

    /// wordmark โผล่ตอนสองขั้นสุดท้าย ไม่ใช่ตั้งแต่เฟรมแรก — ระหว่างที่ดอกไม้กำลังเคลื่อน
    /// สายตาต้องอยู่ที่ดอกไม้
    func testWordmarkArrivesWithTheLastTwoStages() {
        XCTAssertFalse(IntroTimeline.wordmarkVisible(stage: 1))
        XCTAssertFalse(IntroTimeline.wordmarkVisible(stage: 3),
                       "โผล่เร็วไปคือแย่งสายตาไปจากดอกไม้ที่กำลังบาน")
        XCTAssertTrue(IntroTimeline.wordmarkVisible(stage: 4))
        XCTAssertTrue(IntroTimeline.wordmarkVisible(stage: 5))
    }

    /// เครื่องที่ตั้ง "ลดการเคลื่อนไหว" ต้อง **ข้าม** จอนี้ ไม่ใช่เล่นเร็วขึ้น
    ///
    /// ทั้งจอมีเนื้อหาเดียวคือแอนิเมชัน 2.8 วิ — คนที่ขอไม่ให้มีการเคลื่อนไหวจึงไม่มีอะไรให้ดู
    /// ที่นี่เลย ต้นทาง Android ตัดสินแบบเดียวกันผ่าน `ANIMATOR_DURATION_SCALE == 0`
    func testReduceMotionSkipsTheIntroEntirely() {
        XCTAssertTrue(IntroTimeline.shouldSkip(reduceMotion: true))
        XCTAssertFalse(IntroTimeline.shouldSkip(reduceMotion: false))
    }
}
