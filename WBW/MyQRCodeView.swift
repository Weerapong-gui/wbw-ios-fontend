import SwiftUI
import CoreImage.CIFilterBuiltins

/// สร้าง QR จาก token (แพทเทิร์นเดียวกับ barcode ใน TicketView)
enum QRCode {
    static func image(from string: String) -> UIImage? {
        guard !string.isEmpty else { return nil }
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(string.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// My QR Code — QR ประจำตัวสำหรับเช็คอิน (Figma 16:229) · พื้นป่า + กรอบสแกน
struct MyQRCodeView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    private var me: Me? { profile.me }

    var body: some View {
        ZStack {
            VStack(spacing: 28) {
                Text("My QR Code")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 24)
                qrCard
                Spacer()
            }
        }
        // อยู่ใน MainTabView (แท็บ QR) — ใช้ bottomClearance ค่าเริ่มต้นที่พ้นแท็บบาร์ลอย
        .forestBackground(day: ForestMath.dayStill)
        .task { if me == nil, let t = session.token { await profile.load(token: t) } }
    }

    private var qrCard: some View {
        ZStack {
            if let token = me?.qrToken, let img = QRCode.image(from: token) {
                Image(uiImage: img).resizable().interpolation(.none).scaledToFit()
                    .padding(28)
                    .frame(width: 300, height: 300)
                    .background(.white, in: RoundedRectangle(cornerRadius: 24))
                    // ทั้งจอมีของอยู่ชิ้นเดียว — ไม่มีป้ายแล้ว VoiceOver อ่านได้แค่ "รูปภาพ"
                    // (ตัวเดียวกันที่ ParticipantPassView มีป้ายอยู่แล้ว ที่นี่ตกหล่น)
                    .accessibilityLabel("profile_qr_mine_label")
            } else {
                RoundedRectangle(cornerRadius: 24).fill(.white)
                    .frame(width: 300, height: 300)
                    .overlay(ProgressView())
            }
        }
        .overlay(ScanFrame().stroke(.white, lineWidth: 6).frame(width: 340, height: 340))
    }
}

/// กรอบสแกนมุม L 4 มุม
struct ScanFrame: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let len = rect.width * 0.18
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ]
        p.move(to: CGPoint(x: corners[0].x, y: corners[0].y + len)); p.addLine(to: corners[0]); p.addLine(to: CGPoint(x: corners[0].x + len, y: corners[0].y))
        p.move(to: CGPoint(x: corners[1].x - len, y: corners[1].y)); p.addLine(to: corners[1]); p.addLine(to: CGPoint(x: corners[1].x, y: corners[1].y + len))
        p.move(to: CGPoint(x: corners[2].x, y: corners[2].y - len)); p.addLine(to: corners[2]); p.addLine(to: CGPoint(x: corners[2].x + len, y: corners[2].y))
        p.move(to: CGPoint(x: corners[3].x - len, y: corners[3].y)); p.addLine(to: corners[3]); p.addLine(to: CGPoint(x: corners[3].x, y: corners[3].y - len))
        return p
    }
}

#Preview {
    MyQRCodeView()
        .environmentObject(Session())
        .environmentObject(ProfileStore())
        .environmentObject(ForestSceneHost())
}
