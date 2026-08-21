import SwiftUI

/// ทรงฟองข้อความ — **ไม่มีหางแล้ว มนทุกฟอง** (2026-08-20)
///
/// ของเดิม (`BubbleShape`) วาดสี่เหลี่ยมมนรัศมี 18 แล้ว `addPath` สามเหลี่ยมทับ โดยฐานสามเหลี่ยม
/// เริ่มที่ `x - dir * 18` ซึ่งอยู่ในเขตที่มุมมนกินไปแล้ว และปลายโผล่พ้นขอบที่ `y = maxY` พอดี —
/// เส้นโค้งของหางไม่ต่อเนื่องกับเส้นโค้งของมุม ตาจึงอ่านเป็นธงสามเหลี่ยมคม ๆ แปะอยู่ข้างฟอง
/// ไม่ใช่หางที่งอกออกมา (เห็นชัดจากสกรีนช็อตจริง โดยเฉพาะฟองฝั่งเรา)
///
/// **พอไม่มีหาง สิ่งเดียวที่บอกว่าฟองไหนอยู่ชุดเดียวกันคือรัศมีมุม** — มุมด้านที่ติดกับฟองข้างเคียง
/// ในชุดเดียวกันมนน้อยลง ส่วนมุมฝั่งนอกมนเต็มเสมอ (ท่าเดียวกับ LINE/Telegram)
/// ห้ามทำข้อนี้หายตอนไปแตะอย่างอื่น ไม่งั้นเหลือแค่กล่องมนเรียงกันที่อ่านไม่ออกว่าใครพูดติดกัน
struct ChatBubbleShape: Shape {
    let isMine: Bool
    let isFirstInGroup: Bool
    let isLastInGroup: Bool

    static let full: CGFloat = 18
    /// ยังมนอยู่ ไม่ใช่มุมฉาก — ศูนย์เมื่อไหร่ฟองจะดูเป็นกล่องเหลี่ยม
    static let tight: CGFloat = 6

    /// แยกเป็นฟังก์ชันบริสุทธิ์เพื่อให้เทสจับกฎนี้ได้โดยไม่ต้องไปวัด path (ดู ChatBubbleShapeTests)
    static func corners(isMine: Bool, isFirstInGroup: Bool,
                        isLastInGroup: Bool) -> RectangleCornerRadii {
        // ฟองเรียงเป็นแถวตั้ง เพื่อนบ้านจึงอยู่ "เหนือ" กับ "ใต้" — มุมที่ต้องหุบคือมุมฝั่งคนพูด
        // (ขวาสำหรับเรา ซ้ายสำหรับเขา) ด้านบนถ้ามีฟองก่อนหน้า และด้านล่างถ้ามีฟองถัดไป
        let top = isFirstInGroup ? full : tight
        let bottom = isLastInGroup ? full : tight
        return isMine
            ? RectangleCornerRadii(topLeading: full, bottomLeading: full,
                                   bottomTrailing: bottom, topTrailing: top)
            : RectangleCornerRadii(topLeading: top, bottomLeading: bottom,
                                   bottomTrailing: full, topTrailing: full)
    }

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            cornerRadii: Self.corners(isMine: isMine,
                                      isFirstInGroup: isFirstInGroup,
                                      isLastInGroup: isLastInGroup),
            style: .continuous
        ).path(in: rect)
    }
}

/// ป้ายคั่นวัน
struct ChatDayPill: View {
    let day: Date
    var body: some View {
        Text(ChatFormat.dayLabel(for: day))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            // wbwSurface ไม่ใช่ black.opacity(0.05) — ค่าเดิมมองไม่เห็นเลยในโหมดมืด (ดำบนดำ)
            // ซึ่งกลายเป็นค่าปริยายของแอปไปแล้ว ป้ายจึงลอยอยู่โดยไม่มีพื้น (เห็นจากสกรีนช็อตจริง)
            .background(Color.wbwSurface, in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }
}

/// เส้น "ข้อความใหม่"
struct ChatUnreadDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            // แดงของระบบบนภาพพื้นหลังได้แค่ 2.2:1 — เส้นนี้ไม่มีพื้นของตัวเอง วางบนภาพตรง ๆ
            Rectangle().fill(Color.wbwOnBackdropDanger.opacity(0.25)).frame(height: 1)
            Text("chat_new_messages")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.wbwOnBackdropDanger.opacity(0.7))
            Rectangle().fill(Color.wbwOnBackdropDanger.opacity(0.25)).frame(height: 1)
        }
        .padding(.vertical, 8)
    }
}

