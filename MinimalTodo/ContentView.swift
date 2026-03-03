import SwiftUI
import CoreData

struct ContentView: View {
    @StateObject private var viewModel: TodoListPersistenceController
    @State private var newTask: String = ""
    @State private var includesDeadline = false
    @State private var selectedDeadline = Date()
    @AppStorage("isDarkModeEnabled") private var isDarkModeEnabled = false

    init(context: NSManagedObjectContext) {
        _viewModel = StateObject(wrappedValue: TodoListPersistenceController(context: context))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Todos")
                    .font(.system(size: 16))
                    .bold()
                Spacer()
                Toggle(isOn: $isDarkModeEnabled) {
                    Image(systemName: isDarkModeEnabled ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 13))
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .help("Toggle dark mode")

                Text("\(viewModel.items.count) tasks")
                    .font(.system(size: 16))
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("New task", text: $newTask)
                        .onSubmit(addTask)

                    Button("Add", action: addTask)
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

            Picker("", selection: $viewModel.selectedFilter) {
                Text("All").tag(TodoListPersistenceController.TodoFilter.all)
                Text("Todo").tag(TodoListPersistenceController.TodoFilter.todo)
                Text("Done").tag(TodoListPersistenceController.TodoFilter.done)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.trailing, 16)
            .padding(.leading, 8)

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
                                    .foregroundColor(isDarkModeEnabled ? Color(red: 0.18, green: 0.19, blue: 0.22) : .white)
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
                        .padding(.leading, 2)
                    }
                }
            }
        }
        .background(isDarkModeEnabled ? Color(red: 0.16, green: 0.17, blue: 0.2) : Color(red: 0.93, green: 0.95, blue: 0.96))
        .cornerRadius(8)
        .preferredColorScheme(isDarkModeEnabled ? .dark : .light)
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
