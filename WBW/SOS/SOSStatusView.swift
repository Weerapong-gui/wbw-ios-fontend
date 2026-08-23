import SwiftUI

/// จอสถานะ · เปิดเต็มจอทันทีที่กดครบ ไม่ใช่ toast
/// คนกดต้องเห็นว่าเกิดอะไรขึ้น และปุ่มยกเลิกกับปุ่มโทรต้องอยู่ตรงหน้า
struct SOSStatusView: View {
    @ObservedObject var store: SOSStore
    let token: String
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var secondsSinceRaise = 0
    @State private var cancelOutcome: APIClient.SOSCancelOutcome?
    /// ผลของการกด "ส่งข้อความ" ครั้งล่าสุด · nil = ยังไม่เคยกด (ดู noteRow)
    @State private var noteDelivered: Bool?
    @State private var sendingNote = false
    @State private var markingForOther = false
    /// การกด "คนอื่นเจ็บ" ครั้งล่าสุดส่งไม่ถึง — ปุ่มยังอยู่ให้กดใหม่ได้ พร้อมบอกว่ายังไม่ถึง
    @State private var forOtherFailed = false

    private var canCancel: Bool { secondsSinceRaise < 15 && store.serverCase?.ackedAt == nil }

    /// เคสนี้ถูกทำเครื่องหมายว่า "คนอื่นเจ็บ" **และเซิร์ฟเวอร์ยืนยันแล้ว** หรือยัง
    ///
    /// อ่านจาก serverCase อย่างเดียวโดยตั้งใจ (แก้จากรีวิว) — เดิมมี `store.draft?.forOther == true`
    /// อยู่ด้วย ซึ่ง markForOther เขียนลงไปก่อนยิงเสมอ ป้ายจึงเปลี่ยนเป็น "แจ้งไว้แล้ว" แม้การส่งจะ
    /// ล้มเหลว และปุ่มก็หายไปพร้อมกัน ไม่เหลือทางกดใหม่ · ป้ายบนจอนี้ต้องแปลว่า "เจ้าหน้าที่รู้แล้ว"
    /// เท่านั้น ไม่ใช่ "เราตั้งใจจะบอก" — สองอย่างนี้ต่างกันตรงที่คนที่ไปช่วยเห็นอะไร
    private var isForOther: Bool { store.serverCase?.forOther == true }

