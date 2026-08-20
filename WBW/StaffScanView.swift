import SwiftUI
import AVFoundation

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

    var body: some View {
        ZStack {
            Color.wbwInk.ignoresSafeArea()

            VStack(spacing: 16) {
                header
                basePicker

                // กล้องสแกน QR
                QRScannerView { code in handleScan(code) }
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.25), lineWidth: 1))
                    .overlay(alignment: .center) {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.wbwCream, lineWidth: 3)
                            .frame(width: 180, height: 180)
                    }
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
        .task { await load() }
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
                            .foregroundStyle(selected == cp.id ? Color.wbwInk : .white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(selected == cp.id ? Color.wbwCream : Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
        }
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
                    .foregroundStyle(Color.wbwInk)
                    .frame(width: 96, height: 48)
                    .background(Color.wbwCream, in: RoundedRectangle(cornerRadius: 14))
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
                    .foregroundStyle(result.alreadyCheckedIn ? Color.wbwCream : .green)
                Text(result.fullName.isEmpty ? Loc.t("role_participant") : result.fullName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.wbwInk)
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
                        .background(Color.wbwInk, in: Capsule())
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
    let onScan: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onScan = onScan
        return vc
    }
    func updateUIViewController(_ vc: ScannerVC, context: Context) {}
}

private final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    private let captureSession = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else { return }
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
