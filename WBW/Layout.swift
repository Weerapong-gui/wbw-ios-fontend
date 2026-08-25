import SwiftUI

/// ระยะของเลย์เอาต์ที่ต้อง "รู้เรื่องขนาดจอ" — คนละเรื่องกับสีและแฟลกใน `Config.swift`
///
/// **มีไฟล์นี้เพราะค่าเดียวกันต้องตอบต่างกันบนสองไอดิอม** เดิมระยะพ้นแถบแท็บเป็น `static let`
/// ตัวเดียวที่ตอบเหมือนกันทุกที่ (`ForestSceneHost.tabBarClearance`) ซึ่งถูกบน iPhone
/// และผิดไป 89pt บน iPad โดยไม่มี build หรือ test ตัวไหนฟ้องเลย
enum WBWLayout {

    /// ระยะพ้นแถบแท็บลอยของ `MainTabView` — **0 บน iPad โดยตั้งใจ ไม่ใช่เพราะยังไม่ได้วัด**
    ///
    /// `TabView` แบบ `Tab(value:)` ในไอดิอม regular วางแท็บไว้ **ข้างบน** ไม่ใช่ข้างล่าง
    /// ขอบล่างจึงไม่มีอะไรให้พ้นนอกจาก safe area ซึ่งระบบให้มาเองอยู่แล้ว — เว้น 89pt ตรงนั้น
    /// คือที่ว่างตายที่ไม่มีอะไรอยู่ ขณะที่ขอบที่ต้องการระยะจริงกลายเป็นขอบบน
    ///
    /// ค่าของ compact มาจากการสแกนพิกเซลบนสกรีนช็อตจริงสองเครื่อง — คอมเมนต์ยาวที่
    /// `ForestSceneHost.tabBarClearance` ยังจริงทุกตัวอักษรสำหรับไอดิอมนั้น ไม่ได้ถูกทิ้ง
    ///
    /// **`nil` ต้องตอบเท่า compact ไม่ใช่ 0** — SwiftUI ให้ `nil` มาในเฟรมแรกก่อน resolve
    /// size class ได้ · เขียนเป็น `h == .compact ? … : 0` (ซึ่งอ่านแล้วดูเหมือนกัน) จะตอบ 0
    /// ให้เฟรมนั้น แล้วเนื้อหากระพริบไปอยู่ใต้แถบแท็บหนึ่งเฟรมทุกครั้งที่เข้าจอ บน iPhone ทุกเครื่อง
    static func tabBarClearance(_ horizontal: UserInterfaceSizeClass?) -> CGFloat {
        horizontal == .regular ? 0 : ForestSceneHost.tabBarClearance
    }

    /// ความกว้างสูงสุดของคอลัมน์เนื้อหาบนจอกว้าง
    ///
    /// มีหลายค่าเพราะของแต่ละชนิดพังคนละแบบเมื่อกว้างเกิน: ฟอร์มทำให้ตากวาดกลับไกลเกินระหว่าง
    /// ป้ายกับค่า ส่วนบัตรเป็น **วัตถุที่มีสัดส่วนของตัวเอง** — บัตรกว้าง 560 อ่านเป็นบัตรที่ถูกยืด
    /// ไม่ใช่บัตรที่ใหญ่ขึ้น · ตัวเลขเป็นดุลพินิจ แต่ **ลำดับ** คือเหตุผลของการมีหลายค่า
    /// (`WBWTests/LayoutMetricsTests` ค้ำลำดับไว้ ไม่ได้ค้ำตัวเลข)
    enum Column: CGFloat, CaseIterable {
        /// กล่องยืนยัน — `LeaveGroupDialog` ใช้ 320 มาก่อนแล้ว
        case dialog = 340
        /// บัตรผู้เข้าร่วม / ตั๋ว
        case pass = 420
        /// ฟอร์ม ตั้งค่า ล็อกอิน
        case form = 480
        /// การ์ด รายการ จอทั่วไป
        case card = 560
        /// บทสนทนาแชท — ฟองข้อความเป็นร้อยแก้วยาวไม่เท่ากัน ต้องการมากกว่าฟอร์ม
        case transcript = 680
    }

