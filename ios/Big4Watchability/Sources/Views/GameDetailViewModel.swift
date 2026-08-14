import Foundation

// Swift mirror of GameDetailViewModel.kt - backs the game-detail popup's
// top-performers/head-to-head/standings context, fetched fresh every time
// the popup opens (never cached client-side, matching the backend's own
// on-demand design).
enum GameDetailUiState {
    case loading
    case error(String)
    case loaded(GameDetailResponse)
}

@MainActor
final class GameDetailViewModel: ObservableObject {
    @Published private(set) var uiState: GameDetailUiState = .loading

    private let client: APIClient
    private var currentEventId: String?
    private var loadTask: Task<Void, Never>?

    init(client: APIClient = .shared) {
        self.client = client
    }

    func load(eventId: String) {
        currentEventId = eventId
        uiState = .loading
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            let result: GameDetailUiState
            do {
                let detail = try await client.gameDetail(eventId: eventId)
                result = .loaded(detail)
            } catch {
                result = .error(error.localizedDescription)
            }
            // Same stale-response guard as GameDetailViewModel.kt - discard a
            // result for a game the caller has since navigated away from.
            if self.currentEventId == eventId {
                self.uiState = result
            }
        }
    }

    func retry() {
        if let eventId = currentEventId {
            load(eventId: eventId)
        }
    }
}
