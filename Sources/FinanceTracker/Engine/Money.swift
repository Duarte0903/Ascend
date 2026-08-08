import Foundation

/// Currency and percentage formatting matching the source workbook:
/// narrow no-break space separators, comma decimal, trailing symbol.
enum Money {
    static let dash = "—"
    private static let nnbsp = "\u{202F}"

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
        return "\(n)\(nnbsp)€"
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
