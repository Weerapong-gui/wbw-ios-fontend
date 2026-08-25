import CoreLocation
import Foundation

/// หมุดฐานบนโมเดลแผนที่ — `marker_1`…`marker_8` ที่มากับ Map2.0
///
/// ต่างจากใบก่อนตรงที่ **โมเดลบอกลำดับฐานเอง**: ชื่อ prim มีเลขอยู่ในตัว และมีเลขปั้นเป็น mesh
/// (`markerNum_N`) ให้คนเดินเห็นบนแผนที่ตรงกัน · ใบเก่าชื่อ prim เป็น `Cylinder_00N` ที่ไม่ได้
/// บอกอะไรเลย ต้องเดาคู่แล้วยืนยันด้วยสกรีนช็อต — และตอนเทียบกับใบใหม่พบว่าเดาผิด 6 จาก 8
enum Map3DPins {
    /// ชื่อ prim ทุกตัวที่ต้องติด collision ให้ — รวมทั้งแท่งและเลขที่ปั้นติดหมุด
    static var entityNames: [String] { Map3DConfig.current.pins.flatMap(\.entityNames) }

    /// ชื่อแท่งหลักของฐานนั้น (ชื่อแรกในตาราง) — กล้องต้องบินไปจ้องแท่ง ไม่ใช่เลขที่ลอยสูงกว่า
    /// ไม่งั้นเฟรมสุดท้ายของแอนิเมชันโฟกัสเป็นภาพกลางอากาศเหนือฐาน
    static func primaryEntityName(for sequence: Int) -> String? {
        Map3DConfig.current.pins.first { $0.sequence == sequence }?.entityNames.first
    }

    /// prim นี้เป็นฐานลำดับที่เท่าไร — nil = ไม่ใช่หมุด (อาคาร ถนน ต้นไม้ ฯลฯ)
    static func sequence(forEntityNamed name: String) -> Int? {
        Map3DConfig.current.pins.first { $0.entityNames.contains(name) }?.sequence
    }

    /// ข้อความบนการ์ดตอนแตะหมุด
    ///
    /// **แหล่งชื่อเปลี่ยนแล้ว (2026-08-21)** เดิมชื่อจริงมีให้เฉพาะฐานที่เช็คอินไปแล้ว เพราะ
    /// `/me/progress` คืนแค่ `checked_in` — คนที่ยังไม่ได้เดินจึงเห็น "ฐานที่ 1"…"ฐานที่ 8"
    /// ทั้งแผนที่ และแอดมินแก้ชื่อบนแดชบอร์ดแล้วแอปไม่รู้เรื่องจนกว่าจะมีคนไปเช็คอินฐานนั้น ·
    /// ตอนนี้อ่านจาก `GET /wbw/checkpoints` ซึ่งคืนทุกฐานพร้อมชื่อสองภาษา
    ///
    /// กติกา **"ห้ามเดาชื่อ"** ยังอยู่ครบ — ถอยไป "ฐานที่ N" เมื่อยังไม่เคยดึงสำเร็จและไม่มีแคช
    /// ซึ่งคือ "ไม่รู้" จริง ๆ ไม่ใช่การเดา · `checkedIn` ไม่ได้ใช้เป็นแหล่งชื่ออีกแล้วแต่ยังรับไว้
    /// เป็นทางถอยสำหรับเครื่องที่เพิ่งอัปเดตแอปแล้วยังไม่ได้ต่อเน็ตเลยสักครั้ง (แคชเก่ามีแต่ progress)
    static func label(sequence: Int, checkedIn: [CheckinProgressItem],
                      checkpoints: [Checkpoint] = []) -> String {
        if let match = checkpoints.first(where: { $0.sequence == sequence }) {
            return match.displayName
        }
        if let match = checkedIn.first(where: { $0.sequence == sequence }) {
            return match.name
        }
        return String(format: Loc.t("map_base_number"), sequence)
    }

    /// มีคนเช็คอินฐานนี้ไปแล้วกี่คน — ไม่รู้จัก/เซิร์ฟเวอร์ยังไม่ส่ง = **ศูนย์**
    ///
    /// ตัดสินแบบเดียวกับฝั่ง Android (`7211c6f`): บรรทัดที่หายไปกับบรรทัดที่บอกว่า "ยังไม่มีใคร"
    /// อ่านต่างกันมากสำหรับคนที่กำลังเลือกว่าจะแวะฐานไหนก่อน
    static func checkinCount(sequence: Int, checkpoints: [Checkpoint]) -> Int {
        checkpoints.first { $0.sequence == sequence }?.checkinCount ?? 0
    }

    /// ระยะจากคนอ่านถึงฐานนี้ (เมตร) — **nil = ไม่รู้ อย่าโชว์บรรทัดนั้นเลย**
    ///
    /// ขาดได้สองทาง: เซิร์ฟเวอร์ยังไม่ส่งพิกัดฐาน หรือผู้ใช้ยังไม่ให้สิทธิ์ตำแหน่ง · ทั้งสองทาง
    /// จบที่ "ไม่มีข้อมูล" เหมือนกัน และการโชว์ "ห่าง —" ค้างไว้อ่านเป็นแอปพัง ไม่ใช่ข้อมูลขาด
    static func distanceFromMe(sequence: Int, checkpoints: [Checkpoint],
                               me: CLLocationCoordinate2D?) -> Double? {
        guard let me,
              let base = checkpoints.first(where: { $0.sequence == sequence }),
              let lat = base.lat, let lng = base.lng
        else { return nil }
        return CLLocation(latitude: me.latitude, longitude: me.longitude)
            .distance(from: CLLocation(latitude: lat, longitude: lng))
    }

    /// ชื่อกิจกรรมของฐานนั้น — nil = ไม่มีข้อมูล (การ์ดซ่อนบรรทัดนั้นไปเลย)
    ///
    /// เดิมมีให้เฉพาะฐานที่เช็คอินแล้วด้วยเหตุผลเดียวกับชื่อฐาน
    static func activity(sequence: Int, checkedIn: [CheckinProgressItem],
                         checkpoints: [Checkpoint] = []) -> String? {
        if let match = checkpoints.first(where: { $0.sequence == sequence }) {
            return match.displayActivity
        }
        let visited = checkedIn.first { $0.sequence == sequence }
        guard let activity = visited?.activityName, !activity.isEmpty else { return nil }
        return activity
    }
}
