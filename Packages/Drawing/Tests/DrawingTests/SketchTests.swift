import XCTest
@testable import Drawing

final class SketchTests: XCTestCase {
    func test_totalDuration_returns_max_last_point_t_across_strokes() {
        let s = Sketch(id: "x-0", categoryId: "x", strokes: [
            Stroke(points: [
                StrokePoint(x: 0, y: 0, t: 0.0),
                StrokePoint(x: 1, y: 1, t: 0.5),
            ]),
            Stroke(points: [
                StrokePoint(x: 2, y: 2, t: 1.2),
                StrokePoint(x: 3, y: 3, t: 2.4),
            ]),
        ])
        XCTAssertEqual(s.totalDuration, 2.4, accuracy: 0.001)
    }

    func test_totalDuration_zero_when_empty() {
        let s = Sketch(id: "x-0", categoryId: "x", strokes: [])
        XCTAssertEqual(s.totalDuration, 0)
    }

    func test_strokePoint_normalizes_into_target_size() {
        let p = StrokePoint(x: 128, y: 0, t: 0)
        let cg = p.cgPoint(in: .init(width: 200, height: 200))
        XCTAssertEqual(cg.x, 200 * (128.0 / 255.0), accuracy: 0.001)
        XCTAssertEqual(cg.y, 0)
    }

    func test_codable_roundtrip_of_sketch() throws {
        let original = Sketch(id: "cat-0", categoryId: "cat", strokes: [
            Stroke(points: [StrokePoint(x: 10, y: 20, t: 0.5)]),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Sketch.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
