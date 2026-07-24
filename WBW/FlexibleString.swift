import Foundation

/// รับค่า id ที่ backend อาจส่งมาเป็น number (SUS int64) หรือ string (Node bigint)
/// แล้วเก็บเป็น String เสมอ
@propertyWrapper
struct FlexibleString: Codable, Equatable {
    var wrappedValue: String

    init(wrappedValue: String) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            wrappedValue = s
        } else if let i = try? c.decode(Int64.self) {
            wrappedValue = String(i)
        } else if let d = try? c.decode(Double.self) {
            wrappedValue = String(Int64(d))
        } else {
            wrappedValue = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue)
    }
}
