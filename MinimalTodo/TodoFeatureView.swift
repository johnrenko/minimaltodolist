import SwiftUI
import CoreData

struct TodoFeatureRootView: View {
    @StateObject private var viewModel: TodoListPersistenceController
    @Environment(\.colorScheme) private var colorScheme

    init(context: NSManagedObjectContext) {
        _viewModel = StateObject(wrappedValue: TodoListPersistenceController(context: context))
    }

    var body: some View {
        TodoFeatureView(viewModel: viewModel)
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(featureBackground)
    }

    private var featureBackground: some View {
        ZStack {
            colorScheme == .dark
                ? Color(red: 0.16, green: 0.17, blue: 0.20)
                : Color(red: 0.95, green: 0.97, blue: 0.99)

            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.08 : 0.45),
                    Color.clear,
                    Color.blue.opacity(colorScheme == .dark ? 0.18 : 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct TodoFeatureView: View {
    @ObservedObject private var viewModel: TodoListPersistenceController
    @Environment(\.colorScheme) private var colorScheme

    @State private var newTask = ""
    @State private var includesDeadline = false
    @State private var selectedDeadline = Date()

    init(viewModel: TodoListPersistenceController) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    private var accentColor: Color {
        Color(hue: 0.528, saturation: 0.86, brightness: 0.64)
    }

    private var pendingCircleFillColor: Color {
        colorScheme == .dark ? Color(red: 0.18, green: 0.19, blue: 0.22) : .white
    }

    private var glassCardBaseColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.76)
    }

    private var glassCardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.85)
    }

    private var glassCardShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.12)
    }

    private var trimmedTask: String {
        newTask.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 12) {
            TodoComposerCard(
                newTask: $newTask,
                includesDeadline: $includesDeadline,
                selectedDeadline: $selectedDeadline,
                glassCardBaseColor: glassCardBaseColor,
                glassCardBorderColor: glassCardBorderColor,
                glassCardShadowColor: glassCardShadowColor,
                addTask: addTask
            )

            TodoFilterCard(
                selectedFilter: $viewModel.selectedFilter,
                glassCardBaseColor: glassCardBaseColor,
                glassCardBorderColor: glassCardBorderColor,
                glassCardShadowColor: glassCardShadowColor
            )

            if viewModel.items.isEmpty {
                TodoEmptyStateCard(
                    glassCardBaseColor: glassCardBaseColor,
                    glassCardBorderColor: glassCardBorderColor,
                    glassCardShadowColor: glassCardShadowColor
                )
            } else {
                List {
                    ForEach(viewModel.items, id: \.objectID) { item in
                        TodoTaskRow(
                            item: item,
                            accentColor: accentColor,
                            pendingCircleFillColor: pendingCircleFillColor,
                            deleteTask: { viewModel.removeTask(id: item.id) },
                            toggleTask: { viewModel.toggleIsCompleted(id: item.id) }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(glassCardBaseColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(glassCardBorderColor, lineWidth: 0.8)
                                )
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(.clear)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

private struct TodoComposerCard: View {
    @Binding var newTask: String
    @Binding var includesDeadline: Bool
    @Binding var selectedDeadline: Date

    let glassCardBaseColor: Color
    let glassCardBorderColor: Color
    let glassCardShadowColor: Color
    let addTask: () -> Void

    private var trimmedTask: String {
        newTask.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("New task", text: $newTask)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(glassCardBorderColor, lineWidth: 0.8)
                    )
                    .onSubmit(addTask)

                Button("Add", action: addTask)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedTask.isEmpty)
            }

            Toggle("Add deadline", isOn: $includesDeadline)

            if includesDeadline {
                DatePicker(
                    "Deadline",
                    selection: $selectedDeadline,
                    displayedComponents: [.date]
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(glassCardBaseColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(glassCardBorderColor, lineWidth: 0.8)
        )
        .shadow(color: glassCardShadowColor, radius: 14, x: 0, y: 8)
    }
}

private struct TodoFilterCard: View {
    @Binding var selectedFilter: TodoListPersistenceController.TodoFilter

    let glassCardBaseColor: Color
    let glassCardBorderColor: Color
    let glassCardShadowColor: Color

    var body: some View {
        Picker("Filter", selection: $selectedFilter) {
            Text("All").tag(TodoListPersistenceController.TodoFilter.all)
            Text("Todo").tag(TodoListPersistenceController.TodoFilter.todo)
            Text("Done").tag(TodoListPersistenceController.TodoFilter.done)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(glassCardBaseColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(glassCardBorderColor, lineWidth: 0.8)
        )
        .shadow(color: glassCardShadowColor, radius: 14, x: 0, y: 8)
    }
}

private struct TodoEmptyStateCard: View {
    let glassCardBaseColor: Color
    let glassCardBorderColor: Color
    let glassCardShadowColor: Color

    var body: some View {
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
        .padding(.vertical, 32)
        .background(glassCardBaseColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(glassCardBorderColor, lineWidth: 0.8)
        )
        .shadow(color: glassCardShadowColor, radius: 14, x: 0, y: 8)
    }
}

private struct TodoTaskRow: View {
    let item: Item
    let accentColor: Color
    let pendingCircleFillColor: Color
    let deleteTask: () -> Void
    let toggleTask: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: toggleTask) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isCompleted ? accentColor : pendingCircleFillColor)
                        .overlay(
                            Circle()
                                .stroke(accentColor, lineWidth: item.isCompleted ? 0 : 2)
                        )
                        .font(.system(size: 18, weight: .semibold))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.task ?? "")
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .strikethrough(item.isCompleted, color: .primary)
                            .multilineTextAlignment(.leading)

                        if let deadline = item.deadline {
                            Text(deadline, format: .dateTime.month(.abbreviated).day().year())
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.task ?? "Task")

            Button(role: .destructive, action: deleteTask) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete task")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
