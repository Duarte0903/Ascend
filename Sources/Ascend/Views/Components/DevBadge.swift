import SwiftUI

/// The mark that says "this is the preview, not the release". Only a Debug
/// build launched through `scripts/dev.sh` ever shows it.
struct DevBadge: View {
    var body: some View {
        Text("DEV")
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.ftNegative, in: Capsule())
            .help("Development preview — separate data, no updates")
    }
}
