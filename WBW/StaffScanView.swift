import SwiftUI
import AVFoundation
import UIKit

/// สิทธิ์กล้องแปลเป็นสิ่งที่จอต้องทำ
///
/// แยกออกมาเป็นฟังก์ชันบริสุทธิ์เพราะ `AVAuthorizationStatus` จริงตั้งค่าในเทสไม่ได้ —
/// สิ่งที่ต้องพิสูจน์คือ "สถานะไหนแปลว่าอะไร" ไม่ใช่ตัว AVFoundation (ดู `StaffScanPermissionTests`)
enum CameraPermission: Equatable {
    /// เปิดกล้องได้เลย
    case ready
    /// ยังไม่เคยถาม — ต้องยิงกล่องขอสิทธิ์ของระบบก่อน
    case ask
    /// ถูกปฏิเสธ หรือถูกล็อกด้วย MDM/Screen Time — ผู้ใช้เปิดเองในแอปไม่ได้
    case denied

    /// **สถานะที่ไม่รู้จักต้องตกมาที่ `.denied`** ไม่ใช่ `.ready` — เดาเป็น ready แล้วจะกลับไป
    /// เป็นจอดำเงียบแบบเดิมที่ไม่มีอะไรบอกผู้ใช้เลย
    static func from(_ status: AVAuthorizationStatus) -> CameraPermission {
        switch status {
        case .authorized:    return .ready
        case .notDetermined: return .ask
        case .denied, .restricted: return .denied
        @unknown default:    return .denied
        }
    }
}

/// หน้าเจ้าหน้าที่ประจำฐาน — เลือกฐาน + สแกน QR / กรอก BIB เพื่อเช็คอินผู้เข้าร่วม
struct StaffScanView: View {
    @EnvironmentObject var session: Session
    @State private var checkpoints: [StaffCheckpoint] = []
    @State private var selected: Int?
    @State private var bib = ""
    /// ผลลัพธ์ที่กำลังโชว์ — ห่อด้วย id ของตัวเอง **ไม่ใช่ `CheckinResult` เปล่า ๆ**
    ///
    /// timer ปิดการ์ดอัตโนมัติเคยเทียบด้วย `result?.bib == r.bib` ซึ่ง `bib` เป็น `Int?` —
    /// ผู้เข้าร่วมสองคนที่ยังไม่มีบิบเทียบกันได้ `nil == nil` = true · timer ของคนก่อนหน้า
    /// จึงปิดการ์ดของคนถัดไปทิ้งก่อนเวลา รวมถึงป้ายแดง "มีข้อมูลการแพทย์" ที่แพงที่สุดบนการ์ด
    @State private var shown: ShownResult?

    private struct ShownResult: Identifiable {
        let id = UUID()
        let value: CheckinResult
    }
    @State private var error: String?
    @State private var busy = false
    /// โค้ดล่าสุดที่เห็น + เวลาที่เห็นครั้งล่าสุด — ตัวกันสแกนซ้ำ (ดู `ScanGate.evaluate`)
    /// **ขยับเวลาทุกครั้งที่เห็น ไม่ใช่เฉพาะตอนรับ** ไม่งั้นถือกล้องค้างไว้แล้วยิงซ้ำไม่รู้จบ
    @State private var lastCode: String?
    @State private var lastAt: Date?
    /// ปุ่มเปิด/ปิดกล้อง — อ่านค่าที่จำไว้ตอนสร้าง state ไม่ใช่ใน `onAppear`
    /// (เหตุผลเดียวกับ `MapMode.initialForLaunch` — ของที่แขวนบน view ที่ยังไม่ถูกสร้างจะถูกกลืนเงียบ)
    @State private var power: ScannerPower = .stored()
    /// ระบบยึดกล้องไปอยู่ตอนนี้ไหม (สายเข้า แอปอื่นแย่ง Split View บน iPad)
    @State private var interrupted = false
    /// เริ่มที่ `.ask` ไม่ใช่ `.ready` — ยังไม่ได้ถามระบบ จะเปิดกล้องเลยไม่ได้
    @State private var camera: CameraPermission = .ask
    /// ซิมูเลเตอร์กับเครื่องที่ไม่มีกล้องจะได้สิทธิ์ผ่าน แต่ `AVCaptureDevice.default` คืน nil
    /// ต้องมีข้อความบอกเหมือนกัน ไม่งั้นก็ได้จอดำเงียบอยู่ดี
    @State private var cameraMissing = false

