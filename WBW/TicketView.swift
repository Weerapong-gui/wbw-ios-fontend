import SwiftUI
import CoreImage.CIFilterBuiltins

/// รัศมี avatar และช่องไฟที่อยากให้เห็นพื้นหลังลอดระหว่าง avatar กับขอบการ์ด
private let avatarSize: CGFloat = 116
private let avatarGap: CGFloat = 9

/// โปรไฟล์ = ตั๋วประจำตัวทรงป้ายห้อย (luggage tag) + barcode + ปุ่ม Medical ID — ตาม DOI-APP
struct TicketView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var showMedical = false
    @State private var showSettings = false
    /// ตำแหน่งแนวฉีกในพิกัดของการ์ด — วัดจาก layout จริงแล้วส่งกลับมาให้ TicketShape เจาะรอยเว้า
    /// ให้ตรงเส้นประ ถ้าฮาร์ดโค้ดไว้ รอยเว้ากับเส้นประจะเลื่อนออกจากกันทันทีที่ชื่อยาวขึ้นอีกบรรทัด
    @State private var tearY: CGFloat = 0

    private var me: Me? { profile.me }

    var body: some View {
        NavigationStack {
            // ScrollView เพราะจอเตี้ยใส่ไม่ครบ — SE สูง 667pt เทียบ iPhone 17 ที่ 852 หายไป 185pt
            // ปุ่ม Medical ID เคยโดนตัดครึ่งแล้วกดไม่ได้เลย · จอสูงยังเห็นเต็มใบเหมือนเดิมเพราะ
            // minHeight ดันให้เต็มจอก่อน แล้ว Spacer ค่อยกระจายที่ว่างที่เหลือ
            GeometryReader { g in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        topBar
                        Spacer(minLength: 8)
                        card
                        Spacer(minLength: 18)
                        medicalButton
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 22)
                    .frame(minHeight: g.size.height)
                }
            }
            // background เป็น .background ไม่ใช่ ZStack sibling — ภาพที่ ignoresSafeArea อยู่ใน
            // ZStack จะดันให้ทั้ง stack กินเต็มจอ แล้วเนื้อหาวางในกรอบเต็มตามไปด้วย ปุ่ม top bar
            // เลยไปชนแถบสถานะบนเครื่องที่ safe area บาง (SE ขอบบน 20pt เทียบเครื่องมีบาก 59pt)
            .background(background)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if profile.me == nil, let token = session.token { await profile.load(token: token) }
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "uitestMedical") { showMedical = true }
                if UserDefaults.standard.bool(forKey: "uitestSettings") { showSettings = true }
                #endif
            }
            .sheet(isPresented: $showMedical) {
                MedicalIdView(me: me).presentationDetents([.large])
            }
            // push เนทีฟ = สไลด์จากขวาไปซ้าย และได้ปัดขอบจอกลับมาฟรี — .fullScreenCover เดิม
            // ขึ้นจากล่างเสมอ เปลี่ยน transition ไม่ได้
            .navigationDestination(isPresented: $showSettings) { SettingsView() }
        }
    }

    /// พื้นหลังจอ — ตัวเดียวกับทั้งแอป (ดู AppBackdrop) จะได้ไม่มีรอยต่อตอนสลับจอ
    private var background: some View { AppBackdrop() }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { barIcon("chevron.left") }
                .accessibilityLabel("action_back")
            Spacer()
            Button { showSettings = true } label: { barIcon("gearshape.fill") }
                .accessibilityLabel("action_settings")
        }
        .padding(.top, 6)
    }

    /// ไอคอนบนกระจก ไม่ใช่ไอคอนเปล่า — พื้นหลังเป็นภาพป่าที่สว่างมากและสว่างไม่เท่ากันทั้งจอ
    /// ไอคอนสีเดียวล้วนจะจมหายเป็นบางจุดไม่ว่าจะเลือกสีขาวหรือดำ · กระจกให้พื้นรองที่อ่านออก
    /// ทุกพื้นหลังโดยไม่ต้องคลุม scrim ทับรูปทั้งใบจนภาพวาดหมดความหมาย
    private func barIcon(_ system: String) -> some View {
        Image(systemName: system)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(Color.wbwInk)
            .frame(width: 44, height: 44)
            .glassSurface(Circle(), interactive: true)
    }

    private var medicalButton: some View {
        Button { showMedical = true } label: {
            Text("Medical ID")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 258, height: 52)
                .glassSurface(Capsule(), tint: Color.wbwMedical, interactive: true)
        }
    }

    private var card: some View {
        let first = (me?.firstName?.isEmpty == false ? me?.firstName : nil) ?? me?.username ?? ""
        let last = me?.lastName ?? ""
        let school = me?.schoolName ?? "—"
        let major = me?.major ?? "—"
        let group = me?.groupNumber.map(String.init) ?? "—"
        let seat = me?.bibNumber.map(String.init) ?? "—"
        let idDigits = (me?.studentId ?? me?.username ?? "").map { String($0) }.joined(separator: " ")

        return ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                // เว้นที่ให้ avatar ที่ห้อยคร่อมรอยเว้าขอบบน
                Color.clear.frame(height: avatarSize / 2 + 14)

                Text(first)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
                if !last.isEmpty {
                    Text(last)
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Color(white: 0.15))
                        .fixedSize(horizontal: false, vertical: true)
                }

                field("School of", school).padding(.top, 18)
                field("Major", major).padding(.top, 14)

                tearLine.padding(.top, 20)

                HStack(alignment: .top) {
                    miniField("Group", group)
                    Spacer()
                    miniField("Seat", seat)
                    Spacer()
                    miniField("Date", WBWEvent.ticketDate())
                }
                .padding(.top, 18)

                barcode(idDigits: idDigits).padding(.top, 18)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 26)
            // ตั้งชื่อกรอบนี้ไว้ให้ tearLine วัดตำแหน่งตัวเองเทียบกับมัน — เป็นกรอบเดียวกับที่
            // TicketShape ได้รับเป็น rect พอดี (background ใช้ bounds ของ view ที่มันเกาะอยู่)
            .coordinateSpace(name: "ticket")
            .background(
                TicketShape(corner: 34, avatarCut: avatarSize / 2 + avatarGap,
                            sideCut: 14, tearY: tearY)
                    .fill(.white)
                    // เงาเบา ๆ ตามทรงที่เจาะรูแล้ว — ภาพอ้างอิงแทบไม่มีเงา แต่พอพื้นหลังเป็นรูปจริง
                    // การ์ดจะจมไปกับรูปถ้าไม่มีเลย
                    .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
            )

            // avatar ห้อยคร่อมรอยเว้า (รูปจาก store = อัปเดตทันทีเมื่อเปลี่ยน)
            // ringColor .clear เพราะช่องไฟ avatarGap ทำหน้าที่วงแหวนอยู่แล้ว
            ProfileAvatar(name: first, photoUrl: profile.photoUrl, size: avatarSize, ringColor: .clear)
                .offset(y: -avatarSize / 2)
        }
        .padding(.top, avatarSize / 2 + 8)
        .onPreferenceChange(TearYKey.self) { tearY = $0 }
    }

    /// เส้นประแนวฉีก + รายงานตำแหน่งกลับให้ TicketShape เจาะรอยเว้าข้างให้ตรงกัน
    private var tearLine: some View {
        DashedLine()
            .stroke(Color(white: 0.78), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            .frame(height: 1)
            // -10 = ยืดออกไปให้ชนโคนรอยเว้าข้างพอดี (padding การ์ด 24 − รัศมีรอยเว้า 14)
            .padding(.horizontal, -10)
        .background(
            GeometryReader { g in
                // frame(in: .named("ticket")) = พิกัดในกรอบการ์ด ตรงกับ rect ที่ TicketShape ได้รับ
                Color.clear.preference(key: TearYKey.self, value: g.frame(in: .named("ticket")).midY)
            }
        )
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Color(white: 0.55))
            Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func miniField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Color(white: 0.55))
            Text(value).font(.system(size: 18, weight: .heavy)).foregroundStyle(.black)
        }
    }

    private func barcode(idDigits: String) -> some View {
        VStack(spacing: 6) {
            if let token = me?.qrToken, let img = Self.barcode(token) {
                Image(uiImage: img)
                    .resizable().interpolation(.none).scaledToFit()
                    .frame(height: 60).frame(maxWidth: .infinity)
                    .accessibilityLabel("profile_barcode_label")
            } else {
                Rectangle().fill(Color(white: 0.9)).frame(height: 60)
            }
            Text(idDigits)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.25))
        }
    }

    /// Code128 barcode จาก token
    static func barcode(_ s: String) -> UIImage? {
        let f = CIFilter.code128BarcodeGenerator()
        f.message = Data(s.utf8); f.quietSpace = 2
        guard let out = f.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 3, y: 3))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Medical ID — โมดัลการ์ดดำ (DOI-APP): Name/Age · height/Weight/Blood · Emergency · Allergies · Medication
