//
//  ContentView.swift
//  MinimalTodo
//
//  Created by John Dutamby 2 on 21/06/2023.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TodoListPersistenceController()
    @State private var newTask: String = ""
    @State private var selectedFilter: ContentView.TodoFilter = .all
    @State private var selection = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("", selection: $selectedFilter) {
                Text("All").tag(TodoFilter.all)
                Text("Todo").tag(TodoFilter.todo)
                Text("Done").tag(TodoFilter.done)
            }
            .pickerStyle(SegmentedPickerStyle())
            
            Form {
                TextField("New task", text: $newTask)
            }.onSubmit {
                viewModel.addTask(task: newTask)
                newTask = ""
            }
            List {
                ForEach(viewModel.filteredItems(for: selectedFilter)) { item in
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
                                .foregroundColor(.white)
                                .overlay(
                                    Circle()
                                        .stroke(Color(hue: 0.528, saturation: 0.86, brightness: 0.64), lineWidth: 2)
                                )
                            
                        }
                        Text(item.task ?? "")
                            .font(.system(size:12))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14, alignment: .topLeading)
                            .strikethrough(item.isCompleted, color: .black)
                            .help(item.task ?? "")
                        Spacer()
                        Button(action: {
                            if let index = viewModel.items.firstIndex(where: { $0.id == item.id }) {
                                viewModel.removeTask(at: IndexSet(integer: index))
                            }
                        }) {
                            Image("trash")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let index = viewModel.items.firstIndex(where: { $0.id == item.id }) {
                            viewModel.toggleIsCompleted(forItemAtIndex: index)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 0)
                    Divider()
                }
            }
            
        }
        .padding(16)
        .background(Color(red: 0.93, green: 0.95, blue: 0.96))
        .cornerRadius(8)
    }
    
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(isSelected ? .white : .black)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(isSelected ? Color.blue : Color.clear)
                .cornerRadius(8)
        }
    }
}

extension ContentView {
    enum TodoFilter {
        case all
        case done
        case todo
    }
}