    var body: some View {
        VStack(spacing: 20) {
            statusBlock

            if store.statusCheckStopped {
                // poll ชนเพดาน "ไม่มีเคส" ติดกันแล้วเลิกเช็คไปเอง (ดู SOSStore.maxConsecutiveEmptyPolls)
                // ต้องบอกตรงๆ ว่าหยุดแล้ว ไม่ใช่ปล่อยให้จอค้างสถานะเก่าเงียบๆ โดยดูเหมือนยังติดตามอยู่
                // (พบจากรีวิว Task 14 รอบสาม)
                warningBox {
                    Text("sos_status_stopped")
                        .multilineTextAlignment(.center)
                    Button("sos_status_recheck") { store.retryStatusCheck(token: token) }
                        .sosTapTarget()
                }
            }

            locationBanner

            noteRow

            forOtherRow

            if canCancel {
                Button("sos_status_cancel", role: .destructive) {
                    Task { cancelOutcome = await store.cancel(token: token) }
                }
                .sosTapTarget()
            }

            // เบอร์มาจากเซิร์ฟเวอร์ ไม่ใช่ลิเทอรัล — `URL(string:)!` ที่เคยอยู่ตรงนี้ crash ทันที
            // ถ้าเบอร์ที่ส่งมามีช่องว่างหรือตัวอักษรพ่วง · ต่อไม่ได้ = ซ่อนปุ่ม ไม่ใช่พังทั้งจอ
            if store.showCallFallback, let callURL = Config.emergencyPhoneURL {
                // ทางออกสุดท้ายเมื่อข้อมูลไปไม่ถึง — เสียง/SMS ไปได้ไกลกว่าดาต้าบนดอย
                Link(destination: callURL) {
                    Label(Loc.t("sos_status_call_center", Config.emergencyPhone), systemImage: "phone.fill")
                        .frame(maxWidth: .infinity).padding()
                        .background(.red).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            if cancelOutcome == .alreadyAcked || cancelOutcome == .tooLate {
                Text("sos_status_already_acked")
                    .foregroundStyle(.secondary)
            }

            minimizeRow

            // ปุ่ม SOS สื่อว่า "กดแล้วมีคนมาช่วยแน่นอน" ซึ่งเกินจริง — แอปนี้แจ้งทีมงานของกิจกรรม
            // ไม่ใช่หน่วยกู้ชีพ · แอปอยู่หมวด Health & Fitness ซึ่ง Apple อ่านละเอียดที่สุดเรื่อง
            // การอ้างความสามารถทางการแพทย์/ฉุกเฉิน และผู้ใช้จริงบนดอยก็ต้องรู้ว่ายังต้องโทร 1669 เอง
            Text("sos_not_emergency_service")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .onAppear {
            // จอนี้เปิดขึ้นมาแปลว่ามีเคสฉุกเฉินอยู่จริงตอนนี้ — ถ้ายังไม่เคยถูกถามเรื่องสิทธิ์ตำแหน่งเลย
            // นี่คือโอกาสสุดท้ายก่อนที่เจ้าหน้าที่จะได้เคสที่ไม่มีพิกัดติดมาด้วย · ขอเฉพาะตอน
            // .notDetermined (ดู SOSLocator.requestPermissionIfNeeded) ไม่มีกล่องเด้งซ้ำให้คนที่ตอบไปแล้ว
            SOSLocator.shared.requestPermissionIfNeeded()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                secondsSinceRaise += 1
            }
        }
        // ยกเลิกสำเร็จแบบที่ยังไม่เคยถึงเซิร์ฟเวอร์ (cancel() เคลียร์ draft/status เป็น nil ทันที
        // ดู SOSStore.cancel) ไม่มีอะไรให้จอนี้แสดงต่อแล้ว — ปิดเองแทนที่จะค้างว่างเปล่าไว้ให้คนหา
        // ทางออกเอง (statusBlock ตกไปสาขา `case nil` ซึ่งไม่มีปุ่มไหนเลย)
        .onChange(of: store.status) { _, new in
            if new == nil { dismiss() }
        }
    }

    /// ทางออกจากจอนี้ที่ **มีอยู่ทุกสถานะ** — ไม่ใช่แค่ตอนเคสปิดแล้ว
    ///
    /// จอนี้เป็น `.fullScreenCover` ซึ่งปัดปิดไม่ได้โดยธรรมชาติ (ตั้งใจ — ดูคอมเมนต์ที่
    /// `MainTabView.fullScreenCover`) และของเดิมมีปุ่มพาออกทางเดียวคือ "ปิดหน้านี้" ที่โผล่เฉพาะ
    /// `case .closed` ส่วนปุ่มยกเลิกก็หายไปเองเมื่อพ้น 15 วินาที · ผลคือ **เคสที่ค้างอยู่ใน
    /// queued/received/onTheWay ขังคนกดไว้ในจอนี้ถาวร** ออกได้ทางเดียวคือ force-quit — ซึ่งใน
    /// โหมดเดโม่ (ทางเข้าของผู้รีวิว App Store) เกิดขึ้นแน่นอน เพราะไม่มีเจ้าหน้าที่จริงมาปิดเคสให้
    ///
    /// ปุ่มนี้ **ไม่แตะเคส** — แค่ปิดจอ เคสยังเปิดอยู่และปุ่ม SOS ที่หน้าบัตรก็เปลี่ยนเป็น
    /// `sos_pass_active` ("กำลังดำเนินการ · แตะดูสถานะ") ให้กดกลับเข้ามาได้ ทางกลับจึงไม่หายไปไหน
    /// · ไม่เปลี่ยนไปใช้ `.sheet` เพราะจะได้ swipe ปิดหลุดมือระหว่างเหตุฉุกเฉิน ซึ่งคือสิ่งที่
    /// `fullScreenCover` ถูกเลือกมากันตั้งแต่แรก
    @ViewBuilder private var minimizeRow: some View {
        if case .closed = store.status {
            // สถานะนี้มีปุ่ม "ปิดหน้านี้" ของตัวเองอยู่แล้ว (statusBlock) ไม่ต้องมีสองปุ่มที่ทำเหมือนกัน
            EmptyView()
        } else {
            VStack(spacing: 4) {
                Button("sos_status_minimize") { dismiss() }
                    .buttonStyle(.bordered)
                    .sosTapTarget()
                Text("sos_status_minimize_hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// สองสถานะที่ทำให้เคสนี้ไม่มีพิกัดติดไปด้วย แก้คนละทางกัน จึงต้องเป็นคนละแบนเนอร์
    ///
    /// เดิมเช็คแค่ `.denied` (พบจากรีวิวรอบสุดท้าย) — คนที่ล็อกอินค้างอยู่ก่อนอัปเดตมาเป็น build นี้
    /// ค้างอยู่ที่ `.notDetermined` ทั้งหมด ซึ่งเป็นสถานะที่ทั้ง oneShot และ cachedFix คืน nil เงียบๆ
    /// เหมือน `.denied` ทุกประการ แต่จอกลับไม่บอกอะไรเลย · `.restricted` (ถูกล็อกโดย MDM/parental
    /// controls) ให้ผลเหมือน `.denied` และแก้ทางเดียวกัน จึงรวมไว้ด้วย
    @ViewBuilder private var locationBanner: some View {
        if SOSLocator.shared.needsPermission {
            warningBox {
                Text("sos_status_loc_undecided")
                    .multilineTextAlignment(.center)
                // คำกลาง ไม่ใช่ "อนุญาตตำแหน่ง" — ปุ่มนี้พาไปสู่กล่องของระบบเหมือน
                // `LocationPrimerSheet` เป๊ะ จึงอยู่ใต้ Guideline 5.1.1(iv) ข้อเดียวกันที่ตีกลับ
                // 1.0 (11) แม้ผู้ตรวจจะยกมาเฉพาะจออธิบาย (ดู `WBWTests/PermissionCopyTests`)
                Button("action_continue") { SOSLocator.shared.requestPermission() }
                    .sosTapTarget()
            }
        } else if SOSLocator.shared.authorization == .denied
                    || SOSLocator.shared.authorization == .restricted {
            // บอกความจริงว่าเสียอะไรไป แทนที่จะเงียบแล้วให้เจ้าหน้าที่หาไม่เจอ
            warningBox {
                Text("sos_status_loc_denied")
                    .multilineTextAlignment(.center)
                Button("sos_status_open_settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .sosTapTarget()
            }
        }
    }

    /// ช่องพิมพ์ข้อความ **พร้อมปุ่มส่ง**
    ///
    /// เดิมมีแต่ `.onSubmit` ซึ่งไม่มีวันยิงเลยกับ `TextField(axis: .vertical)` — ปุ่ม Return บนคีย์บอร์ด
    /// กลายเป็นการขึ้นบรรทัดใหม่ ไม่ใช่การ submit (พบจากรีวิวรอบสุดท้าย) ผลคือคนกดพิมพ์อธิบายอาการลงไป
    /// แล้วไม่มีอะไรถูกส่งเลยสักตัวอักษร บนจอที่กำลังฉุกเฉินอยู่ และ sos_event.message ไม่มีทางมีค่า
    /// เลยทั้งระบบ — ตรงกับกับดัก "ดูเหมือนกดได้แต่กดไม่ได้" ที่โปรเจกต์นี้เพิ่งโดนมาที่จอล็อกอิน
    ///
    /// ข้อความยืนยันบอกจากค่าที่เซิร์ฟเวอร์สะท้อนกลับมาจริง ไม่ใช่บอกว่า "ส่งแล้ว" ทันทีที่กด
    @ViewBuilder private var noteRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("sos_status_note_placeholder", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .onChange(of: note) { _, _ in noteDelivered = nil }

            HStack {
                switch noteDelivered {
                case .some(true):
                    Label("sos_status_note_delivered", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                case .some(false):
                    Label("sos_status_note_failed", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                case nil:
                    EmptyView()
                }
                Spacer()
                Button(sendingNote ? "sos_status_note_sending" : "sos_status_note_send") {
                    sendingNote = true
                    Task {
                        noteDelivered = await store.attachNote(note, token: token)
                        sendingNote = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .sosTapTarget()
                .disabled(sendingNote || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    /// "คนที่เจ็บคือคนอื่น" — ทางเข้าเดียวของ for_other ในแอปทั้งฉบับ
    ///
    /// เดิม SOSButton hard-code `forOther: false` ไว้เป็นผู้เรียกเดียวของ raise() ทั้งแอป ทำให้ทุกอย่าง
    /// ที่สร้างไว้รองรับเรื่องนี้ตายหมด: คอลัมน์ฝั่งเซิร์ฟเวอร์ การ OR ตอนย้ำ เงื่อนไขข้อที่สามของประตู
    /// ข้อมูลสุขภาพ แบนเนอร์ "คนอื่นเจ็บ" บนการ์ดเจ้าหน้าที่ และข้อความที่กลุ่มเพื่อนเห็น — สเปกข้อ 5
    /// ไม่ถูกส่งมอบเลยแม้แต่นิดเดียว (พบจากรีวิวรอบสุดท้าย)
    ///
    /// **ไม่ใช้ Toggle โดยตั้งใจ** — ค่านี้ถอนกลับไม่ได้ (เซิร์ฟเวอร์ OR เข้ากับของเดิมเสมอ) Toggle ที่
    /// ปิดกลับไม่ได้คือ control ที่โกหกผู้ใช้ · ตั้งใจไม่ใส่ไว้บนปุ่ม SOS หลักด้วย: การกดค้าง 3 วิต้อง
    /// เหลือทางเลือกเดียวเสมอ ไม่ใช่ให้เลือกอะไรตอนตกใจ — เลือกทีหลังบนจอนี้ได้ ตอนที่เคสถูกส่งไปแล้ว
    @ViewBuilder private var forOtherRow: some View {
        if isForOther {
            Label("sos_status_for_other_done", systemImage: "person.2.fill")
                .font(.callout).foregroundStyle(.orange)
        } else if store.status?.isActive == true {
            VStack(spacing: 6) {
                Button {
                    markingForOther = true
                    forOtherFailed = false
                    Task {
                        // ใช้ค่าที่คืนมาจริง ไม่ใช่ทิ้งแล้วเดาว่าสำเร็จ — ทรงเดียวกับปุ่มส่งข้อความ
                        // ข้างบน · ล้มเหลวแล้วปุ่มยังอยู่ตรงนี้ให้กดใหม่ได้ทันที ไม่ต้องรอเปิดแอปใหม่
                        let ok = await store.markForOther(token: token)
                        forOtherFailed = !ok
                        markingForOther = false
                    }
                } label: {
                    Label(markingForOther ? "sos_status_for_other_sending" : "sos_status_for_other",
                          systemImage: "person.2.fill")
                }
                .buttonStyle(.bordered)
                .sosTapTarget()
                .disabled(markingForOther)

                if forOtherFailed {
                    Label("sos_status_for_other_failed", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// กล่องเตือนสีเหลือง — รูปแบบเดียวกับที่ statusCheckStopped ใช้อยู่แล้ว ไม่ให้เขียนซ้ำสามที่
    @ViewBuilder private func warningBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 8) { content() }
            .padding().background(.yellow.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// สามชั้นแรกล้มเหลวคนละสาเหตุ จึงต้องเขียนต่างกัน ไม่ใช่ตัวหมุนเดียว
    @ViewBuilder private var statusBlock: some View {
        switch store.status {
        case .queued:
            Label("sos_status_queued", systemImage: "arrow.up.circle")
        case .received:
            Label("sos_status_received", systemImage: "checkmark.circle")
        case .onTheWay:
            Label(Loc.t("sos_status_on_the_way",
                        store.serverCase?.ackedByName ?? Loc.t("sos_status_staff_fallback")),
                  systemImage: "figure.walk.circle.fill")
        case .closed(let reason):
            // เคสจบแล้ว (ยกเลิกเองหลังเคสถึงเซิร์ฟเวอร์แล้ว หรือเจ้าหน้าที่ปิดให้) — ต้องมีทางออก
            // จากจอเต็มจอนี้ด้วย บรีฟเดิมไม่มีปุ่มไหนพาออกจากสถานะนี้เลย (พบระหว่างทำงานนี้เอง — ไม่งั้น
            // คนกดติดอยู่ในจอที่ปิดเคสไปแล้วแต่กลับแอปไม่ได้)
            VStack(spacing: 16) {
                Label(reason == "canceled_by_user" ? "sos_case_canceled" : "sos_status_closed_done",
                      systemImage: "flag.checkered")
                Button("sos_status_close") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .sosTapTarget()
            }
        case nil:
            EmptyView()
        }
    }
}

/// พื้นที่รับนิ้วขั้นต่ำตาม HIG สำหรับปุ่มบนจอ SOS
///
/// ปุ่มเกือบทั้งจอนี้เป็น `Button("ข้อความ")` เปล่า ๆ ซึ่ง SwiftUI ให้ความสูงเท่าบรรทัดข้อความ
/// (~21pt) — ต่ำกว่า 44 ที่ `Config.Tap.minTarget` กำหนดไว้เกือบครึ่ง · นี่คือจอที่คนกดตอนมือสั่น
/// และตอนตกใจ พลาดแล้วต้องเล็งใหม่คือสิ่งที่ยอมไม่ได้ที่สุดตรงนี้
private extension View {
    func sosTapTarget() -> some View {
        frame(minWidth: Config.Tap.minTarget, minHeight: Config.Tap.minTarget)
            .contentShape(Rectangle())
    }
}
