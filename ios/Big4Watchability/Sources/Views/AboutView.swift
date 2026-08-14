import SwiftUI

// Swift mirror of AboutScreen.kt - reached from Settings. Hosts two
// undocumented tap gestures: the title (12 taps) opens the hidden Admin
// page, the version number (8 taps, Kobe's number after 8->24) opens
// SecretScreenView. Neither is advertised anywhere in the app's own UI.
private let tapsToUnlockAdmin = 12
private let tapsToUnlockSecret = 8
private let privacyPolicyURL = URL(string: "https://jamiebaldock.github.io/NBA-Watchability/privacy-policy.html")!
private let contactEmail = "help@tech3d.com.au"

struct AboutView: View {
    @StateObject private var adminViewModel = AdminViewModel()
    @State private var titleTapCount = 0
    @State private var versionTapCount = 0
    @State private var showAdminPin = false
    @State private var showAdminDashboard = false
    @State private var showSecretScreen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                VStack(spacing: 4) {
                    Text("Big4 Watchability")
                        .font(.title.bold())
                        .onTapGesture {
                            titleTapCount += 1
                            if titleTapCount >= tapsToUnlockAdmin {
                                titleTapCount = 0
                                if adminViewModel.isLoggedIn {
                                    showAdminDashboard = true
                                } else {
                                    showAdminPin = true
                                }
                            }
                        }
                    Text("Spoiler-free NBA, WNBA, MLB, NFL & NHL watchability scores.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("v1.0")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .onTapGesture {
                            versionTapCount += 1
                            if versionTapCount >= tapsToUnlockSecret {
                                versionTapCount = 0
                                showSecretScreen = true
                            }
                        }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

                Divider()

                sectionHeader("How it works", systemImage: "info.circle")
                Text("Every NBA, WNBA, MLB, NFL, and NHL game gets a Watchability Score once it's final, built from what actually makes a game exciting: close margins, comebacks, lead changes, clutch finishes, buzzer-beaters, overtime, and standout individual performances.\n\nScores land in one of four tiers, shown as a badge right on the tile - and each league is scored on its own scale, calibrated separately against real completed games. Nothing about how a game turns out is shown until you ask for it.")
                    .font(.subheadline)
                    .padding(.bottom, 12)

                VStack(alignment: .leading, spacing: 8) {
                    ScoreBadge(score: 92, tier: .instantClassic, showNumber: true)
                    ScoreBadge(score: 75, tier: .worthYourTime, showNumber: true)
                    ScoreBadge(score: 55, tier: .solid, showNumber: true)
                    ScoreBadge(score: 30, tier: .skippable, showNumber: true)
                }
                .padding(.bottom, 16)

                Divider()

                sectionHeader("Legal", systemImage: "text.book.closed")
                Text("NBA, WNBA, MLB, NFL, NHL, and all associated team names, logos, and marks are trademarks of their respective owners. Big4 Watchability is an independent app, not affiliated with, endorsed by, or sponsored by any of these leagues or teams. Game schedules, scores, statistics, team crests, and news are sourced from ESPN's publicly accessible content servers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)

                Divider()

                Link(destination: privacyPolicyURL) {
                    HStack {
                        Text("Privacy policy")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
                .padding(.vertical, 12)

                Divider()

                Link(destination: URL(string: "mailto:\(contactEmail)")!) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Questions or feedback")
                            Text(contactEmail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "envelope")
                    }
                }
                .padding(.vertical, 12)

                Text("© 2026 Tech3D. All rights reserved.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            }
            .padding(.horizontal, 16)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdminPin) {
            AdminPinView(viewModel: adminViewModel)
        }
        .sheet(isPresented: $showAdminDashboard) {
            AdminDashboardView(viewModel: adminViewModel)
        }
        .sheet(isPresented: $showSecretScreen) {
            SecretScreenView()
        }
        .onChange(of: adminViewModel.isLoggedIn) { loggedIn in
            if loggedIn, showAdminPin {
                showAdminPin = false
                showAdminDashboard = true
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

#Preview {
    NavigationStack { AboutView() }
}
