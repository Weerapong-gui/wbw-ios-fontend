import Foundation

/// เจ้าหน้าที่เห็นตำแหน่งของเคสนี้แบบไหน — อ่านจาก `loc_source` ที่เซิร์ฟเวอร์ส่งมากับทุกเคส
///
/// **ยกมาจากฝั่ง Android** (`ui/map/SosButton.kt` แถว `sos_location_*`) ซึ่งบอกเรื่องนี้บนจอของ
/// คนกดมาตั้งแต่แรก ส่วน iOS พูดถึงตำแหน่งเฉพาะตอน *สิทธิ์ขาด* เท่านั้น (`locationBanner`)
/// เคสที่ให้สิทธิ์แล้วแต่ยังจับพิกัดไม่ได้ทัน เซิร์ฟเวอร์จะตอบ `last_checkin` กลับมา แล้วจอเงียบสนิท
///
/// **`last_checkin` ไม่ใช่ตำแหน่ง** — มันคือฐานที่เช็คอินล่าสุด ซึ่งบนเส้นทาง 6 กม. อาจอยู่ห่าง
/// ไปหนึ่งชั่วโมงเดินแล้ว · "เรารู้ว่าคุณอยู่ไหน" กับ "เราเดาจากฐานล่าสุด" เป็นคนละคำสัญญากัน
/// และคนที่กำลังนั่งรออยู่ควรรู้ว่าตัวเองได้อันไหน
enum SOSWhere: Equatable {
    case gps
    case nearCheckpoint(String)
    case lastCheckin
    case unknown

    static func from(locSource: String?, checkpointName: String?) -> SOSWhere {
        switch locSource {
        case "gps":
            return .gps
        case "last_checkin":
            let name = checkpointName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? .lastCheckin : .nearCheckpoint(name)
        default:
            // ค่าที่ไม่รู้จัก/หายไป = เซิร์ฟเวอร์ไม่มีตำแหน่งให้เจ้าหน้าที่เลย · ตกไปทาง "รู้"
            // คือการโกหกคนที่กำลังรอว่ามีคนรู้ว่าเขาอยู่ตรงไหน
            return .unknown
        }
    }

    var textKey: String {
        switch self {
        case .gps: return "sos_status_where_gps"
        case .nearCheckpoint: return "sos_status_where_near"
        case .lastCheckin: return "sos_status_where_last_seen"
        case .unknown: return "sos_status_where_unknown"
        }
    }
}

/// การ์ด "ให้คนที่มาถึงอ่าน" — สี่แถวจากโปรไฟล์ที่แคชไว้แล้ว
///
/// **ยกมาจากฝั่ง Android** (`SosFullScreen` → `Stat`/`VitalRow`) พร้อมเหตุผลของมัน: คนที่กดค้าง
/// 3 วินาทีเพราะเจ็บ มีโอกาสสูงมากที่จะยื่นเครื่องให้เจ้าหน้าที่ เพื่อน หรือคนแปลกหน้า —
/// และของที่มีค่าบนกระจกตอนนั้นไม่ใช่บรรทัดสถานะ แต่เป็นกรุ๊ปเลือด บิบ และเบอร์ญาติ
/// ทั้งหมดอยู่ในเครื่องอยู่แล้วจากโปรไฟล์ที่โหลดไว้ จึงไม่ต้องมีสัญญาณและไม่ต้องปลดล็อกอะไรเพิ่ม
///
/// **ค่าที่ไม่มีคืน `nil` ให้จอพิมพ์ว่า "ไม่ได้ระบุ" ห้ามซ่อนแถวทิ้ง** — แถวที่หายไปทำให้การ์ด
/// ดูครบทั้งที่ไม่ครบ คนที่กวาดตาหากรุ๊ปเลือดต้องได้คำตอบว่าไม่มีในระบบ ไม่ใช่สงสัยว่ามองข้าม
///
/// เนื้อหาเท่าฝั่ง Android เป๊ะ — แพ้ยา/โรคประจำตัว/ยาที่ใช้ **ไม่อยู่ที่นี่** ถึงแม้ `/me` ของ
/// iOS จะส่งมาให้ก็ตาม ของพวกนั้นไปถึงเจ้าหน้าที่ทาง SOS feed (ดู `StaffSOSView`) ซึ่งเป็นฝั่งที่
/// เซิร์ฟเวอร์ตัดสินใจเปิดให้เห็นเอง
enum SOSVitals {

    struct Row: Equatable {
        let labelKey: String
        let value: String?
    }

    static func rows(for me: Me?) -> [Row] {
        [Row(labelKey: "sos_vitals_blood", value: trimmed(me?.bloodType)),
         Row(labelKey: "sos_vitals_contact", value: contact(me)),
         Row(labelKey: "sos_vitals_bib", value: me?.bibNumber.map(String.init)),
         Row(labelKey: "sos_vitals_group", value: me?.groupNumber.map(String.init))]
    }

    /// ชื่อกับเบอร์อยู่แถวเดียวกัน — มีอย่างใดอย่างหนึ่งก็ยังใช้ได้ · เบอร์เปล่า ๆ กดโทรได้
    /// โดยไม่ต้องรู้ว่าโทรหาใคร ส่วนชื่อเปล่า ๆ อย่างน้อยบอกว่าให้ตามหาใคร
    private static func contact(_ me: Me?) -> String? {
        let parts = [trimmed(me?.emergencyContactName), trimmed(me?.emergencyContactPhone)]
        let joined = parts.compactMap { $0 }.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    /// เบอร์ที่พร้อมยัดลง `tel://` — เบอร์จริงในฐานข้อมูลมีทั้งขีดและช่องว่าง ซึ่งทำให้
    /// `URL(string:)` คืน nil เงียบ ๆ แล้วปุ่มโทรหายไปทั้งปุ่ม (ทรงเดียวกับที่ `StaffSOSView` ทำ)
    static func dialable(_ phone: String?) -> String? {
        guard let phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : digits
    }

    private static func trimmed(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
