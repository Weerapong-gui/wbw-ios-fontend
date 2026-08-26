import SwiftUI

/// จอที่ gate ยึดไว้ — ฟอร์มให้คะแนน (ปิดเองไม่ได้) + ปุ่ม SOS ที่ยังกดได้เสมอ
///
/// **ทำไมต้องมีจอนี้แทนที่จะยัด `FeedbackView` เข้า cover ตรง ๆ**: gate ยึดจอทั้งใบจนกว่าข้อมูลจะ
/// เปลี่ยน (ตอบฐาน/ตอบทั้งงาน/กดข้ามหลังส่งพัง) แปลว่าตลอดเวลานั้นผู้ใช้ไปที่แท็บบัตร — ที่เดียวที่มี
/// ปุ่ม SOS — ไม่ได้เลย · การขอความช่วยเหลือฉุกเฉินต้องไม่ถูกฟอร์มความเห็นขวางไว้ ปุ่มจึงต้องเดินทาง
/// มากับ gate เสมอ (ข้อ 2 ของสเปก ยกมาจาก Android)
///
/// **ปุ่ม SOS มีแถวของตัวเอง ไม่ลอยทับฟอร์ม** — ฝั่ง Android เคยวางลอยแล้วมันไปทับปุ่มส่ง
/// บนจอนี้การกดพลาดปุ่มเดียวมีค่าสองทางที่แย่ทั้งคู่: แจ้งเหตุปลอมให้เจ้าหน้าที่วิ่งมาหาคนที่ไม่ได้
/// เดือดร้อน หรือกดโดนปุ่มส่งทั้งที่ตั้งใจขอความช่วยเหลือจริง · ฟอร์มเลื่อนอยู่ในพื้นที่ของตัวเอง
/// ลอดใต้แถวนี้ไม่ได้
struct FeedbackGateScreen: View {
    let item: FeedbackGateItem
    @ObservedObject var sos: SOSStore
    let token: String
    /// จอสถานะ SOS ของ `MainTabView` (ตัวเดียวกับที่แท็บบัตรใช้) — ดูคอมเมนต์ที่ `.fullScreenCover`
    /// ข้างล่างว่าทำไมต้องผูก cover ซ้ำตรงนี้ทั้งที่ MainTabView ก็ผูกไว้แล้ว
    @Binding var showSOSStatus: Bool
    /// `.event` เท่านั้น: ส่งสำเร็จ หรือกด "ข้ามไปก่อน" — `.base` ไม่ใช้ (ดู `onClose` ข้างล่าง)
    let onEventDone: () -> Void

