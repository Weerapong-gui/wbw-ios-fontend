import XCTest
@testable import WBW

/// สภาพเส้นทาง (อากาศ + ฝุ่น) มาจาก Open-Meteo ซึ่งเป็นบริการข้างนอก ไม่ใช่ backend ของงาน
///
/// เทสชุดนี้จับสามอย่างที่พังแบบเงียบ: แมปรหัสอากาศผิดแล้วได้ไอคอนผิดโดยไม่มีอะไรฟ้อง,
/// เกณฑ์ AQI คลาดหนึ่งหน่วยแล้วบอกว่าอากาศ "ดี" ตอนที่ควรเตือน (ช่วงหมอกควันภาคเหนือ
/// นี่คือตัวเลขที่คนใช้ตัดสินใจว่าจะขึ้นดอยไหม), และ cache key ที่ไม่แยกตาม backend
final class TrailConditionsTests: XCTestCase {

    // MARK: - แมปรหัสสภาพอากาศ WMO 4677

    func testKnownWeatherCodes() {
        XCTAssertEqual(Sky.of(code: 0), .clear)
        XCTAssertEqual(Sky.of(code: 3), .overcast)
        XCTAssertEqual(Sky.of(code: 48), .fog)
        XCTAssertEqual(Sky.of(code: 65), .rain)
        XCTAssertEqual(Sky.of(code: 95), .thunderstorm)
    }

    func testUnknownWeatherCodeStillDraws() {
        XCTAssertEqual(Sky.of(code: 4242), .overcast,
                       "รหัสที่ไม่รู้จักก็ยังเป็นสภาพอากาศ ต้องได้ไอคอนกลาง ๆ ไม่ใช่ทำให้ทั้งแถวหาย")
    }

    func testEverySkyHasSymbolAndLabel() {
        for sky in [Sky.clear, .mainlyClear, .partlyCloudy, .overcast, .fog,
                    .drizzle, .rain, .showers, .snow, .thunderstorm] {
            XCTAssertFalse(sky.symbol.isEmpty, "\(sky) ไม่มีชื่อ SF Symbol")
            XCTAssertFalse(sky.label.isEmpty, "\(sky) ไม่มีคำไทยกำกับ — VoiceOver จะอ่านได้แค่ตัวเลข")
        }
    }

    // MARK: - เกณฑ์ AQI ของ US EPA

    func testAqiBandBoundaries() {
        XCTAssertEqual(AqiBand.of(aqi: 50), .good, "50 พอดียังอยู่ในช่วง 'ดี' ตามเกณฑ์ EPA")
        XCTAssertEqual(AqiBand.of(aqi: 51), .moderate)
        XCTAssertEqual(AqiBand.of(aqi: 100), .moderate)
        XCTAssertEqual(AqiBand.of(aqi: 101), .sensitiveGroups)
        XCTAssertEqual(AqiBand.of(aqi: 150), .sensitiveGroups)
        XCTAssertEqual(AqiBand.of(aqi: 151), .unhealthy)
        XCTAssertEqual(AqiBand.of(aqi: 200), .unhealthy)
        XCTAssertEqual(AqiBand.of(aqi: 201), .veryUnhealthy)
        XCTAssertEqual(AqiBand.of(aqi: 300), .veryUnhealthy)
        XCTAssertEqual(AqiBand.of(aqi: 301), .hazardous)
    }

    func testOnlyBadAirTurnsTheWordRed() {
        XCTAssertFalse(AqiBand.of(aqi: 120).isAlarming,
                       "'กลุ่มเสี่ยง' ยังไม่ใช่ระดับที่ต้องทำให้คำเปลี่ยนสี — ไอคอนบอกพอแล้ว")
        XCTAssertTrue(AqiBand.of(aqi: 175).isAlarming,
                      "ระดับที่มีผลต่อสุขภาพต้องเห็นชัดโดยไม่ต้องเพ่ง")
    }

    // MARK: - cache

    func testCacheKeyDiffersPerBackend() {
        let keys = [Backend.prodNode, .nodeLocal, .susLocal, .susProd, .susLan]
            .map(ConditionsStore.cacheKey(for:))
        XCTAssertEqual(Set(keys).count, 5,
                       "cache ทุกตัวในแอปต้องแยกตาม backend ตามกติกาเดียวกับ FeedbackOutbox/CheckinProgressStore")
    }

    func testCacheRoundTrip() {
        let defaults = UserDefaults(suiteName: "TrailConditionsTests.roundtrip")!
        defaults.removePersistentDomain(forName: "TrailConditionsTests.roundtrip")
        let value = TrailConditions(weather: Weather(temperatureC: 29, feelsLikeC: 33,
                                                     humidityPercent: 70, code: 2),
                                    air: AirReading(usAqi: 88))
        let at = Date(timeIntervalSince1970: 1_780_000_000)
        ConditionsStore.save(value, at: at, backend: .susProd, defaults: defaults)

        let snapshot = ConditionsStore.cached(backend: .susProd, defaults: defaults)
        XCTAssertEqual(snapshot?.value, value)
        XCTAssertEqual(snapshot?.savedAt.timeIntervalSince1970, at.timeIntervalSince1970,
                       "เวลาที่บันทึกต้องรอด round trip ไม่งั้นอายุ cache คำนวณผิดแล้วยิงซ้ำทุกครั้งที่เปิดจอ")
        XCTAssertNil(ConditionsStore.cached(backend: .susLocal, defaults: defaults),
                     "อ่านด้วย backend อื่นต้องไม่เจอ — นี่คือจุดประสงค์ทั้งหมดของการแยก namespace")
    }

    func testEmptyResultIsRecognised() {
        XCTAssertTrue(TrailConditions(weather: nil, air: nil).isEmpty)
        XCTAssertFalse(TrailConditions(weather: nil, air: AirReading(usAqi: 40)).isEmpty,
                       "ได้ค่าฝุ่นอย่างเดียวเป็นผลลัพธ์ปกติ สองโฮสต์ล่มแยกกันได้")
    }
}
