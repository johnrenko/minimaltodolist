//
//  TodoListViewModel.swift
//  MinimalTodo
//
//  Created by John Dutamby 2 on 21/06/2023.
//

import Foundation

class TodoListViewModel: ObservableObject {
    @Published var items = [TodoItem]()

    func addTask(task: String) {
            let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTask.isEmpty else {
                return
            }
            
            let todoItem = TodoItem(task: trimmedTask, isCompleted: false)
            items.append(todoItem)
    }

    func removeTask(at index: Int) {
        items.remove(at: index)
    }

    func toggleIsCompleted(forItemAtIndex index: Int) {
        items[index].isCompleted.toggle()
    }
    
}
