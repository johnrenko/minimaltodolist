import Foundation
import AuthenticationServices
import CryptoKit
import Network
import Security

struct XBookmark: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let authorUsername: String?
    let createdAt: Date?

    var tweetURL: URL? {
        if let authorUsername {
            let encodedUsername = authorUsername.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? authorUsername
            return URL(string: "https://x.com/\(encodedUsername)/status/\(id)")
        }

        return URL(string: "https://x.com/i/web/status/\(id)")
    }
}

enum XBookmarksUpdateSource: String, Codable {
    case xAPI = "x-api"
    case chromeExtension = "chrome-extension"
}

struct XBookmarksImportResult: Equatable {
    let importedCount: Int
    let totalCount: Int
    let replacedExisting: Bool
}

@MainActor
final class XBookmarksSyncService: ObservableObject {
    @Published var clientId: String {
        didSet {
            defaults.set(clientId, forKey: Self.clientIdKey)

            if activeTokenBundle == nil {
                authenticatedUser = nil
            }
        }
    }

    @Published private(set) var bookmarks: [XBookmark]
    @Published private(set) var lastSyncError: String?
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var isSyncing = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var authenticatedUser: AuthenticatedUser?
    @Published private(set) var updateSource: XBookmarksUpdateSource?
    @Published private(set) var isExtensionImportServerRunning = false

    var isAuthorized: Bool {
        activeTokenBundle != nil
    }

    var redirectURI: String {
        Self.callbackURL.absoluteString
    }

