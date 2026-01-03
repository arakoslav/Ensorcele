//
//  SpiralEngine.swift
//  HypnoticSpiral
//
//  Main animation engine - replaces pygame's 60 FPS clock
//  Manages frequency-based timing for spiral rotation, image cycling, and word display
//

import Foundation
import Combine
import QuartzCore

#if os(macOS)
import AppKit
#endif

/// Main engine driving the spiral animation loop
/// Replaces pygame.time.Clock() with display-synchronized updates
@MainActor
class SpiralEngine: ObservableObject {
    private var displayTimer: Timer?
    private let state: SpiralState
    private let config: SpiralConfig
    private let configLoader: ConfigLoader

    // Audio components
    private let musicPlayer = MusicPlayer()
    private let speechSynthesizer: SpeechSynthesizerProtocol

    // Speech batching
    private var sentenceBuffer: [String] = []

    // Time-based spiral rotation
    private var spiralStartTime: CFAbsoluteTime = 0
    private var spiralRotationRate: Double = 0.0  // Frames per second

    // Tempo control
    var tempoMultiplier: Double = 1.0

    // Frame timing for consistent frequency counters
    private var lastUpdateTime: CFAbsoluteTime = 0
    private var targetFrameInterval: Double = 0  // Expected seconds per frame

    #if os(macOS)
    private var displayLink: CVDisplayLink?
    #endif

    init(state: SpiralState, config: SpiralConfig, configLoader: ConfigLoader = ConfigLoader()) {
        self.state = state
        self.config = config
        self.configLoader = configLoader

        // Create platform-specific speech synthesizer
        #if os(macOS)
        self.speechSynthesizer = SpeechSynthesizerMac()
        #else
        self.speechSynthesizer = SpeechSynthesizeriOS()
        #endif

        // Set up speech delegate after initialization
        Task { @MainActor in
            setupSpeechDelegate()
            setupAudio()
        }
    }

    private func setupSpeechDelegate() {
        speechSynthesizer.delegate = self
    }

    private func setupAudio() {
        // Load and start music if specified
        if let music = config.properties.music {
            musicPlayer.loadMusic(filename: music)
            musicPlayer.play()
        }

        // Set voice if specified
        speechSynthesizer.setVoice(config.properties.voice)
    }

    // MARK: - Engine Control

    /// Start the animation loop
    func start() {
        guard !state.isRunning else { return }

        state.isRunning = true
        state.initializeFrequencies(from: config)

        // Calculate spiral rotation rate in degrees per second
        // With frequency=1, timeScale=2, frameRate=60, spiralStep=1:
        // Advances 1 degree per frame = 60 deg/sec
        let spiralFrequency = Double(config.properties.frequencies.spiral)
        let timeScale = Double(config.properties.timeScale)
        let frameRate = Double(config.properties.frameRate)
        let spiralStep = Double(config.properties.spiralStep)
        spiralRotationRate = (frameRate * timeScale / spiralFrequency) * spiralStep

        // Store target frame interval for time-based frequency decrements
        targetFrameInterval = 1.0 / frameRate

        let now = CACurrentMediaTime()
        spiralStartTime = now
        lastUpdateTime = now

        print("Spiral rotation rate: \(String(format: "%.1f", spiralRotationRate)) degrees/sec")
        print("Target frame interval: \(String(format: "%.3f", targetFrameInterval * 1000))ms (\(Int(frameRate))fps)")

        #if os(macOS)
        startDisplayLink()
        #else
        startTimer()
        #endif
    }

    #if os(macOS)
    private func startDisplayLink() {
        var displayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)

        guard let link = displayLink else {
            print("Failed to create CVDisplayLink, falling back to Timer")
            startTimer()
            return
        }

        // Capture self weakly for the callback
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo in
            guard let enginePtr = userInfo else { return kCVReturnSuccess }
            let engine = Unmanaged<SpiralEngine>.fromOpaque(enginePtr).takeUnretainedValue()

