import Foundation

public enum MigrationError: Error, Equatable {
    case missingSchemaVersion
    case newerSchema(kind: DocumentKind, found: Int, supported: Int)
    case missingStep(kind: DocumentKind, from: Int)
    case notAnObject
}

/// Reads and writes the `schemaVersion` of stored files, and upgrades older files one
/// version at a time on the raw JSON object before decoding.
public struct Migrator {
    /// Upgrades a JSON object from version `n` to `n + 1`.
    public typealias Step = (inout [String: Any]) throws -> Void

    public static let schemaVersionKey = "schemaVersion"

    /// Every file kind is at version 1, and no migrations exist yet.
    public static let standard = Migrator(currentVersions: [:], steps: [:])

    private let currentVersions: [DocumentKind: Int]
    private let steps: [DocumentKind: [Int: Step]]

    /// - Parameters:
    ///   - currentVersions: the version written for each kind; kinds not listed are at 1.
    ///   - steps: for each kind, the step that upgrades version `n` keyed by `n`.
    public init(currentVersions: [DocumentKind: Int], steps: [DocumentKind: [Int: Step]]) {
        self.currentVersions = currentVersions
        self.steps = steps
    }

    public func currentVersion(of kind: DocumentKind) -> Int {
        currentVersions[kind] ?? 1
    }

    public func decode<T: StoredDocument>(_: T.Type, from data: Data, using decoder: JSONDecoder) throws -> T {
        guard let version = try decoder.decode(VersionProbe.self, from: data).schemaVersion else {
            throw MigrationError.missingSchemaVersion
        }
        let current = currentVersion(of: T.kind)
        if version == current {
            return try decoder.decode(T.self, from: data)
        }
        guard version < current else {
            throw MigrationError.newerSchema(kind: T.kind, found: version, supported: current)
        }
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MigrationError.notAnObject
        }
        for from in version ..< current {
            guard let step = steps[T.kind]?[from] else {
                throw MigrationError.missingStep(kind: T.kind, from: from)
            }
            try step(&object)
            object[Self.schemaVersionKey] = from + 1
        }
        return try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    public func encode<T: StoredDocument>(_ value: T, using encoder: JSONEncoder) throws -> Data {
        try encoder.encode(Versioned(version: currentVersion(of: T.kind), value: value))
    }
}

private struct VersionProbe: Decodable {
    let schemaVersion: Int?
}

/// Encodes `value`'s keys and `schemaVersion` side by side in one JSON object.
private struct Versioned<Value: Encodable>: Encodable {
    let version: Int
    let value: Value

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .schemaVersion)
    }
}