    var extensionImportEndpoint: String {
        Self.extensionImportURL.absoluteString
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let presentationContextProvider = AuthenticationPresentationContextProvider()

    private var tokenBundle: OAuthTokenBundle?
    private var authenticationSession: ASWebAuthenticationSession?
    private var extensionImportServer: LoopbackBookmarkImportServer?

    init(defaults: UserDefaults = .standard, keychainService: String? = nil) {
        self.defaults = defaults
        keychain = KeychainStore(service: keychainService ?? Bundle.main.bundleIdentifier ?? "MinimalTodo.XBookmarks")
        clientId = defaults.string(forKey: Self.clientIdKey) ?? ""

        if let data = defaults.data(forKey: Self.bookmarksKey),
           let decoded = try? JSONDecoder().decode([XBookmark].self, from: data) {
            bookmarks = decoded
        } else {
            bookmarks = []
        }

        lastSyncedAt = defaults.object(forKey: Self.lastSyncedAtKey) as? Date
        authenticatedUser = Self.loadAuthenticatedUser(from: defaults)
        updateSource = defaults.string(forKey: Self.lastUpdateSourceKey).flatMap(XBookmarksUpdateSource.init(rawValue:))
        tokenBundle = try? Self.loadTokenBundle(from: keychain)

        if activeTokenBundle == nil {
            authenticatedUser = nil
        }
    }

    func setPresentationAnchor(_ anchor: ASPresentationAnchor?) {
        presentationContextProvider.anchor = anchor
    }

    func startExtensionImportListenerIfNeeded() {
        guard extensionImportServer == nil else {
            isExtensionImportServerRunning = true
            return
        }

        do {
            let server = LoopbackBookmarkImportServer(port: Self.extensionImportPort) { [weak self] request in
                guard let self else {
                    return .json(statusCode: 503, jsonObject: [
                        "status": "error",
                        "message": "MinimalTodo is unavailable."
                    ])
                }

                return await self.handleLoopbackRequest(request)
            }

            try server.start()
            extensionImportServer = server
            isExtensionImportServerRunning = true
        } catch {
            isExtensionImportServerRunning = false
            lastSyncError = "Could not start the Chrome extension sync listener: \(error.localizedDescription)"
        }
    }

    func connectAndSyncBookmarks() async {
        if isAuthorized {
            await syncBookmarks()
        } else {
            await authorizeAndSync()
        }
    }

    func syncBookmarks() async {
        let trimmedClientId = trimmedClientId

        guard !trimmedClientId.isEmpty else {
            lastSyncError = "Add your X OAuth client ID before syncing."
            return
        }

        guard activeTokenBundle != nil else {
            lastSyncError = tokenBundle == nil
                ? "Connect your X account before syncing bookmarks."
                : "Reconnect X to refresh this session for the current client ID."
            return
        }

        isSyncing = true
        lastSyncError = nil

        defer { isSyncing = false }

        do {
            let accessToken = try await validAccessToken(clientId: trimmedClientId)
            let authenticatedUser = try await fetchAuthenticatedUser(clientId: trimmedClientId, accessToken: accessToken)
            persistAuthenticatedUser(authenticatedUser)

            let synced = try await fetchAllBookmarks(
                userId: authenticatedUser.id,
                clientId: trimmedClientId,
                accessToken: accessToken
            )

            bookmarks = synced
            lastSyncedAt = Date()
            persistBookmarks()
            defaults.set(lastSyncedAt, forKey: Self.lastSyncedAtKey)
            persistUpdateSource(.xAPI)
        } catch SyncError.authorizationCancelled {
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    func disconnect() async {
        let currentClientId = trimmedClientId
        let currentTokenBundle = activeTokenBundle

        clearAuthorization(preserveClientID: true, clearBookmarks: true)

        guard !currentClientId.isEmpty, let currentTokenBundle else {
            return
        }

        if let refreshToken = currentTokenBundle.refreshToken, !refreshToken.isEmpty {
            try? await revoke(token: refreshToken, clientId: currentClientId, tokenTypeHint: "refresh_token")
        } else {
            try? await revoke(token: currentTokenBundle.accessToken, clientId: currentClientId, tokenTypeHint: "access_token")
        }
    }

    private func authorizeAndSync() async {
        let trimmedClientId = trimmedClientId

        guard !trimmedClientId.isEmpty else {
            lastSyncError = "Add your X OAuth client ID before connecting."
            return
        }

        guard presentationContextProvider.anchor != nil else {
            lastSyncError = "Reopen the menu and try Connect X again."
            return
        }

        isAuthenticating = true
        lastSyncError = nil

        defer {
            isAuthenticating = false
            authenticationSession = nil
        }

        do {
            let authorization = try await requestAuthorizationCode(clientId: trimmedClientId)
            let tokenResponse = try await exchangeAuthorizationCode(
                authorization.code,
                clientId: trimmedClientId,
                codeVerifier: authorization.codeVerifier
            )

            try persistTokenResponse(tokenResponse, clientId: trimmedClientId)
            await syncBookmarks()
        } catch SyncError.authorizationCancelled {
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    private var trimmedClientId: String {
        clientId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeTokenBundle: OAuthTokenBundle? {
        guard let tokenBundle else {
            return nil
        }

        let trimmedClientId = trimmedClientId

        guard !trimmedClientId.isEmpty, tokenBundle.clientId == trimmedClientId else {
            return nil
        }

        return tokenBundle
    }

    private func requestAuthorizationCode(clientId: String) async throws -> AuthorizationCodeGrant {
        let state = Self.randomURLSafeString(length: 48)
        let codeVerifier = Self.randomURLSafeString(length: 64)

        var components = URLComponents(string: "https://x.com/i/oauth2/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: Self.callbackURL.absoluteString),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let url = components?.url else {
            throw SyncError.invalidURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { [weak self] callbackURL, error in
                self?.authenticationSession = nil

                if let sessionError = error as? ASWebAuthenticationSessionError, sessionError.code == .canceledLogin {
                    continuation.resume(throwing: SyncError.authorizationCancelled)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: SyncError.invalidCallback)
                    return
                }

                do {
                    let code = try Self.authorizationCode(from: callbackURL, expectedState: state)
                    continuation.resume(returning: AuthorizationCodeGrant(code: code, codeVerifier: codeVerifier))
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            session.presentationContextProvider = presentationContextProvider
            session.prefersEphemeralWebBrowserSession = false
            authenticationSession = session

            guard session.start() else {
                authenticationSession = nil
                continuation.resume(throwing: SyncError.unableToStartAuthentication)
                return
            }
        }
    }

    private func exchangeAuthorizationCode(
        _ code: String,
        clientId: String,
        codeVerifier: String
    ) async throws -> XOAuthTokenResponse {
        guard let url = URL(string: "https://api.x.com/2/oauth2/token") else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncodedBody([
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: Self.callbackURL.absoluteString),
            URLQueryItem(name: "code_verifier", value: codeVerifier)
        ])

        let data = try await sendRequest(request)
        return try JSONDecoder().decode(XOAuthTokenResponse.self, from: data)
    }

    private func validAccessToken(clientId: String) async throws -> String {
        guard let activeTokenBundle else {
            throw SyncError.missingAuthorization
        }

        if let expiresAt = activeTokenBundle.expiresAt, expiresAt.timeIntervalSinceNow < 60 {
            return try await refreshAccessToken(clientId: clientId)
        }

        return activeTokenBundle.accessToken
    }

    private func refreshAccessToken(clientId: String) async throws -> String {
        guard let refreshToken = activeTokenBundle?.refreshToken, !refreshToken.isEmpty else {
            clearAuthorization(preserveClientID: true, clearBookmarks: false)
            throw SyncError.sessionExpired
        }

        guard let url = URL(string: "https://api.x.com/2/oauth2/token") else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncodedBody([
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: clientId)
        ])

        do {
            let data = try await sendRequest(request)
            let response = try JSONDecoder().decode(XOAuthTokenResponse.self, from: data)
            try persistTokenResponse(response, clientId: clientId)
            return response.accessToken
        } catch {
            clearAuthorization(preserveClientID: true, clearBookmarks: false)
            throw SyncError.sessionExpired
        }
    }

    private func fetchAuthenticatedUser(clientId: String, accessToken: String) async throws -> AuthenticatedUser {
        var components = URLComponents(string: "https://api.x.com/2/users/me")
        components?.queryItems = [
            URLQueryItem(name: "user.fields", value: "name,username")
        ]

        guard let url = components?.url else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data = try await sendAuthorizedRequest(request, accessToken: accessToken, clientId: clientId)
        let decoded = try JSONDecoder.xAPI.decode(XAuthenticatedUserResponse.self, from: data)

        guard let authenticatedUser = decoded.data else {
            throw SyncError.invalidResponse
        }

        return authenticatedUser
    }

    private func fetchAllBookmarks(userId: String, clientId: String, accessToken: String) async throws -> [XBookmark] {
        var paginationToken: String?
        var tweets: [XBookmarksResponse.XTweet] = []
        var usersById: [String: String] = [:]

        repeat {
            let response = try await fetchBookmarksPage(
                userId: userId,
                paginationToken: paginationToken,
                clientId: clientId,
                accessToken: accessToken
            )

            tweets.append(contentsOf: response.data ?? [])

            for user in response.includes?.users ?? [] {
                usersById[user.id] = user.username
            }

            paginationToken = response.meta?.nextToken
        } while paginationToken != nil

        return tweets.map {
            XBookmark(
                id: $0.id,
                text: $0.text,
                authorUsername: $0.authorId.flatMap { usersById[$0] },
                createdAt: $0.createdAt
            )
        }
    }

    private func fetchBookmarksPage(
        userId: String,
        paginationToken: String?,
        clientId: String,
        accessToken: String
    ) async throws -> XBookmarksResponse {
        var components = URLComponents(string: "https://api.x.com/2/users/\(userId)/bookmarks")
        components?.queryItems = [
            URLQueryItem(name: "max_results", value: "100"),
            URLQueryItem(name: "tweet.fields", value: "created_at,author_id,text"),
            URLQueryItem(name: "expansions", value: "author_id"),
            URLQueryItem(name: "user.fields", value: "username")
        ]

        if let paginationToken {
            components?.queryItems?.append(URLQueryItem(name: "pagination_token", value: paginationToken))
        }

        guard let url = components?.url else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data = try await sendAuthorizedRequest(request, accessToken: accessToken, clientId: clientId)
        return try JSONDecoder.xAPI.decode(XBookmarksResponse.self, from: data)
    }

    private func sendAuthorizedRequest(
        _ request: URLRequest,
        accessToken: String,
        clientId: String,
        canRetryAfterRefresh: Bool = true
    ) async throws -> Data {
        var authorizedRequest = request
        authorizedRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            return try await sendRequest(authorizedRequest)
        } catch let SyncError.requestFailed(statusCode, _) where statusCode == 401 && canRetryAfterRefresh {
            let refreshedAccessToken = try await refreshAccessToken(clientId: clientId)
            return try await sendAuthorizedRequest(
                request,
                accessToken: refreshedAccessToken,
                clientId: clientId,
                canRetryAfterRefresh: false
            )
        }
    }

    private func sendRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let serverError = try? JSONDecoder().decode(XAPIErrorResponse.self, from: data)
            throw SyncError.requestFailed(statusCode: httpResponse.statusCode, message: serverError?.bestMessage)
        }

        return data
    }

    private func revoke(token: String, clientId: String, tokenTypeHint: String) async throws {
        guard let url = URL(string: "https://api.x.com/2/oauth2/revoke") else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncodedBody([
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "token_type_hint", value: tokenTypeHint)
        ])

        _ = try await sendRequest(request)
    }

    private func persistTokenResponse(_ tokenResponse: XOAuthTokenResponse, clientId: String) throws {
        let tokenBundle = OAuthTokenBundle(
            clientId: clientId,
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            tokenType: tokenResponse.tokenType,
            scope: tokenResponse.scope,
            expiresAt: tokenResponse.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )

        do {
            let encoded = try JSONEncoder().encode(tokenBundle)
            try keychain.set(encoded, account: Self.tokenKey)
            self.tokenBundle = tokenBundle
        } catch {
            throw SyncError.keychainFailure
        }
    }

    private static func loadTokenBundle(from keychain: KeychainStore) throws -> OAuthTokenBundle? {
        guard let data = try keychain.data(for: tokenKey) else {
            return nil
        }

        return try JSONDecoder().decode(OAuthTokenBundle.self, from: data)
    }

    private func persistAuthenticatedUser(_ authenticatedUser: AuthenticatedUser) {
        self.authenticatedUser = authenticatedUser
        defaults.set(authenticatedUser.id, forKey: Self.authenticatedUserIdKey)
        defaults.set(authenticatedUser.username, forKey: Self.authenticatedUsernameKey)
        defaults.set(authenticatedUser.name, forKey: Self.authenticatedNameKey)
    }

    private static func loadAuthenticatedUser(from defaults: UserDefaults) -> AuthenticatedUser? {
        guard let id = defaults.string(forKey: authenticatedUserIdKey),
              let username = defaults.string(forKey: authenticatedUsernameKey),
              let name = defaults.string(forKey: authenticatedNameKey) else {
            return nil
        }

        return AuthenticatedUser(id: id, name: name, username: username)
    }

    private func clearAuthorization(preserveClientID: Bool, clearBookmarks: Bool) {
        authenticatedUser = nil
        tokenBundle = nil
        lastSyncError = nil
        authenticationSession?.cancel()
        authenticationSession = nil

        defaults.removeObject(forKey: Self.authenticatedUserIdKey)
        defaults.removeObject(forKey: Self.authenticatedUsernameKey)
        defaults.removeObject(forKey: Self.authenticatedNameKey)

        try? keychain.remove(account: Self.tokenKey)

        if !preserveClientID {
            clientId = ""
        }

        if clearBookmarks {
            bookmarks = []
            lastSyncedAt = nil
            persistUpdateSource(nil)
            defaults.removeObject(forKey: Self.bookmarksKey)
            defaults.removeObject(forKey: Self.lastSyncedAtKey)
        }
    }

    private func persistBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            defaults.set(data, forKey: Self.bookmarksKey)
        }
    }

    private static func authorizationCode(from url: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SyncError.invalidCallback
        }

        let parameters = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        if let error = parameters["error"], !error.isEmpty {
            let message = parameters["error_description"].flatMap { $0.isEmpty ? nil : $0 } ?? error
            throw SyncError.authorizationRejected(message: message)
        }

        guard parameters["state"] == expectedState else {
            throw SyncError.stateMismatch
        }

        guard let code = parameters["code"], !code.isEmpty else {
            throw SyncError.invalidCallback
        }

        return code
    }

    private static func formEncodedBody(_ queryItems: [URLQueryItem]) -> Data? {
        var components = URLComponents()
        components.queryItems = queryItems
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private static func codeChallenge(for codeVerifier: String) -> String {
        let digest = SHA256.hash(data: Data(codeVerifier.utf8))
        return Self.base64URLEncodedString(Data(digest))
    }

    private static func base64URLEncodedString(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func randomURLSafeString(length: Int) -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }

    @discardableResult
    func importBookmarksFromExtension(_ payloadData: Data) throws -> XBookmarksImportResult {
        let payload = try JSONDecoder.xAPI.decode(ChromeExtensionBookmarksPayload.self, from: payloadData)
        let importedBookmarks = payload.bookmarks.compactMap(Self.extensionBookmark(from:))

        guard !importedBookmarks.isEmpty else {
            throw SyncError.noImportedBookmarks
        }

        let replacedExisting = payload.replaceExisting ?? false
        let nextBookmarks: [XBookmark]

        if replacedExisting {
            nextBookmarks = Self.sortedBookmarks(Self.deduplicatedBookmarks(importedBookmarks))
        } else {
            nextBookmarks = Self.mergeBookmarks(existing: bookmarks, imported: importedBookmarks)
        }

        bookmarks = nextBookmarks
        lastSyncedAt = payload.exportedAt ?? Date()
        lastSyncError = nil
        persistBookmarks()
        defaults.set(lastSyncedAt, forKey: Self.lastSyncedAtKey)
        persistUpdateSource(.chromeExtension)

        return XBookmarksImportResult(
            importedCount: importedBookmarks.count,
            totalCount: nextBookmarks.count,
            replacedExisting: replacedExisting
        )
    }

    private func handleLoopbackRequest(_ request: LoopbackHTTPRequest) async -> LoopbackHTTPResponse {
        switch (request.method, request.path) {
        case ("OPTIONS", _):
            return .noContent()
        case ("GET", Self.extensionImportHealthPath):
            var response: [String: Any] = [
                "status": "ok",
                "ready": isExtensionImportServerRunning,
                "bookmarkCount": bookmarks.count,
                "bookmarkIDs": bookmarks.map(\.id)
            ]
            response["updateSource"] = updateSource?.rawValue ?? NSNull()
            return .json(statusCode: 200, jsonObject: response)
        case ("POST", Self.extensionImportPath):
            do {
                let result = try importBookmarksFromExtension(request.body)
                return .json(statusCode: 200, jsonObject: [
                    "status": "ok",
                    "importedCount": result.importedCount,
                    "totalCount": result.totalCount,
                    "replacedExisting": result.replacedExisting
                ])
            } catch {
                return .json(statusCode: 400, jsonObject: [
                    "status": "error",
                    "message": error.localizedDescription
                ])
            }
        default:
            return .json(statusCode: 404, jsonObject: [
                "status": "error",
                "message": "Not found."
            ])
        }
    }

    private func persistUpdateSource(_ source: XBookmarksUpdateSource?) {
        updateSource = source

        if let source {
            defaults.set(source.rawValue, forKey: Self.lastUpdateSourceKey)
        } else {
            defaults.removeObject(forKey: Self.lastUpdateSourceKey)
        }
    }

    private static func extensionBookmark(from imported: ChromeExtensionBookmarksPayload.Bookmark) -> XBookmark? {
        let id = imported.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            return nil
        }

        let text = imported.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedText = text.isEmpty ? "Saved post" : text
        let normalizedUsername = imported.authorUsername?
            .trimmingCharacters(in: CharacterSet(charactersIn: "@/").union(.whitespacesAndNewlines))

        return XBookmark(
            id: id,
            text: normalizedText,
            authorUsername: normalizedUsername?.isEmpty == false ? normalizedUsername : nil,
            createdAt: imported.createdAt
        )
    }

    private static func mergeBookmarks(existing: [XBookmark], imported: [XBookmark]) -> [XBookmark] {
        var bookmarksByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        for bookmark in imported {
            if let existingBookmark = bookmarksByID[bookmark.id] {
                bookmarksByID[bookmark.id] = XBookmark(
                    id: bookmark.id,
                    text: bookmark.text.isEmpty ? existingBookmark.text : bookmark.text,
                    authorUsername: bookmark.authorUsername ?? existingBookmark.authorUsername,
                    createdAt: bookmark.createdAt ?? existingBookmark.createdAt
                )
            } else {
                bookmarksByID[bookmark.id] = bookmark
            }
        }

        return sortedBookmarks(Array(bookmarksByID.values))
    }

    private static func deduplicatedBookmarks(_ bookmarks: [XBookmark]) -> [XBookmark] {
        mergeBookmarks(existing: [], imported: bookmarks)
    }

    private static func sortedBookmarks(_ bookmarks: [XBookmark]) -> [XBookmark] {
        bookmarks.sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (leftDate?, rightDate?) where leftDate != rightDate:
                return leftDate > rightDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.id > rhs.id
            }
        }
    }

    private static let clientIdKey = "xBookmarksClientId"
    private static let tokenKey = "xBookmarksOAuthTokens"
    private static let bookmarksKey = "xBookmarksCachedItems"
    private static let lastSyncedAtKey = "xBookmarksLastSyncedAt"
    private static let lastUpdateSourceKey = "xBookmarksLastUpdateSource"
    private static let authenticatedUserIdKey = "xBookmarksAuthenticatedUserId"
    private static let authenticatedUsernameKey = "xBookmarksAuthenticatedUsername"
    private static let authenticatedNameKey = "xBookmarksAuthenticatedName"
    private static let callbackScheme = "minimaltodo"
    private static let callbackURL = URL(string: "minimaltodo://x-auth")!
    private static let extensionImportPort: UInt16 = 48123
    private static let extensionImportPath = "/x-bookmarks/import"
    private static let extensionImportHealthPath = "/x-bookmarks/health"
    private static let extensionImportURL = URL(string: "http://127.0.0.1:48123/x-bookmarks/import")!
    private static let scopes = ["tweet.read", "users.read", "bookmark.read", "offline.access"]
}