            Task { @MainActor in
                engine.update()
            }
            return kCVReturnSuccess
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, callback, selfPtr)
        CVDisplayLinkStart(link)

        self.displayLink = link
        print("Using CVDisplayLink for display synchronization")
    }
    #endif

    private func startTimer() {
        let interval = 1.0 / Double(config.properties.frameRate)
        displayTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.update()
            }
        }
        // Add to common run loop mode for better responsiveness
        RunLoop.main.add(displayTimer!, forMode: .common)
        print("Using Timer for updates")
    }

    /// Stop the animation loop
    func stop() {
        displayTimer?.invalidate()
        displayTimer = nil

        #if os(macOS)
        if let link = displayLink {
            CVDisplayLinkStop(link)
            self.displayLink = nil
        }
        #endif

        // Stop any ongoing speech
        speechSynthesizer.stop()
        state.isSpeaking = false

        state.isRunning = false
    }

    /// Pause the animation (keeps timer running but stops updates)
    func pause() {
        state.isRunning = false
    }

    /// Resume the animation
    func resume() {
        state.isRunning = true
    }

    // MARK: - Main Update Loop

    /// Called every frame - decrements frequency counters and triggers events
    private func update() {
        guard state.isRunning && !state.isWaiting else { return }

        let now = CACurrentMediaTime()
        let deltaTime = now - lastUpdateTime
        lastUpdateTime = now

        // Calculate how many "target frames" worth of time has elapsed
        // This makes timing consistent regardless of actual display refresh rate
        let frameEquivalent = deltaTime / targetFrameInterval

        // Update spiral rotation using time-based angle (smooth, GPU-accelerated)
        if state.drawSpiral && state.spiralImage != nil {
            let elapsed = now - spiralStartTime
            // spiralRotationRate is in degrees per second
            state.spiralRotation = elapsed * spiralRotationRate

            // Add pulsing scale effect (oscillates between 1.3 and 1.5 - scaled up to prevent edge clipping during wobble)
            let scaleFrequency = 0.5  // Cycles per second
            state.spiralScale = 1.4 + 0.1 * sin(elapsed * scaleFrequency * 2.0 * .pi)

            // Add wobble/tilt effect (small 3D rotation oscillations)
            let wobbleFrequency = 0.3  // Slower wobble
            let wobbleAmplitude = 15.0  // Degrees of tilt
            state.spiralTiltX = wobbleAmplitude * sin(elapsed * wobbleFrequency * 2.0 * .pi)
            state.spiralTiltY = wobbleAmplitude * cos(elapsed * wobbleFrequency * 1.7 * .pi)  // Slightly different frequency for more complex motion
        }

        // Decrement frequency counters for images and words using time-based scaling
        for key in state.frequencies.keys {
            // Skip spiral - it's time-based now
            if key == "spiral" { continue }

            // Decrement by timeScale * frameEquivalent * tempoMultiplier to maintain consistent speed
            let decrement = Double(config.properties.timeScale) * frameEquivalent * tempoMultiplier
            state.frequencies[key]! -= Int(decrement)

            // When counter hits zero or below, trigger ONCE and reset
            if state.frequencies[key]! < 0 {
                handleFrequencyTick(key)

                // Reset counter to base frequency (matching Python behavior)
                switch key {
                case "images":
                    state.frequencies[key] = config.properties.frequencies.images
                case "words":
                    state.frequencies[key] = config.properties.frequencies.words
                default:
                    break
                }
            }
        }
    }

    // MARK: - Frequency Event Handlers

    /// Handle when a frequency counter reaches zero
    private func handleFrequencyTick(_ key: String) {
        switch key {
        case "images":
            handleImageTick()
        case "words":
            handleWordTick()
        default:
            break
        }
    }

    /// Advance to next image
    private func handleImageTick() {
        guard state.drawImages && !state.images.isEmpty else { return }

        // Don't cycle images if we're holding a specific image
        guard state.holdImageIndex < 0 else { return }

        state.imageIndex = (state.imageIndex + 1) % state.images.count
    }

    /// Advance to next word in text sequence
    private func handleWordTick() {
        // Process words if we're either drawing OR speaking them
        guard (state.drawWords || state.speakWords) && !state.textSequence.isEmpty else { return }

        // Don't advance if currently speaking
        if state.isSpeaking {
            return
        }

        // Get next item from sequence
        if state.wordsIndex < state.textSequence.count {
            let item = state.textSequence[state.wordsIndex]
            state.wordsIndex += 1

            // Process the item (word or command)
            Task {
                await processTextItem(item)
            }
        }
    }

    // MARK: - Speech Markup Processing

    /// Strip speech markup [[...]] from text for display
    private func stripMarkup(_ text: String) -> String {
        // Remove all [[...]] patterns
        let pattern = "\\[\\[[^\\]]*\\]\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    /// Parse and process speech markup commands like [[rate +1000]]
    /// Strips markup and applies rate changes to the synthesizer
    /// Returns the text with markup removed
    private func parseAndApplyMarkupCommands(_ text: String) -> String {
        var processedText = text

        // Find all [[rate ...]] patterns
        let pattern = "\\[\\[rate ([+-]?\\d+)\\]\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            if match.numberOfRanges >= 2 {
                let rateRange = match.range(at: 1)
                let rateString = nsText.substring(with: rateRange)

                if let rateValue = Int(rateString) {
                    // Check if it's a relative change (starts with + or -)
                    let isRelative = rateString.hasPrefix("+") || rateString.hasPrefix("-")

                    // Apply to synthesizer using Speech Manager scale (0-65535)
                    #if os(macOS)
                    if let macSynthesizer = speechSynthesizer as? SpeechSynthesizerMac {
                        macSynthesizer.setSpeechManagerRate(rateValue, relative: isRelative)
                    }
                    #elseif os(iOS)
                    if let iosSynthesizer = speechSynthesizer as? SpeechSynthesizeriOS {
                        iosSynthesizer.setSpeechManagerRate(rateValue, relative: isRelative)
                    }
                    #endif

                    // Track in state for reference
                    if isRelative {
                        let currentRate = state.currentSpeechRate ?? 0
                        state.currentSpeechRate = currentRate + rateValue
                    } else {
                        state.currentSpeechRate = rateValue
                    }
                }

                // Remove the markup from the text (process in reverse to maintain indices)
                let fullMatchRange = match.range(at: 0)
                let swiftRange = Range(fullMatchRange, in: processedText)!
                processedText.removeSubrange(swiftRange)
            }
        }

        return processedText
    }

    // MARK: - Text Processing

    /// Process a single text sequence item (word or command)
    private func processTextItem(_ item: String) async {
        // Check if it's a command (starts with !)
        if item.hasPrefix("!") {
            await executeCommand(item)
        } else {
            // It's a regular word - display it
            await displayWord(item)
        }
    }

    /// Display a word on screen
    private func displayWord(_ word: String) async {
        // Perform variable substitution ($name → value)
        let substituted = await performVariableSubstitution(word)

        // If speech is enabled, batch into sentences
        if state.speakWords {
            // Add the word WITH markup to the speech buffer
            sentenceBuffer.append(substituted)

            // Check if this word ends a sentence (has punctuation)
            // Strip markup for punctuation check
            let strippedForCheck = stripMarkup(substituted)
            if strippedForCheck.hasSuffix(".") || strippedForCheck.hasSuffix("!") ||
               strippedForCheck.hasSuffix("?") || strippedForCheck.hasSuffix(",") {
                // Join the sentence - this handles broken markup across array elements
                let sentence = sentenceBuffer.joined(separator: " ")

                // Parse and apply markup commands, get stripped text
                let cleanSentence = parseAndApplyMarkupCommands(sentence)

                // Speak the stripped sentence
                speechSynthesizer.speak(cleanSentence)
                state.isSpeaking = true
                sentenceBuffer = []

                // Words will be displayed via didSpeakWord callback (which will strip markup)
            }
        } else {
            // No speech - parse markup on individual words and display WITHOUT markup
            let cleanText = parseAndApplyMarkupCommands(substituted)
            state.currentWord = cleanText
        }
    }

    /// Replace $variable references with their values
    /// Automatically prompts for any unset variables
    private func performVariableSubstitution(_ text: String) async -> String {
        var result = text

        // Find all $variable patterns using regex
        let pattern = "\\$([a-zA-Z_][a-zA-Z0-9_]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        // Collect all variable names found
        var variableNames: [String] = []
        for match in matches {
            if match.numberOfRanges >= 2 {
                let varNameRange = match.range(at: 1)
                let varName = nsText.substring(with: varNameRange)
                if !variableNames.contains(varName) {
                    variableNames.append(varName)
                }
            }
        }

        // For each variable, check if it's set - if not, prompt for it
        for varName in variableNames {
            if state.variables[varName] == nil || state.variables[varName]!.isEmpty {
                // Variable not set - implicitly ask for it
                await showOpenQuestion(prompt: "\(varName)?", variableName: varName)
            }
        }

        // Now perform substitution with all variables set
        for (key, value) in state.variables {
            result = result.replacingOccurrences(of: "$\(key)", with: value)
        }

        return result
    }

    // MARK: - Command Execution

    /// Execute a command string like "!spiral_on()" or "!speak('hello')"
    private func executeCommand(_ commandString: String) async {
        // Parse command format: !name(args)
        let trimmed = String(commandString.dropFirst()) // Remove !

        guard let parenIndex = trimmed.firstIndex(of: "(") else {
            print("Warning: Invalid command format: \(commandString)")
            return
        }

        let commandName = String(trimmed[..<parenIndex])

        // For now, implement basic commands directly
        // TODO: Replace with CommandDispatcher in Phase 3
        switch commandName {
        case "spiral_on":
            state.drawSpiral = true
        case "spiral_off":
            state.drawSpiral = false
        case "words_on":
            state.drawWords = true
        case "words_off":
            state.drawWords = false
        case "images_on":
            state.drawImages = true
            print("Images ON - have \(state.images.count) images")
        case "images_off":
            state.drawImages = false
            print("Images OFF")
        case "speaking_on":
            state.speakWords = true
        case "speaking_off":
            state.speakWords = false

        // Music commands
        case "pause_music":
            musicPlayer.pause()
        case "unpause_music":
            musicPlayer.play()
        case "stop_music":
            musicPlayer.stop()
        case "start_music":
            musicPlayer.play()

        // Speech commands
        case "speak":
            if let args = extractArgs(from: trimmed) {
                let text = await performVariableSubstitution(args.first ?? "")
                // Parse and apply markup commands, get stripped text
                let cleanText = parseAndApplyMarkupCommands(text)
                speechSynthesizer.speak(cleanText)
                state.isSpeaking = true
            }
        case "whisper":
            // TODO: Implement whisper with lower volume
            if let args = extractArgs(from: trimmed) {
                let text = await performVariableSubstitution(args.first ?? "")
                // Parse and apply markup commands, get stripped text
                let cleanText = parseAndApplyMarkupCommands(text)
                speechSynthesizer.speak(cleanText)
                state.isSpeaking = true
            }

        // Text commands
        case "hold_text":
            if let args = extractArgs(from: trimmed) {
                let text = await performVariableSubstitution(args.first ?? "")
                state.persistentText = text  // Empty string clears it
            }
        case "background":
            if let args = extractArgs(from: trimmed) {
                let text = await performVariableSubstitution(args.first ?? "")
                state.backgroundText = text  // Empty string clears it
            }

        // Image commands
        case "hold_image":
            // Single-command version: !hold_image('filename.jpg')
            if let args = extractArgs(from: trimmed), let filename = args.first {
                let imageFilename = await performVariableSubstitution(filename)

                // Look up the image by filename
                if let index = state.imageFilenames.firstIndex(of: imageFilename) {
                    state.holdImageIndex = index
                    state.drawImages = true
                    print("Holding image: \(imageFilename) at index \(index)")
                } else {
                    print("Warning: Could not find image '\(imageFilename)' in loaded images")
                    print("  Available images: \(state.imageFilenames.prefix(10).joined(separator: ", "))")
                }
            }

        case "hold_image_start":
            // Start capturing the next non-command words as an image filename
            state.isCapturingImageName = true
            var capturedName = ""

            // Advance and read words until we hit a command or end
            while state.wordsIndex + 1 < state.textSequence.count {
                state.wordsIndex += 1
                let word = state.textSequence[state.wordsIndex]

                // Stop if we hit a command
                if word.starts(with: "!") {
                    state.wordsIndex -= 1  // Back up one so the command gets processed
                    break
                }

                // Add word to captured name
                if !capturedName.isEmpty {
                    capturedName += " "
                }
                capturedName += await performVariableSubstitution(word)
            }

            // Look up the image by filename
            if let index = state.imageFilenames.firstIndex(of: capturedName) {
                state.holdImageIndex = index
                print("Holding image: \(capturedName) at index \(index)")
            } else {
                print("Warning: Could not find image '\(capturedName)' in loaded images")
                print("  Available images: \(state.imageFilenames.prefix(10).joined(separator: ", "))")
            }
            state.isCapturingImageName = false

        case "hold_image_end":
            // Turn on image drawing (the image index was set by hold_image_start)
            state.drawImages = true

        case "hold_image_blank":
            // Clear the held image
            state.holdImageIndex = -1
            state.drawImages = false

        // Control flow commands
        case "jump":
            if let args = extractArgs(from: trimmed), let scriptRef = args.first {
                // Handle "self.scriptname" and "parent.scriptname" references
                let scriptName: String
                if scriptRef.hasPrefix("self.") {
                    scriptName = String(scriptRef.dropFirst(5)) // Remove "self."
                } else if scriptRef.hasPrefix("parent.") {
                    scriptName = String(scriptRef.dropFirst(7)) // Remove "parent."
                    // TODO: Handle parent script loading if needed
                    print("Warning: parent script references not yet fully supported")
                } else {
                    scriptName = scriptRef
                }

                do {
                    try loadScript(named: scriptName)
                    print("Jumped to script: \(scriptName)")
                } catch {
                    print("Error jumping to script '\(scriptName)': \(error)")
                }
            }

        case "quit":
            stop()

        // User input commands
        case "prompt", "short_prompt":
            if let args = extractArgs(from: trimmed), let message = args.first {
                await showPrompt(message: await performVariableSubstitution(message))
            }

        case "open_question":
            if let args = extractArgs(from: trimmed), args.count >= 2 {
                let prompt = await performVariableSubstitution(args[0])
                let varName = args[1]
                await showOpenQuestion(prompt: prompt, variableName: varName)
            }

        case "yn_question", "question_yn":
            if let args = extractArgs(from: trimmed), args.count >= 3 {
                let question = await performVariableSubstitution(args[0])
                // Strip "self." prefix from script names if present
                let yesScript = args[1].replacingOccurrences(of: "self.", with: "")
                let noScript = args[2].replacingOccurrences(of: "self.", with: "")
                await showYesNoQuestion(question: question, yesScript: yesScript, noScript: noScript)
            }

        case "challenge":
            if let args = extractArgs(from: trimmed), args.count >= 2 {
                let prompt = await performVariableSubstitution(args[0])
                let varName = args[1]
                await showChallenge(prompt: prompt, variableName: varName)
            }

        case "set_pref":
            if let args = extractArgs(from: trimmed), args.count >= 2 {
                let prompt = await performVariableSubstitution(args[0])
                let varName = args[1]
                await setPreference(prompt: prompt, variableName: varName)
            }

        default:
            print("Warning: Unimplemented command: \(commandName)")
        }
    }

    /// Extract arguments from command string "cmd(arg1, arg2)"
    private func extractArgs(from commandString: String) -> [String]? {
        guard let parenStart = commandString.firstIndex(of: "("),
              let parenEnd = commandString.lastIndex(of: ")") else {
            return nil
        }

        let argsString = String(commandString[commandString.index(after: parenStart)..<parenEnd])

        if argsString.isEmpty {
            return []
        }

        // Basic argument parsing - split by comma and trim quotes
        return argsString.split(separator: ",").map { arg in
            var trimmed = arg.trimmingCharacters(in: .whitespaces)
            // Remove surrounding quotes if present (single or double)
            if (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) ||
               (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) {
                trimmed = String(trimmed.dropFirst().dropLast())
            }
            return trimmed
        }
    }

    // MARK: - Script Loading

    /// Load and resolve a script from the configuration
    func loadScript(named scriptName: String) throws {
        let resolvedElements = try configLoader.resolveScript(named: scriptName, in: config)
        state.textSequence = resolvedElements
        state.wordsIndex = 0
    }

    // MARK: - User Input Methods

    /// Show a simple prompt message and wait for OK
    private func showPrompt(message: String) async {
        await withCheckedContinuation { continuation in
            state.currentQuestion = .prompt(message: message) {
                self.state.currentQuestion = nil
                self.state.isWaiting = false
                continuation.resume()
            }
            state.isWaiting = true
        }
    }

    /// Ask an open-ended question and store answer in variable
    private func showOpenQuestion(prompt: String, variableName: String) async {
        await withCheckedContinuation { continuation in
            state.currentQuestion = .openQuestion(prompt: prompt, variableName: variableName) { answer in
                self.state.variables[variableName] = answer
                self.state.currentQuestion = nil
                self.state.isWaiting = false
                continuation.resume()
            }
            state.isWaiting = true
        }
    }

    /// Ask a yes/no question and branch to different scripts
    private func showYesNoQuestion(question: String, yesScript: String, noScript: String) async {
        await withCheckedContinuation { continuation in
            state.currentQuestion = .yesNo(question: question, onYes: {
                self.state.currentQuestion = nil
                self.state.isWaiting = false
                // Load yes script
                Task {
                    do {
                        try self.loadScript(named: yesScript)
                    } catch {
                        print("Error loading yes script '\(yesScript)': \(error)")
                    }
                }
                continuation.resume()
            }, onNo: {
                self.state.currentQuestion = nil
                self.state.isWaiting = false
                // Load no script
                Task {
                    do {
                        try self.loadScript(named: noScript)
                    } catch {
                        print("Error loading no script '\(noScript)': \(error)")
                    }
                }
                continuation.resume()
            })
            state.isWaiting = true
        }
    }

    /// Show a challenge prompt (like open_question but styled differently)
    private func showChallenge(prompt: String, variableName: String) async {
        await withCheckedContinuation { continuation in
            state.currentQuestion = .challenge(prompt: prompt, variableName: variableName) { answer in
                self.state.variables[variableName] = answer
                self.state.currentQuestion = nil
                self.state.isWaiting = false
                continuation.resume()
            }
            state.isWaiting = true
        }
    }

    /// Set a persistent preference - only prompts if not already set
    private func setPreference(prompt: String, variableName: String) async {
        // Check if preference already exists in SharedVariables
        let sharedVars = SharedVariables.shared
        if let existingValue = sharedVars.variables[variableName], !existingValue.isEmpty {
            // Already set - just use the existing value
            state.variables[variableName] = existingValue
            print("Using existing preference for '\(variableName)': \(existingValue)")
            return
        }

        // Not set - prompt user and save
        await withCheckedContinuation { continuation in
            state.currentQuestion = .setPref(prompt: prompt, variableName: variableName) { answer in
                // Save to SharedVariables for persistence
                SharedVariables.shared.variables[variableName] = answer
                // Also set in current session
                self.state.variables[variableName] = answer
                self.state.currentQuestion = nil
                self.state.isWaiting = false
                continuation.resume()
            }
            state.isWaiting = true
        }
    }
}

// MARK: - SpeechSynthesizerDelegate

extension SpiralEngine: SpeechSynthesizerDelegate {
    func synthesizer(_ synthesizer: SpeechSynthesizerProtocol, didSpeakWord word: String) {
        // Strip markup from the word before displaying it
        let strippedWord = stripMarkup(word)
        state.currentWord = strippedWord
        state.spokenWord = strippedWord
    }

    func synthesizerDidFinish(_ synthesizer: SpeechSynthesizerProtocol) {
        state.isSpeaking = false
        state.spokenWord = ""
        state.currentWord = ""  // Clear the display
    }
}
