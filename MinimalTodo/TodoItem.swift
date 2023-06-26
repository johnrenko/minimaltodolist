//
//  TodoItem.swift
//  MinimalTodo
//
//  Created by John Dutamby 2 on 21/06/2023.
//

import Foundation

struct TodoItem: Identifiable {
    var id = UUID()
    var task: String
    var isCompleted: Bool
}
