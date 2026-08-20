import SwiftUI

/// บัตรผู้เข้าร่วม — **ยกมาจาก `ui/profile/ProfileScreen.kt` ของแอป Android**
///
/// เปิดจากปุ่ม QR ข้างแถบแท็บ (`QrRoute = "profile"` ใน `HomeScaffold.kt`) — ปุ่มที่หน้าตาเป็น
/// QR ควรผลิต QR ออกมา ไม่ใช่เปิดกล้องไปอ่านของคนอื่น
///
/// **บัตรอ่านเป็นแผ่นกระจกฝ้าใบเดียวบนพื้นป่า ไม่ใช่ตั๋วกระดาษ** — ของเดิมฝั่ง iOS
/// (`TicketView`) เป็นตั๋วกระดาษจริง ๆ มีรอยปรุ บาร์โค้ด และพื้นครีม ซึ่งต้นทางเลิกใช้ไปแล้ว
/// ด้วยเหตุผลว่า *"a piece of paper laid over a photograph never belongs to it"*
///
/// ทุกอย่างบนบัตรเป็นขาวบนกระจก **ทั้งสองธีม** ด้วยเหตุผลเดียวกับที่ของเดิมตรึง palette ครีมไว้:
/// บัตรคือดีไซน์ตายตัวที่ยกให้เจ้าหน้าที่ดู ไม่ใช่พื้นผิวที่เดินตามการตั้งค่ารูปลักษณ์
/// ลำดับชั้นมาจากน้ำหนัก ไม่ใช่สี — นั่นคือสิ่งที่ทำให้ขาวสีเดียวทำงานแทนเจ็ดเฉดของ palette เดิมได้
struct ParticipantPassView: View {
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var progress: CheckinProgressStore
    @EnvironmentObject var session: Session
    var onBack: () -> Void = {}

    @State private var showSettings = false

    private var me: Me? { profile.me }

    /// จำนวนแสตมป์ที่เต็มแล้ว — ต้นทางฮาร์ดโค้ด `if (p.checkedIn) 3 else 0` เพราะฝั่งนั้นไม่มี
    /// ความคืบหน้าจริงให้อ่าน · ฝั่ง iOS มี `CheckinProgressStore` อยู่แล้ว จึงใช้ของจริง
    private var stamped: Int { progress.progress?.stage ?? 0 }
    private var totalStamps: Int { max(progress.progress?.total ?? 8, 1) }

