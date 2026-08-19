import SwiftUI

/// สภาพบนดอยตอนนี้: อุณหภูมิซ้าย ฝุ่นขวา
///
/// วาดลงบนพื้นฉากตรง ๆ ไม่มีการ์ด ไม่มีขอบ ไม่มีพื้นของตัวเอง — สองค่านี้เป็นข้อเท็จจริงที่เงียบ
/// ที่สุดบนหน้า Home แต่ถ้าใส่กระจกให้มันจะกลายเป็นของที่ดังที่สุดบนจอ และไปได้พื้นผิวระดับ
/// เดียวกับบัตรผู้เข้าร่วม ทั้งที่ไม่มีใครเปิดแอปมาเพื่อดูตัวเลขนี้
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
                            symbolColor: .white.opacity(0.75),
                            lead: "\(weather.temperatureC)°",
                            trail: weather.feelsLikeC.map { "รู้สึก \($0)°" },
                            trailColor: .white.opacity(0.65),
                            accessibility: sky.label)
                }
                if let air = conditions.air {
                    let band = AqiBand.of(aqi: air.usAqi)
                    reading(symbol: "aqi.medium",
                            symbolColor: band.isAlarming ? .orange : .white.opacity(0.75),
                            lead: "AQI \(air.usAqi)",
                            trail: band.label,
                            trailColor: band.isAlarming ? .orange : .white.opacity(0.65),
                            accessibility: "คุณภาพอากาศ")
                }
            }
        }
    }

    private func reading(symbol: String, symbolColor: Color, lead: String,
                         trail: String?, trailColor: Color, accessibility: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(symbolColor)
                .accessibilityLabel(accessibility)
            Text(lead)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
            if let trail {
                Text(trail)
                    .font(.caption)
                    .foregroundStyle(trailColor)
            }
        }
    }
}
