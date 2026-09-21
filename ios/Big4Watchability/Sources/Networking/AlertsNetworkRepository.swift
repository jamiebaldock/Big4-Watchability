import Foundation

// Swift mirror of mobile/app/.../data/AlertsNetworkRepository.kt - same two
// POST routes (alertsService.ts), same body shapes. The field names below
// are the wire contract and must match registerAlertDevice's validation
// exactly; renaming one silently turns into a 400.
//
// Note the payload still says `fcmToken` on iOS. That's deliberate and
// accurate: the iOS app registers with APNs and then hands the APNs token
// to Firebase Messaging, which returns a real FCM token - the same kind of
// value Android sends, delivered over the same backend send path. No
// platform column, no second sender. See backend/src/fcm.ts's sendPush.

private struct AlertFavoriteBody: Encodable {
    let teamName: String
    let leagueGroup: String?
}

private struct RegisterDeviceBody: Encodable {
    let deviceId: String
    let fcmToken: String?
    let leagues: [String]
    let favorites: [AlertFavoriteBody]
    let closeSwingEnabled: Bool
    let delivery: String
    let favoritesOnly: Bool
}

private struct GameSubBody: Encodable {
    let deviceId: String
    let eventId: String
    let subscribed: Bool
}

struct AlertsRequestError: Error {
    let message: String
}

enum AlertsNetworkRepository {

    /// Full-state upsert - prefs, leagues and the favorites snapshot all go
    /// up together on every change, matching alertStore.ts's deliberate
    /// "replace wholesale, never merge" contract (so a team unfavorited
    /// on-device can't linger server-side and keep firing alerts).
    static func registerDevice(
        deviceId: String,
        fcmToken: String?,
        leagues: [LeagueGroup],
        favorites: [FavoriteTeam],
        closeSwingEnabled: Bool,
        delivery: AlertDelivery,
        favoritesOnly: Bool
    ) async throws {
        let body = RegisterDeviceBody(
            deviceId: deviceId,
            fcmToken: fcmToken,
            leagues: leagues.map(\.apiValue),
            favorites: favorites.map {
                AlertFavoriteBody(teamName: $0.team.name, leagueGroup: $0.leagueGroup.apiValue)
            },
            closeSwingEnabled: closeSwingEnabled,
            delivery: delivery.apiValue,
            favoritesOnly: favoritesOnly
        )
        try await post("/alerts/register", body: body)
    }

    /// The per-game bell. Subscribing an already-belled game (or
    /// unsubscribing an unbelled one) is a harmless server-side no-op, so
    /// callers can fire-and-forget toggles.
    static func setGameSub(deviceId: String, eventId: String, subscribed: Bool) async throws {
        try await post("/alerts/game-sub", body: GameSubBody(deviceId: deviceId, eventId: eventId, subscribed: subscribed))
    }

    private static func post<Body: Encodable>(_ path: String, body: Body) async throws {
        guard let url = URL(string: "\(backendBaseURL)\(path)") else {
            throw AlertsRequestError(message: "Bad URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Matches the Android client's 45s timeout - headroom for Render
        // waking from a cold start rather than a real network problem.
        request.timeoutInterval = 45
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AlertsRequestError(message: "No response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw AlertsRequestError(message: "Alerts backend returned HTTP \(http.statusCode): \(detail)")
        }
    }
}
