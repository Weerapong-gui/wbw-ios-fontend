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

                // ตรงนี้เคยมี "Forget password?" (สะกดผิดด้วย) — ถอดออกด้วยเหตุผลเดียวกับปุ่ม
                // สมัครด้านล่าง: เป็น Text เฉยๆ กดไม่ได้ ไม่มี action ซึ่ง App Review ตีกลับ
                // ด้วย Guideline 2.1
                //
                // ต่างจากปุ่มสมัครตรงที่ลิงก์ไปหน้ารีเซ็ตรหัส **ไม่** กระตุ้นข้อบังคับเรื่องลบบัญชี
                // จึงลิงก์ออกไปได้อย่างปลอดภัย — แต่ตรวจแล้วเว็บยังไม่มีหน้านั้นเลย
                // (/auth/participant/forgot-password และอีกสาม path ตอบ 404 ทั้งหมด)
                // จึงไม่มีอะไรให้ลิงก์ไป
                //
                // ใส่กลับได้เมื่อเว็บมีหน้ารีเซ็ตรหัสจริงแล้ว โดยทำเป็น Link ไม่ใช่ Text

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

                // ปุ่มโหมดตัวอย่าง — **ห้ามย้ายเข้า `#if DEBUG` และห้ามถอดออก**
                //
                // build 1.0 (7) โดน App Review ตีกลับด้วย Guideline 2.1 เพราะบัญชีเดโม่ที่ส่งให้
                // ล็อกอินไม่ผ่าน (prod ตอบ 401 ยืนยันด้วยการยิงจริงแล้ว) และงานปิดรับสมัครไปแล้วที่
                // 2000/2000 ที่นั่ง — สมัครบัญชีใหม่ไม่ได้อีก · ใบตีกลับของ Apple เขียนเองว่ารับ
                // "a demonstration mode that shows all of the features and functionality" แทนได้
                //
                // ต่างจาก `-uitest*` ทั้ง 14 ตัวตรงที่ปุ่มนี้ต้องกดได้จริงบน build ที่ส่งขึ้น store
                Button {
                    session.startDemo()
                } label: {
                    Text("ดูตัวอย่างแอป (Demo)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 200, height: 42)
                        .glassSurface(Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .disabled(busy)

                Text("เดินดูทุกหน้าจอด้วยข้อมูลตัวอย่าง ไม่ต้องมีบัญชี")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)

                // ตรงนี้เคยมี "Don't have an account? Sign up" — ถอดออกโดยตั้งใจ ห้ามใส่กลับ
                // โดยไม่อ่านเหตุผลก่อน
                //
                // ของเดิมเป็น Text เฉยๆ กดไม่ได้ ไม่มี action ซึ่ง App Review ตีกลับด้วย
                // Guideline 2.1 แน่นอน เพราะ reviewer กดทุกอย่างบนจอแล้วสมัครไม่ได้
                //
                // ทางแก้ที่ตรงไปตรงมาคือทำเป็นลิงก์ไปหน้าสมัครบนเว็บ แต่พอทำแบบนั้นแล้ว Apple
                // ถือว่าแอป "รองรับการสร้างบัญชี" ซึ่ง Guideline 5.1.1(v) บังคับให้ต้องมีทาง
                // **ลบบัญชีในแอป** ตามมาด้วย · ตอนนี้ยังไม่มีทั้งหน้าจอในแอปและ endpoint ฝั่ง
                // server เลย จึงเลือกถอดออกไปก่อนสำหรับรอบแรก
                //
                // จะใส่กลับได้ต่อเมื่อทำระบบลบบัญชีเสร็จแล้วเท่านั้น (DELETE /wbw/me + หน้ายืนยัน
                // + ตัดสินใจว่า check_in / checkin_feedback / ข้อความแชท จะถูกลบตามหรือไม่)

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
