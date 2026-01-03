//
//  SpiralEngine.swift
//  HypnoticSpiral
//
//  Main engine that drives the spiral animation loop
//  Replaces pygame's 60 FPS loop with SwiftUI-friendly timer
//

import Foundation
import SwiftUI
import Combine

/// Main engine that runs the spiral animation loop
/// Replaces pygame's clock.tick() with CADisplayLink-style updates
@MainActor
class SpiralEngine: ObservableObject {
    private var displayTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    let state: SpiralState
    let config: SpiralConfig
    private let configLoader = ConfigLoader()

    // Track last update time for consistent timing
    private var lastUpdateTime: Date?

    init(state: SpiralState, config: SpiralConfig) {
        self.state = state
        self.config = config
    }

    // MARK: - Engine Control

    func start() {
        state.isRunning = true
        state.initializeFrequencies(from: config)
        lastUpdateTime = Date()

        // Start display timer at configured frame rate
        let interval = 1.0 / Double(config.properties.frameRate)
        displayTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.update()
            }
        }

        // Ensure timer runs during UI interactions
        if let timer = displayTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    func stop() {
        state.isRunning = false
        displayTimer?.invalidate()
        displayTimer = nil
    }

    func pause() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    func resume() {
        guard state.isRunning else { return }

        let interval = 1.0 / Double(config.properties.frameRate)
        displayTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.update()
            }
        }

        if let timer = displayTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    // MARK: - Main Update Loop

    /// Main update loop - called at frame rate (default 60 FPS)
    /// Replaces pygame's clock.tick() and event processing
    private func update() {
        guard state.isRunning else { return }
        guard !state.isWaiting else { return }  // Pause during user input

        // Decrement all frequency counters
        for key in state.frequencies.keys {
            state.frequencies[key]! -= config.properties.timeScale

            if state.frequencies[key]! < 0 {
                // Reset counter and trigger action
                state.frequencies[key] = getFrequency(for: key)
                handleFrequencyTick(key)
            }
        }
    }

    /// Get the configured frequency value for a key
    private func getFrequency(for key: String) -> Int {
        switch key {
        case "spiral":
            return config.properties.frequencies.spiral
        case "images":
            return config.properties.frequencies.images
        case "words":
            return config.properties.frequencies.words
        default:
            return 1
        }
    }

    /// Handle frequency timer expiration
    private func handleFrequencyTick(_ key: String) {
        switch key {
        case "spiral":
            advanceSpiral()
        case "images":
            advanceImage()
        case "words":
            advanceText()
        default:
            break
        }
    }

    // MARK: - Advancement Functions

    /// Advance to next spiral frame
    private func advanceSpiral() {
        guard !state.spiralFrames.isEmpty else { return }
        state.spiralIndex = (state.spiralIndex + 1) % state.spiralFrames.count
    }

    /// Advance to next image
    private func advanceImage() {
        guard !state.images.isEmpty else { return }
        state.imageIndex = (state.imageIndex + 1) % state.images.count

        // Re-shuffle on loop if configured
        if config.properties.shuffleImages && state.imageIndex == 0 {
            // TODO: Implement image shuffling
        }
    }

    /// Advance to next word/command in text sequence
    private func advanceText() {
        guard !state.textSequence.isEmpty else { return }
        guard !state.isSpeaking else { return }  // Don't advance while speaking

        state.wordsIndex = (state.wordsIndex + 1) % state.textSequence.count
        let item = state.textSequence[state.wordsIndex]

        if item.hasPrefix("!") {
            // Command - will be handled by command dispatcher
            Task {
                // TODO: Execute command via dispatcher
                print("Command: \(item)")
            }
        } else {
            // Regular word - perform variable substitution
            state.currentWord = substituteVariables(in: item)
        }
    }

    /// Substitute variables ($name) in text
    private func substituteVariables(in text: String) -> String {
        var result = text

        // Sort by length descending to avoid partial replacements
        let sortedVars = state.variables.keys.sorted { $0.count > $1.count }

        for key in sortedVars {
            if let value = state.variables[key] {
                result = result.replacingOccurrences(of: key, with: value)
            }
        }

        return result
    }

    // MARK: - Resource Loading

    /// Load text sequence from config
    func loadTextSequence() {
        do {
            state.textSequence = try configLoader.resolveScript(
                named: "text",
                in: config
            )
            print("Loaded \(state.textSequence.count) text elements")
        } catch {
            print("Error loading text sequence: \(error)")
            state.textSequence = ["Error loading text"]
        }
    }

    /// Initialize the engine with config data
    func initialize() {
        state.reset()
        state.config = config
        state.initializeFrequencies(from: config)
        loadTextSequence()

        // TODO: Load spiral frames
        // TODO: Load images
        // TODO: Initialize speech synthesizer if needed
    }
}

// MARK: - Helper Extensions

extension SpiralEngine {
    /// Calculate delay before starting (from config min/max delay)
    var startupDelay: TimeInterval {
        let min = config.properties.minimumDelay
        let max = config.properties.maximumDelay

        if min == max {
            return TimeInterval(min)
        } else {
            return TimeInterval.random(in: TimeInterval(min)...TimeInterval(max))
        }
    }
}
