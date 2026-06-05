import SwiftUI

/// A named, color-coded collection of clips. One category at a time can be
/// "collecting": every new copy is filed into it automatically (research mode).
struct ClipCategory: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
    var isCollecting: Bool
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, colorHex: String = "#F59E0B",
         isCollecting: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isCollecting = isCollecting
        self.sortOrder = sortOrder
    }

    var color: Color { Color(hex: colorHex) ?? .orange }

    static let palette: [String] = [
        "#F59E0B", "#EF4444", "#10B981", "#3B82F6",
        "#8B5CF6", "#EC4899", "#14B8A6", "#6B7280",
    ]
}

extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}
