import SwiftUI
import CoreData
import Combine
import AppKit

struct ContentView: View {
    private enum ThemePreference: String, CaseIterable {
        case system
        case light
        case dark

        var colorScheme: ColorScheme? {
            switch self {
            case .system:
                return nil
            case .light:
                return .light
            case .dark:
                return .dark
            }
        }

        var iconName: String {
            switch self {
            case .system:
                return "circle.lefthalf.filled"
            case .light:
                return "sun.max.fill"
            case .dark:
                return "moon.fill"
            }
        }

        var label: String {
            rawValue.capitalized
        }
    }

    @Environment(\.colorScheme) private var systemColorScheme
    @StateObject private var viewModel: TodoListPersistenceController
    @State private var newTask: String = ""
    @State private var includesDeadline = false
    @State private var selectedDeadline = Date()
    @State private var pomodoroSecondsRemaining = 25 * 60
    @State private var pomodoroMode: PomodoroMode = .work
    @State private var isPomodoroRunning = false
    @AppStorage("themePreference") private var themePreferenceRawValue = ThemePreference.system.rawValue
    @StateObject private var xBookmarksSyncService = XBookmarksSyncService()

    private let pomodoroTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private enum PomodoroMode: String {
        case work
        case shortBreak

        var durationInSeconds: Int {
            switch self {
            case .work:
                return 25 * 60
            case .shortBreak:
                return 5 * 60
            }
        }

        var title: String {
            switch self {
            case .work:
                return "Work"
            case .shortBreak:
                return "Break"
            }
        }
    }

    init(context: NSManagedObjectContext) {
        _viewModel = StateObject(wrappedValue: TodoListPersistenceController(context: context))
    }

    private var themePreference: ThemePreference {
        get { ThemePreference(rawValue: themePreferenceRawValue) ?? .system }
        set { themePreferenceRawValue = newValue.rawValue }
    }

    private var effectiveColorScheme: ColorScheme {
        themePreference.colorScheme ?? systemColorScheme
    }

    private var backgroundColor: Color {
        effectiveColorScheme == .dark ? Color(red: 0.16, green: 0.17, blue: 0.2) : Color(red: 0.93, green: 0.95, blue: 0.96)
    }

    private var pendingCircleFillColor: Color {
        effectiveColorScheme == .dark ? Color(red: 0.18, green: 0.19, blue: 0.22) : .white
    }

