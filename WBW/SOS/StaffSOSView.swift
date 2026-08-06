import SwiftUI

// SOSStaffCase ย้ายไปนิยามใน WBW/APIClient+SOS.swift แล้ว (Task 10) — staffSOSFeed
// คืนค่าเป็นชนิดนี้ตรงๆ จึงต้องมีอยู่ก่อนไฟล์นั้นจะคอมไพล์ผ่าน ไม่ต้องประกาศซ้ำที่นี่
// (field/computed property ทั้งหมด: fullName, isCoarse, accuracyLabel, positionLabel
// อยู่ที่นิยามจริงใน Task 10 ไม่ใช่ที่นี่)

/// รายการเคสของเจ้าหน้าที่ · long-poll ตอนจอเปิด พึ่ง push ตอนจอปิด
///
/// start()/stop() ผูกกับ "เป็นเจ้าหน้าที่อยู่ไหม" (ดู RootView) ไม่ใช่ผูกกับว่าแท็บ SOS เปิดอยู่
/// หรือเปล่า — เคสใหม่ต้องทับจอได้แม้เจ้าหน้าที่กำลังก้มสแกน QR อยู่แท็บอื่น (ดูคอมเมนต์ที่ newCase
/// ด้านล่าง) ถ้า poll หยุดตอนออกจากแท็บนี้ ก็ไม่มีทางรู้เลยว่ามีเคสใหม่เข้ามาจนกว่าจะสลับกลับมาเอง
@MainActor
final class StaffSOSStore: ObservableObject {
    @Published private(set) var cases: [SOSStaffCase] = []

    /// badge บนแท็บ = งานที่ยังเหลือ ไม่ใช่จำนวนแถวบนจอ
    var openCount: Int { cases.filter { !$0.resolved }.count }

    /// เคสที่เพิ่งเห็นเป็นครั้งแรก (ยังไม่ resolved) หลัง baseline — RootView ผูก .fullScreenCover(item:)
    /// กับตัวนี้ตรงๆ ผ่าน $store.newCase เพื่อทับทั้งจอทันทีที่มีเคสใหม่เข้า ไม่ใช่แค่ badge มุมจอ
    /// (สเปก: เจ้าหน้าที่กำลังก้มมองคิว QR อยู่ ตัวเลขมุมจอไม่มีทางถูกเห็น) ปิดอะไรอื่นไม่ได้นอกจาก
    /// ตัวแปรนี้เอง — ไม่แตะ cases เลย เคสยังอยู่ในลิสต์ตามปกติหลังปิดจอทับ (ดู StaffSOSAlertView)
    ///
    /// ไม่ใช่ private(set): .fullScreenCover(item: $store.newCase) ต้องการ Binding ที่เขียนได้
    /// (SwiftUI ตั้งกลับเป็น nil เองตอนปิดจอทับ ผ่าน dismiss() ในสภาพแวดล้อมของจอที่เปิดมา)
    @Published var newCase: SOSStaffCase?

    /// เคส id ที่เคยเห็นแล้ว (ไม่ว่าจะ resolved หรือไม่ก็ตาม) — ใช้แยก "เพิ่งเข้ามาใหม่" ออกจาก
    /// "แค่แถวเดิมถูกอัปเดต" (เช่น มีคนกดรับเรื่อง) เพราะ apply() รวมสองเหตุการณ์นี้เข้าด้วยกันเป็น
    /// การเขียนทับ dictionary แบบเดียวกันหมด แยกไม่ออกจากกันเองถ้าไม่จำ id ที่เคยเห็นไว้ต่างหาก
    private var seenIDs: Set<Int64> = []

    /// cursor เป็นคู่ "<updated_at>|<id>" ไม่ใช่ updated_at เดี่ยวๆ — updated_at ไม่ unique สองเคสที่มี
    /// เวลาเท่ากันเป๊ะจะทำให้ตัวหนึ่งหายจากทุกรอบถัดไปถาวรถ้าตัด id ทิ้ง (ดูคอมเมนต์ที่ apply())
    /// private(set) แทนที่จะ private ล้วน เพื่อให้เทสยืนยันรูปแบบคู่นี้ได้ตรงๆ ไม่ใช่แค่เดาจากผลข้างเคียง
    private(set) var cursor: String?

    private var loop: Task<Void, Never>?
    private let feedCall: (String, String?) async throws -> [SOSStaffCase]
    /// ช่วงพักระหว่างรอบ poll — ฉีดได้เพื่อให้เทส round-trip ของ cursor ไม่ต้องรอ 1 วินาทีจริงต่อรอบ
    /// (ทรงเดียวกับ pollInterval ของ SOSStore) ค่าเริ่มต้น 1 วิเท่าของเดิมทุกประการสำหรับผู้เรียกจริง
    private let pollInterval: Duration

