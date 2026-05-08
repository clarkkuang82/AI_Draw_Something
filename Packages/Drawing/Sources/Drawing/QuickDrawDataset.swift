import Foundation

public enum QuickDrawDatasetError: Error, LocalizedError {
    case resourceMissing
    case decodeFailed(String)
    case noSketchesForCategory(String)

    public var errorDescription: String? {
        switch self {
        case .resourceMissing: return "sketches.json not found in bundle"
        case .decodeFailed(let why): return "decode failed: \(why)"
        case .noSketchesForCategory(let id): return "no sketches for category \(id)"
        }
    }
}

/// Loads the bundled MVP JSON dataset. v2 will swap to mmap'd binary + zstd.
public final class QuickDrawDataset: @unchecked Sendable {
    private let byCategory: [String: [Sketch]]

    public init(sketches: [Sketch]) {
        self.byCategory = Dictionary(grouping: sketches, by: \.categoryId)
    }

    public convenience init() throws {
        try self.init(bundle: .module)
    }

    public convenience init(bundle: Bundle) throws {
        guard let url = bundle.url(forResource: "sketches", withExtension: "json") else {
            throw QuickDrawDatasetError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        do {
            let payload = try JSONDecoder().decode(SketchesPayload.self, from: data)
            self.init(sketches: payload.sketches)
        } catch {
            throw QuickDrawDatasetError.decodeFailed(String(describing: error))
        }
    }

    public func randomSketch(for categoryId: String) throws -> Sketch {
        guard let arr = byCategory[categoryId], let pick = arr.randomElement() else {
            throw QuickDrawDatasetError.noSketchesForCategory(categoryId)
        }
        return pick
    }

    public var categoryIds: [String] { Array(byCategory.keys).sorted() }
}

private struct SketchesPayload: Decodable {
    let sketches: [Sketch]
}
