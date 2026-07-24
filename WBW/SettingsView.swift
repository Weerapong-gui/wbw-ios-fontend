import SwiftUI
import PhotosUI

/// หน้าตั้งค่า — dark mode / ภาษา / บัญชี / ข้อมูล + ออกจากระบบ (ตาม DOI mockup)
struct SettingsView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showLogoutConfirm = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return v
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        // การ์ด toggle
                        card {
                            toggleRow(icon: "moon.fill", title: settings.t("โหมดมืด", "Dark mode"), isOn: $settings.isDark)
                            Divider().padding(.leading, 56)
                            toggleRow(icon: "bell.fill", title: settings.t("การแจ้งเตือน", "Notifications"), isOn: $settings.notiEnabled)
                        }

                        // ภาษา + บัญชี
                        card {
                            Menu {
                                Button("ไทย") { settings.lang = "th" }
                                Button("English") { settings.lang = "en" }
                            } label: {
                                navRow(icon: "globe", title: settings.t("ภาษา", "Language"),
                                       value: settings.lang == "en" ? "English" : "ไทย")
                            }
                            Divider().padding(.leading, 56)
                            NavigationLink { AccountView() } label: {
                                navRow(icon: "person.crop.circle", title: settings.t("บัญชี", "Account"))
                            }
                        }

                        // ข้อมูล/นโยบาย
                        card {
                            NavigationLink { docView(settings.t("คำถามที่พบบ่อย", "FAQ"), faqText) } label: {
                                navRow(icon: "questionmark.circle", title: settings.t("คำถามที่พบบ่อย", "FAQ"))
                            }
                            Divider().padding(.leading, 56)
                            NavigationLink { docView(settings.t("เงื่อนไขการใช้งาน", "Terms of service"), termsText) } label: {
                                navRow(icon: "doc.text", title: settings.t("เงื่อนไขการใช้งาน", "Terms of service"))
                            }
                            Divider().padding(.leading, 56)
                            NavigationLink { docView(settings.t("นโยบายผู้ใช้", "User policy"), policyText) } label: {
                                navRow(icon: "hand.raised", title: settings.t("นโยบายผู้ใช้", "User policy"))
                            }
                            Divider().padding(.leading, 56)
                            navRow(icon: "info.circle", title: settings.t("เวอร์ชัน", "Version"), value: version, chevron: false)
                        }

                        Spacer(minLength: 8)

                        // ออกจากระบบ
                        Button { showLogoutConfirm = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text(settings.t("ออกจากระบบ", "Log Out")).fontWeight(.semibold)
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
            .navigationTitle(settings.t("ตั้งค่า", "Settings"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").fontWeight(.semibold).foregroundStyle(.primary)
                    }
                }
            }
            .alert(settings.t("ออกจากระบบใช่หรือไม่", "Log out?"), isPresented: $showLogoutConfirm) {
                Button(settings.t("ยกเลิก", "Cancel"), role: .cancel) {}
                Button(settings.t("ออกจากระบบ", "Log Out"), role: .destructive) { session.logout() }
            }
            .onChange(of: settings.notiEnabled) { _, on in
                // เปิด = ลงทะเบียน device, ปิด = ถอน token
                if on { PushManager.shared.registerCurrent() } else { PushManager.shared.unregister() }
            }
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
        settings.t(
            "ถาม: เข้าสู่ระบบอย่างไร\nตอบ: ใช้รหัสนักศึกษาและรหัสผ่านที่ลงทะเบียนไว้\n\nถาม: เช็คอินฐานอย่างไร\nตอบ: ให้เจ้าหน้าที่สแกน QR หรือแจ้ง BIB ที่ฐาน",
            "Q: How do I log in?\nA: Use your student ID and the password you registered.\n\nQ: How do I check in at a base?\nA: Let staff scan your QR or tell them your BIB number.")
    }
    private var termsText: String {
        settings.t(
            "เงื่อนไขการใช้งานแอปเดินรอบดอย 2569 (ฉบับเต็มจะเพิ่มภายหลัง)",
            "Terms of service for Walk Beyond the Wild 2569 (full text to be added).")
    }
    private var policyText: String {
        settings.t(
            "นโยบายผู้ใช้และการคุ้มครองข้อมูลส่วนบุคคล (PDPA) ฉบับเต็มจะเพิ่มภายหลัง",
            "User policy and personal data protection (PDPA), full text to be added.")
    }
}

/// ข้อมูลบัญชีย่อ + เปลี่ยนรูปโปรไฟล์
private struct AccountView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var settings: AppSettings
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
                Text(settings.t("แตะรูปเพื่อเปลี่ยน", "Tap photo to change"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }

                VStack(spacing: 0) {
                    row(settings.t("ชื่อ", "Name"), me?.fullName)
                    Divider().padding(.leading, 16)
                    row(settings.t("รหัสนักศึกษา", "Student ID"), me?.studentId ?? session.user?.username)
                    Divider().padding(.leading, 16)
                    row(settings.t("สำนักวิชา", "School"), me?.schoolName)
                    Divider().padding(.leading, 16)
                    row("BIB", me?.bibNumber.map(String.init))
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(settings.t("บัญชี", "Account"))
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
            error = settings.t("อ่านรูปไม่ได้", "Cannot read image"); return
        }
        uploading = true
        defer { uploading = false; pickerItem = nil }
        guard let t = session.token else { return }
        // optimistic: profile.photoUrl เปลี่ยนทันที → Home/Ticket/Account เห็นพร้อมกัน; พลาด = คืนค่าเดิม
        let ok = await profile.updatePhoto(dataUrl: dataUrl, token: t)
        if !ok { error = settings.t("อัปโหลดไม่สำเร็จ ลองใหม่", "Upload failed, try again") }
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
