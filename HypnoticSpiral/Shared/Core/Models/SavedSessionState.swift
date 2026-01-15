//
//  SavedSessionState.swift
//  HypnoticSpiral
//
//  Persisted state for resuming a config session
//

import Foundation

/// Saved state for resuming a paused config
struct SavedSessionState: Codable {
    let configName: String
    let wordsIndex: Int
    let textSequence: [String]
    let variables: [String: String]

    // Rendering flags
    let drawSpiral: Bool
    let drawWords: Bool
    let drawImages: Bool
    let speakWords: Bool

    let holdImageIndex: Int
    let savedAt: Date

    /// Check if session has meaningful progress (not at start)
    var hasProgress: Bool {
        return wordsIndex > 0
    }
}

/// Manager for saving and loading session states
class SessionStateManager {
    static let shared = SessionStateManager()

    private let userDefaults = UserDefaults.standard
    private let keyPrefix = "savedSession_"

    private init() {}

    /// Save session state for a config
    func saveState(_ state: SavedSessionState) {
        let key = keyPrefix + state.configName
        if let encoded = try? JSONEncoder().encode(state) {
            userDefaults.set(encoded, forKey: key)
            print("Saved session state for '\(state.configName)' at index \(state.wordsIndex)")
        }
    }

    /// Load saved session state for a config
    func loadState(for configName: String) -> SavedSessionState? {
        let key = keyPrefix + configName
        guard let data = userDefaults.data(forKey: key),
              let state = try? JSONDecoder().decode(SavedSessionState.self, from: data) else {
            return nil
        }
        return state
    }

    /// Check if a saved session exists for a config
    func hasSavedSession(for configName: String) -> Bool {
        let state = loadState(for: configName)
        return state?.hasProgress ?? false
    }

    /// Clear saved session for a config
    func clearState(for configName: String) {
        let key = keyPrefix + configName
        userDefaults.removeObject(forKey: key)
        print("Cleared session state for '\(configName)'")
    }

    /// Get all config names with saved sessions
    func allSavedConfigNames() -> [String] {
        return userDefaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(keyPrefix) }
            .map { String($0.dropFirst(keyPrefix.count)) }
    }
}
