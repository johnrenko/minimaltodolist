import SwiftUI
import CoreData

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
    @AppStorage("themePreference") private var themePreferenceRawValue = ThemePreference.system.rawValue

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
}
