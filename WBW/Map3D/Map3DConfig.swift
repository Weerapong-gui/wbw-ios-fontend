import Foundation

/// ค่าทุกตัวที่ผูกกับไฟล์โมเดล `map.usdz` รวมไว้ที่เดียว — อ่านจาก `WBW/Resources/map_config.json`
///
/// **ทำไมต้องเป็นไฟล์ ไม่ใช่ค่าคงที่ในโค้ด:** โมเดลกับตำแหน่งแท่งแดงจะถูกเปลี่ยนใบ ก่อนหน้านี้ค่าที่
/// ต้องเปลี่ยนตามกระจายอยู่ 4 ไฟล์ — ชื่อ prim ของหมุด (`Map3DPins`), กรอบ lat/lng (`Map3DGeo`),
/// มุมหันพื้นที่งาน (`Map3DScreen.cameraFramingYaw`) และขอบเขตกล้อง (`Map3DCamera`) — ลืมที่ใดที่หนึ่ง
/// แล้วไม่มีอะไรฟ้อง อาการที่ได้คือหมุดกดไม่ติดหรือจุด GPS ไปโผล่ผิดที่ ซึ่งดูเหมือนบั๊กคนละเรื่อง
///
/// **fallback ที่ compile ไว้จำเป็น ไม่ใช่ของเผื่อ:** ถ้า JSON พิมพ์ผิดแล้วปล่อยให้ config เป็น nil
/// แท็บแผนที่จะเปิดได้ โมเดล 10 MB ขึ้นครบ แต่แตะแท่งแดงไม่มีอะไรเกิดขึ้นเลยสักอัน — ล้มแบบเงียบที่สุด
/// เท่าที่จะเป็นไปได้ · ค่าใน fallback ต้องตรงกับไฟล์ JSON เป๊ะ (Map3DConfigFileTests คุมไว้)
struct Map3DConfig: Decodable, Equatable {

    struct Camera: Decodable, Equatable {
        let defaultPitchDegrees: Float
        let minPitchDegrees: Float
        let maxPitchDegrees: Float
        let minDistance: Float
        let maxDistance: Float
        let defaultDistance: Float
        /// มุมเงยตอนกล้องบินเข้าไปจ้องหมุด — ต่ำกว่าค่าเริ่มต้นเพื่อให้เห็นฐานเป็นทรงสามมิติ
        let focusPitchDegrees: Float
        let focusDistance: Float
        /// ความเร็วหมุนวนรอบฐานหลังบินถึง องศาต่อวินาที
        let orbitDegreesPerSecond: Float
    }

    struct Sky: Decodable, Equatable {
        let domeRadius: Float
        /// ชายพื้นแนวนอนกว้างกี่เท่าของรัศมีแผนที่ — กันไม่ให้เห็นก้นแผ่นตอนกล้องอยู่สูง
        let apronSpanMultiplier: Float
    }

    struct Pin: Decodable, Equatable {
        let sequence: Int
        /// ชื่อ prim ทุกตัวที่แตะแล้วต้องนับเป็นฐานนี้ · **ตัวแรกคือแท่งหลัก** ที่กล้องจะบินไปจ้อง
        ///
        /// ต้องเป็นลิสต์ไม่ใช่ชื่อเดี่ยว เพราะโมเดล Map2.0 ปั้นเลขฐานเป็น prim `markerNum_N`
        /// ที่เป็น **พี่น้อง** ของ `marker_N` ใต้ root ไม่ใช่ลูกของมัน — ตัวไต่หาพ่อใน
        /// `Map3DScreen` ไต่จากเลขแล้วไปสุดที่ root โดยไม่เจอฐาน ผลคือคนแตะเลขที่เห็นชัด
        /// ที่สุดบนจอแล้วไม่มีอะไรเกิดขึ้นเลย
        let entityNames: [String]
    }

    let modelName: String
    /// ทิศของพื้นที่งานเทียบกับกล้อง — ไม่ใช่ทิศเหนือจริง อย่าตีความเป็น compass bearing
    let framingYawDegrees: Float
    let bounds: Map3DGeo.Bounds
    let camera: Camera
    let sky: Sky
    let pins: [Pin]

    var framingYaw: Float { framingYawDegrees * .pi / 180 }

    // MARK: - อ่านไฟล์

    /// ปฏิเสธ config ที่ decode ผ่านแต่ใช้จริงไม่ได้ ไม่ใช่แค่ที่ JSON พัง
    ///
    /// ทุกข้อในนี้คืออาการที่เคยทำให้จอพังจริงมาแล้วอย่างน้อยครั้งหนึ่ง — โดมเล็กกว่าระยะกล้อง
    /// สูงสุดคือเหตุผลที่โดมถูกใส่เข้ามาตั้งแต่แรก (ซูมออกแล้วกล้องทะลุออกนอกโดม เห็นพื้นดำ)
    static func decode(_ data: Data) -> Map3DConfig? {
        guard let config = try? JSONDecoder().decode(Map3DConfig.self, from: data) else { return nil }
        guard !config.pins.isEmpty,
              config.pins.allSatisfy({ !$0.entityNames.isEmpty }),
              Set(config.pins.flatMap(\.entityNames)).count == config.pins.flatMap(\.entityNames).count,
              config.bounds.south < config.bounds.north,
              config.bounds.west < config.bounds.east,
              config.camera.minPitchDegrees < config.camera.maxPitchDegrees,
              config.camera.minDistance < config.camera.maxDistance,
              config.sky.domeRadius > config.camera.maxDistance
        else { return nil }
        return config
    }

    private final class BundleMarker {}

    /// ต้องลอง `Bundle(for:)` ก่อน `Bundle.main` เพราะตอนรันในชุดเทส `Bundle.main` คือตัวรันเทส
    /// ไม่ใช่ตัวแอป (แพทเทิร์นเดียวกับ `TrailRoute.bundled`)
    static let bundled: Map3DConfig? = {
        for bundle in [Bundle(for: BundleMarker.self), Bundle.main] {
            if let url = bundle.url(forResource: "map_config", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let config = decode(data) {
                return config
            }
        }
        return nil
    }()

    static let current: Map3DConfig = bundled ?? fallback

    /// ค่าเดียวกับไฟล์ JSON ที่ส่งไปกับแอป — ที่มาของแต่ละตัวเลขอยู่ในไฟล์ที่เคยถือมันไว้:
    /// มุมกล้องดู `Map3DCamera` · กรอบ lat/lng ดู `Map3DGeo.eventArea` เดิม (fit แบบ Procrustes
    /// กับจุดสำรวจจริง 7 จุด) · ชื่อ prim มาจากตัวโมเดลตรง ๆ (Map2.0 ปั้นเลขฐานติดหมุดมาแล้ว
    /// ไม่ต้องเดาคู่เหมือนใบก่อน)
    static let fallback = Map3DConfig(
        modelName: "map",
        framingYawDegrees: 90,
        bounds: Map3DGeo.Bounds(south: 20.02371, west: 99.88272,
                                north: 20.06727, east: 99.92288),
        camera: Camera(defaultPitchDegrees: 68, minPitchDegrees: 34, maxPitchDegrees: 75,
                       minDistance: 0.8, maxDistance: 4.0, defaultDistance: 1.6,
                       focusPitchDegrees: 34, focusDistance: 0.55, orbitDegreesPerSecond: 8),
        sky: Sky(domeRadius: 9.0, apronSpanMultiplier: 4.0),
        pins: (1...8).map { number in
            Pin(sequence: number,
                entityNames: ["marker_\(number)", "markerNum_\(number)"])
        })
}
