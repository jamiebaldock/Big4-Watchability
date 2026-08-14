import SwiftUI

// Swift mirror of AdminDashboardScreen.kt - hidden operational page (About
// screen's 12x title tap -> AdminPinView -> here). Test-push section
// deliberately omitted, see AdminViewModel.swift's header comment.
struct AdminDashboardView: View {
    @ObservedObject var viewModel: AdminViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Admin")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Log Out") {
                            viewModel.logOut()
                            dismiss()
                        }
                    }
                }
                .task { viewModel.loadDashboard() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.dashboardState {
        case .loading:
            ProgressView()
        case .error(let message):
            VStack(spacing: 12) {
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Retry") { viewModel.loadDashboard() }.buttonStyle(.bordered)
            }
            .padding()
        case .loaded(let stats, let missingGames):
            List {
                Section("YouTube search quota") {
                    Text("\(stats.todayCount) / \(stats.dailyCap) used today")
                        .foregroundStyle(stats.todayCount >= stats.dailyCap ? .red : .secondary)
                    if !stats.budgetHistory.isEmpty {
                        Text(stats.budgetHistory.map { "\(String($0.date.suffix(5))): \($0.count)" }.joined(separator: "   "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("Last 7 days — matched \(stats.outcomeCounts["matched"] ?? 0), no match \(stats.outcomeCounts["no_match"] ?? 0), errors \(stats.outcomeCounts["api_error"] ?? 0), quota-skipped \(stats.outcomeCounts["quota_exhausted"] ?? 0)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Median upload lag (learned)") {
                    ForEach(stats.lagPercentiles.sorted(by: { $0.key < $1.key }), id: \.key) { league, lag in
                        Text("\(league.uppercased()): \(lagDisplay(lag))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Push delivery (Alerts)") {
                    Text("\(stats.pushStats.registeredDevices) device(s) registered")
                    Text("Last 7 days — sent \(stats.pushStats.sentLastNDays), delivered \(stats.pushStats.deliveredLastNDays), failed \(stats.pushStats.failedLastNDays)")
                        .foregroundStyle(stats.pushStats.failedLastNDays > 0 ? .red : .secondary)
                        .font(.caption)
                }

                Section("Backend (Render)") {
                    RenderStatusRows(render: stats.renderStatus)
                }

                Section("Claude API cost") {
                    AnthropicUsageRows(usage: stats.anthropicUsage)
                }

                Section("Missing highlights (\(missingGames.count))") {
                    if missingGames.isEmpty {
                        Text("Nothing missing right now.").foregroundStyle(.secondary)
                    } else {
                        ForEach(missingGames) { game in
                            MissingGameRow(game: game, viewModel: viewModel)
                        }
                    }
                }
            }
        }
    }

    private func lagDisplay(_ lag: LagPercentiles) -> String {
        if lag.sampleCount == 0 { return "no data yet" }
        if lag.p50Ms < 0 { return "unreliable reading (final-detection lag)" }
        let minutes = lag.p50Ms / 60000
        return "\(minutes) min (\(lag.sampleCount) samples\(lag.fromRealData ? "" : ", default"))"
    }
}

private func formatAdminUtc(_ iso: String?) -> String {
    guard let iso else { return "never" }
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = withFractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    guard let date else { return iso }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, h:mm a"
    return formatter.string(from: date)
}

private struct RenderStatusRows: View {
    let render: RenderStatus

    var body: some View {
        if !render.configured {
            Text("Not configured - add RENDER_API_KEY on Render to see live service status here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let error = render.error {
            Text(error).font(.caption).foregroundStyle(.red)
        } else {
            Text("Status: \(render.serviceStatus ?? "unknown")")
                .foregroundStyle(render.serviceStatus == "running" ? .green : .red)
            Text("Last deploy: \(render.lastDeployStatus ?? "unknown")\(render.lastDeployAt.map { " (\(formatAdminUtc($0)))" } ?? "")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AnthropicUsageRows: View {
    let usage: AnthropicUsage

    var body: some View {
        if !usage.configured {
            Text("Not configured - add ANTHROPIC_ADMIN_KEY on Render to see cost here (requires an Organization Console account).")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let error = usage.error {
            Text(error).font(.caption).foregroundStyle(.red)
        } else {
            Text("Last 7 days: $\(String(format: "%.2f", usage.last7DaysCostUsd ?? 0))")
        }
    }
}

private struct MissingGameRow: View {
    let game: AdminMissingGame
    @ObservedObject var viewModel: AdminViewModel
    @State private var manualUrl = ""

    private var resendState: ResendState? { viewModel.resendStates[game.eventId] }
    private var isManualEntryExpanded: Bool { viewModel.manualEntryExpanded[game.eventId] ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(game.away) @ \(game.home)").font(.subheadline)
                    Text("\(game.leagueGroup.uppercased()) · \(formatAdminUtc(game.tipoffUtc)) · \(game.ytCheckCount) check(s), last \(formatAdminUtc(game.ytLastCheckedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if case .inFlight = resendState {
                    ProgressView()
                } else {
                    Button("Re-search") { viewModel.resendHighlights(game.eventId) }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
            }

            switch resendState {
            case .found(let title):
                Text("Found: \(title)").font(.caption2).foregroundStyle(.green)
            case .notFound:
                Text("No match found").font(.caption2).foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).font(.caption2).foregroundStyle(.red)
            default:
                EmptyView()
            }

            if !isFound, (isNotFound || isManualEntryExpanded) {
                if !isManualEntryExpanded {
                    Button("Add a link manually") {
                        viewModel.toggleManualEntry(game.eventId)
                    }
                    .font(.caption2)
                } else {
                    HStack {
                        TextField("Paste a YouTube link", text: $manualUrl)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isSubmitting)
                        Button("Save") {
                            viewModel.submitManualHighlight(game.eventId, url: manualUrl)
                        }
                        .disabled(isSubmitting || manualUrl.isEmpty)
                        Button("Cancel") {
                            viewModel.toggleManualEntry(game.eventId)
                        }
                        .disabled(isSubmitting)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var isFound: Bool { if case .found = resendState { return true }; return false }
    private var isNotFound: Bool { if case .notFound = resendState { return true }; return false }
    private var isSubmitting: Bool { if case .inFlight = resendState { return true }; return false }
}
