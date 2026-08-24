import Foundation

/// ตรรกะของจอสแกนเจ้าหน้าที่ที่แยกออกมาจาก View เพื่อให้เทสถึง
///
/// **แยกออกมาเพราะซิมูเลเตอร์ไม่มีกล้อง** — `AVCaptureDevice.default(for: .video)` คืน nil
/// จอสแกนจึงเดินเข้าทาง "เครื่องนี้ไม่มีกล้อง" เสมอบนซิม ไม่มีทางทดสอบเส้นทางการสแกนจริงได้เลย
/// ตรรกะที่ฝังอยู่ใน View จึงเท่ากับตรรกะที่ไม่มีวันถูกทดสอบ (เหตุผลเดียวกับที่
/// `CameraPermission.from` ถูกแยกไว้ก่อนหน้านี้ ดู `StaffScanPermissionTests`)

// MARK: - ปุ่มเปิด/ปิดกล้อง

/// กล้องเปิดอยู่ไหม — จำข้ามการเปิดแอป
///
/// เจ้าหน้าที่บางฐานเช็คอินด้วยหมายเลข BIB อย่างเดียว (คิวยาว แดดจ้าจนอ่าน QR ไม่ติด
/// หรือแค่ต้องการประหยัดแบตกับความร้อนตลอดงาน) — ปิดแล้วต้องปิดค้างไว้ ไม่ใช่ต้องกดใหม่
/// ทุกครั้งที่เปิดแอป
///
/// ทรงเดียวกับ `MapMode.stored` ทุกประการ (`WBW/Map3D/MapMode.swift`) ใช้แพทเทิร์นที่ repo
/// พิสูจน์แล้ว ไม่คิดใหม่
enum ScannerPower: String {
    case on, off

    static let storageKey = "wbw.staff.scannerPower"

    var isOn: Bool { self == .on }

    func toggled() -> ScannerPower { self == .on ? .off : .on }

    /// **ค่าที่อ่านไม่ออกต้องตกมาที่ `.on` ไม่ใช่ `.off`** — ตกไปทางปิดแล้วเจ้าหน้าที่ที่เปิดแอป
    /// ครั้งแรกจะเจอแพนว่างเปล่าโดยไม่รู้ว่าต้องกดอะไร ซึ่งอ่านเหมือนจอพัง ไม่เหมือนค่าตั้งต้น
    static func stored(in defaults: UserDefaults = .standard) -> ScannerPower {
        guard let raw = defaults.string(forKey: storageKey),
              let value = ScannerPower(rawValue: raw) else { return .on }
        return value
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }
}

// MARK: - ตัวกรองช่องกรอก BIB

enum StaffBibInput {
    /// จำนวนหลักสูงสุดของหมายเลขบิบ
    static let maxDigits = 5

    /// **ต้องกรองด้วย ASCII ไม่ใช่ `Character.isNumber`**
    ///
    /// `isNumber` เป็น true กับตัวเลขทุกภาษาในยูนิโคด (ไทย อารบิก เศษส่วน ตัวยก) แต่
    /// `Int(String)` อ่านได้เฉพาะเลขอารบิกล้วน · ตัวกรองเดิมใช้ `isNumber` เลขไทยจึงผ่านเข้าไป
    /// นั่งในช่อง ปุ่มเช็คอินเปิดให้กด (เงื่อนไขคือช่องไม่ว่าง) แล้ว `Int(bib)` คืน nil ทำให้
    /// request ถูกยิงโดย**ไม่มีทั้ง `qr_token` และ `bib`** — เจ้าหน้าที่เห็นแต่ "เช็คอินไม่สำเร็จ"
    /// ลอย ๆ ทั้งที่ตัวเลขในช่องยังดูถูกต้องทุกประการ
    ///
    /// ตัดความยาว **หลัง**กรอง ไม่ใช่ก่อน ไม่งั้นตัวอักษรขยะกินโควตาหลักไปเปล่า ๆ
    static func sanitise(_ raw: String) -> String {
        String(raw.filter(\.isASCII).filter(\.isNumber).prefix(maxDigits))
    }
}

// MARK: - ตัวตัดสินว่ารับสแกนไหม

enum ScanGate {
    /// โค้ดเดิมต้องหายออกจากเฟรมนานเท่านี้ถึงจะสแกนได้อีก (วินาที)
    static let repeatWindow: TimeInterval = 2

    enum Decision: Equatable {
        /// ยิงเช็คอินได้
        case accept
        /// เมินเงียบ ๆ — ไม่ใช่ความผิดของใคร ไม่ต้องขึ้นข้อความ
        case ignore
        /// ต้องบอกผู้ใช้ว่ายังไม่ได้เลือกฐาน
        case needsBase
    }

    struct Outcome: Equatable {
        let decision: Decision
        let lastCode: String?
        let lastAt: Date?
    }

    /// คืน **ทั้งคำตัดสินและ state ใหม่**
    ///
    /// คืน state ด้วยเพราะตัวกันสแกนซ้ำที่ถูกต้องต้องขยับเวลาทุกครั้งที่ *เห็น* โค้ด ไม่ใช่เฉพาะ
    /// ตอนรับ — ของเดิมปลดล็อกด้วย timer 2 วิที่นับจากตอนเริ่มสแกน ทำให้การถือกล้องค้างไว้ที่
    /// QR เดิม (ซึ่งคือท่ายืนปกติของเจ้าหน้าที่ที่ฐาน) ยิง `POST /staff/checkin` ของคนเดิมซ้ำ
    /// ทุก ~2 วิไม่รู้จบ · พอขยับเวลาทุกครั้งที่เห็น หน้าต่างเวลาจะเริ่มนับก็ต่อเมื่อโค้ดหายไป
    /// จากเฟรมจริง ๆ
    ///
    /// ลำดับการตัดสินสำคัญ: **ไม่มีฐานชนะทุกอย่าง** เพราะมันเป็นเหตุผลเดียวที่ต้องบอกผู้ใช้
    /// เรียงไว้ทีหลังแล้วเจ้าหน้าที่จะไม่มีวันเห็นข้อความในจังหวะที่บังเอิญมี request ค้างอยู่
    static func evaluate(code: String, busy: Bool, resultOpen: Bool, hasBase: Bool,
                         lastCode: String?, lastAt: Date?, now: Date) -> Outcome {
        /// โค้ดเดิมที่ยังอยู่ในเฟรม — ขยับเวลาไว้ ไม่งั้นหน้าต่างจะหมดทั้งที่ยังส่องอยู่
        func holding() -> Outcome {
            Outcome(decision: .ignore, lastCode: lastCode,
                    lastAt: code == lastCode ? now : lastAt)
        }

        guard hasBase else {
            return Outcome(decision: .needsBase, lastCode: lastCode, lastAt: lastAt)
        }
        guard !busy, !resultOpen else { return holding() }

        if code == lastCode, let lastAt, now.timeIntervalSince(lastAt) < repeatWindow {
            return holding()
        }
        return Outcome(decision: .accept, lastCode: code, lastAt: now)
    }
}
