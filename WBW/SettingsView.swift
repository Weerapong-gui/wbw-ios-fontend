import SwiftUI

/// หน้าตั้งค่า — **ยกมาจาก `ui/settings/SettingsScreen.kt` ของแอป Android**
///
/// สี่หมวดตามต้นทาง: ภาษา · รูปลักษณ์ · แจ้งเตือน · ทั่วไป · ทุกหมวดเป็นหัวข้อตัวเล็กพิมพ์ใหญ่
/// ถ่างตัวอักษร แล้วตามด้วยการ์ดกระจกใบเดียว
///
/// **ตัวเลือกภาษากลับมาแล้ว** หลังถูกถอดไปเพราะเคยแปลจริงแค่หน้านี้หน้าเดียว — ตอนนี้ชุดคีย์
/// ทั้ง `en.lproj`/`th.lproj` ยกมาจาก `strings.xml` ของ Android ครบแล้ว ปุ่มจึงมีของจริงให้เปลี่ยน
struct SettingsView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showLogoutConfirm = false
    @State private var showCredits = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("settings_language")
                card {
                    HStack {
                        Text("settings_display_language")
                            .font(.wbwBodyLarge)
                            .foregroundStyle(Color.wbwOnBackdrop)
                        Spacer(minLength: 12)
                        languagePicker
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                sectionHeader("settings_appearance")
                card {
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            themeTile(.light, systemImage: "sun.max", titleKey: "settings_theme_light")
                            themeTile(.dark, systemImage: "moon", titleKey: "settings_theme_dark")
                            themeTile(.auto, systemImage: "circle.lefthalf.filled", titleKey: "settings_theme_auto")
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                        Text("settings_appearance_hint")
                            .font(.wbwBodySmall)
                            .foregroundStyle(Color.wbwOnBackdropMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                }

                sectionHeader("settings_notifications")
                card {
                    VStack(spacing: 0) {
                        // ตัวเดียวที่ต่อกับของจริง — คุมการลงทะเบียน device token (ดู PushManager)
                        toggleRow("settings_noti_announcements", "settings_noti_announcements_desc",
                                  isOn: $settings.notiEnabled)
                        divider
                        // สามตัวล่างเก็บค่าไว้เฉย ๆ ยังไม่มีหมวด push ฝั่ง backend ให้กั้น
                        toggleRow("settings_noti_nearby", "settings_noti_nearby_desc",
                                  isOn: $settings.notiNearby)
                        divider
                        toggleRow("settings_noti_chat", "settings_noti_chat_desc",
                                  isOn: $settings.notiChat)
                        divider
                        toggleRow("settings_noti_daily", "settings_noti_daily_desc",
                                  isOn: $settings.notiDaily)
                    }
                }

                sectionHeader("settings_general")
                card {
                    VStack(spacing: 0) {
                        NavigationLink { AboutEventView() } label: {
                            navRow("settings_about", systemImage: "info.circle")
                        }
                        .buttonStyle(.plain)
                        divider
                        NavigationLink { HelpContactView() } label: {
                            navRow("settings_help", systemImage: "questionmark.circle")
                        }
                        .buttonStyle(.plain)
                        divider
                        NavigationLink { CreditsView() } label: {
                            navRow("settings_credits", systemImage: "doc.text")
                        }
                        .buttonStyle(.plain)
                        divider
                        Button { showLogoutConfirm = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.body)
                                Text("settings_logout")
                                    .font(.wbwBodyLarge)
                                Spacer()
                            }
                            .foregroundStyle(Color.wbwDanger)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 15)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, ForestSceneHost.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .forestBackground(day: ForestMath.dayStill)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left").font(.body.weight(.semibold))
                }
                .accessibilityLabel("action_back")
            }
            ToolbarItem(placement: .principal) {
                Text("settings_title")
                    .font(.wbwTitleLarge)
                    .foregroundStyle(Color.wbwOnBackdrop)
            }
        }
        .confirmationDialog("settings_logout_confirm", isPresented: $showLogoutConfirm,
                            titleVisibility: .visible) {
            Button("settings_logout", role: .destructive) { session.logout() }
            Button("settings_logout_cancel", role: .cancel) {}
        }
        // เปิดหน้าเครดิตตรงๆ เพื่อถ่ายภาพยืนยัน — ทรงเดียวกับ `-uitestSettings` ที่ `TicketView`
        // (เครื่องนี้ไม่มีตัวกดจอ) · หน้านี้เป็นเงื่อนไขสัญญาอนุญาต จึงต้องมีทางถ่ายให้เห็นจริง
        // ไม่ใช่เชื่อว่าเทสเนื้อหาผ่านแล้วแปลว่าเรนเดอร์ถูก
        .navigationDestination(isPresented: $showCredits) { CreditsView() }
        .task {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "uitestCredits") { showCredits = true }
            #endif
        }
        // ต่อสวิตช์ประกาศกับการลงทะเบียนจริง — ปิดแล้วต้องปิดจริง ไม่ใช่แค่จำค่าไว้
        .onChange(of: settings.notiEnabled) { _, on in
            // เปิด = ลงทะเบียน device, ปิด = ถอน token
            if on { PushManager.shared.registerCurrent() } else { PushManager.shared.unregister() }
        }
    }

    // MARK: - ชิ้นส่วน

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.wbwLabelMedium)
            .kerning(1.4)
            .foregroundStyle(Color.wbwOnBackdropMuted)
            .padding(.leading, 4)
            .padding(.top, 22)
            .padding(.bottom, 10)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var divider: some View {
        Rectangle().fill(Color.glassSheerBorder).frame(height: 1)
    }

    /// ตัวเลือกภาษาแบบแบ่งช่อง — ไม่ใช้ `Picker(.segmented)` ของระบบเพราะมันวาดพื้นทึบของ
    /// ตัวเองทับกระจก ซึ่งเป็นสิ่งเดียวที่ทั้งจอนี้พยายามไม่ทำ
    private var languagePicker: some View {
        HStack(spacing: 0) {
            languageChip(.en, label: "settings_lang_english")
            languageChip(.th, label: "settings_lang_thai")
        }
        .padding(3)
        .background(Color.passWell, in: Capsule())
    }

    private func languageChip(_ lang: AppLanguage, label: LocalizedStringKey) -> some View {
        // ค่าปริยายคือ `.system` ซึ่งไม่ตรงกับชิปไหนเลย — ถ้าเทียบตรง ๆ จะไม่มีชิปไหนสว่างสักอัน
        // ทั้งที่แอปกำลังแสดงภาษาใดภาษาหนึ่งอยู่ · เทียบกับภาษาที่ **กำลังแสดงจริง** แทน
        let selected = settings.language == lang || (settings.language == .system && lang == systemLanguage)
        return Button { settings.language = lang } label: {
            Text(label)
                .font(.wbwLabelLarge)
                .foregroundStyle(Color.wbwOnBackdrop)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    if selected { Capsule().fill(Color.passSurface) }
                }
                // ชิปวาดสูง ~31pt ตามดีไซน์ — ขยายเฉพาะพื้นที่รับนิ้ว กราฟิกคงเดิม
                .frame(minHeight: Config.Tap.minTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // สีพื้นอย่างเดียวบอกไม่ได้ว่าอันไหนถูกเลือก — VoiceOver ต้องได้ยินด้วย
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// ภาษาที่เครื่องกำลังใช้กับแอปนี้ — อ่านจาก `preferredLocalizations` ไม่ใช่ `Locale.current`
    /// เพราะเราสนใจว่า bundle เลือก `.lproj` ไหนมาแสดง ไม่ใช่ภาษาที่ผู้ใช้ตั้งไว้ในเครื่อง
    /// (เครื่องตั้งเป็นญี่ปุ่นแล้วแอปตกมาที่ th — ชิปที่ควรสว่างคือ ไทย ไม่ใช่ไม่มีเลย)
    private var systemLanguage: AppLanguage {
        Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true ? .en : .th
    }

    private func themeTile(_ mode: ThemeMode, systemImage: String,
                           titleKey: LocalizedStringKey) -> some View {
        let selected = settings.themeMode == mode
        return Button { settings.themeMode = mode } label: {
            VStack(spacing: 8) {
                Image(systemName: systemImage).font(.title3)
                Text(titleKey).font(.wbwLabelMedium)
            }
            .foregroundStyle(Color.wbwOnBackdrop)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.passWell.opacity(selected ? 2 : 1)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.glassSheerBorder.opacity(selected ? 2.4 : 1), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggleRow(_ titleKey: LocalizedStringKey, _ subtitleKey: LocalizedStringKey,
                           isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(titleKey)
                    .font(.wbwBodyLarge)
                    .foregroundStyle(Color.wbwOnBackdrop)
                Text(subtitleKey)
                    .font(.wbwBodySmall)
                    .foregroundStyle(Color.wbwOnBackdropMuted)
            }
            Spacer(minLength: 8)
            // `labelsHidden()` ซ่อนป้ายจาก VoiceOver ไปด้วย ไม่ใช่แค่จากสายตา — ตัวหนังสือ
            // ข้างซ้ายเป็น `Text` คนละตัวใน HStack เดียวกัน ไม่ได้ผูกกับสวิตช์นี้เลย
            // ผลคือ VoiceOver อ่านได้แค่ "สวิตช์ ปิด" สามครั้งติดกันโดยไม่รู้ว่าอะไรปิด
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.wbwGreen)
                .accessibilityLabel(titleKey)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func navRow(_ titleKey: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).font(.body)
            Text(titleKey).font(.wbwBodyLarge)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(Color.wbwOnBackdropMuted)
        }
        .foregroundStyle(Color.wbwOnBackdrop)
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}

/// หน้าเนื้อหาแบบอ่านอย่างเดียว — สองใบใน "ทั่วไป" ของหน้าตั้งค่าใช้ทรงเดียวกัน
private struct DocView: View {
    let titleKey: LocalizedStringKey
    let bodyKey: LocalizedStringKey

    var body: some View {
        ScrollView {
            Text(bodyKey)
                .font(.wbwBodyLarge)
                .foregroundStyle(Color.wbwOnBackdrop)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, ForestSceneHost.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .forestBackground(day: ForestMath.dayStill)
        .navigationTitle(titleKey)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutEventView: View {
    var body: some View { DocView(titleKey: "settings_about", bodyKey: "about_event_body") }
}

struct HelpContactView: View {
    var body: some View { DocView(titleKey: "settings_help", bodyKey: "help_contact_body") }
}

/// เครดิตข้อมูลแผนที่กับโมเดล 3 มิติ — **เงื่อนไขสัญญาอนุญาต ห้ามลบ**
///
/// โมเดลแผนที่มาจาก maps3d.io ที่ใช้ภาพ `satlas-superes-2023` ของ Allen Institute for AI
/// กับข้อมูล OpenStreetMap · ส่วนไฟล์ `.glb` ใน `WBW/Resources/models/` หลายชิ้นเป็น CC BY 4.0
/// ซึ่งผูกกับ**การเผยแพร่** ไม่ใช่แค่การแสดงผล — ต่อให้ฉากป่าปิดอยู่ (`Config.forest3D = false`)
/// ไฟล์ก็ยังถูกแพ็กไปกับ .ipa เครดิตจึงต้องมี
///
/// เดิมเครดิตแผนที่เป็นข้อความฮาร์ดโค้ดวางทับบนจอแผนที่ (ไม่ผ่านชุดคีย์ด้วย) ย้ายมาที่นี่
/// 2026-08-21 เพราะมันบังแผนที่อยู่ตลอดเวลา · `WBWTests/MapCreditsTests.swift` ตรวจว่าชื่อ
/// ที่สัญญาอนุญาตบังคับยังอยู่ครบทั้งสองภาษา — สคริปต์ตรวจคีย์จับแทนไม่ได้ เพราะ regex ของมัน
/// ไม่ครอบ `DocView(titleKey:bodyKey:)` และมันไม่รู้ว่าข้างในเขียนอะไร
struct CreditsView: View {
    /// คีย์เป็นค่าคงที่ ไม่ใช่ลิเทอรัลในบรรทัด `DocView(...)` เพราะ **`DocView` รับ
    /// `LocalizedStringKey` ซึ่งพิมพ์ผิดแล้วเรนเดอร์ชื่อคีย์ออกมาเฉย ๆ** ไม่มี error ไม่มี warning
    /// และ `scripts/check-localization.sh` ก็จับไม่ได้ (regex ของมันไม่ครอบ `DocView(...)`) ·
    /// ดึงออกมาแล้วเทสอ่านคีย์ตัวเดียวกับที่จอใช้จริง พิมพ์ผิดที่นี่ = เทสแดง ไม่ใช่ผู้ใช้เห็นคำว่า
    /// "credits_body" บนหน้าเครดิต
    static let titleKey = "settings_credits"
    static let bodyKey = "credits_body"

    var body: some View {
        DocView(titleKey: LocalizedStringKey(Self.titleKey),
                bodyKey: LocalizedStringKey(Self.bodyKey))
    }
}
