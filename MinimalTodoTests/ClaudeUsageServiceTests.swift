import XCTest
@testable import MinimalTodo

final class ClaudeUsageServiceTests: XCTestCase {
    func testParseCredentialsReturnsOAuthFields() throws {
        let data = Data(
            """
            {
              "claudeAiOauth": {
                "accessToken": "token-123",
                "expiresAt": 1772760823014,
                "subscriptionType": "team",
                "rateLimitTier": "default_raven"
              }
            }
            """.utf8
        )

        let credentials = try ClaudeUsageParsing.parseCredentials(data: data)

        XCTAssertEqual(credentials.accessToken, "token-123")
        XCTAssertEqual(credentials.subscriptionType, "team")
        XCTAssertEqual(credentials.rateLimitTier, "default_raven")
        XCTAssertNotNil(credentials.expiresAt)
        XCTAssertEqual(credentials.expiresAt?.timeIntervalSince1970 ?? 0, 1_772_760_823.014, accuracy: 0.001)
    }

    func testParseCredentialsRejectsMissingClaudeAiOauth() {
        let data = Data(#"{"mcpOAuth":{"accessToken":"abc"}}"#.utf8)

        XCTAssertThrowsError(try ClaudeUsageParsing.parseCredentials(data: data)) { error in
            XCTAssertEqual(error as? ClaudeCredentialProviderError, .invalidPayload)
        }
    }

    func testParseCredentialsRejectsMalformedJSON() {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"abc"}"#.utf8)

        XCTAssertThrowsError(try ClaudeUsageParsing.parseCredentials(data: data)) { error in
            XCTAssertEqual(error as? ClaudeCredentialProviderError, .invalidPayload)
        }
    }

    func testParseUsageResponseSupportsNullResetTimestamps() throws {
        let data = Data(
            """
            {
              "five_hour": { "utilization": 12.2, "resets_at": null },
              "seven_day": { "utilization": 64, "resets_at": "2026-03-06T13:00:00.378167+00:00" }
            }
            """.utf8
        )

        let response = try ClaudeUsageParsing.parseUsageResponse(data: data)

        XCTAssertEqual(response.fiveHour.utilization, 12.2)
        XCTAssertNil(response.fiveHour.resetsAt)
        XCTAssertEqual(response.sevenDay.utilization, 64)
        XCTAssertEqual(
            response.sevenDay.resetsAt,
            ClaudeUsageParsing.parseISO8601Date("2026-03-06T13:00:00.378167+00:00")
        )
    }

    func testParseUsageResponseIgnoresUnknownFields() throws {
        let data = Data(
            """
            {
              "five_hour": {
                "utilization": 0,
                "resets_at": null,
                "extra_field": "ignored"
              },
              "seven_day": {
                "utilization": 88.6,
                "resets_at": null
              },
              "extra_usage": {
                "monthly_limit": 3000
              }
            }
            """.utf8
        )

        let response = try ClaudeUsageParsing.parseUsageResponse(data: data)

        XCTAssertEqual(response.fiveHour.utilization, 0)
        XCTAssertEqual(response.sevenDay.utilization, 88.6)
    }

    @MainActor
    func testLoadSnapshotBuildsSnapshotFromUsageResponse() async throws {
        let credentials = ClaudeCodeOAuthCredentials(
            accessToken: "token-123",
            expiresAt: nil,
            subscriptionType: "team",
            rateLimitTier: "default_raven"
        )
        let response = ClaudeUsageResponse(
            fiveHour: ClaudeUsageWindow(utilization: 18.6, resetsAt: nil),
            sevenDay: ClaudeUsageWindow(utilization: 63.5, resetsAt: Date(timeIntervalSince1970: 1_772_760_823))
        )
        let now = Date(timeIntervalSince1970: 1_772_000_000)
        let service = ClaudeUsageService(
            credentialProvider: MockCredentialProvider(result: .success(credentials)),
            usageFetcher: MockUsageFetcher(result: .success(response)),
            availabilityChecker: MockClaudeCodeAvailabilityChecker(isInstalled: true),
            now: { now },
            userAgent: "MinimalTodoTests/1.0"
        )

        let snapshot = try await service.loadSnapshot()

        XCTAssertEqual(snapshot.fiveHourUsagePercent, 19)
        XCTAssertEqual(snapshot.weeklyUsagePercent, 64)
        XCTAssertEqual(snapshot.refreshedAt, now)
        XCTAssertEqual(snapshot.weeklyResetAt, Date(timeIntervalSince1970: 1_772_760_823))
    }