private struct ChromeExtensionBookmarksPayload: Decodable {
    let exportedAt: Date?
    let replaceExisting: Bool?
    let bookmarks: [Bookmark]

    struct Bookmark: Decodable {
        let id: String
        let text: String
        let authorUsername: String?
        let createdAt: Date?
    }
}

private struct XOAuthTokenResponse: Decodable {
    let tokenType: String
    let expiresIn: Int?
    let accessToken: String
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case scope
    }
}

private struct OAuthTokenBundle: Codable {
    let clientId: String
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let scope: String?
    let expiresAt: Date?
}

struct AuthenticatedUser: Codable, Equatable {
    let id: String
    let name: String
    let username: String
}

private struct XAuthenticatedUserResponse: Decodable {
    let data: AuthenticatedUser?
}

private struct XBookmarksResponse: Decodable {
    let data: [XTweet]?
    let includes: Includes?
    let meta: Meta?

    struct Includes: Decodable {
        let users: [XUser]
    }

    struct Meta: Decodable {
        let nextToken: String?

        enum CodingKeys: String, CodingKey {
            case nextToken = "next_token"
        }
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

private struct XAPIErrorResponse: Decodable {
    let title: String?
    let detail: String?
    let error: String?
    let errorDescription: String?
    let errors: [NestedError]?

