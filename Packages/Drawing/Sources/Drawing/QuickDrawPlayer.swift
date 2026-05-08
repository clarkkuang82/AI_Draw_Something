#if canImport(SwiftUI)
import SwiftUI

@available(iOS 17, macOS 14, *)
public struct QuickDrawPlaybackView: View {
    public let sketch: Sketch
    public var speed: Double
    public var lineWidth: CGFloat
    public var onComplete: (() -> Void)?

    @State private var startedAt: Date = .now
    @State private var didCompleteFire = false

    public init(sketch: Sketch,
                speed: Double = 2.5,
                lineWidth: CGFloat = 3,
                onComplete: (() -> Void)? = nil) {
        self.sketch = sketch
        self.speed = speed
        self.lineWidth = lineWidth
        self.onComplete = onComplete
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
            Canvas { gc, size in
                let elapsed = ctx.date.timeIntervalSince(startedAt) * speed
                let total = sketch.totalDuration
                if !didCompleteFire, elapsed >= total + 0.1, total > 0 {
                    DispatchQueue.main.async {
                        didCompleteFire = true
                        onComplete?()
                    }
                }
                for stroke in sketch.strokes {
                    let visible = stroke.points.prefix { $0.t <= elapsed }
                    guard visible.count >= 2 else {
                        if let p = visible.first {
                            let cg = p.cgPoint(in: size)
                            gc.fill(Path(ellipseIn: CGRect(x: cg.x - lineWidth/2,
                                                           y: cg.y - lineWidth/2,
                                                           width: lineWidth,
                                                           height: lineWidth)),
                                     with: .color(.primary))
                        }
                        continue
                    }
                    var path = Path()
                    var first = true
                    for p in visible {
                        let cg = p.cgPoint(in: size)
                        if first { path.move(to: cg); first = false }
                        else     { path.addLine(to: cg) }
                    }
                    gc.stroke(path,
                              with: .color(.primary),
                              style: StrokeStyle(lineWidth: lineWidth,
                                                 lineCap: .round,
                                                 lineJoin: .round))
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .onAppear { startedAt = .now; didCompleteFire = false }
    }
}
#endif
