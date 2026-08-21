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
    @State private var result: CheckinResult?
    @State private var error: String?
    @State private var busy = false
    @State private var lastScan = ""
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
                        QRScannerView(onMissingDevice: { cameraMissing = true }) { code in handleScan(code) }
                            .overlay(alignment: .center) {
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.wbwOnBackdrop, lineWidth: 3)
                                    .frame(width: 180, height: 180)
                            }
                    } else {
                        cameraBlocked
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.25), lineWidth: 1))
                .padding(.horizontal, 20)

                // กรอก BIB สำรอง
                bibEntry

                if let error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 22)
                }

                Spacer()
            }
            .padding(.top, 8)

            // ผลลัพธ์เช็คอิน
            if let result {
                ResultCard(result: result) { self.result = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: result != nil)
        .task {
            await requestCamera()
            await load()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("scan_title")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                Text(session.user?.username ?? Loc.t("scan_role_staff"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Button { session.logout() } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
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
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(selected == cp.id ? Color.wbwForestVoid : .white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(selected == cp.id ? Color.wbwOnBackdrop : Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
        }
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
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if !cameraMissing {
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Text("scan_open_settings")
                        .font(.system(size: 15, weight: .semibold))
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
                .onChange(of: bib) { _, v in bib = String(v.filter(\.isNumber).prefix(5)) }
            Button { checkin(qr: nil, bib: Int(bib)) } label: {
                Text("scan_action_checkin")
                    .font(.system(size: 15, weight: .semibold))
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

    private func handleScan(_ code: String) {
        // กันสแกนซ้ำรัวๆ อันเดิม
        guard !busy, code != lastScan else { return }
        lastScan = code
        checkin(qr: code, bib: nil)
        // ปลดล็อกให้สแกนใหม่หลัง 2 วิ
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { lastScan = "" }
    }

    private func checkin(qr: String?, bib: Int?) {
        guard let token = session.token, let cp = selected else { return }
        error = nil
        busy = true
        Task {
            do {
                let r = try await APIClient.shared.staffCheckin(token: token, checkpointId: cp, qrToken: qr, bib: bib)
                result = r
                self.bib = ""
                // ปิดผลอัตโนมัติหลัง 3.5 วิ
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                    if result?.bib == r.bib { result = nil }
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
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.wbwForestVoid)
                if let bib = result.bib {
                    Text("BIB #\(bib)").font(.system(size: 15)).foregroundStyle(Color(white: 0.4))
                }
                Text(result.alreadyCheckedIn ? "scan_already_checked_in" : "scan_checked_in")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(result.alreadyCheckedIn ? Color(red: 0.7, green: 0.5, blue: 0.1) : .green)
                if result.hasMedicalFlag {
                    Label("scan_medical_warning", systemImage: "cross.case.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.red.opacity(0.1), in: Capsule())
                }
                Button(action: onClose) {
                    Text("scan_next")
                        .font(.system(size: 15, weight: .semibold))
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
    /// เครื่องไม่มีกล้อง (ซิมูเลเตอร์) หรือเปิด input ไม่ได้ — ต้องบอกกลับขึ้นไป
    /// ไม่ใช่ `return` เงียบแล้วปล่อยจอดำไว้เหมือนเดิม
    let onMissingDevice: () -> Void
    let onScan: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onScan = onScan
        vc.onMissingDevice = onMissingDevice
        return vc
    }
    func updateUIViewController(_ vc: ScannerVC, context: Context) {}
}

private final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var onMissingDevice: (() -> Void)?
    private let captureSession = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            DispatchQueue.main.async { [weak self] in self?.onMissingDevice?() }
            return
        }
        captureSession.addInput(input)

        let output = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning { captureSession.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let str = obj.stringValue {
            onScan?(str)
        }
    }
}
