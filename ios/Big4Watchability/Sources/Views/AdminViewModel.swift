import Foundation

// Swift mirror of AdminViewModel.kt, minus the test-push section - that
// targets this device's own registered Alerts token, and the Alerts push
// stack itself isn't built on iOS yet.
enum AdminDashboardState {
    case loading
    case error(String)
    case loaded(stats: AdminStats, missingGames: [AdminMissingGame])
}

enum ResendState {
    case inFlight
    case found(String)
    case notFound
    case failed(String)
}

@MainActor
final class AdminViewModel: ObservableObject {
    @Published private(set) var dashboardState: AdminDashboardState = .loading
    @Published private(set) var loginError: String?
    @Published private(set) var isLoggingIn = false
    @Published private(set) var resendStates: [String: ResendState] = [:]
    @Published var manualEntryExpanded: [String: Bool] = [:]
    // Mirrors authStore.token != nil as a directly-@Published value - the
    // view models's own ObservableObject conformance doesn't automatically
    // republish a nested ObservableObject's changes, so views observing
    // isLoggedIn (About's post-PIN-success transition) need this synced
    // explicitly rather than a computed pass-through.
    @Published private(set) var isLoggedIn: Bool

    private let authStore: AdminAuthStore

    init(authStore: AdminAuthStore = .shared) {
        self.authStore = authStore
        isLoggedIn = authStore.token != nil
    }

    var token: String? { authStore.token }

    func toggleManualEntry(_ eventId: String) {
        manualEntryExpanded[eventId] = !(manualEntryExpanded[eventId] ?? false)
    }

    func submitPin(_ pin: String) {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        loginError = nil
        Task {
            do {
                let newToken = try await AdminNetworkRepository.login(baseUrl: backendBaseURL, pin: pin)
                authStore.setToken(newToken)
                isLoggedIn = true
                isLoggingIn = false
                loadDashboard()
            } catch is AdminUnauthorizedError {
                loginError = "Incorrect PIN"
                isLoggingIn = false
            } catch {
                loginError = error.localizedDescription
                isLoggingIn = false
            }
        }
    }

    func logOut() {
        authStore.clearToken()
        isLoggedIn = false
    }

    func loadDashboard() {
        guard let activeToken = authStore.token else { return }
        dashboardState = .loading
        Task {
            do {
                async let statsResult = AdminNetworkRepository.stats(baseUrl: backendBaseURL, token: activeToken)
                async let missingResult = AdminNetworkRepository.missingHighlights(baseUrl: backendBaseURL, token: activeToken)
                let (stats, missing) = try await (statsResult, missingResult)
                dashboardState = .loaded(stats: stats, missingGames: missing)
            } catch is AdminUnauthorizedError {
                // The persisted token's server-side session expired (24h TTL,
                // or the backend restarted and lost its in-memory token set)
                // - clear it so the caller falls back to the PIN screen
                // instead of showing a dead dashboard.
                authStore.clearToken()
                isLoggedIn = false
            } catch {
                dashboardState = .error(error.localizedDescription)
            }
        }
    }

    func resendHighlights(_ eventId: String) {
        guard let activeToken = authStore.token else { return }
        resendStates[eventId] = .inFlight
        Task {
            do {
                let result = try await AdminNetworkRepository.resendHighlights(baseUrl: backendBaseURL, token: activeToken, eventId: eventId)
                resendStates[eventId] = result.matched ? .found(result.title ?? "Match found") : .notFound
                if result.matched { loadDashboard() }
            } catch {
                resendStates[eventId] = .failed(error.localizedDescription)
            }
        }
    }

    func submitManualHighlight(_ eventId: String, url: String) {
        guard let activeToken = authStore.token else { return }
        resendStates[eventId] = .inFlight
        Task {
            do {
                _ = try await AdminNetworkRepository.setHighlight(baseUrl: backendBaseURL, token: activeToken, eventId: eventId, url: url)
                resendStates[eventId] = .found("Added manually")
                manualEntryExpanded[eventId] = false
                loadDashboard()
            } catch {
                resendStates[eventId] = .failed(error.localizedDescription)
            }
        }
    }
}
