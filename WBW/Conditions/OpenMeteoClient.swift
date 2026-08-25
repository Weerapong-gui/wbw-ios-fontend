import Foundation

/// ยิงถาม Open-Meteo — บริการสาธารณะ ไม่มี API key ไม่ต้องแตะ backend ของงาน
///
/// **พิกัดที่ถามคือเส้นทาง ไม่ใช่โทรศัพท์** ไม่ขอสิทธิ์ตำแหน่งและไม่ใช้เลย ด้วยสองเหตุผล:
/// ผู้เข้าร่วมอยากรู้ว่าวันเดินจะเป็นยังไง ซึ่งเป็นข้อเท็จจริงของดอย ไม่ใช่ของที่ที่เขานั่งอ่านอยู่
/// (คืนก่อนงานคือคนละจังหวัด) และหน้า Home คือจอแรกหลังล็อกอิน ซึ่งเป็นจังหวะที่แย่ที่สุด
/// ที่จะเด้ง dialog ขอสิทธิ์เพื่อของประดับ
enum OpenMeteoClient {
    /// กลางเส้นทางที่ bake ไว้ (`route_wbw.json`) — MFU เชียงราย · เขียนตรง ๆ แทนที่จะคำนวณจาก
    /// `TrailRoute` ตอนรัน เพราะเส้นทางยาวราว 5 กม. อยู่ในเซลล์เดียวกันของโมเดลพยากรณ์อยู่แล้ว
    /// จุดไหนบนเส้นก็ได้คำตอบเดียวกัน
    static let latitude = 20.0466
    static let longitude = 99.9014

    /// ยิงสองเส้นพร้อมกัน — คนละโฮสต์ ไม่มีลำดับก่อนหลัง เรียงกันจะกลายเป็นสอง round trip ซ้อน
    static func fetch(session: URLSession = .shared) async -> TrailConditions {
        async let weather = weather(session: session)
        async let air = airQuality(session: session)
        return await TrailConditions(weather: weather, air: air)
    }

    // MARK: - ตัวถอดรหัสตอบกลับ

    private struct WeatherResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double?
            let apparent_temperature: Double?
            let relative_humidity_2m: Int?
            let weather_code: Int?
        }
        let current: Current?
    }

    private struct AirResponse: Decodable {
        struct Current: Decodable { let us_aqi: Double? }
        let current: Current?
    }

    // MARK: - เส้นทางยิง

    private static func weather(session: URLSession) async -> Weather? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = commonItems + [
            URLQueryItem(name: "current",
                         value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code"),
        ]
        guard let body: WeatherResponse = await get(c, session: session),
              // อุณหภูมิเป็นช่องเดียวที่ขาดแล้ววาดแถวไม่ได้
              let temperature = body.current?.temperature_2m
        else { return nil }
        return Weather(temperatureC: Int(temperature.rounded()),
                       feelsLikeC: body.current?.apparent_temperature.map { Int($0.rounded()) },
                       humidityPercent: body.current?.relative_humidity_2m,
                       code: body.current?.weather_code ?? 0)
    }

    private static func airQuality(session: URLSession) async -> AirReading? {
        var c = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        c.queryItems = commonItems + [URLQueryItem(name: "current", value: "us_aqi")]
        guard let body: AirResponse = await get(c, session: session),
              let aqi = body.current?.us_aqi
        else { return nil }
        return AirReading(usAqi: Int(aqi.rounded()))
    }

    private static var commonItems: [URLQueryItem] {
        [URLQueryItem(name: "latitude", value: String(latitude)),
         URLQueryItem(name: "longitude", value: String(longitude)),
         URLQueryItem(name: "timezone", value: "Asia/Bangkok")]
    }

    /// พังยังไงก็คืน nil เงียบ ๆ — นี่เป็นของชิ้นเดียวบนหน้า Home ที่ไม่ใช่ข้อมูลของแอปเอง
    /// บริการข้างนอกล่มต้องไม่กลายเป็นข้อความ error บนจอแรกของผู้เข้าร่วม แถวหายไปเฉย ๆ ก็พอ
    private static func get<T: Decodable>(_ components: URLComponents,
                                          session: URLSession) async -> T? {
        guard let url = components.url else { return nil }
        var req = URLRequest(url: url)
        // 8 วินาที — เท่ากับฝั่ง Android · ยาวกว่านี้แถวจะค้างว่างอยู่นานเกินไปบนสัญญาณแย่
        req.timeoutInterval = 8
        guard let (data, response) = try? await session.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
