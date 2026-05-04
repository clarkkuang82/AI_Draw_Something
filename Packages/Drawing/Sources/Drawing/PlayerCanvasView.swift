#if canImport(PencilKit) && canImport(UIKit)
import SwiftUI
import PencilKit
import UIKit

@available(iOS 17, *)
public struct PlayerCanvasView: UIViewRepresentable {
    @Binding public var drawing: PKDrawing
    public var allowsFingerDrawing: Bool

    public init(drawing: Binding<PKDrawing>, allowsFingerDrawing: Bool = true) {
        self._drawing = drawing
        self.allowsFingerDrawing = allowsFingerDrawing
    }

    public func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        canvas.backgroundColor = .systemBackground
        canvas.tool = PKInkingTool(.pen, color: .label, width: 6)
        canvas.drawing = drawing
        return canvas
    }

    public func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing { uiView.drawing = drawing }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PlayerCanvasView
        init(_ parent: PlayerCanvasView) { self.parent = parent }

        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
#endif
