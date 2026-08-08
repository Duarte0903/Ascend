import SwiftUI

/// A titled card. The workhorse container on every screen.
struct CardSection<Content: View>: View {
    let title: String
    var subtitle: String?
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = nil
        self.content = content()
    }

    init<Trailing: View>(_ title: String,
                         subtitle: String? = nil,
                         @ViewBuilder trailing: () -> Trailing,
                         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = AnyView(trailing())
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color.ftInk)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.ftInkTertiary)
                    }
                }
                if let trailing {
                    Spacer(minLength: 12)
                    trailing
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ftCard()
    }
}

/// An inline note that explains a state rather than reporting an error.
struct Callout: View {
    let text: String
    var systemImage: String = "info.circle"
    var tint: Color = .ftAccent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.ftInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(tint.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
