import SwiftUI

extension Color {
    static let paiPrimary = Color(hex: "#4CAF50")
    static let paiPrimaryLight = Color(hex: "#81C784")
    static let paiBackground = Color(hex: "#F5F7F6")
    static let paiCardBackground = Color(hex: "#FFFFFF")
    static let paiTextPrimary = Color(hex: "#212121")
    static let paiTextSecondary = Color(hex: "#9E9E9E")
    static let paiWarning = Color(hex: "#FF9800")
    static let paiDanger = Color(hex: "#F44336")

    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64

        switch sanitized.count {
        case 6:
            red = (value & 0xFF0000) >> 16
            green = (value & 0x00FF00) >> 8
            blue = value & 0x0000FF
        default:
            red = 0
            green = 0
            blue = 0
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: 1
        )
    }
}

extension TaskStatus {
    var badgeColor: Color {
        switch self {
        case .pending:
            return .paiPrimaryLight
        case .received:
            return .paiPrimary
        case .negotiating:
            return .paiWarning
        case .done:
            return .paiTextSecondary
        }
    }

    var displayName: String {
        switch self {
        case .pending:
            return "待收到"
        case .received:
            return "已收到"
        case .negotiating:
            return "商量中"
        case .done:
            return "已完成"
        }
    }
}