    enum CodingKeys: String, CodingKey {
        case title
        case detail
        case error
        case errorDescription = "error_description"
        case errors
    }

    struct NestedError: Decodable {
        let title: String?
        let detail: String?
        let message: String?
    }

    var bestMessage: String? {
        errorDescription
            ?? detail
            ?? title
            ?? errors?.compactMap { $0.detail ?? $0.title ?? $0.message }.first
            ?? error
    }
}

private enum SyncError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingAuthorization
    case noImportedBookmarks
    case unableToStartAuthentication
    case invalidCallback
    case stateMismatch
    case authorizationRejected(message: String)
    case authorizationCancelled
    case sessionExpired
    case requestFailed(statusCode: Int, message: String?)
    case keychainFailure

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not build the X API request."
        case .invalidResponse:
            return "X returned an unreadable response."
        case .missingAuthorization:
            return "Connect your X account before syncing bookmarks."
        case .noImportedBookmarks:
            return "No bookmarks were found in the Chrome import."
        case .unableToStartAuthentication:
            return "Could not open the X sign-in flow."
        case .invalidCallback:
            return "X did not return a usable authorization code."
        case .stateMismatch:
            return "X returned an invalid OAuth state value."
        case let .authorizationRejected(message):
            return "X authorization failed: \(message)"
        case .authorizationCancelled:
            return "The X sign-in flow was cancelled."
        case .sessionExpired:
            return "Your X session expired. Connect X again to keep syncing."
        case let .requestFailed(statusCode, message):
            if let message, !message.isEmpty {
                return "X request failed (\(statusCode)): \(message)"
            }

