import Foundation

struct CodexUsageSnapshot {
    let lastFiveHoursTokens: Int
    let lastWeekTokens: Int
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

        Task {
            defer { isRefreshing = false }

            do {
                let snapshot = try await Task.detached(priority: .utility) {
                    try Self.loadCodexUsageSnapshot(now: Date())
                }.value
                codexSnapshot = snapshot
            } catch let usageError as UsageReadError {
                codexError = usageError.localizedDescription
            } catch {
                codexError = "Could not read local Codex usage: \(error.localizedDescription)"
            }
        }
    }

    nonisolated private static func loadCodexUsageSnapshot(now: Date) throws -> CodexUsageSnapshot {
        guard let databasePath = locateCodexStateDatabasePath() else {
            throw UsageReadError.databaseNotFound
        }

        let nowTimestamp = Int(now.timeIntervalSince1970)
        let fiveHourCutoff = nowTimestamp - (5 * 60 * 60)
        let weeklyCutoff = nowTimestamp - (7 * 24 * 60 * 60)

        let sql = """
        SELECT
            COALESCE(SUM(CASE WHEN updated_at >= \(fiveHourCutoff) THEN tokens_used ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN updated_at >= \(weeklyCutoff) THEN tokens_used ELSE 0 END), 0)
        FROM threads;
        """

        let queryOutput = try runSQLiteQuery(databasePath: databasePath, sql: sql)
        let outputLine = queryOutput
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? queryOutput

        let values = outputLine.split(separator: "|", omittingEmptySubsequences: false)
        guard values.count >= 2,
              let fiveHourTokens = Int(values[0]),
              let weeklyTokens = Int(values[1]) else {
            throw UsageReadError.malformedQueryOutput(outputLine)
        }

        return CodexUsageSnapshot(
            lastFiveHoursTokens: fiveHourTokens,
            lastWeekTokens: weeklyTokens,
            refreshedAt: now
        )
    }

    nonisolated private static func locateCodexStateDatabasePath() -> String? {
        let codexHomeRaw = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "~/.codex"
        let codexHome = (codexHomeRaw as NSString).expandingTildeInPath
        let fileManager = FileManager.default

        guard let entries = try? fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: codexHome),
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let candidates = entries.filter { url in
            url.lastPathComponent.hasPrefix("state_") && url.lastPathComponent.hasSuffix(".sqlite")
        }

        let sortedCandidates = candidates.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate > rightDate
        }

        return sortedCandidates.first?.path
    }

    nonisolated private static func runSQLiteQuery(databasePath: String, sql: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-readonly",
            "-noheader",
            "-separator",
            "|",
            databasePath,
            sql
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw UsageReadError.sqliteUnavailable
        }

        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let outputString = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorString = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw UsageReadError.queryFailed(errorString.isEmpty ? "sqlite3 exit code \(process.terminationStatus)." : errorString)
        }

        return outputString
    }

    private enum UsageReadError: LocalizedError {
        case databaseNotFound
        case sqliteUnavailable
        case malformedQueryOutput(String)
        case queryFailed(String)

        var errorDescription: String? {
            switch self {
            case .databaseNotFound:
                return "Could not find a local Codex state database in ~/.codex."
            case .sqliteUnavailable:
                return "sqlite3 is unavailable on this Mac."
            case .malformedQueryOutput(let output):
                return "Unexpected Codex usage output: \(output)"
            case .queryFailed(let details):
                return "Could not query Codex usage: \(details)"
            }
        }
    }
}
