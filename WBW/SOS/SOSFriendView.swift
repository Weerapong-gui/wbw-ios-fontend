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
                    Text(c.forOther ? "sos_friend_title_other" : "sos_friend_title_self")
                        .font(.title2.bold())
                    Text(c.checkpointName.map { Loc.t("sos_friend_near", $0) }
                         ?? Loc.t("sos_friend_location_unknown"))
                    if let a = c.accuracyM {
                        Text(Loc.t("sos_accuracy_meters", Int(a))).font(.caption)
                    }

                    // บรรทัดที่สำคัญที่สุดบนจอ — นี่คือสิ่งที่กันคน 50 คนวิ่งเข้าไปพร้อมกัน
                    // ไม่ใช่การซ่อนพิกัด
                    Text("sos_friend_advice")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if let lat = c.lat, let lng = c.lng,
                       let maps = SOSMapLink.appleMaps(lat: lat, lng: lng) {
                        // แอปเราไม่มีแผนที่ออฟไลน์ Apple Maps มี
                        Link(destination: maps) {
                            Label("sos_map_open", systemImage: "map.fill")
                        }
                    }

                    Button("sos_friend_open_chat") {
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
                        Label(c.resolveReason == "canceled_by_user" ? "sos_case_canceled" : "sos_case_resolved",
                              systemImage: "flag.checkered")
                            .foregroundStyle(.secondary)
                    } else if let by = c.ackedByName {
                        Text(Loc.t("sos_friend_on_the_way", by))
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
            catch { loadError = Loc.t("sos_friend_load_failed") }
        }
    }
}