    @MainActor
    func testLoadSnapshotMapsMissingLoginWhenClaudeCodeInstalled() async {
        let service = ClaudeUsageService(
            credentialProvider: MockCredentialProvider(result: .failure(ClaudeCredentialProviderError.itemNotFound)),
            usageFetcher: MockUsageFetcher(result: .failure(ClaudeUsageAPIClientError.requestFailed("unused"))),
            availabilityChecker: MockClaudeCodeAvailabilityChecker(isInstalled: true),
            userAgent: "MinimalTodoTests/1.0"
        )

        do {
            _ = try await service.loadSnapshot()
            XCTFail("Expected a login-not-found error.")
        } catch {
            XCTAssertEqual(error as? ClaudeUsageServiceError, .loginNotFound)
        }
    }

    @MainActor
    func testLoadSnapshotMapsMissingInstallWhenClaudeCodeUnavailable() async {
        let service = ClaudeUsageService(
            credentialProvider: MockCredentialProvider(result: .failure(ClaudeCredentialProviderError.itemNotFound)),
            usageFetcher: MockUsageFetcher(result: .failure(ClaudeUsageAPIClientError.requestFailed("unused"))),
            availabilityChecker: MockClaudeCodeAvailabilityChecker(isInstalled: false),
            userAgent: "MinimalTodoTests/1.0"
        )

        do {
            _ = try await service.loadSnapshot()
            XCTFail("Expected a Claude Code install error.")
        } catch {
            XCTAssertEqual(error as? ClaudeUsageServiceError, .claudeCodeNotInstalled)
        }
    }

    @MainActor
    func testLoadSnapshotMapsUnauthorizedToRunClaudeLogin() async {
        let credentials = ClaudeCodeOAuthCredentials(
            accessToken: "token-123",
            expiresAt: nil,
            subscriptionType: nil,
            rateLimitTier: nil
        )
        let service = ClaudeUsageService(
            credentialProvider: MockCredentialProvider(result: .success(credentials)),
            usageFetcher: MockUsageFetcher(result: .failure(ClaudeUsageAPIClientError.unauthorized)),
            availabilityChecker: MockClaudeCodeAvailabilityChecker(isInstalled: true),
            userAgent: "MinimalTodoTests/1.0"
        )

        do {
            _ = try await service.loadSnapshot()
            XCTFail("Expected an invalid-or-expired credentials error.")
        } catch {
            XCTAssertEqual(error as? ClaudeUsageServiceError, .invalidOrExpiredCredentials)
        }
    }

    @MainActor
    func testLoadSnapshotMapsTransportFailureToReadableError() async {
        let credentials = ClaudeCodeOAuthCredentials(
            accessToken: "token-123",
            expiresAt: nil,
            subscriptionType: nil,
            rateLimitTier: nil
        )
        let service = ClaudeUsageService(
            credentialProvider: MockCredentialProvider(result: .success(credentials)),
            usageFetcher: MockUsageFetcher(result: .failure(ClaudeUsageAPIClientError.requestFailed("Could not fetch Claude usage: offline."))),
            availabilityChecker: MockClaudeCodeAvailabilityChecker(isInstalled: true),
            userAgent: "MinimalTodoTests/1.0"
        )

        do {
            _ = try await service.loadSnapshot()
            XCTFail("Expected a readable request failure.")
        } catch {
            XCTAssertEqual(error as? ClaudeUsageServiceError, .requestFailed("Could not fetch Claude usage: offline."))
        }
    }
}

private struct MockCredentialProvider: ClaudeCodeCredentialProviding {
    let result: Result<ClaudeCodeOAuthCredentials, Error>

    func loadCredentials() throws -> ClaudeCodeOAuthCredentials {
        try result.get()
    }
}

private struct MockUsageFetcher: ClaudeUsageFetching {
    let result: Result<ClaudeUsageResponse, Error>

    func fetchUsage(accessToken: String, userAgent: String) async throws -> ClaudeUsageResponse {
        XCTAssertEqual(accessToken, "token-123")
        XCTAssertEqual(userAgent, "MinimalTodoTests/1.0")
        return try result.get()
    }
}

private struct MockClaudeCodeAvailabilityChecker: ClaudeCodeAvailabilityChecking {
    let isInstalled: Bool

    func isClaudeCodeInstalled() -> Bool {
        isInstalled
    }
}
