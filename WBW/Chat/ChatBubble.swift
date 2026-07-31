import SwiftUI

/// ฟองข้อความ — มุมมน มีหางเฉพาะฟองสุดท้ายของชุด (ท่า iMessage)
struct BubbleShape: Shape {
    let isMine: Bool
    let hasTail: Bool
    private let radius: CGFloat = 18
    private let tail: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let body = rect.insetBy(dx: 0, dy: 0)
        var p = Path(roundedRect: body, cornerRadius: radius)
        guard hasTail else { return p }
        // หางสามเหลี่ยมมนที่มุมล่างฝั่งคนพูด
        let y = body.maxY
        let x = isMine ? body.maxX : body.minX
        let dir: CGFloat = isMine ? 1 : -1
        var t = Path()
        t.move(to: CGPoint(x: x - dir * radius, y: y))
        t.addQuadCurve(to: CGPoint(x: x + dir * tail, y: y),
                       control: CGPoint(x: x, y: y))
        t.addQuadCurve(to: CGPoint(x: x - dir * radius * 0.6, y: y - radius * 0.5),
                       control: CGPoint(x: x - dir * radius * 0.1, y: y - radius * 0.2))
        t.closeSubpath()
        p.addPath(t)
        return p
    }
}

/// ป้ายคั่นวัน
struct ChatDayPill: View {
    let day: Date
    var body: some View {
        Text(ChatFormat.dayLabel(for: day))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Color.black.opacity(0.05), in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }
}

/// เส้น "ข้อความใหม่"
struct ChatUnreadDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.red.opacity(0.25)).frame(height: 1)
            Text("ข้อความใหม่")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.red.opacity(0.7))
            Rectangle().fill(Color.red.opacity(0.25)).frame(height: 1)
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

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isMine { Spacer(minLength: 48) }
            if !isMine {
                // ที่ว่างขนาด avatar เสมอ เพื่อให้ฟองในชุดเดียวกันเรียงตรงกัน
                Group {
                    if layout.isFirstInGroup {
                        ProfileAvatar(name: message.senderName, photoUrl: photoUrl, size: 30)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 30, height: 30)
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                if !isMine && layout.isFirstInGroup {
                    Text(message.senderName)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
                HStack(alignment: .bottom, spacing: 4) {
                    if isMine && layout.showTime { timeLabel }
                    Text(message.body)
                        .font(.system(size: 15))
                        .foregroundStyle(isMine ? .white : Color.wbwInk)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(isMine ? Color.wbwGold : Color.white,
                                    in: BubbleShape(isMine: isMine, hasTail: layout.isLastInGroup))
                    if isMine { stateIcon }
                    if !isMine && layout.showTime { timeLabel }
                }
            }
            if !isMine { Spacer(minLength: 48) }
        }
        .padding(.vertical, layout.isFirstInGroup ? 5 : 1)
    }

    private var timeLabel: some View {
        Text(ChatFormat.time(message.displayTime))
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var stateIcon: some View {
        switch message.state {
        case .pending: Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(.secondary)
        case .sent:    EmptyView()      // สถานะ "ส่งแล้ว/อ่านแล้ว" ย้ายไปบรรทัดสรุปใต้ข้อความล่าสุด
        case .failed:  Button(action: onRetry) {
                           Image(systemName: "exclamationmark.circle.fill")
                               .font(.system(size: 12)).foregroundStyle(.red)
                       }
        }
    }
}

/// ข้อความสถานะใต้ข้อความล่าสุดที่เราส่ง
enum ChatReadStatus {
    static func text(readCount: Int, memberCount: Int) -> String {
        guard readCount > 0 else { return "ส่งแล้ว" }
        let others = max(memberCount - 1, 0)   // ทุกคนยกเว้นเรา
        return readCount >= others ? "อ่านแล้ว \(readCount) · ทั้งกลุ่ม" : "อ่านแล้ว \(readCount)"
    }
}

struct ChatReadStatusLine: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 4).padding(.top, 2).padding(.bottom, 6)
            .animation(.easeOut(duration: 0.2), value: text)
    }
}
