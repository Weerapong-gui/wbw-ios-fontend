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

    private var canCancel: Bool { secondsSinceRaise < 15 && store.serverCase?.ackedAt == nil }

    var body: some View {
        VStack(spacing: 20) {
            statusBlock

            if store.statusCheckStopped {
                // poll ชนเพดาน "ไม่มีเคส" ติดกันแล้วเลิกเช็คไปเอง (ดู SOSStore.maxConsecutiveEmptyPolls)
                // ต้องบอกตรงๆ ว่าหยุดแล้ว ไม่ใช่ปล่อยให้จอค้างสถานะเก่าเงียบๆ โดยดูเหมือนยังติดตามอยู่
                // (พบจากรีวิว Task 14 รอบสาม)
                VStack(spacing: 8) {
                    Text("หยุดเช็คสถานะอัตโนมัติแล้ว สัญญาณอาจหลุดนานเกินไป — ที่เห็นอาจไม่ใช่ล่าสุด")
                        .multilineTextAlignment(.center)
                    Button("เช็คสถานะอีกครั้ง") { store.retryStatusCheck(token: token) }
                }
                .padding().background(.yellow.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if SOSLocator.shared.authorization == .denied {
                // บอกความจริงว่าเสียอะไรไป แทนที่จะเงียบแล้วให้เจ้าหน้าที่หาไม่เจอ
                VStack(spacing: 8) {
                    Text("ไม่ได้อนุญาตตำแหน่ง เจ้าหน้าที่จะเห็นแค่ฐานล่าสุดที่คุณเช็คอิน")
                        .multilineTextAlignment(.center)
                    Button("ไปตั้งค่า") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .padding().background(.yellow.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 12))
            }

            TextField("บอกเจ้าหน้าที่เพิ่มได้ (ไม่บังคับ)", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await store.attachNote(note, token: token) } }

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
