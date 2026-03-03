import Foundation

struct XBookmark: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let authorUsername: String?
    let createdAt: Date?

    var tweetURL: URL? {
        URL(string: "https://x.com/i/web/status/\(id)")
    }
}

@MainActor
final class XBookmarksSyncService: ObservableObject {
    @Published var bearerToken: String
    @Published var userId: String
    @Published private(set) var bookmarks: [XBookmark]
    @Published private(set) var lastSyncError: String?
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var isSyncing = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bearerToken = defaults.string(forKey: Self.bearerTokenKey) ?? ""
        userId = defaults.string(forKey: Self.userIdKey) ?? ""

        if let data = defaults.data(forKey: Self.bookmarksKey),
           let decoded = try? JSONDecoder().decode([XBookmark].self, from: data) {
            bookmarks = decoded
        } else {
            bookmarks = []
        }

        lastSyncedAt = defaults.object(forKey: Self.lastSyncedAtKey) as? Date
    }

    func syncBookmarks() async {
        let trimmedToken = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedToken.isEmpty, !trimmedUserId.isEmpty else {
            lastSyncError = "Add your X API bearer token and user id before syncing."
            return
        }

        isSyncing = true
        lastSyncError = nil
        persistCredentials(token: trimmedToken, userId: trimmedUserId)

        defer { isSyncing = false }

        do {
            let synced = try await fetchBookmarks(userId: trimmedUserId, bearerToken: trimmedToken)
            bookmarks = synced
            lastSyncedAt = Date()
            persistBookmarks()
            defaults.set(lastSyncedAt, forKey: Self.lastSyncedAtKey)
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    private func fetchBookmarks(userId: String, bearerToken: String) async throws -> [XBookmark] {
        var components = URLComponents(string: "https://api.x.com/2/users/\(userId)/bookmarks")
        components?.queryItems = [
            URLQueryItem(name: "max_results", value: "100"),
            URLQueryItem(name: "tweet.fields", value: "created_at,author_id,text"),
            URLQueryItem(name: "expansions", value: "author_id"),
            URLQueryItem(name: "user.fields", value: "username")
        ]

        guard let url = components?.url else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let serverError = try? JSONDecoder().decode(XErrorResponse.self, from: data)
            throw SyncError.requestFailed(statusCode: httpResponse.statusCode, message: serverError?.title ?? serverError?.detail)
        }

        let decoded = try JSONDecoder.xAPI.decode(XBookmarksResponse.self, from: data)
        let usersById = Dictionary(uniqueKeysWithValues: (decoded.includes?.users ?? []).map { ($0.id, $0.username) })

        return decoded.data.map {
            XBookmark(
                id: $0.id,
                text: $0.text,
                authorUsername: $0.authorId.flatMap { usersById[$0] },
                createdAt: $0.createdAt
            )
        }
    }

    private func persistCredentials(token: String, userId: String) {
        defaults.set(token, forKey: Self.bearerTokenKey)
        defaults.set(userId, forKey: Self.userIdKey)
    }

    private func persistBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            defaults.set(data, forKey: Self.bookmarksKey)
        }
    }

    private enum SyncError: LocalizedError {
        case invalidURL
        case invalidResponse
        case requestFailed(statusCode: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Could not build the X Bookmarks API URL."
            case .invalidResponse:
                return "X returned an unreadable response."
            case let .requestFailed(statusCode, message):
                if let message {
                    return "X sync failed (\(statusCode)): \(message)"
                }

                return "X sync failed with status code \(statusCode)."
            }
        }
    }

    private static let bearerTokenKey = "xBookmarksBearerToken"
    private static let userIdKey = "xBookmarksUserId"
    private static let bookmarksKey = "xBookmarksCachedItems"
    private static let lastSyncedAtKey = "xBookmarksLastSyncedAt"
}

private struct XBookmarksResponse: Decodable {
    let data: [XTweet]
    let includes: Includes?

    struct Includes: Decodable {
        let users: [XUser]
    }

    struct XTweet: Decodable {
        let id: String
        let text: String
        let authorId: String?
        let createdAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case text
            case authorId = "author_id"
            case createdAt = "created_at"
        }
    }

    struct XUser: Decodable {
        let id: String
        let username: String
    }
}

private struct XErrorResponse: Decodable {
    let title: String?
    let detail: String?
}

private extension JSONDecoder {
    static var xAPI: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
