import SwiftUI
import PhotosUI

/// หน้าตั้งค่า — โหมดมืด / แจ้งเตือน / บัญชี / ข้อมูล + ออกจากระบบ (ตาม DOI mockup)
///
/// ตัวเลือกภาษาเคยอยู่ตรงนี้ แต่แปลจริงแค่หน้านี้หน้าเดียว เอาออกจนกว่าจะทำ i18n เต็ม (ดู AppSettings)
struct SettingsView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var settings: AppSettings
    @State private var showLogoutConfirm = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return v
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    // การ์ด toggle
                    card {
                        toggleRow(icon: "moon.fill", title: "โหมดมืด", isOn: $settings.isDark)
                        Divider().padding(.leading, 56)
                        toggleRow(icon: "bell.fill", title: "การแจ้งเตือน", isOn: $settings.notiEnabled)
                    }

                    // บัญชี
                    card {
                        NavigationLink { AccountView() } label: {
                            navRow(icon: "person.crop.circle", title: "บัญชี")
                        }
                    }

                    // ข้อมูล/นโยบาย
                    card {
                        NavigationLink { docView("คำถามที่พบบ่อย", faqText) } label: {
                            navRow(icon: "questionmark.circle", title: "คำถามที่พบบ่อย")
                        }
                        Divider().padding(.leading, 56)
                        NavigationLink { docView("เงื่อนไขการใช้งาน", termsText) } label: {
                            navRow(icon: "doc.text", title: "เงื่อนไขการใช้งาน")
                        }
                        Divider().padding(.leading, 56)
                        NavigationLink { docView("นโยบายผู้ใช้", policyText) } label: {
                            navRow(icon: "hand.raised", title: "นโยบายผู้ใช้")
                        }
                        Divider().padding(.leading, 56)
                        navRow(icon: "info.circle", title: "เวอร์ชัน", value: version, chevron: false)
                    }

                    Spacer(minLength: 8)

                    // ออกจากระบบ
                    Button { showLogoutConfirm = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("ออกจากระบบ").fontWeight(.semibold)
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(20)
            }
            .buttonStyle(.plain)  // กัน label ปุ่ม/ลิงก์ ไม่ให้ inherit สีทองจาก tint (text = ขาว)
        }
        .navigationTitle("ตั้งค่า")
        .navigationBarTitleDisplayMode(.large)
        .alert("ออกจากระบบใช่หรือไม่", isPresented: $showLogoutConfirm) {
            Button("ยกเลิก", role: .cancel) {}
            Button("ออกจากระบบ", role: .destructive) { session.logout() }
        }
        .onChange(of: settings.notiEnabled) { _, on in
            // เปิด = ลงทะเบียน device, ปิด = ถอน token
            if on { PushManager.shared.registerCurrent() } else { PushManager.shared.unregister() }
        }
        .tint(.primary)  // back chevron + toolbar ไม่เอาสีทองจาก navbar (เทา/ขาว)
    }

    // การ์ดกลุ่ม (พื้นรอง + มุมมน)
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            rowIcon(icon)
            Text(title).foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Color.wbwGreen)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func navRow(icon: String, title: String, value: String? = nil, chevron: Bool = true) -> some View {
        HStack(spacing: 14) {
            rowIcon(icon)
            Text(title).foregroundStyle(.primary)
            Spacer()
            if let value { Text(value).foregroundStyle(.secondary) }
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func rowIcon(_ system: String) -> some View {
        Image(systemName: system)
            .font(.system(size: 16))
            .foregroundStyle(.secondary)  // เทา
            .frame(width: 28)
    }

    // หน้าเนื้อหา (FAQ/เงื่อนไข/นโยบาย)
    private func docView(_ title: String, _ body: String) -> some View {
        ScrollView {
            Text(body)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // เนื้อหา placeholder (เติมจริงทีหลัง)
    private var faqText: String {
        "ถาม: เข้าสู่ระบบอย่างไร\nตอบ: ใช้รหัสนักศึกษาและรหัสผ่านที่ลงทะเบียนไว้\n\nถาม: เช็คอินฐานอย่างไร\nตอบ: ให้เจ้าหน้าที่สแกน QR หรือแจ้ง BIB ที่ฐาน"
    }
    private var termsText: String {
        "เงื่อนไขการใช้งานแอปเดินรอบดอย 2569 (ฉบับเต็มจะเพิ่มภายหลัง)"
    }
    private var policyText: String {
        "นโยบายผู้ใช้และการคุ้มครองข้อมูลส่วนบุคคล (PDPA) ฉบับเต็มจะเพิ่มภายหลัง"
    }
}

/// ข้อมูลบัญชีย่อ + เปลี่ยนรูปโปรไฟล์
private struct AccountView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @State private var pickerItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var error: String?

    private var me: Me? { profile.me }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                // แตะรูปเพื่อเปลี่ยน (รูปจาก store = อัปเดตทันทีทุกหน้า)
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        ProfileAvatar(name: me?.firstName ?? session.user?.username ?? "", photoUrl: profile.photoUrl, size: 96)
                        if uploading {
                            ProgressView().frame(width: 96, height: 96).background(.black.opacity(0.3), in: Circle())
                        }
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.wbwGreen, in: Circle())
                            .overlay(Circle().stroke(Color(.systemGroupedBackground), lineWidth: 2))
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                Text("แตะรูปเพื่อเปลี่ยน")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }

                VStack(spacing: 0) {
                    row("ชื่อ", me?.fullName)
                    Divider().padding(.leading, 16)
                    row("รหัสนักศึกษา", me?.studentId ?? session.user?.username)
                    Divider().padding(.leading, 16)
                    row("สำนักวิชา", me?.schoolName)
                    Divider().padding(.leading, 16)
                    row("BIB", me?.bibNumber.map(String.init))
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("บัญชี")
        .navigationBarTitleDisplayMode(.inline)
        .task { if profile.me == nil, let t = session.token { await profile.load(token: t) } }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    // โหลดรูป → ครอปสี่เหลี่ยม → ย่อ 400 → base64 → optimistic update (โชว์ทันที) + upload เบื้องหลัง
    private func upload(_ item: PhotosPickerItem) async {
        error = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data),
              let dataUrl = Self.squareDataURL(img) else {
            error = "อ่านรูปไม่ได้"; return
        }
        uploading = true
        defer { uploading = false; pickerItem = nil }
        guard let t = session.token else { return }
        // optimistic: profile.photoUrl เปลี่ยนทันที → Home/Ticket/Account เห็นพร้อมกัน; พลาด = คืนค่าเดิม
        let ok = await profile.updatePhoto(dataUrl: dataUrl, token: t)
        if !ok { error = "อัปโหลดไม่สำเร็จ ลองใหม่" }
    }

    // ครอปกลางเป็นสี่เหลี่ยมจัตุรัส + ย่อ 400px → data URL (JPEG)
    private static func squareDataURL(_ image: UIImage) -> String? {
        let s = min(image.size.width, image.size.height) * image.scale
        let ox = (image.size.width * image.scale - s) / 2
        let oy = (image.size.height * image.scale - s) / 2
        guard let cg = image.cgImage?.cropping(to: CGRect(x: ox, y: oy, width: s, height: s)) else { return nil }
        let square = UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
        let target = CGSize(width: 400, height: 400)
        let resized = UIGraphicsImageRenderer(size: target).image { _ in square.draw(in: CGRect(origin: .zero, size: target)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return nil }
        return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value?.isEmpty == false ? value! : "—").foregroundStyle(.primary)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}
