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
    @Environment(\.dismiss) private var dismiss

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
                        // จอนี้เป็น .sheet ที่คลุมทับ ZStack ทั้งก้อนของ MainTabView อยู่ (รวม
                        // GroupChatView overlay ด้วย) โพสต์อย่างเดียวไม่ปิดชีตเอง แชทที่เพิ่งสั่งเปิด
                        // จะขึ้นอยู่ใต้ชีตนี้เงียบๆ ผู้ใช้แตะแล้วไม่เห็นอะไรเกิดขึ้นเลย ต้องปัดชีตทิ้งเอง
                        // อีกทีโดยไม่มีอะไรบอกให้ทำแบบนั้น (พบจากรีวิว Task 16 — ปุ่มนี้มาจากบรีฟตรงๆ
                        // แต่ไม่มีของแทนให้เห็นว่าเกิดอะไรขึ้น เหมือนปัญหา "ดูกดได้แต่กดไม่ได้" ที่เคยพบใน
                        // หน้า login แต่กลับทิศ: ตัวนี้กดได้จริงแต่ดูเหมือนไม่มีอะไรเกิดขึ้น)
                        //
                        // โพสต์ก่อนเรียก dismiss() เสมอ ไม่ใช่กลับกัน — NotificationCenter ไม่มี
                        // scheduler คั่นระหว่างทาง MainTabView.onReceive(.openGroupChat) จึงทำงานแบบ
                        // sync ในตา post() นี้เอง (ทรงเดียวกับที่ทั้งไฟล์นี้พึ่งอยู่แล้วตอน cold-launch
                        // replay ผ่าน PendingPush) ตั้ง chatOpen = true เสร็จสมบูรณ์ก่อน dismiss() จะเริ่ม
                        // ด้วยซ้ำ แชทจึงพร้อมอยู่ข้างใต้ตั้งแต่ก่อนชีตนี้จะเริ่มเลื่อนหาย ไม่ใช่ตั้งค่าไล่หลัง
                        // ชีตที่ปิดไปแล้ว — ไม่มีจังหวะที่ชีตปิดจบแล้วเห็นพื้นหลังว่างเปล่าเป็นเสี้ยววินาที
                        NotificationCenter.default.post(name: .openGroupChat, object: nil)
                        dismiss()
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
