import SwiftUI


/// ปลายทางที่ push ต่อจากจอแชทได้ — แชทเป็นรากของแท็บ ไม่ใช่ overlay อีกต่อไป
enum GroupRoute: Hashable {
    case home       // กลุ่มของฉัน (ออกจากกลุ่ม, สิทธิ์คงเหลือ)
    case members    // รายชื่อสมาชิก
}

/// แท็บ 3 — ยังไม่เข้ากลุ่ม = หน้าจับกลุ่ม · เข้าแล้ว = จอแชทเลย (หน้ากลุ่มอยู่หลังการกดหัวจอ)
struct GroupTabView: View {
    @EnvironmentObject var profile: ProfileStore
    @ObservedObject var chat: ChatSession
    @Binding var path: [GroupRoute]
    var onBack: () -> Void = {}

    var body: some View {
        // NavigationStack ตัวเดียวของทั้งแท็บ — ทั้งสองสาขาใช้ร่วมกัน ไม่งั้น NavigationLink
        // ในหน้าจับกลุ่ม (ดูสมาชิกก่อนเข้ากลุ่ม) จะไม่มี stack ให้ push แล้วกดแล้วไม่ไปไหนเงียบ ๆ
        NavigationStack(path: $path) {
            Group {
                if profile.me?.groupId == nil {
                    GroupJoinView(onBack: onBack)
                } else {
                    GroupChatView(store: chat, onBack: onBack)
                }
            }
            .navigationDestination(for: GroupRoute.self) { route in
                switch route {
                case .home:
                    GroupHomeView(path: $path)
                case .members:
                    GroupMembersView(groupId: profile.me?.groupId ?? 0,
                                     groupNumber: profile.me?.groupNumber ?? 0)
                }
            }
        }
        // พื้นหลังของทั้งแท็บอยู่ที่นี่ **จุดเดียว** ไม่ใช่จอละอัน
        //
        // `ForestBackground` วาด `AppBackdrop()` ใน `.background{}` ของ view ที่เรียกมัน ใส่ทีละจอ
        // แล้วภาพจะเลื่อนไปกับเฟรมของจอลูกตอน push/pop ขณะที่ `RootView` วาดสำเนาที่นิ่งอยู่ข้างล่าง
        // = ภาพไถลข้ามจอทุกครั้งที่เดินเข้าออก (มองไม่เห็นตอนพื้นเป็นสีเรียบ เห็นชัดตอนเป็นภาพ)
        // แขวนไว้ที่ stack เฟรมไม่ขยับ ภาพจึงนิ่ง · แถมได้ `TabRootOpaqueBackgroundRemover`
        // ตัวเดียวแทนที่จะเป็นสี่ และ `host.day/plantStep` ถูกเขียนครั้งเดียวต่อการเข้าแท็บ
        // แทนที่จะเขียนทุก push (ทุกครั้งที่เขียน `MainTabView.body` ทั้งก้อนถูก invalidate)
        .forestBackground(day: ForestMath.dayStill)
        // แถบหัวจอเป็นพื้นผิวของระบบ ไม่ได้อยู่ใต้กติกา `wbwOnBackdrop` ของเรา — บังคับให้มัน
        // คิดว่าตัวเองอยู่บนพื้นมืดเสมอ ไม่งั้นหัวข้อกับปุ่มกลับที่ระบบสร้างเองจะเป็นสีเข้ม
        // บนภาพมืดในโหมดสว่าง (อาการเดียวกับที่ `Config.swift` เตือนไว้เรื่อง `wbwInk` บนภาพ)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

/// หน้ากลุ่มของฉัน — เข้าถึงจากการกดหัวจอแชท · ดูสมาชิก / ดูสิทธิ์ / ออกจากกลุ่ม
struct GroupHomeView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    @Binding var path: [GroupRoute]
    @State private var leaving = false
    @State private var confirmLeave = false
    @State private var error: String?

    private var groupNo: Int { profile.me?.groupNumber ?? 0 }
    /// อ่านเป็น 0 เมื่อไม่รู้ค่า — backend เก่าไม่ส่ง key นี้มา ปลอดภัยกว่าที่จะไม่โชว์ปุ่มออก
    /// (กดแล้วเจอ 409 จาก server อยู่ดี) ดีกว่าโชว์ปุ่มที่พาไปเจอทางตัน
    private var quota: Int { profile.me?.leaveQuota ?? 0 }

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("group_my_group").font(.system(size: 14)).foregroundStyle(.secondary)
                    Text(String(format: Loc.t("group_number"), groupNo))
                        .font(.system(size: 34, weight: .heavy)).foregroundStyle(Color.wbwInk)
                    QuotaHeartsRow(quota: quota, size: 22)
                        .padding(.top, 2)
                    Text(GroupQuotaText.remaining(quota: quota))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
                .background(Color.wbwSurface, in: RoundedRectangle(cornerRadius: 20))

                Button { path.append(.members) } label: {
                    Label("group_members_link", systemImage: "person.2.fill")
                        .font(.system(size: 16)).foregroundStyle(Color.wbwInk)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(Color.wbwSurface, in: RoundedRectangle(cornerRadius: 16))
                }

                Spacer()

                // สิทธิ์หมด = ไม่มีปุ่ม ไม่ใช่ปุ่มกดไม่ได้ — ไม่มีอะไรให้กดแล้วจริง ๆ
                // ปุ่มจาง ๆ ที่กดไม่ได้ชวนให้กดซ้ำแล้วสงสัยว่าแอปค้าง
                if quota > 0 {
                    Button(role: .destructive) { confirmLeave = true } label: {
                        // แดงของระบบบนภาพพื้นหลังได้ 3.1:1 · `wbwDanger` ยิ่งแย่กว่าในโหมดสว่าง
                        // (ขาสว่างของมันคือ #C0503A = 2.4:1) ปุ่มนี้ไม่มีพื้นของตัวเอง
                        Text(leaving ? "group_leaving" : "group_leave")
                            .font(.system(size: 15)).foregroundStyle(Color.wbwOnBackdropDanger)
                    }
                    .disabled(leaving)
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(Color.wbwOnBackdropDanger)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(20).padding(.top, 8)
        }
        .clearsHostOpaqueBackground()
        .navigationBarTitleDisplayMode(.inline)
        // หัวข้อวางบนภาพพื้นหลัง จึงต้องเป็น principal item ที่กำหนดสีเอง ไม่ใช่ `.navigationTitle`
        // — ตัวนั้นเรนเดอร์ด้วย `UIColor.label` ซึ่งพลิกตามธีม แล้วหัวข้อจะเป็นสีเข้มบนภาพมืด
        // ในโหมดสว่าง (ถ่ายพิสูจน์แล้ว) · `.toolbarColorScheme(.dark)` ที่ `GroupTabView`
        // ก็ไม่ช่วย มันคุมพื้นแถบ ไม่ได้คุมสีหัวข้อ · ท่าเดียวกับ `SettingsView`
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(String(format: Loc.t("group_number"), groupNo))
                    .font(.headline)
                    .foregroundStyle(Color.wbwOnBackdrop)
            }
        }
        // วาดกล่องเอง ไม่ใช่ .alert — alert ของ SwiftUI ใส่ Image ไม่ได้ และจอนี้ต้องโชว์หัวใจ
        // บอกสิทธิ์คงเหลือ (ดูคอมเมนต์หัว LeaveGroupDialog)
        .overlay {
            if confirmLeave {
                LeaveGroupDialog(
                    groupNumber: groupNo, quota: quota, busy: leaving,
                    onCancel: { confirmLeave = false },
                    onConfirm: { Task { await leave() } })
            }
        }
        .animation(.easeOut(duration: 0.18), value: confirmLeave)
        .task {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "uitestLeaveConfirm") { confirmLeave = true }
            #endif
        }
    }

    private func leave() async {
        guard let t = session.token else { return }
        error = nil
        leaving = true
        // ต้องปิดกล่องเองทุกทางออก — `.alert` เดิมปิดตัวเองตอนกดปุ่ม แต่ overlay ที่วาดเอง
        // ผูกอยู่กับ confirmLeave ล้วน ๆ ลืมปิดแล้วกล่องจะค้างทับข้อความ error ที่อยู่ข้างหลัง
        defer { leaving = false; confirmLeave = false }
        do {
            try await APIClient.shared.leaveGroup(token: t)
            await profile.load(token: t)   // group_id = nil → GroupTabView สลับไปหน้าจับกลุ่มเอง
            path.removeAll()               // หน้านี้กำลังจะไม่มีกลุ่มให้แสดง เด้งกลับรากก่อน
        } catch {
            // 409 = admin ตัดสิทธิ์ระหว่างที่จอนี้เปิดค้าง หรือออกไปแล้วจากอีกเครื่อง
            // โหลดโปรไฟล์ใหม่ให้จอตรงกับความจริงทันที ไม่ใช่แค่โชว์ข้อความแล้วปล่อยค้าง
            self.error = (error as? LocalizedError)?.errorDescription ?? Loc.t("error_leave_failed")
            await profile.load(token: t)
        }
    }
}
