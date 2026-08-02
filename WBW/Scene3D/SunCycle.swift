import simd

/// สถานะแสง/ฟ้าที่เวลาหนึ่งของวัน — พอร์ตจาก SunState ใน
/// ~/su-wbw-website/components/landing/trail.ts
struct SunState {
    var elevation: Float        // องศาเหนือขอบฟ้า (ติดลบ = ยังไม่ขึ้น)
    var azimuth: Float          // องศา
    var sun: SIMD3<Float>       // สีแสงตรง 0..1
    var sunIntensity: Float
    var skyColor: SIMD3<Float>  // hemiSky ของเว็บ
    var groundColor: SIMD3<Float>
    var ambientIntensity: Float // hemiIntensity ของเว็บ
    var fog: SIMD3<Float>
    var fogDensity: Float
    var stars: Float            // 0..1 ความชัดของดาว
}

/// วงจรแสงหนึ่งวัน — 6 keyframe เดียวกับ SUN_KEYS ของเว็บ ห้ามแก้ค่าโดยไม่แก้ที่เว็บด้วย
enum SunCycle {
    private struct Key { let p: Float; let s: SunState }

    private static let keys: [Key] = [
        Key(p: 0.00, s: SunState(elevation: -8, azimuth: 104,
            sun: [0.35, 0.45, 0.72], sunIntensity: 0.18,
            skyColor: [0.13, 0.18, 0.30], groundColor: [0.05, 0.09, 0.07],
            ambientIntensity: 0.40, fog: [0.07, 0.11, 0.15], fogDensity: 0.0090, stars: 1.00)),
        Key(p: 0.18, s: SunState(elevation: 3, azimuth: 100,
            sun: [1.00, 0.55, 0.26], sunIntensity: 2.20,
            skyColor: [0.56, 0.50, 0.50], groundColor: [0.15, 0.20, 0.15],
            ambientIntensity: 0.85, fog: [0.76, 0.60, 0.45], fogDensity: 0.0072, stars: 0.22)),
        Key(p: 0.36, s: SunState(elevation: 24, azimuth: 94,
            sun: [1.00, 0.86, 0.66], sunIntensity: 2.60,
            skyColor: [0.70, 0.80, 0.92], groundColor: [0.20, 0.30, 0.22],
            ambientIntensity: 1.15, fog: [0.80, 0.83, 0.79], fogDensity: 0.0055, stars: 0.00)),
        Key(p: 0.56, s: SunState(elevation: 58, azimuth: 78,
            sun: [1.00, 0.98, 0.93], sunIntensity: 2.85,
            skyColor: [0.76, 0.86, 1.00], groundColor: [0.25, 0.35, 0.25],
            ambientIntensity: 1.35, fog: [0.85, 0.88, 0.86], fogDensity: 0.0045, stars: 0.00)),
        Key(p: 0.79, s: SunState(elevation: 25, azimuth: 58,
            sun: [1.00, 0.86, 0.60], sunIntensity: 2.50,
            skyColor: [0.72, 0.78, 0.86], groundColor: [0.22, 0.30, 0.22],
            ambientIntensity: 1.05, fog: [0.86, 0.80, 0.70], fogDensity: 0.0055, stars: 0.00)),
        Key(p: 1.00, s: SunState(elevation: 2, azimuth: 48,
            sun: [1.00, 0.46, 0.20], sunIntensity: 2.00,
            skyColor: [0.50, 0.40, 0.43], groundColor: [0.14, 0.16, 0.14],
            ambientIntensity: 0.72, fog: [0.73, 0.50, 0.38], fogDensity: 0.00725, stars: 0.18)),
    ]

    /// interpolate ระหว่าง keyframe ด้วย smoothstep — เปลี่ยนช่วงนุ่ม ไม่หักมุม
    static func state(at p: Float) -> SunState {
        let q = min(max(p, 0), 1)
        var i = 0
        while i < keys.count - 2 && q > keys[i + 1].p { i += 1 }
        let a = keys[i], b = keys[i + 1]
        let span = b.p - a.p
        let t = min(max(span > 0 ? (q - a.p) / span : 0, 0), 1)
        let s = t * t * (3 - 2 * t)

        func f(_ x: Float, _ y: Float) -> Float { x + (y - x) * s }
        func v(_ x: SIMD3<Float>, _ y: SIMD3<Float>) -> SIMD3<Float> { x + (y - x) * s }

        return SunState(
            elevation: f(a.s.elevation, b.s.elevation),
            azimuth: f(a.s.azimuth, b.s.azimuth),
            sun: v(a.s.sun, b.s.sun),
            sunIntensity: f(a.s.sunIntensity, b.s.sunIntensity),
            skyColor: v(a.s.skyColor, b.s.skyColor),
            groundColor: v(a.s.groundColor, b.s.groundColor),
            ambientIntensity: f(a.s.ambientIntensity, b.s.ambientIntensity),
            fog: v(a.s.fog, b.s.fog),
            fogDensity: f(a.s.fogDensity, b.s.fogDensity),
            stars: f(a.s.stars, b.s.stars))
    }

    /// ทิศดวงอาทิตย์เป็นเวกเตอร์หนึ่งหน่วย (Y ขึ้น เหมือนเว็บ)
    static func direction(_ s: SunState) -> SIMD3<Float> {
        let e = s.elevation * .pi / 180
        let a = s.azimuth * .pi / 180
        return SIMD3<Float>(cos(e) * sin(a), sin(e), -cos(e) * cos(a))
    }
}
