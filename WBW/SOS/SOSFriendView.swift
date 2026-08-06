import SwiftUI

/// สิ่งที่เพื่อนในกลุ่มเห็น
///
/// ไม่มีเบอร์โทรของคนกดอยู่บนจอนี้ — contact_phone ไม่เคยถูกเปิดให้เพื่อนเห็นในแอปนี้
/// และเหตุฉุกเฉินไม่ใช่เหตุผลที่ดีพอจะเริ่มเปิด มีแชทกลุ่มอยู่แล้ว
struct SOSFriendView: View {
    let sosId: Int64
    let token: String
    @State private var sosCase: SOSCase?
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let c = sosCase {
                    Text(c.forOther ? "เพื่อนแจ้งว่ามีคนเจ็บ" : "เพื่อนขอความช่วยเหลือ")
                        .font(.title2.bold())
                    Text(c.checkpointName.map { "ใกล้\($0)" } ?? "ไม่ทราบตำแหน่ง")
                    if let a = c.accuracyM { Text("ความแม่น ±\(Int(a)) ม.").font(.caption) }

                    // บรรทัดที่สำคัญที่สุดบนจอ — นี่คือสิ่งที่กันคน 50 คนวิ่งเข้าไปพร้อมกัน
                    // ไม่ใช่การซ่อนพิกัด
                    Text("อย่าเคลื่อนย้ายผู้บาดเจ็บ · ถ้าอยู่ใกล้ให้ไปดู 1-2 คน ที่เหลืออยู่กับที่")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if let lat = c.lat, let lng = c.lng,
                       let maps = URL(string: "maps://?ll=\(lat),\(lng)&q=จุดขอความช่วยเหลือ") {
                        // แอปเราไม่มีแผนที่ออฟไลน์ Apple Maps มี
                        Link(destination: maps) {
                            Label("เปิดในแผนที่", systemImage: "map.fill")
                        }
                    }

                    Button("เปิดแชทกลุ่ม") {
                        NotificationCenter.default.post(name: .openGroupChat, object: nil)
                    }

                    if c.resolved {
                        Label(c.resolveReason == "canceled_by_user" ? "ยกเลิกแล้ว" : "เจ้าหน้าที่ดูแลเรียบร้อยแล้ว",
                              systemImage: "flag.checkered")
                            .foregroundStyle(.secondary)
                    } else if let by = c.ackedByName {
                        Text("\(by) กำลังไปถึงแล้ว")
                    }
                } else if let loadError {
                    Text(loadError).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .padding()
        }
        .task {
            do { sosCase = try await APIClient.shared.sosCase(token: token, id: sosId) }
            catch { loadError = "โหลดข้อมูลไม่สำเร็จ ลองใหม่อีกครั้ง" }
        }
    }
}