            return "X request failed with status code \(statusCode)."
        case .keychainFailure:
            return "Could not store the X session securely in Keychain."
        }
    }
}

private enum XDateParser {
    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let legacyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        return formatter
    }()

    static func decode(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        if let date = iso8601WithFractionalSeconds.date(from: rawValue)
            ?? iso8601.date(from: rawValue)
            ?? legacyFormatter.date(from: rawValue) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported X API date format: \(rawValue)"
        )
    }
}

private extension JSONDecoder {
    static var xAPI: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try XDateParser.decode(decoder)
        }
        return decoder
    }
}

private struct AuthorizationCodeGrant {
    let code: String
    let codeVerifier: String
}

private final class AuthenticationPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    var anchor: ASPresentationAnchor?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }
}

private struct KeychainStore {
    let service: String

    func data(for account: String) throws -> Data? {
        var result: CFTypeRef?
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    func set(_ data: Data, account: String) throws {
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account
            ]

            let update: [CFString: Any] = [
                kSecValueData: data
            ]

            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

            guard updateStatus == errSecSuccess else {
                throw KeychainStoreError.unexpectedStatus(updateStatus)
            }

            return
        }

        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    func remove(account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }
}

private enum KeychainStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            return "Keychain error \(status)."
        }
    }
}