    /// `nil` = ไม่จำกัด · **compact ใช้เต็มความกว้างเสมอ**
    ///
    /// จอ iPhone SE กว้าง 375pt อยู่แล้ว หนีบเข้าไปอีกคือทำให้จอที่แคบอยู่แล้วแคบลง ·
    /// ผลพลอยได้ที่สำคัญกว่า: ทำให้ทุก commit ที่ทา `.contentColumn()` เป็น **no-op บน iPhone
    /// แบบพิสูจน์ได้** สกรีนช็อตที่ส่ง App Store ไปแล้วจึงไม่ขยับสักใบ
    static func columnWidth(_ column: Column, _ horizontal: UserInterfaceSizeClass?) -> CGFloat? {
        horizontal == .regular ? column.rawValue : nil
    }
}

// MARK: - ระยะพ้นแถบแท็บ

private struct TabBarClearanceModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontal
    let extra: CGFloat

    func body(content: Content) -> some View {
        content.padding(.bottom, WBWLayout.tabBarClearance(horizontal) + extra)
    }
}

// MARK: - คอลัมน์เนื้อหา

private struct ContentColumnModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontal
    let column: WBWLayout.Column
    let alignment: Alignment

    func body(content: Content) -> some View {
        content
            // ชั้นใน: หนีบความกว้าง — `nil` บน compact แปลว่าไม่หนีบ (iPhone เหมือนเดิมเป๊ะ)
            .frame(maxWidth: WBWLayout.columnWidth(column, horizontal) ?? .infinity,
                   alignment: alignment)
            // ชั้นนอก: กินเต็มความกว้างแล้ววางคอลัมน์ไว้กลาง — **ต้องมีสองชั้น** เพราะ frame
            // ชั้นเดียวได้แค่ "กว้างไม่เกิน N" ส่วนจะไปนั่งตรงไหนของจอขึ้นกับ container ที่ห่ออยู่
            // ซึ่งแต่ละจอไม่เหมือนกัน — คอลัมน์จะไปชิดซ้ายบ้างกลางบ้างแล้วแต่จอ
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - เนื้อหาที่เลื่อนได้เฉพาะตอนใส่ไม่ลง

/// จอที่ปกติยืดเต็มจอด้วย `Spacer()` แต่ต้องเลื่อนได้เมื่อเนื้อหาใส่ไม่ลง
///
/// **ห่อด้วย `ScrollView` เฉย ๆ ไม่ได้** — `Spacer()` ใน `ScrollView` ยุบเหลือ 0 เสมอ
/// เพราะ scroll view ให้ความสูงไม่จำกัดกับลูก การจัดกึ่งกลาง/ดันไปก้นจอทั้งหมดจะหายไปทันที
/// บนจอที่ *ใส่ลงอยู่แล้ว* ซึ่งคือเครื่องส่วนใหญ่ — แก้จอที่ล้นบน SE แล้วพังจอบน iPhone 17 แทน
///
/// `minHeight: geo.size.height` คือสิ่งที่ทำให้ `Spacer()` ยังทำงาน: เนื้อหาสูงเท่าจอพอดี
/// ตอนใส่ลง และสูงกว่าจอเมื่อไม่ลง
///
/// `GeometryReader` อยู่ **นอก** `ScrollView` โดยตั้งใจ — วางไว้ข้างในมันจะอ่านความสูงของ
/// เนื้อหา ไม่ใช่ของ viewport แล้ว `minHeight` จะอ้างอิงตัวเอง
///
/// `.scrollBounceBehavior(.basedOnSize)` ไม่ใช่ของประดับ — ไม่มีมันแล้วทุกจอที่ใช้ตัวนี้จะเริ่ม
/// เด้งยางบนเครื่องที่เนื้อหาใส่ลงสบาย ๆ ซึ่งเป็น regression ที่ผู้ใช้เห็น
struct FitsOrScrolls<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content.frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

extension View {
    /// เว้นให้พ้นแถบแท็บลอย — เท่ากับ safe area เปล่า ๆ บน iPad เพราะแถบอยู่ข้างบน
    func tabBarClearance(extra: CGFloat = 0) -> some View {
        modifier(TabBarClearanceModifier(extra: extra))
    }

    /// หนีบเนื้อหาเป็นคอลัมน์กลางจอบนจอกว้าง — **ไม่มีผลบน iPhone เลย**
    ///
    /// วางไว้ **นอกสุด ถัดจาก `.padding(.horizontal,)`** เพื่อให้ระยะขอบในคอลัมน์เท่ากับที่ตา
    /// เห็นบนมือถือพอดี ไม่ใช่คอลัมน์ 560 แล้วมีขอบโผล่ออกมาอีกชั้น
    ///
    /// ใส่กับ **เนื้อหาข้างใน `ScrollView` ไม่ใช่ตัว `ScrollView`** — หนีบตัว scroll view แล้ว
    /// แถบเลื่อนขยับเข้ามาจากขอบจอ และพื้นที่รับการปัดถูกตัดเหลือแค่ความกว้างคอลัมน์
    func contentColumn(_ column: WBWLayout.Column = .card,
                       alignment: Alignment = .center) -> some View {
        modifier(ContentColumnModifier(column: column, alignment: alignment))
    }
}

/// เลย์เอาต์ที่ต้องเปลี่ยนทรงเมื่อผู้ใช้ตั้งตัวอักษรใหญ่ระดับ Accessibility
///
/// **เจอจากการรันจริงที่ `AccessibilityXXXL` ไม่ใช่จากการอ่านโค้ด** — สองจอที่พังคนละแบบ:
/// จอสถานะ SOS แถบทางออกที่ปักไว้โตจนกินเกือบทั้งจอ (การ์ดกรุ๊ปเลือดที่ทำมาให้ยื่นให้คนช่วยดู
/// ถูกดันออกนอกจอ) ส่วนแถวอากาศหน้า Home ตัดคำทิ้งจนเหลือ "27° รู้…" กับ "AQI… ดี"
///
/// แยกกติกาออกมาจากจอด้วยเหตุผลเดียวกับ `WBWLayout` ข้างบน: เงื่อนไขเดียวกันถูกใช้สองที่
/// และ "เมื่อไหร่ถึงเรียกว่าใหญ่" เป็นของที่เทสตรวจได้ ส่วนหน้าตาที่ออกมาต้องใช้ตาคนดู
enum BigTextLayout {

    /// แถบทางออกท้ายจอ SOS เหลือปักไว้เฉพาะปุ่มยกเลิกไหม
    ///
    /// ปุ่มยกเลิกคือปุ่มที่แพงที่สุดบนจอนั้นถ้าหาไม่เจอ — เคสที่ยกเลิกไม่ได้แปลว่าเจ้าหน้าที่
    /// ออกเดินไปหาคนที่ไม่ได้ต้องการความช่วยเหลือแล้ว · ที่เหลือ (ย่อลง + ข้อความ 1669)
    /// ย้ายลงไปอยู่ในส่วนที่เลื่อนได้ เพราะอ่านครั้งเดียวก็พอ ไม่ต้องอยู่ตรงหน้าตลอดเวลา
    static func pinsOnlyTheCancelButton(_ size: DynamicTypeSize) -> Bool {
        size.isAccessibilitySize
    }

    /// แถวอากาศ/AQI เรียงลงเป็นสองบรรทัดแทนการอยู่บรรทัดเดียวไหม
    static func stacksTrailConditions(_ size: DynamicTypeSize) -> Bool {
        size.isAccessibilitySize
    }
}
