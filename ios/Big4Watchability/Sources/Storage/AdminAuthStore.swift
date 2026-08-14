import Foundation

// Swift mirror of AdminAuthRepository.kt - persists the Admin page's bearer
// token on-device only, so re-entering the hidden page doesn't require the
// PIN every single time. The token itself is opaque and short-lived
// server-side (adminService.ts, 24h TTL, invalidated on every backend
// restart), so persisting it locally is no worse than a normal "stay signed
// in" cookie; the real gate is the PIN check that issued it. UserDefaults,
// same as every other store in this app (FavoritesStore, RubricWeightsStore)
// - no Keychain used anywhere here yet.
@MainActor
final class AdminAuthStore: ObservableObject {
    static let shared = AdminAuthStore()

    @Published private(set) var token: String?

    private let defaults: UserDefaults
    private let key = "admin.token"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        token = defaults.string(forKey: key)
    }

    func setToken(_ token: String) {
        self.token = token
        defaults.set(token, forKey: key)
    }

    func clearToken() {
        token = nil
        defaults.removeObject(forKey: key)
    }
}