    /// คนที่เปิดตัวเลือกนี้ไว้ต้องได้ขอบจอแดงที่ **นิ่ง** ไม่ใช่เต้น (ดู `SOSPulse`)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            FeedbackView(kind: kind, blocking: true, onClose: onClose)
            sosRow
        }
        // พื้นของจอนี้เอง — `FeedbackView` ทาพื้นเฉพาะกรอบของตัวมัน แถว SOS ที่อยู่นอกกรอบนั้น
        // จะเหลือพื้นโปร่งให้เห็นจอที่อยู่ข้างหลัง cover ถ้าไม่ทาตรงนี้
        .background(Color.wbwBg.ignoresSafeArea())
        // **ขอบจอเรืองแดงตราบใดที่เคส SOS ยังเปิดอยู่ — บนจอนี้มันคือสัญญาณเดียวที่เหลือ**
        //
        // กดปุ่มค้างครบ 3 วินาทีแล้ว `SOSButton` จงใจ **ไม่**เปิดจอสถานะให้ (ดูคอมเมนต์
        // "ห้ามใส่กลับ" ที่ `SOSButton.tick`) สิ่งที่บอกว่า "ส่งไปแล้ว" มีสามอย่าง: haptic หนัก
        // หนึ่งจังหวะ · ขอบจอที่เรืองแดง · ข้อความบนปุ่มที่เปลี่ยนเป็น `sos_pass_active` —
        // แต่บนจอนี้ปุ่มเป็นทรงวงกลม (ไม่มีข้อความ) และ haptic ก็จบไปพร้อมนิ้วที่ยกขึ้น
        // ไม่มีบรรทัดนี้ = กดขอความช่วยเหลือครบแล้วจอที่ยึดหน้าจออยู่ไม่เปลี่ยนอะไรเลยสักอย่าง
        // ผู้ใช้ไม่มีทางรู้ว่าคำขอออกไปหรือยัง แล้วจะกดซ้ำ (ซึ่งสาขา `caseIsActive` จะพาไปจอสถานะ
        // แทน — ไม่ได้ยิงซ้ำ แต่ก็ไม่ใช่สิ่งที่ควรบังคับให้คนกำลังเจ็บลองเดาเอาเอง)
        //
        // **ต้องเป็น `overlay` ไม่ใช่ `background`** — พื้น `Color.wbwBg` บรรทัดบนทึบสนิท
        // อะไรที่วางเป็น background จะไปอยู่ใต้มันแล้วมองไม่เห็นเลย (กับดักเดียวกับที่
        // `ParticipantPassView` จดไว้กับ `forestBackground`) · วงไล่เฉดมีใจกลางโปร่งและ
        // `allowsHitTesting(false)` อยู่แล้ว จึงไม่บังฟอร์มและไม่แย่งแตะจากปุ่มไหน
        .overlay {
            SOSEmergencyBackdrop(pulsing: SOSPulse.pulses(status: sos.status),
                                 reduceMotion: reduceMotion)
        }
        // **จอสถานะ SOS ต้องผูกไว้ "ข้างใน" gate** — cover ที่ MainTabView ผูกไว้ present ออกมาจาก
        // controller ที่ถูก gate cover ทับอยู่แล้ว จอสถานะจึงไปโผล่ *ใต้* gate (คนที่กดขอความช่วยเหลือ
        // สำเร็จจะไม่เห็นอะไรเปลี่ยนเลย) · ผูกกับ view ที่อยู่ใน cover ชั้นแรกแบบนี้ SwiftUI ซ้อน
        // cover ต่อขึ้นไปอีกชั้นให้ได้ · binding เป็นตัวเดียวกับของ MainTabView โดยตั้งใจ: ปิดจอ
        // สถานะจากในนี้แล้วค่าที่แท็บบัตรอ่านอยู่ต้องตรงกัน ไม่ใช่ธงคนละใบที่ค้างไม่ตรงกันเงียบ ๆ
        .fullScreenCover(isPresented: $showSOSStatus) {
            SOSStatusView(store: sos, token: token)
        }
    }

    private var kind: FeedbackView.Kind {
        switch item.state {
        case .base(let base): return .base(checkpointId: base.checkpointId)
        case .event: return .event
        }
    }

    /// `.base`: ไม่ทำอะไร — ฟอร์มไม่มีปุ่มปิดอยู่แล้ว (`blocking: true`) และ gate ถอยเองเมื่อ
    /// `progress` รอบใหม่บอกว่าฐานนี้ตอบแล้ว ไม่ใช่เพราะใครสั่งปิดจอ
    private var onClose: () -> Void {
        switch item.state {
        case .base: return {}
        case .event: return onEventDone
        }
    }

    /// แถวปุ่ม SOS ชิดขวา — ทรงวงกลม 64pt ตัวเดียวกับฝั่งเจ้าหน้าที่ (ไม่ใช่แคปซูลเต็มความกว้าง
    /// แบบหน้าบัตร ซึ่งกว้างพอ ๆ กับปุ่มส่งจนอ่านเป็นปุ่มคู่กัน)
    ///
    /// `.contentColumn(.form, alignment: .trailing)` ให้ปุ่มไปชิดขอบขวาของ *คอลัมน์ฟอร์ม* บน iPad
    /// ไม่ใช่ขอบขวาของจอกว้าง ๆ ที่ห่างจากฟอร์มไปครึ่งจอ (ระยะ 16 เท่ากับที่การ์ดฟอร์มใช้)
    private var sosRow: some View {
        HStack {
            Spacer()
            SOSButton(store: sos, token: token, showStatus: $showSOSStatus)
        }
        .padding(.horizontal, 16)
        .contentColumn(.form, alignment: .trailing)
        .padding(.vertical, 12)
    }
}