    var body: some View {
        ZStack {
            // **พื้นตายตัว ไม่ใช่ `wbwInk`** — `wbwInk` พลิกเป็น #E9EEE0 ในโหมดมืด (ค่าปริยาย
            // ของแอป) ทั้งจอนี้เขียนตัวอักษรเป็น `.white` ตายตัวตั้งแต่ยุคที่ ink ยังมืดเสมอ
            // ผลคือขาวบนขาวทั้งจอ ใช้งานไม่ได้เลย (ถ่ายเจอจริง 2026-08-21)
            // จอเจ้าหน้าที่เป็นเครื่องมือกลางแดด กลางคืน — มืดตายตัวคือสิ่งที่ต้องการอยู่แล้ว
            Color.wbwForestVoid.ignoresSafeArea()

            // วัดพื้นที่จริงเพื่อคิดขนาดแพนกล้อง — ไม่ใช้ `UIScreen` (ทั้ง repo ไม่มีสักจุด)
            // และค่าคงที่ต่อรุ่นก็ผิดทันทีบน iPad หรือหน้าต่างที่ถูกย่อ
            GeometryReader { geo in
            let paneHeight = min(max(geo.size.height * 0.38, 200), 340)

            VStack(spacing: 16) {
                header
                basePicker

                // กล้องสแกน QR — โผล่เฉพาะตอนได้สิทธิ์จริงและเครื่องมีกล้อง
                // ไม่งั้นโชว์คำอธิบายแทน (เดิมได้สี่เหลี่ยมดำค้างถาวรโดยไม่มีอะไรบอก)
                Group {
                    if camera == .ask && !cameraMissing {
                        // ระหว่างที่กล่องขอสิทธิ์ของระบบเปิดค้างอยู่ ยังไม่รู้คำตอบ — โชว์พื้นเปล่า
                        // ไม่ใช่ข้อความ "ไม่ได้รับสิทธิ์" ที่จะโผล่อยู่หลังกล่องแล้วอ่านว่าโดนปฏิเสธไปแล้ว
                        Color.white.opacity(0.06)
                    } else if camera == .ready && !cameraMissing {
                        // **`.opacity` ไม่ใช่ `if`** — สลับกิ่งใน `Group` ทำให้ SwiftUI ทิ้ง
                        // `ScannerVC` แล้วสร้างใหม่ทุกครั้งที่กดปุ่ม ซึ่งช้ากว่าและเสียจุดประสงค์
                        // ของการ "หยุดชั่วคราว" ไป · ให้ VC อยู่ตัวเดิมแล้วสั่งหยุด/เริ่มผ่าน `isOn`
                        QRScannerView(isOn: power.isOn && !interrupted,
                                      onMissingDevice: { cameraMissing = true },
                                      onInterrupted: { interrupted = $0 },
                                      onScan: { handleScan($0) })
                            .opacity(power.isOn && !interrupted ? 1 : 0)
                            .overlay(alignment: .center) {
                                if power.isOn && !interrupted {
                                    // กรอบเล็งคิดจากขนาดแพน ไม่ใช่ 180 ตายตัว — แพนหดแล้วกรอบ
                                    // เท่าเดิมจะเกือบเต็มแพน อ่านเป็นขอบของแพนไม่ใช่กรอบเล็ง
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.wbwOnBackdrop, lineWidth: 3)
                                        .frame(width: paneHeight * 0.6, height: paneHeight * 0.6)
                                }
                            }
                            .background(Color.white.opacity(0.06))
                            .overlay { if interrupted { cameraTaken } else if !power.isOn { cameraOff } }
                            .overlay(alignment: .topTrailing) { powerToggle }
                    } else {
                        cameraBlocked
                    }
                }
                .frame(maxWidth: .infinity)
                // สูงตามสัดส่วนพื้นที่จริง ไม่ใช่ 300pt ตายตัว — บน iPhone SE (สูง 667) ค่าเดิม
                // กินเกือบครึ่งจอ จนหัวจอ ตัวเลือกฐาน ช่องกรอกบิบ และข้อความ error เบียดกันจนล้น
                // · เพดาน 340 กันไม่ให้กลายเป็นช่องมองยักษ์บน iPad
                .frame(height: paneHeight)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.25), lineWidth: 1))
                .padding(.horizontal, 20)

