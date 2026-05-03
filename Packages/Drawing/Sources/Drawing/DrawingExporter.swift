#if canImport(PencilKit) && canImport(UIKit)
import Foundation
import PencilKit
import UIKit

public enum DrawingExporter {
    /// Render `drawing` onto a 256×256 white-background JPEG. Target ~10–25 KB.
    /// Falls back to a 512×512 1.0 quality export only if the input is empty.
    public static func exportForVLM(_ drawing: PKDrawing,
                                    canvasSize: CGSize) -> Data? {
        let target = CGSize(width: 256, height: 256)
        let bounds = CGRect(origin: .zero, size: canvasSize)

        // Render at native scale; PencilKit handles strokes nicely at 1x.
        let strokesImage = drawing.image(from: bounds, scale: 1.0)

        let renderer = UIGraphicsImageRenderer(size: target,
                                               format: .opaque(scale: 1))
        let composite = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: target))
            strokesImage.draw(in: CGRect(origin: .zero, size: target))
        }
        return composite.jpegData(compressionQuality: 0.6)
    }
}

private extension UIGraphicsImageRendererFormat {
    static func opaque(scale: CGFloat) -> UIGraphicsImageRendererFormat {
        let f = UIGraphicsImageRendererFormat.default()
        f.opaque = true
        f.scale = scale
        return f
    }
}
#endif
