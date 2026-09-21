import SwiftUI

// The "in-app banner" half of the delivery pref. Android draws this itself
// from AlertsFirebaseMessagingService when a data-only push arrives and the
// pref says in_app/both; on iOS the same decision is split - the backend
// sends a silent or alert push (fcm.ts), and this is what gets drawn when
// one lands while the app is foregrounded.
//
// The message field is `message`, not `body`: a SwiftUI View already owes
// the protocol a `body` property, so a stored one of that name doesn't
// compile.
struct InAppAlertBanner: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.fill")
                .foregroundStyle(AppColors.tierInstantClassic)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.surfaceCardElevated)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.tierInstantClassic.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            // Auto-dismiss so a banner can't sit on top of the UI forever if
            // the user never taps the close button.
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                onDismiss()
            }
        }
    }
}