/// ฟองข้อความหนึ่งฟอง
struct ChatBubble: View {
    let message: ChatMessage
    let isMine: Bool
    let layout: ChatRow.Layout
    let photoUrl: String?
    let onRetry: () -> Void
    /// ระยะที่แถวถูกลากไปทางซ้าย (ปัดซ้ายค้างเพื่อดูเวลาทุกฟอง)
    var revealOffset: CGFloat = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isMine { Spacer(minLength: 48) }
            if !isMine {
                // ที่ว่างขนาด avatar เสมอ เพื่อให้ฟองในชุดเดียวกันเรียงตรงกัน
                //
                // ติดฟอง **สุดท้าย** ของชุด ไม่ใช่ฟองแรก — แถวนี้จัดชิดล่าง (`alignment: .bottom`)
                // ติดฟองแรกแล้ว avatar จะไปห้อยอยู่ใต้ชื่อผู้ส่งโดยไม่ชิดอะไรเลย ยิ่งฟองสูงขึ้น
                // หลังเวลาย้ายเข้ามาอยู่ข้างในยิ่งลอย (เห็นจากสกรีนช็อตจริง) · ชิดฟองสุดท้าย
                // คือท่าที่ iMessage/Telegram ใช้ และเป็นตำแหน่งที่ "ปิดท้าย" ชุดพอดี
                Group {
                    if layout.isLastInGroup {
                        ProfileAvatar(name: message.senderName, photoUrl: photoUrl, size: 30)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 30, height: 30)
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                if !isMine && layout.isFirstInGroup {
                    // นอกฟอง = วางบนภาพพื้นหลังตรง ๆ ใช้ `.secondary` ไม่ได้ (มันพลิกตามธีม
                    // แต่ภาพไม่พลิก โหมดสว่างจะได้ชื่อสีเข้มบนภาพมืด = หายไป)
                    Text(message.senderName)
                        .font(.caption).foregroundStyle(Color.wbwOnBackdropMuted)
                        .padding(.leading, 4)
                }
                HStack(alignment: .bottom, spacing: 4) {
                    bubble
                    if isMine { stateIcon }
                }
            }
            if !isMine { Spacer(minLength: 48) }
        }
        .padding(.vertical, layout.isFirstInGroup ? 5 : 1)
        .offset(x: -revealOffset)
        .overlay(alignment: .trailing) {
            // ฟองที่โชว์เวลาอยู่แล้ว (ฟองท้ายชุด) ไม่ต้องซ้ำ — เผยเฉพาะฟองที่ปกติไม่มีเวลา
            if revealOffset > 1 && !layout.showTime {
                Text(ChatFormat.time(message.displayTime))
                    .font(.caption2)
                    .foregroundStyle(Color.wbwOnBackdropMuted)   // นอกฟอง
                    .frame(width: 48)
                    .offset(x: 56 - revealOffset)
                    .opacity(Double(revealOffset / 56))
            }
        }
    }

    /// เวลาอยู่ **ในฟอง** มุมล่างขวา (ท่า WhatsApp/LINE) — เดิมลอยอยู่ข้างฟอง กินความกว้าง
    /// ที่ควรเป็นของข้อความไปฟรี ๆ
    ///
    /// `ViewThatFits` เลือกเองว่าเวลาต่อท้ายบรรทัดเดียวกันได้ไหม — ใช้ `HStack` ตรง ๆ ทางเดียว
    /// ไม่ได้ เพราะพอข้อความยาวมันจะไปบีบ `Text` ให้ตัดคำเร็วขึ้นเพื่อเว้นที่ให้เวลา ซึ่งเป็นอาการ
    /// ที่มองไม่ออกว่ามาจากตรงไหนเวลาไปเจอทีหลัง · ใช้ `VStack` ทางเดียวก็ไม่ดี เพราะข้อความสั้น ๆ
    /// อย่าง "โอเค" จะได้ฟองสูงสองบรรทัดโดยไม่จำเป็น
    private var bubble: some View {
        ViewThatFits(in: .horizontal) {
            // ข้อความสั้นพอ = เวลาไปต่อท้ายบรรทัดเดียวกัน (ท่า WhatsApp) ฟองจึงไม่สูงเกินจำเป็น
            HStack(alignment: .lastTextBaseline, spacing: 6) { messageText; time }
            // ยาวกว่านั้น = เวลาลงบรรทัดใหม่ชิดขวา
            VStack(alignment: .trailing, spacing: 2) { messageText; time }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        // ฟองฝั่งเราเป็นเขียวสถานะ ไม่ใช่ `wbwGold` — ตัวนั้นเป็น alias ของ `wbwAccent`
        // (#E9EEE0 ในโหมดมืด) คู่กับตัวอักษร `.white` ตายตัวจากยุคที่มันยังเป็นสีทอง = ขาวบนขาว
        // ฝั่งเขาคง `wbwSurface` + `wbwInk` ไว้ คู่นั้นจับคู่กันเองอยู่แล้วทั้งสองธีม
        .background(isMine ? Color.wbwGreen : Color.wbwSurface,
                    in: ChatBubbleShape(isMine: isMine,
                                        isFirstInGroup: layout.isFirstInGroup,
                                        isLastInGroup: layout.isLastInGroup))
    }

    private var messageText: some View {
        Text(message.body)
            .font(.body)
            .foregroundStyle(isMine ? Color.wbwOnGreen : Color.wbwInk)
    }

    @ViewBuilder private var time: some View {
        if layout.showTime {
            Text(ChatFormat.time(message.displayTime))
                .font(.caption2)
                // ฝั่งเขาคง `.secondary` ได้ — เวลาตัวนี้อยู่**ใน**ฟองที่มีพื้น `wbwSurface`
                // ต่างจากเวลาที่เผยตอนปัดซ้ายซึ่งอยู่นอกฟอง
                .foregroundStyle(isMine ? Color.wbwOnGreen.opacity(0.7) : .secondary)
        }
    }

    @ViewBuilder private var stateIcon: some View {
        switch message.state {
        case .pending: Image(systemName: "clock").font(.caption2)
                           .foregroundStyle(Color.wbwOnBackdropMuted)   // นอกฟอง
        case .sent:    EmptyView()      // สถานะ "ส่งแล้ว/อ่านแล้ว" ย้ายไปบรรทัดสรุปใต้ข้อความล่าสุด
        case .failed:  Button(action: onRetry) {
                           Image(systemName: "exclamationmark.circle.fill")
                               .font(.footnote).foregroundStyle(.red)
                       }
        }
    }
}

/// ข้อความสถานะใต้ข้อความล่าสุดที่เราส่ง
enum ChatReadStatus {
    static func text(readCount: Int, memberCount: Int) -> String {
        guard readCount > 0 else { return Loc.t("chat_sent") }
        let others = max(memberCount - 1, 0)   // ทุกคนยกเว้นเรา
        return String(format: Loc.t(readCount >= others ? "chat_read_by_all" : "chat_read_by"), readCount)
    }
}

struct ChatReadStatusLine: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Color.wbwOnBackdropMuted)   // วางบนภาพพื้นหลังตรง ๆ ไม่มีพื้นของตัวเอง
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 4).padding(.top, 2).padding(.bottom, 6)
            .animation(.easeOut(duration: 0.2), value: text)
    }
}