struct MedicalIdView: View {
    let me: Me?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(white: 0.11).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.white.opacity(0.12), in: Circle())
                                // พื้นที่รับนิ้ว 44 ตาม HIG · วงกลมยังกว้าง 40
                                .frame(width: Config.Tap.minTarget, height: Config.Tap.minTarget)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("action_close")
                        Spacer()
                    }
                    Text("Medical ID")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 4)

                    HStack(alignment: .top) {
                        field("Name", me?.fullName)
                        field("Age", me.flatMap { $0.age(asOf: Date()) }.map { "\($0) years old" })
                    }
                    HStack(alignment: .top, spacing: 8) {
                        field("height", me?.heightCm?.display.map { "\($0) cm." })
                        field("Weight", me?.weightKg?.display.map { "\($0) kg." })
                        field("Blood Type", me?.bloodType)
                    }
                    field("Emergency contact", emergency)
                    field("Allergies & Reactions", me?.foodAllergies)
                    field("Medication", me?.medications)
                }
                .padding(28)
            }
        }
    }

    private var emergency: String? {
        let phone = me?.emergencyContactPhone ?? me?.contactPhone
        let name = me?.emergencyContactName
        let parts = [phone, name.map { "(\($0))" }].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func field(_ label: String, _ value: String?) -> some View {
        let v = (value?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? "Non"
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(Color(white: 0.6))
            Text(v).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
