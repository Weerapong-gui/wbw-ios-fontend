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
                    Text("หยุดเช็คสถานะอัตโนมัติแล้ว สัญญาณอาจหลุดนานเกินไป — ที่เห็นอาจไม่ใช่ล่าสุด")
                        .multilineTextAlignment(.center)
                    Button("เช็คสถานะอีกครั้ง") { store.retryStatusCheck(token: token) }
                }
            }

            locationBanner

            noteRow

            forOtherRow

            if canCancel {
                Button("กดผิด · ยกเลิก", role: .destructive) {
                    Task { cancelOutcome = await store.cancel(token: token) }
                }
            }

            if store.showCallFallback {
                // ทางออกสุดท้ายเมื่อข้อมูลไปไม่ถึง — เสียง/SMS ไปได้ไกลกว่าดาต้าบนดอย
                Link(destination: URL(string: "tel://\(Config.emergencyPhone)")!) {
                    Label("โทรหาทีมกลาง \(Config.emergencyPhone)", systemImage: "phone.fill")
                        .frame(maxWidth: .infinity).padding()
                        .background(.red).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            if cancelOutcome == .alreadyAcked || cancelOutcome == .tooLate {
                Text("เจ้าหน้าที่รับเรื่องแล้ว ยกเลิกไม่ได้ ให้โทรบอกแทน")
                    .foregroundStyle(.secondary)
            }
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

    /// สองสถานะที่ทำให้เคสนี้ไม่มีพิกัดติดไปด้วย แก้คนละทางกัน จึงต้องเป็นคนละแบนเนอร์
    ///
    /// เดิมเช็คแค่ `.denied` (พบจากรีวิวรอบสุดท้าย) — คนที่ล็อกอินค้างอยู่ก่อนอัปเดตมาเป็น build นี้
    /// ค้างอยู่ที่ `.notDetermined` ทั้งหมด ซึ่งเป็นสถานะที่ทั้ง oneShot และ cachedFix คืน nil เงียบๆ
    /// เหมือน `.denied` ทุกประการ แต่จอกลับไม่บอกอะไรเลย · `.restricted` (ถูกล็อกโดย MDM/parental
    /// controls) ให้ผลเหมือน `.denied` และแก้ทางเดียวกัน จึงรวมไว้ด้วย
    @ViewBuilder private var locationBanner: some View {
        if SOSLocator.shared.needsPermission {
            warningBox {
                Text("ยังไม่ได้อนุญาตให้แอปใช้ตำแหน่ง เจ้าหน้าที่จะเห็นแค่ฐานล่าสุดที่คุณเช็คอิน")
                    .multilineTextAlignment(.center)
                Button("อนุญาตตำแหน่ง") { SOSLocator.shared.requestPermission() }
            }
        } else if SOSLocator.shared.authorization == .denied
                    || SOSLocator.shared.authorization == .restricted {
            // บอกความจริงว่าเสียอะไรไป แทนที่จะเงียบแล้วให้เจ้าหน้าที่หาไม่เจอ
            warningBox {
                Text("ไม่ได้อนุญาตตำแหน่ง เจ้าหน้าที่จะเห็นแค่ฐานล่าสุดที่คุณเช็คอิน")
                    .multilineTextAlignment(.center)
                Button("ไปตั้งค่า") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
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
            TextField("บอกเจ้าหน้าที่เพิ่มได้ (ไม่บังคับ)", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .onChange(of: note) { _, _ in noteDelivered = nil }

            HStack {
                switch noteDelivered {
                case .some(true):
                    Label("เจ้าหน้าที่เห็นข้อความนี้แล้ว", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                case .some(false):
                    Label("ยังส่งไม่ถึง เก็บไว้ในเครื่องแล้ว กดส่งอีกครั้งได้", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                case nil:
                    EmptyView()
                }
                Spacer()
                Button(sendingNote ? "กำลังส่ง…" : "ส่งข้อความ") {
                    sendingNote = true
                    Task {
                        noteDelivered = await store.attachNote(note, token: token)
                        sendingNote = false
                    }
                }
                .buttonStyle(.borderedProminent)
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
            Label("แจ้งไว้แล้วว่าคนที่เจ็บเป็นคนอื่น", systemImage: "person.2.fill")
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
                    Label(markingForOther ? "กำลังแจ้ง…" : "คนที่เจ็บเป็นคนอื่น ไม่ใช่ฉัน",
                          systemImage: "person.2.fill")
                }
                .buttonStyle(.bordered)
                .disabled(markingForOther)

                if forOtherFailed {
                    Label("ยังแจ้งไม่ถึงเจ้าหน้าที่ กดอีกครั้งได้", systemImage: "exclamationmark.circle")
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
            Label("กำลังส่ง… ยังไม่ถึงเจ้าหน้าที่", systemImage: "arrow.up.circle")
        case .received:
            Label("ส่งถึงเจ้าหน้าที่แล้ว กำลังรอคนรับเรื่อง", systemImage: "checkmark.circle")
        case .onTheWay:
            Label("\(store.serverCase?.ackedByName ?? "เจ้าหน้าที่") กำลังไปหาคุณ",
                  systemImage: "figure.walk.circle.fill")
        case .closed(let reason):
            // เคสจบแล้ว (ยกเลิกเองหลังเคสถึงเซิร์ฟเวอร์แล้ว หรือเจ้าหน้าที่ปิดให้) — ต้องมีทางออก
            // จากจอเต็มจอนี้ด้วย บรีฟเดิมไม่มีปุ่มไหนพาออกจากสถานะนี้เลย (พบระหว่างทำงานนี้เอง — ไม่งั้น
            // คนกดติดอยู่ในจอที่ปิดเคสไปแล้วแต่กลับแอปไม่ได้)
            VStack(spacing: 16) {
                Label(reason == "canceled_by_user" ? "ยกเลิกแล้ว" : "เรื่องจบแล้ว",
                      systemImage: "flag.checkered")
                Button("ปิดหน้านี้") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        case nil:
            EmptyView()
        }
    }
}