    var body: some View {
        VStack(spacing: 0) {
            // ไม่มีแถบหัวจอ — จอนี้เปิดจากปุ่ม QR แล้วปิดกลับ ต้องการแค่ทางกลับ ไม่ต้องการอย่างอื่น
            // หัวจอที่เขียนว่า "บัตรผู้เข้าร่วม" ทับบัตรที่เขียนคำนั้นอยู่แล้วคือการใช้ยอดจอไปกับความว่าง
            //
            // อยู่นอก ScrollView โดยตั้งใจ: บัตรสูงกว่าจอ ปุ่มกลับที่เลื่อนหายไปคือปุ่มที่ต้องเลื่อนกลับ
            // ขึ้นไปหา
            HStack {
                circleButton(systemImage: "arrow.left", label: "กลับ", action: onBack)
                Spacer()
                circleButton(systemImage: "gearshape", label: "ตั้งค่า") { showSettings = true }
            }
            .padding(.top, 6)
            .padding(.bottom, 14)

            ScrollView {
                pass
                    .padding(.bottom, 16)
                    .padding(.bottom, ForestSceneHost.tabBarClearance)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // จำเป็น ไม่ใช่ของเผื่อ — per-tab root ของ TabView ทึบ `AppBackdrop` ที่ RootView วาดไว้
        // ใต้ทุกอย่างจึงมองไม่เห็นจากในแท็บ ต้องให้ forestBackground เจาะพื้นทึบนั้นทิ้งก่อน
        // (ดูคอมเมนต์ TabRootOpaqueBackgroundRemover) — ไม่ใส่แล้วบัตรลอยอยู่บนพื้นดำสนิท
        .forestBackground(day: ForestMath.dayStill)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task {
            if profile.me == nil { await profile.load(token: session.token ?? "") }
        }
    }

    // MARK: - ตัวบัตร

    private var pass: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                kicker("บัตรผู้เข้าร่วม")

                // ทั้งแถวหายไปเมื่อไม่มีกลุ่ม ไม่ใช่เหลือกล่องเปล่า — มันมีไว้ใส่ป้าย ระยะห่างด้านบน
                // ของมันจะกลายเป็นช่องว่างที่อ่านว่ามีของหายไป
                if let group = me?.groupNumber {
                    outlinePill("กลุ่ม \(group)")
                        .padding(.top, 16)
                }

                // ตัวตนกับ QR อยู่แถวเดียวกัน: สองอย่างนี้คือของที่เจ้าหน้าที่มอง และ QR คือตัวที่
                // ถูกยกขึ้นให้ดู · วางข้างชื่อแทนที่จะเป็นบล็อกของตัวเองข้างบน ทำให้มันใหญ่ได้
                // และวางโค้ดไว้ข้างคนที่มันเป็นของ
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(me?.fullName ?? "—")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color.passInk)
                        if let school = me?.schoolName, !school.isEmpty {
                            Text(school)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.passMuted)
                                .padding(.top, 8)
                        }
                        // สาขาอยู่ใต้สำนักวิชาที่มันสังกัด ขนาดเท่ากัน ลดลงหนึ่งขั้นบนสเกลของ ink —
                        // เป็นข้อเท็จจริงชนิดเดียวกันที่ระดับรายละเอียดต่างกัน ตัวอักษรจึงอยู่ที่เดิม
                        // ขยับแค่ความเข้ม · ชิดสำนักวิชามากกว่าที่สำนักวิชาชิดชื่อ (4 ต่อ 8)
                        // เพราะสองบรรทัดนั้นคือที่อยู่เดียวกัน ควรอ่านเป็นก้อนเดียว
                        if let major = me?.major, !major.isEmpty {
                            Text(major)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.passFaint)
                                .padding(.top, 4)
                        }
                        // รหัสนักศึกษาเปล่า ๆ ไม่มีคำว่า "นักศึกษา" นำหน้า — บนบัตรที่พาดหัวว่า
                        // "บัตรผู้เข้าร่วม" ข้างชื่อสำนักวิชา ในงานของมหาวิทยาลัย เลขสิบหลักที่ขึ้นต้น
                        // ด้วย 693 บอกตัวเองอยู่แล้ว · ตัวเลขคือส่วนที่คนต้องอ่านออกเสียงหรือจดตาม
                        if let sid = me?.studentId, !sid.isEmpty {
                            Text(sid)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .kerning(1.2)
                                .foregroundStyle(Color.passInk)
                                .padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 14)

                    // ของทึบชิ้นเดียวท่ามกลางกระจก และตั้งใจให้เป็นสี่เหลี่ยมที่สว่างที่สุดบนแผ่น —
                    // โค้ดที่จะถูกสแกนในที่แสงน้อยใต้ร่มไม้ไม่ควรต้องแข่งกับพื้นผิวโปร่งแสง
                    //
                    // เข้ารหัส `qrToken` เท่านั้น ไม่ใช่ id หรือรหัสนักศึกษา · ดำสนิทบนขาวสนิท
                    // ไม่ใช่เขียวของแผ่น — งานตรงนี้คือคอนทราสต์ล้วน เครื่องสแกนไม่มีความเห็นเรื่อง
                    // ระบบดีไซน์
                    //
                    // ไม่มี token = ไม่มีบล็อก · คนที่แถวข้อมูลเก่ากว่าคอลัมน์นี้เช็คอินด้วยหมายเลขบิบ
                    // ซึ่ง server รองรับอยู่ · วาดสี่เหลี่ยมขาวเปล่าไว้จะชวนให้เข้าใจว่าโค้ดโหลดไม่ขึ้น
                    // แล้วยืนรอมันอยู่ตรงนั้น
                    if let token = me?.qrToken, !token.isEmpty,
                       let image = QRCode.image(from: token) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                            .frame(width: 116, height: 116)
                            .background(Color.passInk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityLabel("คิวอาร์โค้ดสำหรับเช็กอิน")
                    }
                }
                .padding(.top, 20)

                rule.padding(.top, 20)

                // หมายเลขบิบ วางเป็นตัวเลข ไม่ใช่ป้าย — เป็นอีกอย่างบนจอนี้ที่คนอ่านออกเสียง
                // มันจึงได้ขนาดระดับ display เหมือนกัน
                HStack(alignment: .bottom, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        kicker("หมายเลขบิบ")
                        Text(me?.bibNumber.map(String.init) ?? "—")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.passInk)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if stamped > 0 { filledPill("เช็คอินแล้ว") }
                }
                .padding(.top, 16)

                rule.padding(.top, 18)

                // แสตมป์เส้นทาง: ช่องเท่าจำนวนฐาน ช่องที่ได้แล้วทึบ · ของเดิมวาดไอคอนต้นไม้ในทุกช่อง
                // แล้วมีแถบความคืบหน้าอีกอันข้างล่าง — เลขเดียวกันอ่านสองรอบ ในดีไซน์ที่ไม่มีที่ให้
                // ทั้งสองอย่าง
                kicker("แสตมป์เส้นทาง")
                    .padding(.top, 16)
                HStack(spacing: 6) {
                    ForEach(0..<totalStamps, id: \.self) { i in
                        Capsule()
                            .fill(i < stamped ? Color.passInk : Color.passWell)
                            .frame(height: 6)
                    }
                }
                .padding(.top, 10)

                rule.padding(.top, 20)

                VStack(spacing: 0) {
                    detailRow("เลือด", me?.bloodType ?? "—")
                    detailRow("ส่วนสูง / น้ำหนัก", heightWeight)
                    detailRow("เบอร์ติดต่อ", me?.contactPhone ?? "—")
                    detailRow("ผู้ติดต่อฉุกเฉิน", emergency, last: true)
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            masthead.padding(.leading, 6)
        }
        .padding(.leading, 24)
        .padding(.trailing, 10)
        .padding(.top, 26)
        .padding(.bottom, 24)
        .glassSurface(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    /// หัวเสาที่วิ่งขึ้นไปตามขอบ — แบกชื่ออีเวนต์กับเครื่องหมาย "ทางการ" ที่ของเดิมต้องใช้
    /// ไอคอนต้นไม้กับหัวสตับมาพูดเรื่องเดียวกัน
    private var masthead: some View {
        VStack(spacing: 16) {
            verticalLabel("WALK BEYOND THE WILD", color: .passMuted, height: 200)
            Rectangle().fill(Color.passHairline).frame(width: 1, height: 46)
            verticalLabel("ทางการ", color: .passFaint, height: 60)
        }
        .frame(width: 16)
    }

    // MARK: - ชิ้นส่วน

    /// ป้ายตัวเล็กพิมพ์ใหญ่ที่ถ่างตัวอักษร — สไตล์ตัวอักษรรองแบบเดียวของแผ่นนี้
    private func kicker(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8.5, weight: .semibold))
            .kerning(3)
            .foregroundStyle(Color.passFaint)
    }

    private func verticalLabel(_ text: String, color: Color, height: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold))
            .kerning(4)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .rotationEffect(.degrees(90))
            .frame(width: 16, height: height)
    }

    /// ชิปขอบเส้นผม
    private func outlinePill(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8.5, weight: .semibold))
            .kerning(1.6)
            .foregroundStyle(Color.passMuted)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .overlay(Capsule().stroke(Color.passHairline, lineWidth: 1))
    }

    /// ชิปทึบชิ้นเดียวบนแผ่น — ต้นทางก็มีใบเดียวเป๊ะ
    private func filledPill(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8.5, weight: .bold))
            .kerning(1.6)
            .foregroundStyle(Color.passDeepInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.passInk, in: Capsule())
    }

    private var rule: some View {
        Rectangle().fill(Color.passHairline).frame(height: 1)
    }

    private func detailRow(_ label: String, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Text(label.uppercased())
                    .font(.system(size: 8.5))
                    .kerning(1.6)
                    .foregroundStyle(Color.passFaint)
                    .padding(.top, 2)
                Spacer(minLength: 0)
                Text(value)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.passInk)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 10)
            if !last { rule }
        }
    }

    private func circleButton(systemImage: String, label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(Color.passInk)
                .frame(width: 40, height: 40)
                .glassSurface(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - ค่าที่ประกอบจากหลายช่อง

    private var heightWeight: String {
        // `me?.heightCm?.value` เป็น Double?? — optional สองชั้น (ตัว Me เอง กับ LossyNumber
        // ที่คืน nil เมื่อ backend ส่งค่าที่แปลงเป็นตัวเลขไม่ได้) `?? nil` แบนลงเหลือชั้นเดียว
        let height = me?.heightCm?.value ?? nil
        let weight = me?.weightKg?.value ?? nil
        guard let h = height, let w = weight else { return "—" }
        return "\(trim(h)) ซม. · \(trim(w)) กก."
    }

    private var emergency: String {
        let parts = [me?.emergencyContactName, me?.emergencyContactPhone]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func trim(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }
}