private struct LoopbackHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    enum ParseResult {
        case incomplete
        case success(LoopbackHTTPRequest)
        case failure(statusCode: Int, message: String)
    }

    private static let headerDelimiter = Data("\r\n\r\n".utf8)

    static func parse(from buffer: Data, maxBodyBytes: Int, maxHeaderBytes: Int) -> ParseResult {
        guard let headerRange = buffer.range(of: headerDelimiter) else {
            if buffer.count > maxHeaderBytes {
                return .failure(statusCode: 431, message: "Request headers are too large.")
            }

            return .incomplete
        }

        let headerData = buffer[..<headerRange.lowerBound]

        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .failure(statusCode: 400, message: "Request headers were not valid UTF-8.")
        }

        let lines = headerText.components(separatedBy: "\r\n")

        guard let requestLine = lines.first else {
            return .failure(statusCode: 400, message: "Missing HTTP request line.")
        }

        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)

        guard requestParts.count >= 2 else {
            return .failure(statusCode: 400, message: "Malformed HTTP request line.")
        }

        let method = String(requestParts[0]).uppercased()
        let target = String(requestParts[1])
        var headers: [String: String] = [:]

        for line in lines.dropFirst() where !line.isEmpty {
            let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)

            guard pieces.count == 2 else {
                return .failure(statusCode: 400, message: "Malformed HTTP header.")
            }

            let name = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        let contentLength: Int

        if let contentLengthValue = headers["content-length"] {
            guard let parsedContentLength = Int(contentLengthValue), parsedContentLength >= 0 else {
                return .failure(statusCode: 400, message: "Invalid Content-Length header.")
            }

            contentLength = parsedContentLength
        } else {
            contentLength = 0
        }

        guard contentLength <= maxBodyBytes else {
            return .failure(statusCode: 413, message: "Request body exceeds the supported size limit.")
        }

        let bodyStart = headerRange.upperBound
        let expectedByteCount = bodyStart + contentLength

        guard buffer.count >= expectedByteCount else {
            return .incomplete
        }

        let requestBody = Data(buffer[bodyStart..<expectedByteCount])
        let path = normalizedPath(from: target)

        return .success(
            LoopbackHTTPRequest(
                method: method,
                path: path,
                headers: headers,
                body: requestBody
            )
        )
    }

    private static func normalizedPath(from target: String) -> String {
        if let absoluteURL = URL(string: target), let host = absoluteURL.host, !host.isEmpty {
            let path = absoluteURL.path.isEmpty ? "/" : absoluteURL.path

            if let query = absoluteURL.query, !query.isEmpty {
                return "\(path)?\(query)"
            }

            return path
        }

        guard let components = URLComponents(string: "http://127.0.0.1\(target)") else {
            return target
        }

        let path = components.path.isEmpty ? "/" : components.path

        if let query = components.query, !query.isEmpty {
            return "\(path)?\(query)"
        }

        return path
    }
}