    private var glassCardBaseColor: Color {
        effectiveColorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.72)
    }

    private var glassCardBorderColor: Color {
        effectiveColorScheme == .dark
            ? Color.white.opacity(0.22)
            : Color.white.opacity(0.85)
    }

    private var glassCardShadowColor: Color {
        effectiveColorScheme == .dark
            ? Color.black.opacity(0.35)
            : Color.black.opacity(0.12)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Todos")
                    .font(.system(size: 16))
                    .bold()
                Spacer()
                Menu {
                    ForEach(ThemePreference.allCases, id: \.self) { option in
                        Button {
                            themePreference = option
                        } label: {
                            Label(option.label, systemImage: option.iconName)
                        }
                    }
                } label: {
                    Image(systemName: themePreference.iconName)
                        .font(.system(size: 13))
                }
                .menuStyle(.borderlessButton)
                .help("Theme: \(themePreference.label)")

                Text("\(viewModel.items.count) tasks")
                    .font(.system(size: 16))
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pomodoro")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(pomodoroMode.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .center, spacing: 12) {
                    Text(pomodoroClock)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()

                    Spacer()

                    Button(isPomodoroRunning ? "Pause" : "Start") {
                        isPomodoroRunning.toggle()
                    }

                    Button("Reset", action: resetPomodoro)
                        .disabled(pomodoroSecondsRemaining == pomodoroMode.durationInSeconds)
                }

                Picker("Timer mode", selection: $pomodoroMode) {
                    Text("Work").tag(PomodoroMode.work)
                    Text("Break").tag(PomodoroMode.shortBreak)
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("New task", text: $newTask)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(glassCardBorderColor, lineWidth: 0.8)
                        )
                        .onSubmit(addTask)

                    Button("Add", action: addTask)
                        .buttonStyle(.borderedProminent)
                        .disabled(newTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack(spacing: 12) {
                    Toggle("Add deadline", isOn: $includesDeadline)
                        .toggleStyle(.checkbox)

                    if includesDeadline {
                        DatePicker(
                            "Deadline",
                            selection: $selectedDeadline,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(glassCardBaseColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(glassCardBorderColor, lineWidth: 0.8)
            )
            .shadow(color: glassCardShadowColor, radius: 14, x: 0, y: 8)
            .padding(.horizontal, 10)

            Picker("", selection: $viewModel.selectedFilter) {
                Text("All").tag(TodoListPersistenceController.TodoFilter.all)
                Text("Todo").tag(TodoListPersistenceController.TodoFilter.todo)
                Text("Done").tag(TodoListPersistenceController.TodoFilter.done)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.vertical, 8)
            .padding(.trailing, 16)
            .padding(.leading, 8)
            .background(glassCardBaseColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(glassCardBorderColor, lineWidth: 0.8)
            )
            .shadow(color: glassCardShadowColor, radius: 14, x: 0, y: 8)
            .padding(.horizontal, 10)

            xBookmarksSection

            if viewModel.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 24))
                    Text("No tasks")
                        .font(.headline)
                    Text("Add a task to get started.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(glassCardBaseColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(glassCardBorderColor, lineWidth: 0.8)
                )
                .shadow(color: glassCardShadowColor, radius: 14, x: 0, y: 8)
                .padding(.horizontal, 10)
            } else {
                List {
                    ForEach(viewModel.items) { item in
                        HStack(alignment: .center, spacing: 12) {
                            if item.isCompleted {
                                ZStack {
                                    Circle()
                                        .frame(width: 16, height: 16)
                                        .foregroundColor(Color(hue: 0.528, saturation: 0.86, brightness: 0.64))

                                    Image("check")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 8, height: 8)
                                }
                            } else {
                                Circle()
                                    .frame(width: 16, height: 16)
                                    .foregroundColor(pendingCircleFillColor)
                                    .overlay(
                                        Circle()
                                            .stroke(Color(hue: 0.528, saturation: 0.86, brightness: 0.64), lineWidth: 2)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.task ?? "")
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)
                                    .strikethrough(item.isCompleted, color: .primary)
                                    .help(item.task ?? "")

                                if let deadline = item.deadline {
                                    Text(deadline, format: .dateTime.month(.abbreviated).day().year())
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                            Spacer()

                            Button(action: {
                                viewModel.removeTask(id: item.id)
                            }) {
                                Image("trash")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 12)
                            }
                            .accessibilityLabel("Delete task")
                            .buttonStyle(PlainButtonStyle())
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.toggleIsCompleted(id: item.id)
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(glassCardBaseColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(glassCardBorderColor, lineWidth: 0.8)
                                )
                                .padding(.vertical, 3)
                        )
                        .padding(.leading, 2)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(.clear)
                .padding(.horizontal, 10)
            }
        }
        .background(
            ZStack {
                backgroundColor
                LinearGradient(
                    colors: [
                        Color.white.opacity(effectiveColorScheme == .dark ? 0.07 : 0.5),
                        Color.clear,
                        Color.blue.opacity(effectiveColorScheme == .dark ? 0.14 : 0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .cornerRadius(8)
        .preferredColorScheme(themePreference.colorScheme)
        .onReceive(pomodoroTicker) { _ in
            guard isPomodoroRunning else { return }

            if pomodoroSecondsRemaining > 0 {
                pomodoroSecondsRemaining -= 1
            } else {
                isPomodoroRunning = false
                NSSound.beep()
            }
        }
        .onChange(of: pomodoroMode) { _ in
            resetPomodoro()
        }
    }

    private var xBookmarksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("X Bookmarks")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                if let lastSyncedAt = xBookmarksSyncService.lastSyncedAt {
                    Text(lastSyncedAt, format: .dateTime.hour().minute())
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Button(xBookmarksSyncService.isSyncing ? "Syncing…" : "Sync") {
                    Task { await xBookmarksSyncService.syncBookmarks() }
                }
                .disabled(xBookmarksSyncService.isSyncing)
                .buttonStyle(.bordered)
            }

            SecureField("X API bearer token", text: $xBookmarksSyncService.bearerToken)
                .textFieldStyle(.roundedBorder)

            TextField("X user id", text: $xBookmarksSyncService.userId)
                .textFieldStyle(.roundedBorder)

            if xBookmarksSyncService.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 8) {
                    Button("Open X Login") {
                        if let loginURL = URL(string: "https://x.com/i/flow/login") {
                            NSWorkspace.shared.open(loginURL)
                        }
                    }
                    .buttonStyle(.link)

                    Text("•")
                        .foregroundColor(.secondary)

                    Button("Get API Token") {
                        if let developerPortalURL = URL(string: "https://developer.x.com/en/portal/dashboard") {
                            NSWorkspace.shared.open(developerPortalURL)
                        }
                    }
                    .buttonStyle(.link)
                }
                .font(.system(size: 11))
            }

            if let lastSyncError = xBookmarksSyncService.lastSyncError {
                Text(lastSyncError)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            if xBookmarksSyncService.bookmarks.isEmpty {
                Text("No synced bookmarks yet.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(xBookmarksSyncService.bookmarks.prefix(5)) { bookmark in
                        Button {
                            if let tweetURL = bookmark.tweetURL {
                                NSWorkspace.shared.open(tweetURL)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                if let authorUsername = bookmark.authorUsername {
                                    Text("@\(authorUsername)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }

                                Text(bookmark.text)
                                    .font(.system(size: 12))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(glassCardBaseColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(glassCardBorderColor, lineWidth: 0.8)
        )
        .shadow(color: glassCardShadowColor, radius: 14, x: 0, y: 8)
        .padding(.horizontal, 10)
    }

    private var pomodoroClock: String {
        let minutes = pomodoroSecondsRemaining / 60
        let seconds = pomodoroSecondsRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func addTask() {
        viewModel.addTask(
            task: newTask,
            deadline: includesDeadline ? selectedDeadline : nil
        )
        newTask = ""
        includesDeadline = false
        selectedDeadline = Date()
    }

    private func resetPomodoro() {
        isPomodoroRunning = false
        pomodoroSecondsRemaining = pomodoroMode.durationInSeconds
    }
}
