import Foundation

/// A task category, such as `#work`. Archived labels are hidden from pickers but keep their stats.
public struct Label: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var colorHex: String
    public var isArchived: Bool

    public init(id: UUID = UUID(), name: String, colorHex: String, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isArchived = isArchived
    }
}

/// The contents of `labels.json`.
public struct LabelList: StoredDocument, Hashable {
    public static let kind = DocumentKind.labels

    public var labels: [Label]

    public init(labels: [Label] = []) {
        self.labels = labels
    }
}