private struct LoopbackHTTPResponse {
    let statusCode: Int
    let reasonPhrase: String
    let headers: [String: String]
    let body: Data

    static func json(statusCode: Int, jsonObject: Any) -> LoopbackHTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])) ?? Data()
        return LoopbackHTTPResponse(
            statusCode: statusCode,
            reasonPhrase: statusText(for: statusCode),
            headers: [
                "Content-Type": "application/json; charset=utf-8"
            ],
            body: body
        )
    }

    static func noContent() -> LoopbackHTTPResponse {
        LoopbackHTTPResponse(
            statusCode: 204,
            reasonPhrase: statusText(for: 204),
            headers: [:],
            body: Data()
        )
    }

    func serialized() -> Data {
        var serializedHeaders = headers
        serializedHeaders["Access-Control-Allow-Origin"] = "*"
        serializedHeaders["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        serializedHeaders["Access-Control-Allow-Headers"] = "Content-Type"
        serializedHeaders["Connection"] = "close"
        serializedHeaders["Content-Length"] = "\(body.count)"

        var responseText = "HTTP/1.1 \(statusCode) \(reasonPhrase)\r\n"

        for (name, value) in serializedHeaders.sorted(by: { $0.key < $1.key }) {
            responseText.append("\(name): \(value)\r\n")
        }

        responseText.append("\r\n")

        var output = Data(responseText.utf8)
        output.append(body)
        return output
    }

    private static func statusText(for statusCode: Int) -> String {
        switch statusCode {
        case 200:
            return "OK"
        case 204:
            return "No Content"
        case 400:
            return "Bad Request"
        case 404:
            return "Not Found"
        case 413:
            return "Payload Too Large"
        case 431:
            return "Request Header Fields Too Large"
        case 500:
            return "Internal Server Error"
        case 503:
            return "Service Unavailable"
        default:
            return "HTTP Response"
        }
    }
}

