import XCTest
@testable import Drawing

final class QuickDrawDatasetTests: XCTestCase {
    func test_default_init_loads_bundled_sketches() throws {
        let dataset = try QuickDrawDataset()
        XCTAssertFalse(dataset.categoryIds.isEmpty,
                       "bundled dataset should have at least one category")
    }

    func test_default_init_includes_seed_categories() throws {
        let dataset = try QuickDrawDataset()
        // These six were the original MVP set; they must always be present
        // for the legacy gameplay path to work.
        for required in ["cat", "fish", "house", "airplane", "umbrella", "guitar"] {
            XCTAssertTrue(dataset.categoryIds.contains(required),
                          "missing required category \(required)")
        }
    }

    func test_randomSketch_returns_a_sketch_for_known_category() throws {
        let dataset = try QuickDrawDataset()
        let sketch = try dataset.randomSketch(for: "cat")
        XCTAssertEqual(sketch.categoryId, "cat")
        XCTAssertGreaterThan(sketch.strokes.count, 0)
    }

    func test_randomSketch_throws_for_unknown_category() {
        let dataset = try? QuickDrawDataset()
        XCTAssertNotNil(dataset)
        XCTAssertThrowsError(try dataset!.randomSketch(for: "nonexistent_category_xyz"))
    }

    func test_init_from_explicit_array_avoids_bundle() {
        let s = Sketch(id: "demo-0", categoryId: "demo", strokes: [])
        let dataset = QuickDrawDataset(sketches: [s])
        XCTAssertEqual(dataset.categoryIds, ["demo"])
    }
}
