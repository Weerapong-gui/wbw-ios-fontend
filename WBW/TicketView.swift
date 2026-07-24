import SwiftUI
import CoreImage.CIFilterBuiltins

private let ticketBG = Color(white: 0.96)

/// โปรไฟล์ = ตั๋วประจำตัวทรงป้ายห้อย (luggage tag) + barcode + ปุ่ม Medical ID — ตาม DOI-APP
struct TicketView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var showMedical = false
    @State private var showSettings = false

    private var me: Me? { profile.me }

    var body: some View {
        ZStack {
            ticketBG.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)
                card
                Spacer(minLength: 14)
                Button { showMedical = true } label: {
                    Text("Medical ID")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 190, height: 44)
                        .background(Color(red: 0.26, green: 0.09, blue: 0.09), in: Capsule())
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
        }
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
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(white: 0.15))
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(white: 0.15))
            }
        }
        .padding(.top, 6)
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
            // การ์ดขาว + รอยบากข้าง (notch) จำลองด้วยวงกลมสีพื้น
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 54) // เว้นที่ให้ avatar ห้อย

                Text(first.uppercased())
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
                if !last.isEmpty {
                    Text(last.uppercased())
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(white: 0.15))
                }

                field("School of", school).padding(.top, 16)
                field("Major", major).padding(.top, 12)

                // แถวบาก + ข้อมูลตั๋ว
                ZStack {
                    Rectangle().fill(Color(white: 0.88)).frame(height: 1)
                }
                .padding(.top, 18)
                .padding(.horizontal, -22)
                .overlay(notches)

                HStack(alignment: .top) {
                    miniField("Group", group)
                    Spacer()
                    miniField("Seat", seat)
                    Spacer()
                    miniField("Date", "29 AUG 2026")
                }
                .padding(.top, 16)

                barcode(idDigits: idDigits).padding(.top, 16)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .background(.white, in: RoundedRectangle(cornerRadius: 26))
            .shadow(color: .black.opacity(0.10), radius: 16, y: 8)

            // avatar ห้อยคร่อมขอบบน (รูปจาก store = อัปเดตทันทีเมื่อเปลี่ยน)
            ProfileAvatar(name: first, photoUrl: profile.photoUrl, size: 104)
                .offset(y: -52)
        }
        .padding(.top, 52)
    }

    // รอยบากครึ่งวงกลมซ้าย/ขวา (สีพื้น) ตรงเส้นแบ่ง
    private var notches: some View {
        HStack {
            Circle().fill(ticketBG).frame(width: 26, height: 26).offset(x: -13)
            Spacer()
            Circle().fill(ticketBG).frame(width: 26, height: 26).offset(x: 13)
        }
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
                        }
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
