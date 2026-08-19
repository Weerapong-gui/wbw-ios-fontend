import SwiftUI

/// รูปโปรไฟล์วงกลม — โชว์รูปจาก data-URL base64 ถ้ามี ไม่งั้น fallback ตัวอักษรแรก
struct ProfileAvatar: View {
    let name: String
    let photoUrl: String?
    var size: CGFloat = 50
    /// จอตั๋วส่ง .clear มา เพราะช่องไฟระหว่าง avatar กับรอยเว้าของการ์ดทำหน้าที่วงแหวนอยู่แล้ว
    /// วงแหวนขาวซ้อนอีกชั้นจะกลายเป็นสองวง · ค่าปริยาย = ของเดิม จุดที่เรียกอยู่ไม่ต้องแก้
    var ringColor: Color = .white.opacity(0.85)
    /// พื้นของ fallback ตัวอักษร — หน้า Home ส่งสีกลางมาแทนครีม
    ///
    /// ครีมเป็นสีแบรนด์โทนอุ่น พอไปนั่งบนภาพป่ากลางคืนที่เป็นโทนเขียว-ฟ้าเย็นแล้วมันกลายเป็น
    /// จุดที่ดังที่สุดบนจอ ทั้งที่รูปโปรไฟล์ไม่ใช่ของที่ต้องดังที่สุด · แอปนี้เหลือ accent ตัวเดียว
    /// คือทอง ครีมจึงเป็นได้แค่สีพื้นผิว/ตัวอักษร ไม่ใช่สีเน้น
    ///
    /// ค่าปริยาย = ของเดิม อีก 8 จุดที่เรียกอยู่ (ตั๋ว ตั้งค่า สมาชิกกลุ่ม แชท) ไม่ต้องแก้
    var fill: Color = .wbwCream
    var initialColor: Color = .wbwInk

    var body: some View {
        Group {
            if let img = Self.decode(photoUrl) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    fill
                    Text(initial)
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(initialColor)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(ringColor, lineWidth: 2))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private var initial: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "?" : String(t.prefix(1)).uppercased()
    }

    /// รองรับ "data:image/...;base64,XXXX" และ base64 ล้วน
    static func decode(_ s: String?) -> UIImage? {
        guard var raw = s, !raw.isEmpty else { return nil }
        if let comma = raw.range(of: ",") , raw.hasPrefix("data:") {
            raw = String(raw[comma.upperBound...])
        }
        guard let data = Data(base64Encoded: raw, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }
}
