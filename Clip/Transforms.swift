import Foundation

/// Text transforms applied at paste time — the Pastebot feature, keyboard-free.
enum TextTransform: String, CaseIterable, Identifiable {
    case uppercase = "UPPERCASE"
    case lowercase = "lowercase"
    case titleCase = "Title Case"
    case trimWhitespace = "Trim Whitespace"
    case collapseLines = "Single Line"
    case jsonPretty = "Pretty-Print JSON"
    case urlEncode = "URL Encode"
    case urlDecode = "URL Decode"

    var id: String { rawValue }

    func apply(to input: String) -> String {
        switch self {
        case .uppercase:
            return input.uppercased()
        case .lowercase:
            return input.lowercased()
        case .titleCase:
            return input.capitalized
        case .trimWhitespace:
            return input
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .collapseLines:
            return input
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case .jsonPretty:
            guard let data = input.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                           options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
                  let result = String(data: pretty, encoding: .utf8) else { return input }
            return result
        case .urlEncode:
            return input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        case .urlDecode:
            return input.removingPercentEncoding ?? input
        }
    }
}