    init(feedCall: @escaping (String, String?) async throws -> [SOSStaffCase]
         = { token, since in try await APIClient.shared.staffSOSFeed(token: token, since: since, wait: 25) },
         pollInterval: Duration = .seconds(1)) {
        self.feedCall = feedCall
        self.pollInterval = pollInterval
    }

    /// รวมของใหม่เข้ากับของเดิมด้วย id · ใหม่สุดอยู่บน
    /// เคสที่ปิดแล้วยังอยู่ในลิสต์ (เซิร์ฟเวอร์ส่งย้อนหลัง 30 นาที) — หายไปเฉยๆ
    /// แยกไม่ออกจาก "โหลดไม่ขึ้น" ซึ่งเป็นคนละเรื่องกันโดยสิ้นเชิง
    func apply(_ incoming: [SOSStaffCase]) {
        // จับไว้ก่อนแก้ seenIDs — apply() ครั้งแรกที่ store เห็นข้อมูลเลยคือ "baseline" ของเจ้าหน้าที่
        // คนนี้ ไม่ใช่ "เคสเพิ่งเข้ามา" ในสายตาเขา (ดูคอมเมนต์ที่ newCase ว่าทำไมต้องแยกสองเรื่องนี้)
        let isBaseline = seenIDs.isEmpty
        let freshlyArrived = incoming.filter { !seenIDs.contains($0.id) && !$0.resolved }
        for c in incoming { seenIDs.insert(c.id) }

        var byID = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })
        for c in incoming { byID[c.id] = c }
        cases = byID.values.sorted {
            ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id)
        }
        // cursor เป็นคู่ "<updated_at>|<id>" — updated_at เดี่ยวๆ ไม่ unique
        // สองเคสที่มีเวลาเท่ากันเป๊ะจะทำให้ตัวหนึ่งหายจากทุกรอบถัดไปถาวร
        if let newest = cases.first { cursor = "\(newest.updatedAt)|\(newest.id)" }

        guard !isBaseline,
              let alert = freshlyArrived.max(by: { ($0.updatedAt, $0.id) < ($1.updatedAt, $1.id) })
        else { return }
        newCase = alert
    }

    func start(token: String) {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let batch = try? await self.feedCall(token, self.cursor) {
                    self.apply(batch)
                }
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    func stop() { loop?.cancel() }

    func ack(id: Int64, token: String) async {
        _ = try? await APIClient.shared.ackSOS(token: token, id: id)
    }

    func resolve(id: Int64, reason: String, token: String) async {
        _ = try? await APIClient.shared.resolveSOS(token: token, id: id, reason: reason)
    }
}

