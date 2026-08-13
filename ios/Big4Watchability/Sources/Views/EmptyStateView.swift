import SwiftUI

// iOS 16-compatible stand-in for ContentUnavailableView (iOS 17+) - deployment
// target is deliberately 16.0 until Jamie confirms what OS his test iPad
// runs, so this stays until that's settled.
struct EmptyStateView: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