                // กรอก BIB สำรอง
                bibEntry

                if let error {
                    Text(error)
                        .font(.wbwText(13, relativeTo: .footnote))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 22)
                }

                Spacer()
            }
            .padding(.top, 8)
            .contentColumn(.card)
            }
            // **ล็อกเพดานขนาดตัวอักษรที่จอนี้จอเดียว** — เป็นเครื่องมือของเจ้าหน้าที่ล้วน
            // ผู้เข้าร่วมไม่มีทางเห็น และที่ขนาดใหญ่สุด หัวจอ+ตัวเลือกฐาน+ช่องกรอกบิบ จะกิน
            // ที่จนช่องมองกล้องเหลือนิดเดียว ซึ่งทำให้เครื่องมือใช้งานไม่ได้จริงกลางแดด
            // · อย่าลบเพดานนี้โดยไม่หาทางอื่นให้ช่องมองก่อน
            // ผลลัพธ์เช็คอิน — **อยู่ในกรอบเดียวกับเนื้อหา ไม่ใช่พี่น้องของ `GeometryReader`**
            // ของเดิมเป็นพี่น้องของ ZStack ชั้นนอก จึงหลุดทั้งเพดานขนาดตัวอักษรข้างล่างและ
            // `.contentColumn(.card)` — ที่ AX5 ปุ่ม "สแกนคนถัดไป" ถูกดันตกขอบจอ และบน iPad
            // การ์ดกางเต็มความกว้างหน้าต่างแทนที่จะเป็นคอลัมน์เหมือนทุกจอ
            .overlay {
                if let shown {
                    ResultCard(result: shown.value) { self.shown = nil }
                        .contentColumn(.card)
                        .transition(.opacity)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .animation(.easeInOut(duration: 0.2), value: shown?.id)
        .task {
            await requestCamera()
            await load()
        }
        // เปิดกล้องใหม่หลังเคยพลาด — `cameraMissing` เคย latch เป็น true ตลอดกาล ความล้มเหลว
        // ชั่วคราวครั้งเดียว (กล้องถูกแอปอื่นจับอยู่ตอนนั้น) จึงเปลี่ยนจอเป็น "เครื่องนี้ไม่มีกล้อง"
        // ถาวรจนกว่าจะปิดแอป ทั้งที่กล้องว่างแล้ว
        .onChange(of: power) { _, on in
            if on.isOn { cameraMissing = false }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("scan_title")
                    .font(.wbwText(22, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(.white)
                Text(session.user?.username ?? Loc.t("scan_role_staff"))
                    .font(.wbwText(13, relativeTo: .footnote))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Button { session.logout() } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: Config.Tap.minTarget, height: Config.Tap.minTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("action_logout")
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    private var basePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(checkpoints) { cp in
                    Button { selected = cp.id } label: {
                        Text(cp.name)
                            .font(.wbwText(13, weight: .semibold, relativeTo: .footnote))
                            .foregroundStyle(selected == cp.id ? Color.wbwForestVoid : .white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(selected == cp.id ? Color.wbwOnBackdrop : Color.white.opacity(0.12), in: Capsule())
                            // ชิปวาดสูง ~32pt ตามดีไซน์ ขยายเฉพาะพื้นที่รับนิ้ว กราฟิกคงเดิม
                            .frame(minHeight: Config.Tap.minTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
        }
    }

    /// ปุ่มเปิด/ปิดกล้อง มุมขวาบนของแพน
    ///
    /// **ไม่โผล่ตอนไม่มีสิทธิ์** — ปุ่มที่กดแล้วไม่มีอะไรเกิดขึ้นแย่กว่าไม่มีปุ่ม
    /// (กิ่งนี้ถูกวาดเฉพาะตอน `camera == .ready` อยู่แล้ว แต่เขียนไว้ให้ชัดว่าตั้งใจ)
    private var powerToggle: some View {
        Button {
            let next = power.toggled()
            next.store()
            power = next
        } label: {
            Image(systemName: power.isOn ? "video.fill" : "video.slash.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: Config.Tap.minTarget, height: Config.Tap.minTarget)
                .glassSurface(Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .padding(10)
        .accessibilityLabel(Loc.t(power.isOn ? "scan_camera_turn_off" : "scan_camera_turn_on"))
    }

    /// แพนตอนเจ้าหน้าที่ปิดกล้องเอง — ว่าง ๆ กับปุ่มเปิดตรงกลาง
    ///
    /// ต่างจาก `cameraBlocked` ตรงที่นี่ไม่ใช่ปัญหา เป็นสิ่งที่เจ้าหน้าที่เลือกเอง ข้อความจึงบอก
    /// ทางกลับ ไม่ใช่บอกเหตุผลว่าทำไมถึงใช้ไม่ได้
    private var cameraOff: some View {
        VStack(spacing: 14) {
            Button {
                ScannerPower.on.store()
                power = .on
            } label: {
                Label("scan_camera_turn_on", systemImage: "video.fill")
                    .font(.wbwText(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.wbwForestVoid)
                    .frame(minWidth: 180, minHeight: Config.Tap.minTarget)
                    .background(Color.wbwOnBackdrop, in: Capsule())
            }
            .buttonStyle(.plain)
            Text("scan_camera_off_hint")
                .font(.wbwText(13, relativeTo: .footnote))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06))
    }

    /// แพนตอนระบบยึดกล้องไป — สายเข้า แอปอื่นแย่ง หรือ Split View บน iPad
    ///
    /// **ไม่มีปุ่มให้กด** เพราะเจ้าหน้าที่ทำอะไรกับมันไม่ได้จริง ๆ นอกจากรอหรือเลิกแบ่งจอ ·
    /// สิ่งที่ต้องมีคือคำอธิบายแทนจอดำเงียบ ๆ ที่อ่านเหมือนแอปค้าง
    private var cameraTaken: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.55))
            Text("scan_camera_interrupted")
                .font(.wbwText(14, relativeTo: .subheadline))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06))
    }

    /// จอแทนกล้องตอนไม่มีสิทธิ์ — ต้องบอกว่าทำไม และพาไปเปิดได้จริง
    ///
    /// ช่องกรอก BIB ข้างล่างยังใช้ได้ตามปกติ เจ้าหน้าที่จึงเช็คอินต่อได้แม้กล้องเปิดไม่ได้
    private var cameraBlocked: some View {
        VStack(spacing: 14) {
            Image(systemName: cameraMissing ? "camera.metering.unknown" : "camera.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.55))
            Text(cameraMissing ? "scan_camera_missing" : "scan_camera_denied")
                .font(.wbwText(14, relativeTo: .subheadline))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if !cameraMissing {
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Text("scan_open_settings")
                        .font(.wbwText(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Color.wbwForestVoid)
                        .frame(minWidth: 160, minHeight: Config.Tap.minTarget)
                        .background(Color.wbwOnBackdrop, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06))
    }

    /// ถามระบบครั้งเดียวตอนจอขึ้น · `.notDetermined` เท่านั้นที่ยิงกล่องขอสิทธิ์
    private func requestCamera() async {
        #if DEBUG
        // บังคับสถานะถูกปฏิเสธไว้ถ่ายภาพยืนยัน — ซิมูเลเตอร์ตั้งสถานะนี้จากภายนอกไม่ได้
        // (`simctl privacy revoke` รีเซ็ตเป็น "ยังไม่เคยถาม" ไม่ใช่ "ปฏิเสธ") และจอนี้อยู่หลัง
        // บัญชีเจ้าหน้าที่ซึ่งโหมดเดโม่ไม่ครอบ · ทรงเดียวกับ `-uitestCredits` ที่หน้าตั้งค่า
        if UserDefaults.standard.bool(forKey: "uitestCameraDenied") {
            camera = .denied
            return
        }
        #endif
        let current = CameraPermission.from(AVCaptureDevice.authorizationStatus(for: .video))
        guard current == .ask else {
            camera = current
            return
        }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        camera = granted ? .ready : .denied
    }

    private var bibEntry: some View {
        HStack(spacing: 10) {
            TextField("", text: $bib, prompt: Text("scan_bib_placeholder").foregroundStyle(.white.opacity(0.5)))
                .keyboardType(.numberPad)
                .foregroundStyle(.white)
                .padding(.horizontal, 16).frame(height: 48)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.2), lineWidth: 1))
                // กรองผ่าน `StaffBibInput` ไม่ใช่ `v.filter(\.isNumber)` — ตัวหลังปล่อยเลขไทย
                // ผ่านเข้ามาแล้ว `Int()` อ่านไม่ได้ (ดูเหตุผลเต็มที่ `StaffBibInput.sanitise`)
                .onChange(of: bib) { _, v in bib = StaffBibInput.sanitise(v) }
                .disabled(busy)
            Button { checkin(qr: nil, bib: Int(bib)) } label: {
                Text("scan_action_checkin")
                    .font(.wbwText(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.wbwForestVoid)
                    .frame(width: 96, height: 48)
                    .background(Color.wbwOnBackdrop, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(busy || bib.isEmpty || selected == nil)
        }
        .padding(.horizontal, 20)

        // ข้อผิดพลาด (แสดงใต้ช่อง)
    }

    private func load() async {
        guard let token = session.token else { return }
        do {
            checkpoints = try await APIClient.shared.staffCheckpoints(token: token)
            if selected == nil { selected = checkpoints.first?.id }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription
        }
    }

    /// ทุกเฟรมที่กล้องอ่าน QR ได้จะวิ่งเข้ามาที่นี่ — ถี่มาก ตรรกะทั้งหมดอยู่ที่ `ScanGate`
    /// ซึ่งเทสได้โดยไม่ต้องมีกล้อง (ดู `StaffScanGateTests`)
    private func handleScan(_ code: String) {
        let out = ScanGate.evaluate(code: code, busy: busy, resultOpen: shown != nil,
                                    hasBase: selected != nil,
                                    lastCode: lastCode, lastAt: lastAt, now: Date())
        lastCode = out.lastCode
        lastAt = out.lastAt

        switch out.decision {
        case .ignore:
            return
        case .needsBase:
            // **เดิมเงียบสนิท** — เจ้าหน้าที่ส่องบัตรทีละใบแล้วไม่มีอะไรเกิดขึ้นเลย
            // สรุปว่ากล้องอ่านไม่ออก ทั้งที่ปัญหาคือยังไม่มีรายชื่อฐานให้เลือก
            error = Loc.t("scan_pick_base_first")
        case .accept:
            checkin(qr: code, bib: nil)
        }
    }

    private func checkin(qr: String?, bib: Int?) {
        guard let cp = selected else {
            error = Loc.t("scan_pick_base_first")
            return
        }
        guard let token = session.token else { return }
        error = nil
        busy = true
        Task {
            do {
                let r = try await APIClient.shared.staffCheckin(token: token, checkpointId: cp, qrToken: qr, bib: bib)
                let card = ShownResult(value: r)
                shown = card
                self.bib = ""
                // ปิดผลอัตโนมัติหลัง 3.5 วิ — เทียบด้วย **id ของการ์ดใบนี้** ไม่ใช่ `bib`
                // ซึ่งเป็น `Int?` และเท่ากันได้ระหว่างคนละคนที่ยังไม่มีบิบ (`nil == nil`)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                    if shown?.id == card.id { shown = nil }
                }
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? Loc.t("error_checkin_failed")
            }
            busy = false
        }
    }
}

/// การ์ดผลลัพธ์เช็คอิน
private struct ResultCard: View {
    let result: CheckinResult
    let onClose: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: result.alreadyCheckedIn ? "checkmark.circle" : "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(result.alreadyCheckedIn ? Color.wbwOnBackdropMuted : .green)
                Text(result.fullName.isEmpty ? Loc.t("role_participant") : result.fullName)
                    .font(.wbwText(22, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(Color.wbwForestVoid)
                if let bib = result.bib {
                    Text("BIB #\(bib)").font(.wbwText(15, relativeTo: .subheadline)).foregroundStyle(Color(white: 0.4))
                }
                Text(result.alreadyCheckedIn ? "scan_already_checked_in" : "scan_checked_in")
                    .font(.wbwText(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(result.alreadyCheckedIn ? Color(red: 0.7, green: 0.5, blue: 0.1) : .green)
                if result.hasMedicalFlag {
                    Label("scan_medical_warning", systemImage: "cross.case.fill")
                        .font(.wbwText(13, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.red.opacity(0.1), in: Capsule())
                }
                Button(action: onClose) {
                    Text("scan_next")
                        .font(.wbwText(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(Color.wbwForestVoid, in: Capsule())
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 26))
            .padding(20)
        }
        .background(Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: onClose))
    }
}

/// กล้องสแกน QR (AVFoundation)
private struct QRScannerView: UIViewControllerRepresentable {
    /// กล้องควรวิ่งอยู่ไหม — ผูกกับปุ่มเปิด/ปิดของจอ
    ///
    /// **นี่คือช่องทางเดียวที่ SwiftUI สั่งกล้องได้** ของเดิม `updateUIViewController` ว่างเปล่า
    /// จึงไม่มีทางบอกอะไรกับ `ScannerVC` ที่สร้างไปแล้วเลย
    let isOn: Bool
    /// เครื่องไม่มีกล้อง (ซิมูเลเตอร์) หรือเปิด input ไม่ได้ — ต้องบอกกลับขึ้นไป
    /// ไม่ใช่ `return` เงียบแล้วปล่อยจอดำไว้เหมือนเดิม
    let onMissingDevice: () -> Void
    /// ระบบยึดกล้องไป (สายเข้า แอปอื่นแย่ง หรือ Split View บน iPad) — จอต้องบอก ไม่ใช่ปล่อยดำ
    let onInterrupted: (Bool) -> Void
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onScan = onScan
        vc.onMissingDevice = onMissingDevice
        vc.onInterrupted = onInterrupted
        vc.setRunning(isOn)
        return vc
    }

    /// **ที่ว่างตรงนี้คือบั๊กเดิม** — ของเดิมเป็น `{}` เปล่า ๆ กล้องจึงถูกสั่งได้ครั้งเดียว
    /// ตอนสร้าง แล้วไม่มีใครสั่งอะไรมันได้อีกเลยตลอดอายุจอ
    func updateUIViewController(_ vc: ScannerVC, context: Context) {
        // callback ต้องถูกเซ็ตใหม่ทุกรอบ ไม่ใช่แค่ตอนสร้าง — closure ที่จับไว้ตอน body รอบแรก
        // จะค้างอยู่กับ VC ตลอดชีวิตมัน ซึ่งวันนี้ยังทำงานถูกเพราะมันอ่าน `@State` ผ่านกล่อง
        // ของ SwiftUI ไม่ใช่ค่าที่ก๊อปมา แต่เป็นกับดักที่รอคนมา refactor
        vc.onScan = onScan
        vc.onMissingDevice = onMissingDevice
        vc.onInterrupted = onInterrupted
        vc.setRunning(isOn)
    }
}

private final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var onMissingDevice: (() -> Void)?
    var onInterrupted: ((Bool) -> Void)?

    private let captureSession = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var output: AVCaptureMetadataOutput?
    /// จอ *อยาก* ให้กล้องวิ่งไหม — แยกจาก "กล้องวิ่งอยู่จริงไหม" เพราะสองอย่างนี้ต่างกันได้
    /// ตอนจอถูกซ่อน (อยากวิ่ง แต่ต้องหยุดเพื่อประหยัดแบต) แล้วต้องกลับมาวิ่งเองตอนจอโผล่อีก
    private var wantsRunning = false
    /// เปิด input/output/preview ไปแล้วหรือยัง — ทำครั้งเดียวตอนต้องใช้จริงครั้งแรก
    private var isConfigured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // ระบบยึดกล้องไปแล้วคืนให้ — ไม่มีตัวรับสองอันนี้ ช่องมองจะดำเงียบโดยไม่มีอะไรบอก
        // · เพิ่งกลายเป็นเรื่องจริงตอนเปิด iPad: Split View ทำให้กล้องถูกยึดด้วยเหตุ
        // `videoDeviceNotAvailableWithMultipleForegroundApps` ซึ่งไม่คืนเองทุกกรณี
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(sessionInterrupted),
                           name: AVCaptureSession.wasInterruptedNotification, object: captureSession)
        center.addObserver(self, selector: #selector(sessionInterruptionEnded),
                           name: AVCaptureSession.interruptionEndedNotification, object: captureSession)

        applyRunning()
    }

    /// เปิดกล้องจริงครั้งแรกที่ *ต้องใช้* ไม่ใช่ตอนสร้างจอ
    ///
    /// **หน่วงไว้โดยตั้งใจ** — เจ้าหน้าที่ที่ปิดกล้องไว้ไม่ควรมี `AVCaptureDeviceInput` ถูกเปิด
    /// ค้างไว้เลยสักครั้ง นั่นคือจุดประสงค์ทั้งหมดของปุ่ม (แบตกับความร้อนตลอดวันงาน) ·
    /// ผลพลอยได้: "เครื่องนี้ไม่มีกล้อง" จะไม่ถูกประกาศตอนที่ผู้ใช้แค่ปิดกล้องเอง
    /// ซึ่งเป็นคนละเรื่องกันคนละอย่าง
    ///
    /// คืน `false` เมื่อเปิดไม่ได้จริง — ผู้เรียกเป็นคนบอกจอ
    @discardableResult
    private func configureIfNeeded() -> Bool {
        guard !isConfigured else { return true }
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else { return false }

        captureSession.addInput(input)

        let output = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            self.output = output
        }

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer

        isConfigured = true
        applyRegionOfInterest()
        return true
    }

    /// **จอโผล่กลับมาต้องเริ่มกล้องเอง** — ของเดิมมีแต่ `viewWillDisappear` ที่สั่งหยุด
    /// ไม่มีใครสั่งเริ่ม เจ้าหน้าที่สลับไปแท็บ SOS (หรือโดนจอเคสใหม่ทับ ซึ่งเป็นสถานการณ์ที่
    /// ออกแบบไว้ตั้งใจ) แล้วกลับมา จะได้ช่องมองดำถาวรจนกว่าจะปิดแอปเปิดใหม่
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
        applyRegionOfInterest()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// สั่งจากข้างนอก (ปุ่มเปิด/ปิด) — จำความตั้งใจไว้ด้วย ไม่ใช่สั่งครั้งเดียวแล้วลืม
    func setRunning(_ on: Bool) {
        wantsRunning = on
        applyRunning()
    }

    private func applyRunning() {
        guard wantsRunning, isViewLoaded else { return stop() }
        guard configureIfNeeded() else {
            DispatchQueue.main.async { [weak self] in self?.onMissingDevice?() }
            return
        }
        guard !captureSession.isRunning else { return }
        // `startRunning()` บล็อก thread ที่เรียก — ห้ามอยู่บนเมนเธรด
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, self.wantsRunning else { return }
            self.captureSession.startRunning()
        }
    }

    private func stop() {
        guard captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    /// **กรอบเล็งต้องเป็นของจริง ไม่ใช่ของประดับ**
    ///
    /// ของเดิมวาดกรอบไว้กลางแพนแต่ไม่เคยตั้ง `rectOfInterest` เลย กล้องจึงอ่านทั้งเฟรม —
    /// คนที่ยืนต่อคิวข้างหลังแล้วถือบัตรของตัวเองอยู่ อาจถูกเช็คอินแทนคนที่เจ้าหน้าที่เล็งอยู่
    /// โดยที่การ์ดผลขึ้นชื่อคนนั้นจริง ๆ และไม่มีอะไรให้สงสัยเลย
    ///
    /// ต้องตั้งใน `viewDidLayoutSubviews` เพราะค่ามันอิงกับ bounds ของเลเยอร์ที่เพิ่งได้ขนาดจริง
    private func applyRegionOfInterest() {
        guard let preview, let output, view.bounds.width > 0, view.bounds.height > 0 else { return }
        // ด้านละ 60% ของด้านที่สั้นกว่า จัดกลาง — ตรงกับกรอบที่ SwiftUI วาดทับอยู่
        let side = min(view.bounds.width, view.bounds.height) * 0.6
        let box = CGRect(x: view.bounds.midX - side / 2, y: view.bounds.midY - side / 2,
                         width: side, height: side)
        output.rectOfInterest = preview.metadataOutputRectConverted(fromLayerRect: box)
    }

    @objc private func sessionInterrupted() {
        DispatchQueue.main.async { [weak self] in self?.onInterrupted?(true) }
    }

    @objc private func sessionInterruptionEnded() {
        DispatchQueue.main.async { [weak self] in
            self?.onInterrupted?(false)
            self?.applyRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let str = obj.stringValue {
            onScan?(str)
        }
    }
}