/// การ์ดเคสหนึ่งใบ — ใช้ทั้งในลิสต์ปกติ (StaffSOSView) และในจอทับเต็มจอตอนเคสใหม่เข้า (StaffSOSAlertView)
///
/// ข้อมูลสุขภาพ (healthNotes/bloodType) โชว์เฉพาะตอนเซิร์ฟเวอร์ส่งมาให้เท่านั้น — เซิร์ฟเวอร์เองเป็นคน
/// คุมเงื่อนไข (ยินยอมแล้ว + เคสยังเปิด + ไม่ใช่เคสที่แจ้งแทนคนอื่น) จอนี้ไม่เพิ่มเงื่อนไขซ้ำ และไม่โชว์
/// placeholder ตอนไม่มีข้อมูล (เช่น "ไม่มีข้อมูลสุขภาพ") เพราะแยกไม่ออกจาก "เซิร์ฟเวอร์ไม่ให้สิทธิ์" กับ
/// "มีสิทธิ์แต่ไม่มีข้อมูลกรอกไว้จริงๆ" — `if let` เฉยๆ คือพอ
struct StaffSOSCard: View {
    let c: SOSStaffCase
    let token: String
    @ObservedObject var store: StaffSOSStore
    @State private var showReasons = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if c.forOther {
                Label("คนอื่นเจ็บ — ไม่ทราบประวัติผู้บาดเจ็บ", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text(c.fullName).font(.title3.bold())
            Text("BIB \(c.bib.map(String.init) ?? "-") · กลุ่ม \(c.groupNumber.map(String.init) ?? "-")")
                .foregroundStyle(.secondary)

            Text(c.checkpointName.map { "ใกล้\($0)" } ?? "ไม่ทราบฐาน")
            Text("\(c.positionLabel) · \(c.accuracyLabel)")
                .font(.caption)
                .foregroundStyle(c.isCoarse ? .orange : .secondary)
            if c.isCoarse {
                Text("พิกัดหยาบ อย่าเชื่อฐานที่ระบบเดา")
                    .font(.caption).foregroundStyle(.orange)
            }

            if let notes = c.healthNotes, !notes.isEmpty {
                Text(notes).font(.callout).padding(8)
                    .background(.red.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if let blood = c.bloodType { Text("กรุ๊ปเลือด \(blood)").font(.callout) }
            if let m = c.message { Text("\u{201c}\(m)\u{201d}").italic() }

            HStack {
                if let phone = c.contactPhone {
                    Link(destination: URL(string: "tel://\(phone)")!) {
                        Label("โทรหาผู้แจ้ง", systemImage: "phone.fill")
                    }
                }
                if let lat = c.lat, let lng = c.lng,
                   let maps = URL(string: "maps://?ll=\(lat),\(lng)&q=จุดขอความช่วยเหลือ") {
                    Link(destination: maps) { Label("เปิดแผนที่", systemImage: "map.fill") }
                }
            }

            if c.resolved {
                Label("ปิดแล้ว", systemImage: "flag.checkered").foregroundStyle(.secondary)
            } else if let by = c.ackedByName {
                // เคสถูกรับไปแล้วโดยใครสักคน (อาจเป็นเจ้าหน้าที่คนอื่นที่กดก่อน) — โชว์ชื่อคนรับแทนปุ่ม
                // "กำลังไป" เสมอ ไม่ใช่แค่ตอนที่เรากดเอง จุดนี้เองที่กันเคสถูก ack ซ้ำสอง: พอ ackedByName
                // ไม่ใช่ nil ปุ่มด้านล่างก็หายไปแล้ว ไม่มีทาง POST ack ซ้ำจาก UI นี้ได้อีก
                Text("\(by) กำลังไป")
            } else {
                Button("กำลังไป") { Task { await store.ack(id: c.id, token: token) } }
                    .buttonStyle(.borderedProminent)
            }

            if !c.resolved {
                Button("ปิดเคส") { showReasons = true }
                    .confirmationDialog("ปิดเคสเพราะ", isPresented: $showReasons) {
                        Button("ช่วยแล้ว") { Task { await store.resolve(id: c.id, reason: "helped", token: token) } }
                        Button("แจ้งเท็จ") { Task { await store.resolve(id: c.id, reason: "false_alarm", token: token) } }
                        Button("ติดต่อไม่ได้") { Task { await store.resolve(id: c.id, reason: "unreachable", token: token) } }
                        Button("ยกเลิก", role: .cancel) {}
                    }
            }
        }
        .padding()
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// จอเจ้าหน้าที่: รายการเคส SOS ทั้งหมด — แท็บที่สองข้างแท็บสแกน QR (ดู RootView)
/// long-poll ขับเคลื่อนจาก RootView ไม่ใช่จากจอนี้เอง (ไม่มี onAppear/onDisappear เรียก
/// store.start()/stop() ที่นี่) — ดูคอมเมนต์ยาวที่ StaffSOSStore ด้านบนว่าทำไม
struct StaffSOSView: View {
    @ObservedObject var store: StaffSOSStore
    let token: String

    var body: some View {
        ZStack {
            Color.wbwInk.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if store.cases.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.cases) { c in
                                StaffSOSCard(c: c, token: token, store: store)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("เคสฉุกเฉิน")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                Text(store.openCount > 0 ? "ค้างอยู่ \(store.openCount) เคส" : "ไม่มีเคสค้าง")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.35))
            Text("ยังไม่มีเคสฉุกเฉิน")
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

/// เคสใหม่เข้าตอนกำลังก้มสแกน QR — badge มุมจอไม่มีทางถูกเห็น ต้องทับทั้งจอทันที (ดูคอมเมนต์ที่
/// StaffSOSStore.newCase และที่ RootView)
///
/// ปิดได้เสมอโดยไม่เสียเคสทิ้ง — ปิด (dismiss()) แค่ทำให้ store.newCase กลับเป็น nil เท่านั้น
/// ไม่แตะ store.cases เลย เคสยังอยู่ในแท็บ SOS ตามปกติทุกประการหลังปิดจอนี้ (สองตัวแปรคนละตัวกัน
/// โดยสิ้นเชิง) — มีสองทางออกให้กด (ปุ่ม X มุมขวาบน กับปุ่มด้านล่าง) กัน "หาทางปิดไม่เจอ" ตอนตกใจ
struct StaffSOSAlertView: View {
    let c: SOSStaffCase
    let token: String
    @ObservedObject var store: StaffSOSStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.wbwInk.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("มีเหตุฉุกเฉินใหม่", systemImage: "sos")
                        .font(.title2.bold())
                        .foregroundStyle(.red)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                ScrollView {
                    StaffSOSCard(c: c, token: token, store: store)
                }

                Button("ดูรายการเคสทั้งหมด") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
    }
}
