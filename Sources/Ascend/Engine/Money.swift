import Foundation

/// Currency and percentage formatting matching the source workbook:
/// narrow no-break space separators, comma decimal, trailing symbol.
enum Money {
    static let dash = "—"
    private static let nnbsp = "\u{202F}"

    static let defaultSymbol = "€"

    /// The symbol every figure is drawn with. Set once when a profile opens,
    /// on the main thread, and read everywhere after — which is why it is a
    /// plain global rather than threaded through every call site.
    nonisolated(unsafe) static var symbol = defaultSymbol

    /// Offered as quick picks; any text is accepted.
    static let commonSymbols = ["€", "$", "£", "CHF", "kr", "R$", "¥", "zł", "₹", "A$"]

    private static func formatter(decimals: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = nnbsp
        f.decimalSeparator = ","
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        return f
    }

    static func currency(_ value: Double, decimals: Int = 0) -> String {
        let n = formatter(decimals: decimals).string(from: NSNumber(value: value)) ?? "0"
        return "\(n)\(nnbsp)\(symbol)"
    }

    static func currency(_ value: Double?, decimals: Int = 0) -> String {
        guard let value else { return dash }
        return currency(value, decimals: decimals)
    }

    /// Takes a fraction (0.122 -> "12,2 %").
    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return dash }
        let n = formatter(decimals: 1).string(from: NSNumber(value: fraction * 100)) ?? "0"
        return "\(n)\(nnbsp)%"
    }
}
