import Combine
import Foundation
import Security

struct ClaudeUsageSnapshot: Sendable, Equatable {
    let fiveHourUsagePercent: Int
    let weeklyUsagePercent: Int
    let fiveHourResetAt: Date?
    let weeklyResetAt: Date?
    let refreshedAt: Date
}

struct ClaudeCodeOAuthCredentials: Decodable, Sendable, Equatable {
    let accessToken: String
    let expiresAt: Date?
    let subscriptionType: String?
    let rateLimitTier: String?
}

struct ClaudeUsageResponse: Decodable, Sendable, Equatable {
    let fiveHour: ClaudeUsageWindow
    let sevenDay: ClaudeUsageWindow

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

struct ClaudeUsageWindow: Decodable, Sendable, Equatable {
    let utilization: Double?
    let resetsAt: Date?

    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(utilization: Double?, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        utilization = try container.decodeIfPresent(Double.self, forKey: .utilization)

        if let resetAtString = try container.decodeIfPresent(String.self, forKey: .resetsAt) {
            resetsAt = ClaudeUsageParsing.parseISO8601Date(resetAtString)
        } else {
            resetsAt = nil
        }
    }
}

enum ClaudeUsageServiceError: LocalizedError, Equatable {
    case claudeCodeNotInstalled
    case loginNotFound
    case invalidOrExpiredCredentials
    case malformedCredentials
    case malformedUsageResponse
    case keychainAccessFailed
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .claudeCodeNotInstalled:
            return "Install Claude Code and sign in, then refresh."
        case .loginNotFound:
            return "Claude Code login not found on this Mac. Run claude login."
        case .invalidOrExpiredCredentials:
            return "Claude Code credentials are invalid or expired. Run claude login."
        case .malformedCredentials:
            return "Could not read valid Claude Code credentials from Keychain."
        case .malformedUsageResponse:
            return "Could not parse Claude usage returned by Anthropic."
        case .keychainAccessFailed:
            return "Could not access Claude Code credentials in Keychain."
        case .requestFailed(let message):
            return message
        }
    }
}

protocol ClaudeCodeCredentialProviding {
    func loadCredentials() throws -> ClaudeCodeOAuthCredentials
}

protocol ClaudeUsageFetching {
    func fetchUsage(accessToken: String, userAgent: String) async throws -> ClaudeUsageResponse
}

protocol ClaudeCodeAvailabilityChecking {
    func isClaudeCodeInstalled() -> Bool
}

@MainActor
final class ClaudeUsageService: ObservableObject {
    @Published private(set) var snapshot: ClaudeUsageSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var isRefreshing = false

    private let credentialProvider: ClaudeCodeCredentialProviding
    private let usageFetcher: ClaudeUsageFetching
    private let availabilityChecker: ClaudeCodeAvailabilityChecking
    private let now: () -> Date
    private let userAgent: String

    init(
        credentialProvider: ClaudeCodeCredentialProviding = ClaudeKeychainCredentialProvider(),
        usageFetcher: ClaudeUsageFetching = ClaudeOAuthUsageClient(),
        availabilityChecker: ClaudeCodeAvailabilityChecking = ClaudeCodeInstallationChecker(),
        now: @escaping () -> Date = Date.init,
        userAgent: String = ClaudeUsageService.defaultUserAgent()
    ) {
        self.credentialProvider = credentialProvider
        self.usageFetcher = usageFetcher
        self.availabilityChecker = availabilityChecker
        self.now = now
        self.userAgent = userAgent
    }

    func refreshClaudeUsage() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        error = nil

        Task {
            do {
                let snapshot = try await loadSnapshot()
                self.snapshot = snapshot
                error = nil
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.snapshot = nil
                self.error = message
            }

            isRefreshing = false
        }
    }

    func loadSnapshot() async throws -> ClaudeUsageSnapshot {
        let credentials: ClaudeCodeOAuthCredentials

        do {
            credentials = try credentialProvider.loadCredentials()
        } catch ClaudeCredentialProviderError.itemNotFound {
            if availabilityChecker.isClaudeCodeInstalled() {
                throw ClaudeUsageServiceError.loginNotFound
            }

            throw ClaudeUsageServiceError.claudeCodeNotInstalled
        } catch ClaudeCredentialProviderError.invalidPayload {
            throw ClaudeUsageServiceError.malformedCredentials
        } catch ClaudeCredentialProviderError.keychainAccessFailed {
            throw ClaudeUsageServiceError.keychainAccessFailed
        }

        do {
            let response = try await usageFetcher.fetchUsage(
                accessToken: credentials.accessToken,
                userAgent: userAgent
            )

            return ClaudeUsageSnapshot(
                fiveHourUsagePercent: Self.clampedPercentage(response.fiveHour.utilization),
                weeklyUsagePercent: Self.clampedPercentage(response.sevenDay.utilization),
                fiveHourResetAt: response.fiveHour.resetsAt,
                weeklyResetAt: response.sevenDay.resetsAt,
                refreshedAt: now()
            )
        } catch ClaudeUsageAPIClientError.unauthorized {
            throw ClaudeUsageServiceError.invalidOrExpiredCredentials
        } catch ClaudeUsageAPIClientError.invalidResponse {
            throw ClaudeUsageServiceError.malformedUsageResponse
        } catch ClaudeUsageAPIClientError.requestFailed(let message) {
            throw ClaudeUsageServiceError.requestFailed(message)
        }
    }

    nonisolated private static func defaultUserAgent() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "MinimalTodo/\(version)"
    }

    private static func clampedPercentage(_ utilization: Double?) -> Int {
        guard let utilization, utilization.isFinite else {
            return 0
        }

        return Int(utilization.rounded()).clamped(to: 0...100)
    }
}

