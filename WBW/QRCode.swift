import UIKit
import CoreImage.CIFilterBuiltins

/// สร้าง QR จาก token (แพทเทิร์นเดียวกับ barcode ใน TicketView)
///
/// **เคยอยู่ในไฟล์เดียวกับจอ `MyQRCodeView`** ซึ่งถูกลบทิ้ง 2026-08-22 (จอตายไม่มีใครอ้างถึง)
/// — ตัวช่วยนี้ไม่ได้ตายไปด้วย หน้าบัตรผู้เข้าร่วมเรียกใช้อยู่จริง จึงแยกออกมาเป็นไฟล์ของตัวเอง
/// `import UIKit` ไม่ใช่ `SwiftUI` เพราะมันคืน `UIImage` ไม่ได้แตะ View เลยสักบรรทัด
enum QRCode {
    static func image(from string: String) -> UIImage? {
        guard !string.isEmpty else { return nil }
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(string.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
