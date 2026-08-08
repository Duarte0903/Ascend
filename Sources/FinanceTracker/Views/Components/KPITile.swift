import SwiftUI

struct KPITile: View {
    let title: String
    let value: String
    var caption: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        let native = NSColor(self).usingColorSpace(.sRGB) ?? .systemBlue
        return String(format: "#%02X%02X%02X",
                      Int(native.redComponent * 255),
                      Int(native.greenComponent * 255),
                      Int(native.blueComponent * 255))
    }
}
