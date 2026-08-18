import Foundation

/// สภาพบนเส้นทางตอนนี้ — อากาศกับฝุ่น
///
/// สองครึ่งเป็นอิสระต่อกัน Open-Meteo เสิร์ฟจากคนละโฮสต์ ล่มแยกกันได้ และไม่คุ้มที่จะทิ้งอีกครึ่ง
/// เพราะอีกครึ่งพัง — ได้อากาศแต่ไม่ได้ค่าฝุ่นจึงเป็นผลลัพธ์ปกติ ไม่ใช่ error
struct TrailConditions: Codable, Equatable {
    var weather: Weather?
    var air: AirReading?

    var isEmpty: Bool { weather == nil && air == nil }
}

struct Weather: Codable, Equatable {
    let temperatureC: Int
    let feelsLikeC: Int?
    let humidityPercent: Int?
    /// รหัสสภาพอากาศ WMO 4677 ดิบ ๆ ไม่แปลง — ฝั่ง UI เป็นคนเลือกไอคอนกับคำเอง
    let code: Int
}

/// ค่าฝุ่นแบบ US EPA AQI
struct AirReading: Codable, Equatable {
    let usAqi: Int
}

/// รหัส WMO 4677 ยุบเหลือเฉพาะสภาพที่ควรวาดต่างกันจริง
///
/// มาตรฐานมีหลายสิบรหัส แยก "ฝนละอองเบา" ออกจาก "ฝนละอองปานกลาง" ด้วยไอคอน 14 pt
/// เป็นความต่างที่ไม่มีใครมองเห็น จึงตัดระดับความแรงทิ้ง เหลือแต่ชนิด · เก็บสภาพหิมะไว้ทั้งที่
/// งานเดินที่ระดับ 500 ม. ในเชียงรายไม่มีวันเจอ เพราะถ้าตัดทิ้งแล้ววันหนึ่งเอาไปใช้กับเส้นทางอื่น
/// มันจะวาดหิมะเป็นฝนแบบเงียบ ๆ
enum Sky: String, Equatable {
    case clear, mainlyClear, partlyCloudy, overcast, fog, drizzle, rain, showers, snow, thunderstorm

    static func of(code: Int) -> Sky {
        switch code {
        case 0: return .clear
        case 1: return .mainlyClear
        case 2: return .partlyCloudy
        case 3: return .overcast
        case 45, 48: return .fog
        case 51, 53, 55, 56, 57: return .drizzle
        case 61, 63, 65, 66, 67: return .rain
        case 80, 81, 82: return .showers
        case 71, 73, 75, 77, 85, 86: return .snow
        case 95, 96, 99: return .thunderstorm
        // รหัสที่ไม่รู้จักก็ยังเป็นสภาพอากาศอยู่ดี — โชว์ท้องฟ้ากลาง ๆ ไว้ ดีกว่าทั้งแถวหายไป
        // เพราะเจอตัวเลขที่ไม่ได้แมป
        default: return .overcast
        }
    }

    var symbol: String {
        switch self {
        case .clear, .mainlyClear: return "sun.max"
        case .partlyCloudy: return "cloud.sun"
        case .overcast: return "cloud"
        case .fog: return "cloud.fog"
        case .drizzle: return "cloud.drizzle"
        case .rain: return "cloud.rain"
        case .showers: return "cloud.heavyrain"
        case .snow: return "snowflake"
        case .thunderstorm: return "cloud.bolt"
        }
    }

    var label: String {
        switch self {
        case .clear: return "ท้องฟ้าโปร่ง"
        case .mainlyClear: return "ส่วนใหญ่โปร่ง"
        case .partlyCloudy: return "มีเมฆบางส่วน"
        case .overcast: return "เมฆมาก"
        case .fog: return "หมอก"
        case .drizzle: return "ฝนละออง"
        case .rain: return "ฝนตก"
        case .showers: return "ฝนซู่"
        case .snow: return "หิมะ"
        case .thunderstorm: return "พายุฝนฟ้าคะนอง"
        }
    }
}

/// ช่วงค่า AQI ตามเกณฑ์ทางการของ US EPA
///
/// ใช้ชื่อของ EPA ตรง ๆ ยกเว้นอันเดียวที่ย่อ: "Unhealthy for Sensitive Groups" ยาวเกินครึ่งจอ
/// จึงเหลือ "กลุ่มเสี่ยง" ซึ่งเก็บส่วนที่บอกว่ามันหมายถึงคุณหรือเปล่าไว้ครบ
///
/// ค่าฝุ่นไม่ใช่ของแถม — งานนี้เดินในภาคเหนือช่วงที่หมอกควันจากการเผาเป็นเหตุผลที่คนจะตัดสินใจ
/// พกหน้ากากหรือไม่ขึ้นดอย เป็นตัวเลขเดียวบนหน้า Home ที่เปลี่ยนสิ่งที่ผู้เข้าร่วมจะทำวันนี้ได้จริง
enum AqiBand: String, Equatable {
    case good, moderate, sensitiveGroups, unhealthy, veryUnhealthy, hazardous

    static func of(aqi: Int) -> AqiBand {
        switch aqi {
        case ...50: return .good
        case ...100: return .moderate
        case ...150: return .sensitiveGroups
        case ...200: return .unhealthy
        case ...300: return .veryUnhealthy
        default: return .hazardous
        }
    }

    var label: String {
        switch self {
        case .good: return "ดี"
        case .moderate: return "ปานกลาง"
        case .sensitiveGroups: return "กลุ่มเสี่ยง"
        case .unhealthy: return "มีผลต่อสุขภาพ"
        case .veryUnhealthy: return "อันตราย"
        case .hazardous: return "อันตรายมาก"
        }
    }

    /// อากาศแย่จริงเท่านั้นที่ทำให้ "คำ" เปลี่ยนสี — ไอคอนเป็นเครื่องหมายที่กวาดตาผ่าน
    /// แต่คำเป็นตัวหนังสือบนพื้นฉาก ต้องอ่านออกก่อนเป็นอันดับแรก
    var isAlarming: Bool {
        switch self {
        case .good, .moderate, .sensitiveGroups: return false
        case .unhealthy, .veryUnhealthy, .hazardous: return true
        }
    }
}
