//
//  SharedVariables.swift
//  HypnoticSpiral
//
//  Manages global variables shared across all configurations
//  Persisted to UserDefaults
//

import Foundation
import SwiftUI

/// Manages persistent storage of common variables used across configs
@MainActor
@Observable
class SharedVariables {
    static let shared = SharedVariables()

    // Dynamic variables storage
    var variables: [String: String] = [:] {
        didSet { save() }
    }

    private init() {
        // Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "SharedVariables.variables"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.variables = decoded
        } else {
            // Default to just "name" variable
            self.variables = ["name": ""]
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(variables) {
            UserDefaults.standard.set(encoded, forKey: "SharedVariables.variables")
        }
    }

    /// Get all non-empty variables as a dictionary for state initialization
    func asDictionary() -> [String: String] {
        variables.filter { !$0.value.isEmpty }
    }

    /// Add a new variable
    func addVariable(name: String) {
        guard !name.isEmpty && !variables.keys.contains(name) else { return }
        variables[name] = ""
    }

    /// Remove a variable
    func removeVariable(name: String) {
        variables.removeValue(forKey: name)
    }
}
