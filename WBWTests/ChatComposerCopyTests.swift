import XCTest
@testable import WBW

/// ช่องพิมพ์ของจอแชทต้องใช้คีย์คำชวนพิมพ์ ไม่ใช่คีย์ชื่อฟิลด์
///
/// `chat_composer_hint` ("พิมพ์ข้อความถึงกลุ่ม…" / "Message your group…") มีอยู่ทั้งสองภาษา
/// มาตลอดแต่ **ไม่มีใครเรียกเลยสักที่** ส่วนช่องพิมพ์ใช้ `chat_message` ("ข้อความ" / "Message")
/// ซึ่งเป็นคำนามเดี่ยว อ่านเหมือนป้ายกำกับฟิลด์ในฟอร์ม ไม่ใช่คำชวนให้พิมพ์ — บนจอแชทที่ไม่มี
/// ป้ายอะไรอยู่ข้าง ๆ เลย ความต่างนี้คือความต่างระหว่าง "ช่องนี้ทำอะไร" กับ "ช่องนี้ชื่ออะไร"
final class ChatComposerCopyTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func testComposerUsesTheHintKey() throws {
        let source = try String(contentsOf: Self.repoRoot.appending(path: "WBW/GroupChatView.swift"),
                                encoding: .utf8)
        XCTAssertTrue(source.contains(#"TextField("chat_composer_hint""#),
                      "ช่องพิมพ์ต้องใช้ chat_composer_hint — คีย์นี้มีอยู่ทั้งสองภาษาแต่ไม่เคยถูกเรียก")
    }

    func testHintExistsInBothLanguages() {
        defer { Loc.use(.system) }
        for language in [AppLanguage.th, .en] {
            Loc.use(language)
            XCTAssertNotEqual(Loc.t("chat_composer_hint"), "chat_composer_hint",
                              "ไม่มีคีย์ในภาษา \(language) — ผู้ใช้จะเห็นชื่อคีย์ในช่องพิมพ์")
        }
    }
}
