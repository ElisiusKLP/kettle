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

    /// Colours given to new labels, in order. Readable on light and dark backgrounds.
    public static let palette = [
        "#C8743A", "#2E8B7A", "#4F6FB5", "#B5487A", "#7A8B2E", "#8A5BB5", "#B59A2E", "#3A9BC8",
    ]

    /// The first palette colour no existing label uses, cycling once all are taken.
    public static func nextColor(after labels: [Label]) -> String {
        let used = Set(labels.map { $0.colorHex.uppercased() })
        return palette.first { !used.contains($0) } ?? palette[labels.count % palette.count]
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
