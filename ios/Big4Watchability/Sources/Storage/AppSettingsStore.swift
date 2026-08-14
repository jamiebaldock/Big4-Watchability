import Foundation

// Backs the "All Leagues" toggle (AppSettingsRepository.kt's
// isAllLeaguesSelected) - one shared, persisted value observed by Games,
// Starred, and History at once, not independent per-tab state. A plain
// @AppStorage property inside each view's own struct would each read/write
// the same UserDefaults key but wouldn't notify each other of a change made
// from a different tab; this shared ObservableObject singleton (same
// pattern as FavoritesStore/RubricWeightsStore) is what makes a toggle in
// one tab reactively update every other tab still on screen, matching the
// exact bug Android fixed (2026-07-20: previously-local per-tab state that
// silently reset switching tabs).
@MainActor
final class AppSettingsStore: ObservableObject {
    static let shared = AppSettingsStore()

    @Published var isAllLeaguesSelected: Bool {
        didSet {
            UserDefaults.standard.set(isAllLeaguesSelected, forKey: AppSettingsKeys.isAllLeaguesSelected)
        }
    }

    init(defaults: UserDefaults = .standard) {
        isAllLeaguesSelected = defaults.bool(forKey: AppSettingsKeys.isAllLeaguesSelected)
    }
}
