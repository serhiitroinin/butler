import Foundation

enum Format {
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }

    /// The formatter's no-break space sets badly in a monospaced face.
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }
}
