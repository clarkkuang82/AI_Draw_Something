import Foundation
import CoreGraphics

public struct StrokePoint: Sendable, Hashable, Codable {
    /// Normalized to 0...255 (QuickDraw simplified format).
    public let x: Int
    public let y: Int
    /// Cumulative time (seconds) since the very first point of the sketch.
    public let t: Double

    public init(x: Int, y: Int, t: Double) {
        self.x = x; self.y = y; self.t = t
    }

    public func cgPoint(in size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(x) / 255.0 * size.width,
                y: CGFloat(y) / 255.0 * size.height)
    }
}

public struct Stroke: Sendable, Hashable, Codable {
    public let points: [StrokePoint]
    public init(points: [StrokePoint]) { self.points = points }
}

public struct Sketch: Sendable, Hashable, Identifiable, Codable {
    public let id: String          // e.g. "cat-0"
    public let categoryId: String  // e.g. "cat"
    public let strokes: [Stroke]

    public init(id: String, categoryId: String, strokes: [Stroke]) {
        self.id = id; self.categoryId = categoryId; self.strokes = strokes
    }

    public var totalDuration: Double {
        strokes.compactMap { $0.points.last?.t }.max() ?? 0
    }
}
