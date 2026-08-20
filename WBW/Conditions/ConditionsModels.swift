import SwiftUI
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

    /// สีของไอคอน — **ที่เดียวในแอปที่ใช้เฉดสีเพื่อบอกความหมาย** และข้อยกเว้นนี้แคบโดยตั้งใจ
    /// (ยกตารางมาจาก `Sky` ใน `TrailConditionsRow.kt` ของ Android)
    ///
    /// "โปร่ง" กับ "ส่วนใหญ่โปร่ง" ใช้สีเดียวกัน — ความต่างของสองอย่างนี้ไม่ใช่สิ่งที่เฉดสีขนาด 17pt
    /// แบกได้ ฝืนแยกจะได้แค่เหลืองสองเฉดที่เกือบเหมือนกัน
    var tint: Color {
        switch self {
        case .clear, .mainlyClear, .partlyCloudy: return .skySunTint
        case .overcast: return .skyCloudTint
        case .fog: return .skyFogTint
        case .drizzle, .rain, .showers: return .skyRainTint
        case .snow: return .skySnowTint
        case .thunderstorm: return .skyStormTint
        }
    }

    /// ชื่อสภาพอากาศ — ผ่านชุดคีย์ร่วมกับ Android (`weather_*` ใน `strings.xml`)
    ///
    /// อ่านออกเสียงให้ VoiceOver เท่านั้น ไม่ได้ขึ้นจอ — ไอคอนเป็นตัวแทนบนจอ · แต่ต้องแปล
    /// เพราะ VoiceOver อ่านด้วยเสียงภาษาที่ผู้ใช้ตั้งไว้ คำไทยในโหมดอังกฤษจะออกมาเป็นเสียงมั่ว
    var label: String {
        switch self {
        case .clear: return Loc.t("weather_clear")
        case .mainlyClear: return Loc.t("weather_mainly_clear")
        case .partlyCloudy: return Loc.t("weather_partly_cloudy")
        case .overcast: return Loc.t("weather_overcast")
        case .fog: return Loc.t("weather_fog")
        case .drizzle: return Loc.t("weather_drizzle")
        case .rain: return Loc.t("weather_rain")
        case .showers: return Loc.t("weather_showers")
        case .snow: return Loc.t("weather_snow")
        case .thunderstorm: return Loc.t("weather_thunderstorm")
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
        case .good: return Loc.t("aqi_good")
        case .moderate: return Loc.t("aqi_moderate")
        case .sensitiveGroups: return Loc.t("aqi_sensitive")
        case .unhealthy: return Loc.t("aqi_unhealthy")
        case .veryUnhealthy: return Loc.t("aqi_very_unhealthy")
        case .hazardous: return Loc.t("aqi_hazardous")
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

    /// สีของไอคอน — ไล่ เขียว-เหลือง-แดง ตามที่คนคุ้นจากทุกแอปอากาศ แต่ที่ความอิ่มสีของ palette นี้
    var iconTint: Color {
        switch self {
        case .good: return .airGoodTint
        case .moderate: return .airModerateTint
        case .sensitiveGroups: return .airSensitiveTint
        case .unhealthy, .veryUnhealthy, .hazardous: return .airUnhealthyTint
        }
    }

    /// สีของ **คำ** ซึ่งไต่ระดับช้ากว่าไอคอนมาก — ไอคอนคือเครื่องหมายที่กวาดตามอง
    /// ส่วนคำคือตัวอักษรบนภาพถ่าย ต้องอ่านออกก่อนเป็นอันดับแรก
    ///
    /// ใช้ `airUnhealthyTint` ไม่ใช่ `wbwDanger` เพราะบรรทัดนี้นั่งบนภาพพื้นหลัง — `wbwDanger`
    /// พลิกเป็นแดงเข้มในโหมดสว่าง แต่พื้นใต้มันเป็นภาพมืดใบเดิมทั้งสองธีม
    var wordTint: Color {
        switch self {
        case .good, .moderate: return .wbwOnBackdropMuted
        case .sensitiveGroups: return .wbwOnBackdrop
        case .unhealthy, .veryUnhealthy, .hazardous: return .airUnhealthyTint
        }
    }
}
