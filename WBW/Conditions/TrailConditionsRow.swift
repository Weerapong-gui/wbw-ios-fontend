import SwiftUI

/// สภาพบนดอยตอนนี้: อุณหภูมิซ้าย ฝุ่นขวา — **ยกทรงมาจาก `TrailConditionsRow.kt` ของ Android**
///
/// วาดลงบนพื้นฉากตรง ๆ ไม่มีการ์ด ไม่มีขอบ ไม่มีพื้นของตัวเอง — สองค่านี้เป็นข้อเท็จจริงที่เงียบ
/// ที่สุดบนหน้า Home แต่ถ้าใส่กระจกให้มันจะกลายเป็นของที่ดังที่สุดบนจอ และไปได้พื้นผิวระดับ
/// เดียวกับบัตรผู้เข้าร่วม ทั้งที่ไม่มีใครเปิดแอปมาเพื่อดูตัวเลขนี้
///
/// **ไอคอนมีสี ตัวอักษรไม่มี** — นี่คือที่เดียวในแอปที่ใช้เฉดสีบอกความหมาย เพราะไอคอนคือส่วนเดียว
/// ของบรรทัดนี้ที่บอกว่า *วันแบบไหน* (คำข้าง ๆ มันเป็นตัวเลข) · พระอาทิตย์ที่เทาเท่าเมฆฝนคือ
/// พระอาทิตย์ที่ไม่ได้ทำงาน · คำท้ายพิมพ์ใหญ่ถ่างตัวอักษร ทำหน้าที่เป็นป้ายกำกับ ไม่ใช่ประโยค
///
/// **ยิงไม่ได้ = ซ่อนทั้งแถว** ไม่ใช่โชว์ "—" · ค่านี้เป็นของบริการข้างนอกชิ้นเดียวบนจอนี้
/// ขีดกลางค้างอยู่จะอ่านว่าแอปพัง ทั้งที่ของของแอปเองไม่ได้พังเลย
struct TrailConditionsRow: View {
    let conditions: TrailConditions?

    var body: some View {
        if let conditions, !conditions.isEmpty {
            HStack(spacing: 22) {
                if let weather = conditions.weather {
                    let sky = Sky.of(code: weather.code)
                    reading(symbol: sky.symbol,
                            iconTint: sky.tint,
                            lead: "\(weather.temperatureC)°",
                            trail: weather.feelsLikeC.map { String(format: String(localized: "home_weather_feels"), $0) },
                            trailTint: .wbwOnBackdropMuted,
                            accessibility: sky.label)
                }
                if let air = conditions.air {
                    let band = AqiBand.of(aqi: air.usAqi)
                    reading(symbol: "aqi.medium",
                            iconTint: band.iconTint,
                            lead: String(format: String(localized: "home_air_aqi"), air.usAqi),
                            trail: band.label,
                            trailTint: band.wordTint,
                            accessibility: String(localized: "home_air_quality"))
                }
            }
        }
    }

    private func reading(symbol: String, iconTint: Color, lead: String,
                         trail: String?, trailTint: Color, accessibility: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(iconTint)
                .accessibilityLabel(accessibility)
            Text(lead)
                .font(.wbwBodyLarge)
                .foregroundStyle(Color.wbwOnBackdrop)
            if let trail {
                Text(trail.uppercased())
                    .font(.wbwLabelMedium)
                    .kerning(1.1)
                    .foregroundStyle(trailTint)
            }
        }
    }
}
