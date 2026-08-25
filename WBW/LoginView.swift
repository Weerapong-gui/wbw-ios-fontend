import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: Session

    @State private var studentId = ""
    @State private var password = ""
    @State private var obscure = true
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        // **`Spacer()` สองตัวข้างล่างคือตัวจัดเนื้อหากลางจอ** ห่อด้วย `ScrollView` เฉย ๆ ไม่ได้
        // มันจะยุบเหลือ 0 แล้วจอที่เคยจัดกลางจะไปกองอยู่ขอบบนทุกเครื่อง — แก้จอที่ล้นบน SE
        // แล้วไปพังจอบน iPhone 17 แทน · `FitsOrScrolls` ให้เนื้อหาสูงเท่าจอพอดีตอนใส่ลง
        // (Spacer ยังทำงาน) และสูงกว่าจอเมื่อไม่ลง (เลื่อนได้) — ดู `WBW/Layout.swift`
        FitsOrScrolls {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                // คีย์นี้มีครบสองภาษามาตลอด แค่ไม่เคยถูกเรียก — แอปตั้ง development region
                // เป็น th คนไทยจึงเคยเห็นจอแรกเป็นอังกฤษ (ดู `HardcodedCopyTests`)
                Text("login_greeting")
                    .font(.wbwText(40, weight: .bold, relativeTo: .largeTitle))
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
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
                            Text("login_action_submit")
                                .font(.wbwText(16, weight: .semibold, relativeTo: .callout))
                                .foregroundStyle(Color(red: 0.23, green: 0.17, blue: 0.07))
                        }
                    }
                    // กว้างได้ถึง 260 ไม่ใช่ตายตัว 200 — คำว่า "เข้าสู่ระบบ" ที่ขนาดตัวอักษรใหญ่สุด
                    // ใส่ไม่ลง 200pt แล้วถูกตัดกลางคำ
                    .frame(maxWidth: 260, minHeight: 46)
                    .background(Color.wbwCream, in: Capsule())
                }
                .frame(maxWidth: .infinity)
                .disabled(busy)

                // **ตรงนี้เคยมีปุ่ม "ดูตัวอย่างแอป (Demo)" — ถอดออกเมื่อ 2026-08-25 ตามที่
                // เจ้าของงานสั่ง · จะใส่กลับต้องอ่านย่อหน้านี้ก่อน**
                //
                // ปุ่มนี้เกิดจาก build 1.0 (7) ที่โดน Guideline 2.1 เพราะบัญชีรีวิวที่ส่งให้ Apple
                // ล็อกอินไม่ผ่าน (prod ตอบ 401) และงานปิดรับสมัครที่ 2000/2000 ที่นั่งแล้ว สมัครใหม่
                // ไม่ได้ · ใบตีกลับของ Apple เขียนเองว่ารับ "a demonstration mode that shows all of
                // the features and functionality" แทนบัญชีได้ ปุ่มจึงถูกใส่มาเป็นทางออกนั้น
                //
                // **เงื่อนไขที่ทำให้ถอดออกได้ตอนนี้: บัญชีรีวิวใช้งานได้จริงแล้ว** — `6939999999`
                // ยิง `POST /wbw/auth/login` บน production ได้ HTTP 200 คืน role participant
                // (ยิงยืนยันอีกครั้ง 2026-08-25 ก่อนถอดปุ่ม) · **บัญชีนี้ล้มเมื่อไหร่ Guideline 2.1
                // กลับมาทันที** เพราะไม่เหลือทางให้ผู้ตรวจเข้าแอปเลยสักทาง — ทางแก้เร็วที่สุดคือ
                // เอาปุ่มนี้กลับมา (ดู git history ของไฟล์นี้)
                //
                // ตัวโหมดเดโม่เองยังอยู่ครบทั้ง `Session.startDemo()` และ `WBW/Demo/` — ที่หายไป
                // คือ *ทางเข้าที่ผู้ใช้กดได้* เท่านั้น · ทางเข้าที่เหลือคือแฟลก `-uitestDemo` ซึ่ง
                // เป็น `#if DEBUG` และเป็นตัวที่ใช้ถ่ายสกรีนช็อตทั้ง 10 ใบของ App Store

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
            .contentColumn(.form)
            .frame(maxWidth: .infinity)
        }
        // **`.ignoresSafeArea()` ถูกถอดออกจากตัวเนื้อหาโดยตั้งใจ** — นั่นคือสาเหตุจริงที่
        // คีย์บอร์ดไม่มีที่ดันบนจอเตี้ย: ฟอร์มเชื่อว่าจอยาวเลยขอบล่างลงไป จึงไม่มีอะไรต้อง
        // หลบตอนคีย์บอร์ดขึ้นมา ช่องรหัสผ่านเลยอยู่ใต้แป้นพิมพ์แบบที่เลื่อนตามไม่ได้
        // · พื้นหลังยังกินเต็มจอเหมือนเดิม เพราะ `AppBackdrop` ยิง `.ignoresSafeArea()`
        // ของตัวเองอยู่แล้ว ไม่ได้พึ่งบรรทัดนี้
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // เที่ยงวันนิ่งๆ (day 0.46) — ไม่มีแท็บบาร์ที่หน้านี้ ส่ง bottomClearance: 0 (เหมือน Welcome)
        .forestBackground(day: ForestMath.dayStill, bottomClearance: 0)
    }

    // ช่องรหัสนักศึกษา (ตัวเลขล้วน ≤10 หลัก)
    private var studentIdField: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.text.rectangle")
                .foregroundStyle(.white.opacity(0.8))
                .font(.system(size: 16))
            TextField("", text: $studentId, prompt:
                Text("login_field_username").foregroundStyle(.white.opacity(0.55)))
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
                        Text("login_field_password").foregroundStyle(.white.opacity(0.55)))
                } else {
                    TextField("", text: $password, prompt:
                        Text("login_field_password").foregroundStyle(.white.opacity(0.55)))
                }
            }
            .foregroundStyle(.white)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            // ไอคอนวาด 15pt ได้ แต่พื้นที่รับนิ้วต้องไม่ต่ำกว่า 44 (Config.Tap.minTarget) —
            // ปุ่มนี้อยู่บนจอแรกที่ผู้รีวิว App Store เห็น และเป็นปุ่มเล็กที่สุดในแอปทั้งตัว
            Button { obscure.toggle() } label: {
                Image(systemName: obscure ? "eye.slash" : "eye")
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.system(size: 15))
                    .frame(width: Config.Tap.minTarget, height: Config.Tap.minTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(obscure ? "login_show_password" : "login_hide_password")
        }
        .glassCapsule()
    }

    private func signIn() {
        error = nil
        let sid = studentId.trimmingCharacters(in: .whitespaces)
        guard !sid.isEmpty, !password.isEmpty else {
            error = Loc.t("login_missing_fields")
            return
        }
        busy = true
        Task {
            do {
                let res = try await APIClient.shared.login(studentId: sid, password: password)
                session.save(res)
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? Loc.t("error_login_failed")
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
