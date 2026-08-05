import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: Session

    @State private var studentId = ""
    @State private var password = ""
    @State private var obscure = true
    @State private var busy = false
    @State private var error: String?

    var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Text("Hey,\nWelcome back")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 2)

                Spacer().frame(height: 28)

                studentIdField
                Spacer().frame(height: 14)
                passwordField

                HStack {
                    Spacer()
                    Text("Forget password?")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .padding(.top, 8)

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.top, 10)
                }

                Spacer().frame(height: 26)

                Button(action: signIn) {
                    Group {
                        if busy {
                            ProgressView().tint(.wbwInk)
                        } else {
                            Text("Sign In")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(red: 0.23, green: 0.17, blue: 0.07))
                        }
                    }
                    .frame(width: 200, height: 46)
                    .background(Color.wbwCream, in: Capsule())
                }
                .frame(maxWidth: .infinity)
                .disabled(busy)

                HStack(spacing: 4) {
                    Text("Don't have an account?")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Sign up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)

                Spacer()
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // เที่ยงวันนิ่งๆ (day 0.46) — ไม่มีแท็บบาร์ที่หน้านี้ ส่ง bottomClearance: 0 (เหมือน Welcome)
            .forestBackground(day: ForestMath.dayStill, bottomClearance: 0)
            .ignoresSafeArea()
    }

    // ช่องรหัสนักศึกษา (ตัวเลขล้วน ≤10 หลัก)
    private var studentIdField: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.text.rectangle")
                .foregroundStyle(.white.opacity(0.8))
                .font(.system(size: 16))
            TextField("", text: $studentId, prompt:
                Text("รหัสนักศึกษา หรือ ชื่อผู้ใช้").foregroundStyle(.white.opacity(0.55)))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: studentId) { _, v in
                    // รับทั้งรหัสนักศึกษาและชื่อผู้ใช้ (เจ้าหน้าที่) — แอปเดียวแตกตาม role
                    studentId = String(v.prefix(40))
                }
        }
        .glassCapsule()
    }

    private var passwordField: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .foregroundStyle(.white.opacity(0.8))
                .font(.system(size: 16))
            Group {
                if obscure {
                    SecureField("", text: $password, prompt:
                        Text("Password").foregroundStyle(.white.opacity(0.55)))
                } else {
                    TextField("", text: $password, prompt:
                        Text("Password").foregroundStyle(.white.opacity(0.55)))
                }
            }
            .foregroundStyle(.white)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            Button { obscure.toggle() } label: {
                Image(systemName: obscure ? "eye.slash" : "eye")
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.system(size: 15))
            }
        }
        .glassCapsule()
    }

    private func signIn() {
        error = nil
        let sid = studentId.trimmingCharacters(in: .whitespaces)
        guard !sid.isEmpty, !password.isEmpty else {
            error = "กรุณากรอกรหัสนักศึกษาและรหัสผ่าน"
            return
        }
        busy = true
        Task {
            do {
                let res = try await APIClient.shared.login(studentId: sid, password: password)
                session.save(res)
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? "เข้าสู่ระบบไม่สำเร็จ"
            }
            busy = false
        }
    }
}

/// modifier: ช่องกระจกฝ้าทรงแคปซูล
private extension View {
    func glassCapsule() -> some View {
        self
            .padding(.horizontal, 18)
            .frame(height: 50)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
    }
}