private final class LoopbackBookmarkImportServer {
    private let port: UInt16
    private let requestHandler: @Sendable (LoopbackHTTPRequest) async -> LoopbackHTTPResponse
    private let queue = DispatchQueue(label: "MinimalTodo.XBookmarksLoopbackServer")
    private var listener: NWListener?

    private static let maxBodyBytes = 4 * 1024 * 1024
    private static let maxHeaderBytes = 32 * 1024
    private static let receiveChunkSize = 64 * 1024

    init(
        port: UInt16,
        requestHandler: @escaping @Sendable (LoopbackHTTPRequest) async -> LoopbackHTTPResponse
    ) {
        self.port = port
        self.requestHandler = requestHandler
    }

    func start() throws {
        guard listener == nil else {
            return
        }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw SyncError.invalidURL
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)

        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { state in
            if case let .failed(error) = state {
                NSLog("MinimalTodo X import listener failed: %@", String(describing: error))
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.configure(connection)
        }

        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func configure(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }

        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.receiveChunkSize) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var nextBuffer = buffer

            if let data, !data.isEmpty {
                nextBuffer.append(data)
            }

            switch LoopbackHTTPRequest.parse(
                from: nextBuffer,
                maxBodyBytes: Self.maxBodyBytes,
                maxHeaderBytes: Self.maxHeaderBytes
            ) {
            case .success(let request):
                Task {
                    let response = await self.requestHandler(request)
                    self.send(response, on: connection)
                }
            case .failure(let statusCode, let message):
                let response = LoopbackHTTPResponse.json(statusCode: statusCode, jsonObject: [
                    "status": "error",
                    "message": message
                ])
                send(response, on: connection)
            case .incomplete:
                if let error {
                    let response = LoopbackHTTPResponse.json(statusCode: 400, jsonObject: [
                        "status": "error",
                        "message": error.localizedDescription
                    ])
                    send(response, on: connection)
                } else if isComplete {
                    let response = LoopbackHTTPResponse.json(statusCode: 400, jsonObject: [
                        "status": "error",
                        "message": "The request ended before the full payload was received."
                    ])
                    send(response, on: connection)
                } else {
                    receive(on: connection, buffer: nextBuffer)
                }
            }
        }
    }

    private func send(_ response: LoopbackHTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
