import Combine
import Foundation

struct CodexUsageSnapshot: Sendable {
    let lastFiveHoursPercent: Int
    let lastWeekPercent: Int
    let lastFiveHoursResetAt: Date?
    let lastWeekResetAt: Date?
    let refreshedAt: Date
}

@MainActor
final class UsageRecapService: ObservableObject {
    @Published private(set) var codexSnapshot: CodexUsageSnapshot?
    @Published private(set) var codexError: String?
    @Published private(set) var isRefreshing = false

    func refreshCodexUsage() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        codexError = nil

        Task.detached(priority: .userInitiated) {
            do {
                let snapshot = try loadCodexUsageSnapshot()

                await MainActor.run {
                    self.codexSnapshot = snapshot
                    self.codexError = nil
                    self.isRefreshing = false
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

                await MainActor.run {
                    self.codexSnapshot = nil
                    self.codexError = message
                    self.isRefreshing = false
                }
            }
        }
    }
}

private struct RolloutEvent: Decodable {
    let timestamp: String?
    let type: String
    let payload: RolloutPayload?
}

private struct RolloutPayload: Decodable {
    let type: String
    let rateLimits: CodexRateLimits?

    private enum CodingKeys: String, CodingKey {
        case type
        case rateLimits = "rate_limits"
    }
}

private struct CodexRateLimits: Decodable {
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
}

private struct CodexRateLimitWindow: Decodable {
    let usedPercent: Double
    let resetsAt: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetsAt = "resets_at"
    }
}

private struct RolloutFile {
    let url: URL
    let modifiedAt: Date
}

private enum CodexUsageError: LocalizedError {
    case noCodexHomes
    case noRolloutFiles
    case noRateLimitMetadata

    var errorDescription: String? {
        switch self {
        case .noCodexHomes:
            return "Could not find a local Codex home directory."
        case .noRolloutFiles:
            return "Could not find any local Codex rollout logs."
        case .noRateLimitMetadata:
            return "Could not find recent Codex rate-limit metadata in local session logs."
        }
    }
}

private let codexJSONDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    return decoder
}()

private let codexISO8601WithFractionalSeconds: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let codexISO8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private func loadCodexUsageSnapshot() throws -> CodexUsageSnapshot {
    let fileManager = FileManager.default
    let codexHomes = codexHomeCandidates().filter { fileManager.fileExists(atPath: $0.path) }

    guard !codexHomes.isEmpty else {
        throw CodexUsageError.noCodexHomes
    }

    let rolloutFiles = codexHomes
        .flatMap(rolloutFiles(in:))
        .sorted { $0.modifiedAt > $1.modifiedAt }

    guard !rolloutFiles.isEmpty else {
        throw CodexUsageError.noRolloutFiles
    }

    for rolloutFile in rolloutFiles.prefix(40) {
        if let snapshot = try codexSnapshot(from: rolloutFile) {
            return snapshot
        }
    }

    throw CodexUsageError.noRateLimitMetadata
}

private func codexHomeCandidates() -> [URL] {
    let fileManager = FileManager.default
    let username = NSUserName()
    let homeDirectory = fileManager.homeDirectoryForCurrentUser.path

    let rawCandidates = [
        ProcessInfo.processInfo.environment["CODEX_HOME"],
        NSHomeDirectoryForUser(username).map { "\($0)/.codex" },
        "\(homeDirectory)/.codex",
        "\(NSHomeDirectory())/.codex",
        "/Users/\(username)/.codex"
    ]

    var seenPaths = Set<String>()

    return rawCandidates
        .compactMap { $0 }
        .map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, isDirectory: true) }
        .filter { seenPaths.insert($0.standardizedFileURL.path).inserted }
}

private func rolloutFiles(in codexHome: URL) -> [RolloutFile] {
    ["sessions", "archived_sessions"].flatMap { subdirectory in
        let directoryURL = codexHome.appendingPathComponent(subdirectory, isDirectory: true)
        return rolloutFilesRecursively(in: directoryURL)
    }
}

private func rolloutFilesRecursively(in directoryURL: URL) -> [RolloutFile] {
    let fileManager = FileManager.default

    guard fileManager.fileExists(atPath: directoryURL.path) else {
        return []
    }

    guard let enumerator = fileManager.enumerator(
        at: directoryURL,
        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var files: [RolloutFile] = []

    for case let fileURL as URL in enumerator {
        guard fileURL.lastPathComponent.hasPrefix("rollout-"),
              fileURL.pathExtension == "jsonl" else {
            continue
        }

        let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])

        guard resourceValues?.isRegularFile == true else {
            continue
        }

        files.append(
            RolloutFile(
                url: fileURL,
                modifiedAt: resourceValues?.contentModificationDate ?? .distantPast
            )
        )
    }

    return files
}

private func codexSnapshot(from rolloutFile: RolloutFile) throws -> CodexUsageSnapshot? {
    let fileContents = try Data(contentsOf: rolloutFile.url)
    let lines = String(decoding: fileContents, as: UTF8.self).split(whereSeparator: \.isNewline)

    for line in lines.reversed() {
        guard let event = try? codexJSONDecoder.decode(RolloutEvent.self, from: Data(line.utf8)),
              event.type == "event_msg",
              event.payload?.type == "token_count",
              let primaryWindow = event.payload?.rateLimits?.primary,
              let secondaryWindow = event.payload?.rateLimits?.secondary else {
            continue
        }

        let refreshedAt = event.timestamp.flatMap(parseCodexTimestamp) ?? rolloutFile.modifiedAt

        return CodexUsageSnapshot(
            lastFiveHoursPercent: clampedPercentage(primaryWindow.usedPercent),
            lastWeekPercent: clampedPercentage(secondaryWindow.usedPercent),
            lastFiveHoursResetAt: primaryWindow.resetsAt.map(Date.init(timeIntervalSince1970:)),
            lastWeekResetAt: secondaryWindow.resetsAt.map(Date.init(timeIntervalSince1970:)),
            refreshedAt: refreshedAt
        )
    }

    return nil
}

private func clampedPercentage(_ value: Double) -> Int {
    Int(value.rounded()).clamped(to: 0...100)
}

private func parseCodexTimestamp(_ value: String) -> Date? {
    codexISO8601WithFractionalSeconds.date(from: value) ?? codexISO8601Formatter.date(from: value)
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