enum ClaudeUsageParsing {
    static func parseCredentials(data: Data) throws -> ClaudeCodeOAuthCredentials {
        do {
            let payload = try JSONDecoder().decode(ClaudeStoredCredentials.self, from: data)

            guard let credentials = payload.claudeAiOauth,
                  !credentials.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ClaudeCredentialProviderError.invalidPayload
            }

            return credentials
        } catch let error as ClaudeCredentialProviderError {
            throw error
        } catch {
            throw ClaudeCredentialProviderError.invalidPayload
        }
    }

    static func parseUsageResponse(data: Data) throws -> ClaudeUsageResponse {
        do {
            return try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        } catch {
            throw ClaudeUsageAPIClientError.invalidResponse
        }
    }

    static func parseISO8601Date(_ value: String) -> Date? {
        claudeUsageISO8601WithFractionalSeconds.date(from: value) ?? claudeUsageISO8601.date(from: value)
    }
}

private struct ClaudeStoredCredentials: Decodable {
    let claudeAiOauth: ClaudeCodeOAuthCredentials?
}

enum ClaudeCredentialProviderError: Error, Equatable {
    case itemNotFound
    case invalidPayload
    case keychainAccessFailed
}

private struct ClaudeKeychainCredentialProvider: ClaudeCodeCredentialProviding {
    private let service = "Claude Code-credentials"

    func loadCredentials() throws -> ClaudeCodeOAuthCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw ClaudeCredentialProviderError.invalidPayload
            }

            return try ClaudeUsageParsing.parseCredentials(data: data)
        case errSecItemNotFound:
            throw ClaudeCredentialProviderError.itemNotFound
        default:
            throw ClaudeCredentialProviderError.keychainAccessFailed
        }
    }
}

enum ClaudeUsageAPIClientError: Error, Equatable {
    case unauthorized
    case invalidResponse
    case requestFailed(String)
}

private struct ClaudeOAuthUsageClient: ClaudeUsageFetching {
    private let session: URLSession
    private let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchUsage(accessToken: String, userAgent: String) async throws -> ClaudeUsageResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClaudeUsageAPIClientError.requestFailed("Could not fetch Claude usage: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeUsageAPIClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try ClaudeUsageParsing.parseUsageResponse(data: data)
        case 401:
            throw ClaudeUsageAPIClientError.unauthorized
        default:
            throw ClaudeUsageAPIClientError.requestFailed("Could not fetch Claude usage: HTTP \(httpResponse.statusCode).")
        }
    }
}

struct ClaudeCodeInstallationChecker: ClaudeCodeAvailabilityChecking {
    func isClaudeCodeInstalled() -> Bool {
        let fileManager = FileManager.default
        var candidates = Set<String>()

        let pathDirectories = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []

        let commonDirectories = pathDirectories + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin"
        ]

        for directory in commonDirectories {
            candidates.insert(URL(fileURLWithPath: directory).appendingPathComponent("claude").path)
        }

        return candidates.contains { fileManager.isExecutableFile(atPath: $0) }
    }
}

private let claudeUsageISO8601WithFractionalSeconds: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let claudeUsageISO8601: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

extension ClaudeCodeOAuthCredentials {
    enum CodingKeys: String, CodingKey {
        case accessToken
        case expiresAt
        case subscriptionType
        case rateLimitTier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        subscriptionType = try container.decodeIfPresent(String.self, forKey: .subscriptionType)
        rateLimitTier = try container.decodeIfPresent(String.self, forKey: .rateLimitTier)

        if let expiresAtMilliseconds = try container.decodeIfPresent(Double.self, forKey: .expiresAt) {
            expiresAt = Date(timeIntervalSince1970: expiresAtMilliseconds / 1000)
        } else if let expiresAtString = try container.decodeIfPresent(String.self, forKey: .expiresAt) {
            if let numericValue = Double(expiresAtString) {
                expiresAt = Date(timeIntervalSince1970: numericValue / 1000)
            } else {
                expiresAt = ClaudeUsageParsing.parseISO8601Date(expiresAtString)
            }
        } else {
            expiresAt = nil
        }
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
