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
    private var speechQueue: [SpeechQueueItem] = []  // Queue of sentences and commands

    /// Items in the speech queue - either sentences to speak or commands to execute
    private enum SpeechQueueItem {
        case sentence(String)
        case command(String)
    }

    /// Commands that require user interaction and should stop pre-buffering
    private let interactiveCommands: Set<String> = [
        "prompt", "short_prompt", "open_question", "yn_question", "question_yn",
        "challenge", "set_pref", "mantra", "speak_mantra", "awareness_test", "awareness_test_inv", "quit"
    ]

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

    init(state: SpiralState, config: SpiralConfig, configLoader: ConfigLoader? = nil) {
        self.state = state
        self.config = config
        self.configLoader = configLoader ?? ConfigLoader()

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
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.update()
            }
        }
        // Add to common run loop mode for better responsiveness
        RunLoop.main.add(displayTimer!, forMode: .common)
        print("Using Timer for updates")
    }

    /// Stop the animation loop
    /// If saveState is true and program hasn't ended, saves progress for resuming
    func stop(saveState shouldSave: Bool = true) {
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

        // Stop music playback
        musicPlayer.stop()

        // Save session state if we have progress and program didn't end naturally
        if shouldSave && !state.programEnded && state.wordsIndex > 0 {
            saveSessionState()
        } else if state.programEnded {
            // Clear saved state when program ends naturally
            SessionStateManager.shared.clearState(for: config.name)
        }

        state.isRunning = false
    }

    /// Save current session state for later resuming
    private func saveSessionState() {
        let savedState = SavedSessionState(
            configName: config.name,
            wordsIndex: state.wordsIndex,
            textSequence: state.textSequence,
            variables: state.variables,
            drawSpiral: state.drawSpiral,
            drawWords: state.drawWords,
            drawImages: state.drawImages,
            speakWords: state.speakWords,
            holdImageIndex: state.holdImageIndex,
            savedAt: Date()
        )
        SessionStateManager.shared.saveState(savedState)
    }

    /// Restore session from saved state
    func restoreSession(from savedState: SavedSessionState) {
        state.wordsIndex = savedState.wordsIndex
        state.textSequence = savedState.textSequence
        state.variables = savedState.variables
        state.drawSpiral = savedState.drawSpiral
        state.drawWords = savedState.drawWords
        state.drawImages = savedState.drawImages
        state.speakWords = savedState.speakWords
        state.holdImageIndex = savedState.holdImageIndex
        print("Restored session at index \(savedState.wordsIndex) of \(savedState.textSequence.count)")
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
        guard state.isRunning else { return }

        let now = CACurrentMediaTime()
        let deltaTime = now - lastUpdateTime
        lastUpdateTime = now

        // Calculate how many "target frames" worth of time has elapsed
        // This makes timing consistent regardless of actual display refresh rate
        let frameEquivalent = deltaTime / targetFrameInterval

        // Update spiral rotation using time-based angle (smooth, GPU-accelerated)
        // This continues even when waiting for user input (dialogs)
        if state.drawSpiral && (state.spiralImage != nil || state.activeSpiralType == .rings) {
            let elapsed = now - spiralStartTime
            // spiralRotationRate is in degrees per second, apply runtime speed multiplier
            let effectiveRate = spiralRotationRate * state.getEffectiveSpiralSpeed()
            state.spiralRotation = -elapsed * effectiveRate

            // Counter-rotation for twist spirals (opposite direction, different rate)
            if state.counterSpiralImage != nil {
                let counterRate = config.properties.spiralCounterRate
                state.counterSpiralRotation = elapsed * effectiveRate * counterRate
            }

            // Add pulsing scale effect (oscillates between 1.3 and 1.5 - scaled up to prevent edge clipping during wobble)
            let scaleFrequency = 0.5  // Cycles per second
            state.spiralScale = 1.4 + 0.1 * sin(elapsed * scaleFrequency * 2.0 * .pi)

            // Add wobble/tilt effect (small 3D rotation oscillations)
            let wobbleFrequency = 0.3  // Slower wobble
            let wobbleAmplitude = 15.0  // Degrees of tilt
            state.spiralTiltX = wobbleAmplitude * sin(elapsed * wobbleFrequency * 2.0 * .pi)
            state.spiralTiltY = wobbleAmplitude * cos(elapsed * wobbleFrequency * 1.7 * .pi)

            // Separate wobble for counter spiral (different frequencies for independent motion)
            if state.counterSpiralImage != nil {
                let counterWobbleFreq = 0.23  // Different frequency
                state.counterSpiralTiltX = wobbleAmplitude * sin(elapsed * counterWobbleFreq * 2.3 * .pi + 1.2)
                state.counterSpiralTiltY = wobbleAmplitude * cos(elapsed * counterWobbleFreq * 1.9 * .pi + 0.8)
            }

            // Animate ringsPhase for Canvas-based ring expansion
            // Phase increases continuously (no wrapping) - rings expand outward forever
            if state.activeSpiralType == .rings {
                let spacing = config.properties.ringsSpacing
                let expansionRate = config.properties.ringsExpansionRate
                let phaseSpeed = spacing * expansionRate  // pixels per second
                state.ringsPhase = elapsed * phaseSpeed  // No wrapping - continuous expansion
            }
        }

        // Don't advance words/images while waiting for user input
        guard !state.isWaiting else { return }

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
                case "backgroundWords":
                    state.frequencies[key] = config.properties.frequencies.backgroundWords
                case "subliminals":
                    state.frequencies[key] = config.properties.frequencies.subliminals
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
        case "backgroundWords":
            handleBackgroundWordTick()
        case "subliminals":
            handleSubliminalTick()
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
        } else {
            // Text sequence exhausted - program has ended
            state.programEnded = true
            stop()
        }
    }

    /// Advance to next background word in the cycling list
    private func handleBackgroundWordTick() {
        guard !state.backgroundWords.isEmpty else { return }

        // Cycle to next word
        state.backgroundWordIndex = (state.backgroundWordIndex + 1) % state.backgroundWords.count
        state.backgroundText = state.backgroundWords[state.backgroundWordIndex]
    }

    /// Advance to next subliminal word in the cycling list
    private func handleSubliminalTick() {
        guard !state.subliminalWords.isEmpty else { return }

        // Check display probability (supports runtime override)
        let displayProbability = state.getEffectiveSubliminalDisplayProbability()
        if Int.random(in: 1...100) > displayProbability {
            state.subliminalText = ""
            return
        }

        // Check change probability (supports runtime override)
        let changeProbability = state.getEffectiveSubliminalChangeProbability()
        if Int.random(in: 1...100) <= changeProbability {
            // Cycle to next word
            state.subliminalWordIndex = (state.subliminalWordIndex + 1) % state.subliminalWords.count
            state.subliminalText = state.subliminalWords[state.subliminalWordIndex]
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
                sentenceBuffer = []

                // If already speaking, queue this sentence; otherwise start speaking and pre-buffer
                if state.isSpeaking {
                    speechQueue.append(.sentence(cleanSentence))
                } else {
                    speechSynthesizer.speak(cleanSentence)
                    state.isSpeaking = true

                    // Pre-buffer all words and non-interactive commands
                    await prebufferSpeechQueue()
                }

                // Words will be displayed via didSpeakWord callback
            }
        } else {
            // No speech - parse markup on individual words and display WITHOUT markup
            let cleanText = parseAndApplyMarkupCommands(substituted)
            state.currentWord = cleanText
        }
    }

    /// Pre-buffer sentences and commands until we hit an interactive command
    /// This prevents pauses between sentences during speech
    private func prebufferSpeechQueue() async {
        while state.wordsIndex < state.textSequence.count {
            let item = state.textSequence[state.wordsIndex]

            // Check if it's a command
            if item.hasPrefix("!") {
                // Extract command name
                let trimmed = String(item.dropFirst())
                let commandName = trimmed.split(separator: "(").first.map(String.init) ?? trimmed

                // Stop if it's an interactive command
                if interactiveCommands.contains(commandName) {
                    break
                }

                // Non-interactive command - queue it and continue
                state.wordsIndex += 1
                speechQueue.append(.command(item))
                continue
            }

            // Regular word - process it
            state.wordsIndex += 1

            // Perform variable substitution
            let substituted = await performVariableSubstitution(item)

            // Add to sentence buffer
            sentenceBuffer.append(substituted)

            // Check if this word ends a sentence
            let strippedForCheck = stripMarkup(substituted)
            if strippedForCheck.hasSuffix(".") || strippedForCheck.hasSuffix("!") ||
               strippedForCheck.hasSuffix("?") || strippedForCheck.hasSuffix(",") {
                // Complete sentence - add to queue
                let sentence = sentenceBuffer.joined(separator: " ")
                let cleanSentence = parseAndApplyMarkupCommands(sentence)
                sentenceBuffer = []
                speechQueue.append(.sentence(cleanSentence))
            }
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

        // Command dispatcher - handles all script commands
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
            // Speak at lower volume (30% of normal)
            if let args = extractArgs(from: trimmed) {
                let text = await performVariableSubstitution(args.first ?? "")
                // Parse and apply markup commands, get stripped text
                let cleanText = parseAndApplyMarkupCommands(text)
                speechSynthesizer.speak(cleanText, volume: 0.3)
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
                if args.count > 1 {
                    // Multiple arguments - set up cycling through word list
                    var words: [String] = []
                    for arg in args {
                        let text = await performVariableSubstitution(arg)
                        words.append(text)
                    }
                    state.backgroundWords = words
                    state.backgroundWordIndex = 0
                    state.backgroundText = words.first ?? ""
                } else {
                    // Single argument or empty - static text (clears cycling)
                    let text = await performVariableSubstitution(args.first ?? "")
                    state.backgroundWords = []
                    state.backgroundWordIndex = 0
                    state.backgroundText = text  // Empty string clears it
                }
            }
        case "subliminals":
            if let args = extractArgs(from: trimmed) {
                if args.count > 1 {
                    // Multiple arguments - set up cycling through word list
                    var words: [String] = []
                    for arg in args {
                        let text = await performVariableSubstitution(arg)
                        words.append(text)
                    }
                    state.subliminalWords = words
                    state.subliminalWordIndex = 0
                    state.subliminalText = words.first ?? ""
                } else if let firstArg = args.first, !firstArg.isEmpty {
                    // Single non-empty argument - static subliminal text (clears cycling)
                    let text = await performVariableSubstitution(firstArg)
                    state.subliminalWords = []
                    state.subliminalWordIndex = 0
                    state.subliminalText = text
                } else {
                    // Empty - clear subliminals
                    state.subliminalWords = []
                    state.subliminalWordIndex = 0
                    state.subliminalText = ""
                }
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
                    // Parent script references would load from the base config if inheritance is used
                    print("Note: parent script references load from current config")
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
            state.programEnded = true
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
            // Syntax: !yn_question('question', 'yes_script', 'no_script')
            // Or with timeout: !yn_question('question', 'yes_script', 'no_script', 30, 'yes')
            // Timeout auto-selects 'yes' or 'no' after N seconds (for auto-advance behavior)
            if let args = extractArgs(from: trimmed), args.count >= 3 {
                let question = await performVariableSubstitution(args[0])
                // Strip "self." prefix from script names if present
                let yesScript = args[1].replacingOccurrences(of: "self.", with: "")
                let noScript = args[2].replacingOccurrences(of: "self.", with: "")
                // Optional timeout parameters
                let timeoutSeconds = args.count >= 4 ? Int(args[3]) : nil
                let timeoutDefault = args.count >= 5 ? args[4].lowercased() : nil
                await showYesNoQuestion(question: question, yesScript: yesScript, noScript: noScript,
                                        timeoutSeconds: timeoutSeconds, timeoutDefault: timeoutDefault)
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

        case "mantra":
            // Demand user type exact text back before continuing (typing only)
            // Syntax: !mantra('I obey')
            // With timeout: !mantra('I obey', 30, 'self.retrain') - jump to script
            // With timeout: !mantra('I obey', 30, ['word1', 'word2']) - insert words
            if let mantraArgs = extractMantraArgs(from: trimmed) {
                let substituted = await performVariableSubstitution(mantraArgs.expectedText)
                await showMantra(
                    expectedText: substituted,
                    timeoutSeconds: mantraArgs.timeoutSeconds,
                    timeoutAction: mantraArgs.timeoutAction,
                    autoStartMic: false
                )
            }

        case "speak_mantra":
            // Demand user speak or type exact text back (mic auto-starts)
            // Same syntax as !mantra but microphone automatically starts
            if let mantraArgs = extractMantraArgs(from: trimmed) {
                let substituted = await performVariableSubstitution(mantraArgs.expectedText)
                await showMantra(
                    expectedText: substituted,
                    timeoutSeconds: mantraArgs.timeoutSeconds,
                    timeoutAction: mantraArgs.timeoutAction,
                    autoStartMic: true
                )
            }

        case "awareness_test":
            // Peripheral awareness test - subtle prompt at bottom of screen
            // User staring at spiral center won't notice it
            // Syntax: !awareness_test('Click if awake', 10, 'self.deep_trance')
            // If not clicked within timeout, jumps to specified script
            if let args = extractArgs(from: trimmed), args.count >= 3 {
                let message = await performVariableSubstitution(args[0])
                let timeoutSeconds = Int(args[1]) ?? 10
                let jumpTarget = args[2].replacingOccurrences(of: "self.", with: "")
                await showAwarenessTest(message: message, timeoutSeconds: timeoutSeconds, jumpTarget: jumpTarget)
            }

        case "awareness_test_inv":
            // Inverted awareness test - for induction relaxation checks
            // If user CLICKS (notices the message), they're not in trance -> jump to script
            // If timeout (didn't notice), they're in trance -> continue inline
            // Syntax: !awareness_test_inv('Click if you notice this', 10, 'self.repeat_induction')
            if let args = extractArgs(from: trimmed), args.count >= 3 {
                let message = await performVariableSubstitution(args[0])
                let timeoutSeconds = Int(args[1]) ?? 10
                let jumpTarget = args[2].replacingOccurrences(of: "self.", with: "")
                await showAwarenessTestInverted(message: message, timeoutSeconds: timeoutSeconds, jumpTarget: jumpTarget)
            }

        case "set_property":
            // Dynamically set a runtime property value
            // Syntax: !set_property('property_name', value)
            // Supported: image_alpha, text_alpha, spiral_alpha, subliminal_alpha,
            //            spiral_type, text_color, spiral_color, font_size, background_font_size, subliminal_color
            if let args = extractArgs(from: trimmed), args.count >= 2 {
                let propertyName = args[0]
                let valueStr = args[1]

                switch propertyName {
                case "image_alpha":
                    if let value = Int(valueStr) {
                        state.runtimeImageAlpha = max(0, min(255, value))
                        print("Set image_alpha to \(value)")
                    }
                case "text_alpha":
                    if let value = Int(valueStr) {
                        state.runtimeTextAlpha = max(0, min(255, value))
                        print("Set text_alpha to \(value)")
                    }
                case "spiral_alpha", "alpha":
                    if let value = Int(valueStr) {
                        state.runtimeSpiralAlpha = max(0, min(255, value))
                        print("Set spiral_alpha to \(value)")
                    }
                case "subliminal_alpha":
                    if let value = Int(valueStr) {
                        state.runtimeSubliminalAlpha = max(0, min(255, value))
                        print("Set subliminal_alpha to \(value)")
                    }
                case "spiral_type":
                    if let spiralType = SpiralType(rawValue: valueStr.lowercased()) {
                        state.activeSpiralType = spiralType
                        // Regenerate spiral image for new type
                        Task {
                            await regenerateSpiralForType(spiralType)
                        }
                        print("Set spiral_type to \(valueStr)")
                    } else {
                        print("Warning: Unknown spiral type '\(valueStr)'. Valid types: fermat, logarithmic, filled, twist, chromatic, colors, rings")
                    }
                case "text_color":
                    if let rgb = parseColor(valueStr) {
                        state.runtimeTextColor = rgb
                        print("Set text_color to \(rgb)")
                    }
                case "spiral_color":
                    if let rgb = parseColor(valueStr) {
                        state.runtimeSpiralColor = rgb
                        // Regenerate spiral with new color
                        Task {
                            await regenerateSpiralForType(state.activeSpiralType)
                        }
                        print("Set spiral_color to \(rgb)")
                    }
                case "subliminal_color":
                    if let rgb = parseColor(valueStr) {
                        state.runtimeSubliminalColor = rgb
                        print("Set subliminal_color to \(rgb)")
                    }
                case "font_size":
                    if let value = Double(valueStr) {
                        state.runtimeFontSize = CGFloat(max(8, min(500, value)))
                        print("Set font_size to \(value)")
                    }
                case "background_font_size":
                    if let value = Double(valueStr) {
                        state.runtimeBackgroundFontSize = CGFloat(max(8, min(1000, value)))
                        print("Set background_font_size to \(value)")
                    }
                case "image_dir":
                    // Set new image directory - view will observe and reload images
                    state.runtimeImageDir = valueStr
                    state.imageIndex = 0
                    state.holdImageIndex = -1
                    print("Set image_dir to \(valueStr)")

                // Timing properties
                case "word_frequency", "words_frequency":
                    if let value = Int(valueStr) {
                        state.runtimeWordFrequency = max(1, value)
                        // Update the frequency counter immediately
                        state.frequencies["words"] = state.runtimeWordFrequency
                        print("Set word_frequency to \(value)")
                    }
                case "image_frequency", "images_frequency":
                    if let value = Int(valueStr) {
                        state.runtimeImageFrequency = max(1, value)
                        state.frequencies["images"] = state.runtimeImageFrequency
                        print("Set image_frequency to \(value)")
                    }
                case "spiral_speed", "rotation_speed":
                    if let value = Double(valueStr) {
                        state.runtimeSpiralSpeed = max(0.1, min(10.0, value))
                        print("Set spiral_speed to \(value)")
                    }

                // Spiral appearance properties
                case "spiral_line_width":
                    if let value = Double(valueStr) {
                        state.runtimeSpiralLineWidth = max(0.5, min(20.0, value))
                        print("Set spiral_line_width to \(value)")
                    }
                case "spiral_tightness":
                    if let value = Double(valueStr) {
                        state.runtimeSpiralTightness = max(0.01, min(1.0, value))
                        print("Set spiral_tightness to \(value)")
                    }
                case "spiral_arms":
                    if let value = Int(valueStr) {
                        state.runtimeSpiralArms = max(1, min(12, value))
                        print("Set spiral_arms to \(value)")
                    }

                // Subliminal behavior properties
                case "subliminal_scatter":
                    if let value = Int(valueStr) {
                        state.runtimeSubliminalScatter = max(0, min(1000, value))
                        print("Set subliminal_scatter to \(value)")
                    }
                case "subliminal_move_probability":
                    if let value = Int(valueStr) {
                        state.runtimeSubliminalMoveProbability = max(0, min(100, value))
                        print("Set subliminal_move_probability to \(value)")
                    }
                case "subliminal_display_probability":
                    if let value = Int(valueStr) {
                        state.runtimeSubliminalDisplayProbability = max(0, min(100, value))
                        print("Set subliminal_display_probability to \(value)")
                    }
                case "subliminal_change_probability":
                    if let value = Int(valueStr) {
                        state.runtimeSubliminalChangeProbability = max(0, min(100, value))
                        print("Set subliminal_change_probability to \(value)")
                    }

                // Rings/Colors properties
                case "rings_line_width":
                    if let value = Double(valueStr) {
                        state.runtimeRingsLineWidth = max(0.5, min(20.0, value))
                        print("Set rings_line_width to \(value)")
                    }
                case "rings_spacing":
                    if let value = Double(valueStr) {
                        state.runtimeRingsSpacing = max(5.0, min(200.0, value))
                        print("Set rings_spacing to \(value)")
                    }
                case "rings_expansion_rate":
                    if let value = Double(valueStr) {
                        state.runtimeRingsExpansionRate = max(0.1, min(5.0, value))
                        print("Set rings_expansion_rate to \(value)")
                    }

                default:
                    print("Warning: Unknown property '\(propertyName)' in !set_property")
                }
            }

        case "set_image_dir":
            // Shorthand for !set_property('image_dir', 'path')
            // Syntax: !set_image_dir('Images/NewFolder/')
            if let args = extractArgs(from: trimmed), let dir = args.first {
                state.runtimeImageDir = dir
                state.imageIndex = 0
                state.holdImageIndex = -1
                print("Set image_dir to \(dir)")
            }

        case "random_jump":
            // Jump to a randomly selected script from a list
            // Syntax: !random_jump(['script1', 'script2', 'script3'])
            if let scripts = extractArrayArg(from: trimmed), !scripts.isEmpty {
                let randomIndex = Int.random(in: 0..<scripts.count)
                var scriptName = scripts[randomIndex]

                // Strip "self." prefix if present
                if scriptName.hasPrefix("self.") {
                    scriptName = String(scriptName.dropFirst(5))
                }

                do {
                    try loadScript(named: scriptName)
                    print("Random jump to script: \(scriptName) (selected from \(scripts.count) options)")
                } catch {
                    print("Error in random_jump to script '\(scriptName)': \(error)")
                }
            }

        case "cond":
            // Syntax: !cond('condition', ['word1', 'word2'], ['else1', 'else2'])
            // With one array: show words if condition is FALSE (guard pattern)
            // With two arrays: show first if TRUE, second if FALSE (if-then-else)
            if let (condition, thenWords, elseWords) = extractCondArgs(from: trimmed) {
                let conditionResult = evaluateCondition(condition)

                let wordsToInsert: [String]
                if elseWords != nil {
                    // Two arrays: standard if-then-else
                    wordsToInsert = conditionResult ? thenWords : (elseWords ?? [])
                } else {
                    // One array: show if condition is FALSE (guard pattern)
                    wordsToInsert = conditionResult ? [] : thenWords
                }

                // Insert words into text sequence after current position
                if !wordsToInsert.isEmpty {
                    let insertIndex = state.wordsIndex + 1
                    state.textSequence.insert(contentsOf: wordsToInsert, at: insertIndex)
                }
            }

        // Camera commands
        case "camera_snapshot":
            await captureAndSavePhoto()

        case "load_lastCameraShot":
            // Load the most recent captured image into state
            await loadLastCapturedImage()

        case "show_lastCamImage":
            // Display the last captured camera image
            state.showLastCamImage = true
            state.drawImages = true

        case "hide_lastCamImage":
            // Hide the camera image
            state.showLastCamImage = false

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

    /// Extract a single array argument from command string like "cmd(['item1', 'item2'])"
    private func extractArrayArg(from commandString: String) -> [String]? {
        guard let bracketStart = commandString.firstIndex(of: "["),
              let bracketEnd = commandString.lastIndex(of: "]") else {
            return nil
        }

        let arrayString = String(commandString[commandString.index(after: bracketStart)..<bracketEnd])

        var items: [String] = []
        var currentItem = ""
        var inQuote = false
        var quoteChar: Character = "'"

        for char in arrayString {
            if (char == "'" || char == "\"") && !inQuote {
                inQuote = true
                quoteChar = char
            } else if char == quoteChar && inQuote {
                inQuote = false
                items.append(currentItem)
                currentItem = ""
            } else if char == "," && !inQuote {
                // Skip comma between items
            } else if inQuote {
                currentItem.append(char)
            }
        }

        return items
    }

    /// Parse a color value from string (hex like "FF0033" or RGB like "255,0,51")
    private func parseColor(_ value: String) -> [Int]? {
        // Try hex format first (with or without #)
        let hex = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        if hex.count == 6, let _ = Int(hex, radix: 16) {
            let r = Int(hex.prefix(2), radix: 16) ?? 0
            let g = Int(hex.dropFirst(2).prefix(2), radix: 16) ?? 0
            let b = Int(hex.dropFirst(4).prefix(2), radix: 16) ?? 0
            return [r, g, b]
        }

        // Try comma-separated RGB format
        let parts = value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 3 {
            return parts.map { max(0, min(255, $0)) }
        }

        print("Warning: Could not parse color '\(value)'. Use hex (FF0033) or RGB (255,0,51)")
        return nil
    }

    /// Signal that spiral needs regeneration (view observes activeSpiralType)
    /// For now this is a no-op since activeSpiralType is @Published and view reacts
    /// In the future, could trigger regeneration with new color here
    private func regenerateSpiralForType(_ spiralType: SpiralType) async {
        // activeSpiralType is already set and is @Published
        // The SpiralView should observe changes and regenerate
        // For rings type, clear the pre-generated images
        if spiralType == .rings {
            state.spiralImage = nil
            state.counterSpiralImage = nil
        }
        print("Spiral type changed to: \(spiralType.rawValue)")
    }

    /// Timeout action for mantra command
    enum MantraTimeoutAction {
        case jump(scriptName: String)
        case insertWords([String])
    }

    /// Parsed arguments for !mantra command
    struct MantraArgs {
        let expectedText: String
        let timeoutSeconds: Int?
        let timeoutAction: MantraTimeoutAction?
    }

    /// Extract arguments for !mantra command
    /// Syntax: !mantra('text') or !mantra('text', timeout, 'script') or !mantra('text', timeout, ['words'])
    private func extractMantraArgs(from commandString: String) -> MantraArgs? {
        guard let parenStart = commandString.firstIndex(of: "("),
              let parenEnd = commandString.lastIndex(of: ")") else {
            return nil
        }

        let argsString = String(commandString[commandString.index(after: parenStart)..<parenEnd])
        var index = argsString.startIndex

        // Skip whitespace
        while index < argsString.endIndex && argsString[index].isWhitespace {
            index = argsString.index(after: index)
        }

        // Extract expected text (first quoted string)
        var expectedText = ""
        if index < argsString.endIndex {
            let quoteChar = argsString[index]
            if quoteChar == "'" || quoteChar == "\"" {
                index = argsString.index(after: index)
                let textStart = index
                while index < argsString.endIndex && argsString[index] != quoteChar {
                    index = argsString.index(after: index)
                }
                expectedText = String(argsString[textStart..<index])
                if index < argsString.endIndex {
                    index = argsString.index(after: index) // Skip closing quote
                }
            }
        }

        guard !expectedText.isEmpty else {
            print("Warning: Could not parse !mantra expected text")
            return nil
        }

        // Skip to comma (if any)
        while index < argsString.endIndex && argsString[index] != "," {
            index = argsString.index(after: index)
        }

        // No more arguments - simple mantra with no timeout
        if index >= argsString.endIndex {
            return MantraArgs(expectedText: expectedText, timeoutSeconds: nil, timeoutAction: nil)
        }

        // Skip comma and whitespace
        index = argsString.index(after: index)
        while index < argsString.endIndex && argsString[index].isWhitespace {
            index = argsString.index(after: index)
        }

        // Extract timeout number
        var timeoutStr = ""
        while index < argsString.endIndex && argsString[index].isNumber {
            timeoutStr.append(argsString[index])
            index = argsString.index(after: index)
        }

        guard let timeoutSeconds = Int(timeoutStr) else {
            print("Warning: Could not parse !mantra timeout value")
            return MantraArgs(expectedText: expectedText, timeoutSeconds: nil, timeoutAction: nil)
        }

        // Skip to comma
        while index < argsString.endIndex && argsString[index] != "," {
            index = argsString.index(after: index)
        }

        if index >= argsString.endIndex {
            // Has timeout but no action
            return MantraArgs(expectedText: expectedText, timeoutSeconds: timeoutSeconds, timeoutAction: nil)
        }

        // Skip comma and whitespace
        index = argsString.index(after: index)
        while index < argsString.endIndex && argsString[index].isWhitespace {
            index = argsString.index(after: index)
        }

        // Check if it's an array or a string
        if index < argsString.endIndex && argsString[index] == "[" {
            // Parse array of words
            index = argsString.index(after: index) // Skip '['
            var words: [String] = []
            var currentWord = ""
            var inQuote = false
            var quoteChar: Character = "'"

            while index < argsString.endIndex {
                let char = argsString[index]

                if char == "]" && !inQuote {
                    if !currentWord.isEmpty {
                        words.append(currentWord)
                    }
                    break
                } else if (char == "'" || char == "\"") && !inQuote {
                    inQuote = true
                    quoteChar = char
                } else if char == quoteChar && inQuote {
                    inQuote = false
                    words.append(currentWord)
                    currentWord = ""
                } else if char == "," && !inQuote {
                    // Skip comma between array elements
                } else if inQuote {
                    currentWord.append(char)
                }

                index = argsString.index(after: index)
            }

            return MantraArgs(expectedText: expectedText, timeoutSeconds: timeoutSeconds, timeoutAction: .insertWords(words))

        } else if index < argsString.endIndex && (argsString[index] == "'" || argsString[index] == "\"") {
            // Parse script name string
            let quoteChar = argsString[index]
            index = argsString.index(after: index)
            let scriptStart = index
            while index < argsString.endIndex && argsString[index] != quoteChar {
                index = argsString.index(after: index)
            }
            var scriptName = String(argsString[scriptStart..<index])

            // Strip "self." prefix if present
            if scriptName.hasPrefix("self.") {
                scriptName = String(scriptName.dropFirst(5))
            }

            return MantraArgs(expectedText: expectedText, timeoutSeconds: timeoutSeconds, timeoutAction: .jump(scriptName: scriptName))
        }

        return MantraArgs(expectedText: expectedText, timeoutSeconds: timeoutSeconds, timeoutAction: nil)
    }

    /// Extract arguments for !cond command which has special syntax with arrays
    /// Returns (condition, thenWords, elseWords?) or nil if parsing fails
    private func extractCondArgs(from commandString: String) -> (String, [String], [String]?)? {
        guard let parenStart = commandString.firstIndex(of: "("),
              let parenEnd = commandString.lastIndex(of: ")") else {
            return nil
        }

        let argsString = String(commandString[commandString.index(after: parenStart)..<parenEnd])

        // Parse: 'condition', ['word1', 'word2'], ['else1', 'else2']
        // Step 1: Find the condition (first quoted string)
        var index = argsString.startIndex
        var condition = ""
        var arrays: [[String]] = []

        // Skip whitespace
        while index < argsString.endIndex && argsString[index].isWhitespace {
            index = argsString.index(after: index)
        }

        // Extract condition string (quoted)
        if index < argsString.endIndex {
            let quoteChar = argsString[index]
            if quoteChar == "'" || quoteChar == "\"" {
                index = argsString.index(after: index)
                let condStart = index
                while index < argsString.endIndex && argsString[index] != quoteChar {
                    index = argsString.index(after: index)
                }
                condition = String(argsString[condStart..<index])
                if index < argsString.endIndex {
                    index = argsString.index(after: index) // Skip closing quote
                }
            }
        }

        // Parse remaining arrays
        while index < argsString.endIndex {
            // Skip to next '['
            while index < argsString.endIndex && argsString[index] != "[" {
                index = argsString.index(after: index)
            }

            if index >= argsString.endIndex { break }

            // Parse array
            index = argsString.index(after: index) // Skip '['
            var words: [String] = []
            var currentWord = ""
            var inQuote = false
            var quoteChar: Character = "'"

            while index < argsString.endIndex {
                let char = argsString[index]

                if char == "]" && !inQuote {
                    // End of array
                    if !currentWord.isEmpty {
                        words.append(currentWord)
                    }
                    index = argsString.index(after: index)
                    break
                } else if (char == "'" || char == "\"") && !inQuote {
                    inQuote = true
                    quoteChar = char
                } else if char == quoteChar && inQuote {
                    inQuote = false
                    words.append(currentWord)
                    currentWord = ""
                } else if char == "," && !inQuote {
                    // Skip comma between array elements
                } else if inQuote {
                    currentWord.append(char)
                }

                index = argsString.index(after: index)
            }

            arrays.append(words)
        }

        guard !condition.isEmpty, arrays.count >= 1 else {
            print("Warning: Could not parse !cond arguments: \(argsString)")
            return nil
        }

        let thenWords = arrays[0]
        let elseWords = arrays.count >= 2 ? arrays[1] : nil

        return (condition, thenWords, elseWords)
    }

    /// Evaluate a condition string for !cond command
    /// Supports: self.draw_image, self.config.fullscreen, not <condition>
    private func evaluateCondition(_ condition: String) -> Bool {
        var cond = condition.trimmingCharacters(in: .whitespaces)
        var negate = false

        // Handle "not" prefix
        if cond.lowercased().hasPrefix("not ") {
            negate = true
            cond = String(cond.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }

        var result: Bool

        switch cond {
        case "self.draw_image", "self.drawImages":
            result = state.drawImages
        case "self.draw_spiral", "self.drawSpiral":
            result = state.drawSpiral
        case "self.draw_words", "self.drawWords":
            result = state.drawWords
        case "self.speak_words", "self.speakWords":
            result = state.speakWords
        case "self.config.fullscreen":
            result = config.properties.fullscreen
        case "self.is_fullscreen", "self.isFullscreen":
            result = state.isFullscreen
        default:
            // Check if it's a variable reference
            if let varValue = state.variables[cond] {
                // Truthy check: non-empty string is true
                result = !varValue.isEmpty && varValue.lowercased() != "false" && varValue != "0"
            } else {
                print("Warning: Unknown condition '\(cond)' in !cond, defaulting to false")
                result = false
            }
        }

        return negate ? !result : result
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
    /// Optional timeout auto-selects an answer (for auto-advance behavior when user doesn't respond)
    private func showYesNoQuestion(question: String, yesScript: String, noScript: String,
                                    timeoutSeconds: Int? = nil, timeoutDefault: String? = nil) async {
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
            }, timeoutSeconds: timeoutSeconds, timeoutDefault: timeoutDefault)
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

    /// Demand user type or speak exact text back (mantra repetition)
    /// Optional timeout with action (jump to script or insert words)
    /// autoStartMic: if true, microphone starts automatically (speak_mantra)
    private func showMantra(expectedText: String, timeoutSeconds: Int?, timeoutAction: MantraTimeoutAction?, autoStartMic: Bool) async {
        await withCheckedContinuation { continuation in
            // Create timeout handler if needed
            let onTimeout: (() -> Void)? = timeoutAction.map { action in
                return {
                    self.state.currentQuestion = nil
                    self.state.isWaiting = false

                    switch action {
                    case .jump(let scriptName):
                        // Jump to the specified script
                        do {
                            try self.loadScript(named: scriptName)
                            print("Mantra timeout: jumped to script '\(scriptName)'")
                        } catch {
                            print("Error jumping to timeout script '\(scriptName)': \(error)")
                        }

                    case .insertWords(let words):
                        // Insert words after current position
                        if !words.isEmpty {
                            let insertIndex = self.state.wordsIndex
                            self.state.textSequence.insert(contentsOf: words, at: insertIndex)
                            print("Mantra timeout: inserted \(words.count) words")
                        }
                    }

                    continuation.resume()
                }
            }

            state.currentQuestion = .mantra(
                expectedText: expectedText,
                timeoutSeconds: timeoutSeconds,
                autoStartMic: autoStartMic,
                onComplete: {
                    self.state.currentQuestion = nil
                    self.state.isWaiting = false
                    continuation.resume()
                },
                onTimeout: onTimeout
            )
            state.isWaiting = true
        }
    }

    /// Show peripheral awareness test at bottom of screen
    /// If user doesn't click within timeout, jumps to specified script
    private func showAwarenessTest(message: String, timeoutSeconds: Int, jumpTarget: String) async {
        await withCheckedContinuation { continuation in
            state.currentQuestion = .awarenessTest(
                message: message,
                timeoutSeconds: timeoutSeconds,
                onDismiss: {
                    // User clicked - they're still aware
                    self.state.currentQuestion = nil
                    self.state.isWaiting = false
                    continuation.resume()
                },
                onTimeout: {
                    // User didn't notice - they're deep in trance
                    self.state.currentQuestion = nil
                    self.state.isWaiting = false

                    // Jump to the specified script
                    do {
                        try self.loadScript(named: jumpTarget)
                        print("Awareness test timeout: jumped to script '\(jumpTarget)'")
                    } catch {
                        print("Error jumping to awareness test script '\(jumpTarget)': \(error)")
                    }

                    continuation.resume()
                }
            )
            state.isWaiting = true
        }
    }

    /// Inverted awareness test - for induction relaxation checks
    /// If user CLICKS (notices the message), jumps to specified script (they're not in trance)
    /// If timeout (didn't notice), continues inline (they're in trance)
    private func showAwarenessTestInverted(message: String, timeoutSeconds: Int, jumpTarget: String) async {
        await withCheckedContinuation { continuation in
            state.currentQuestion = .awarenessTest(
                message: message,
                timeoutSeconds: timeoutSeconds,
                onDismiss: {
                    // User clicked - they noticed, not in trance
                    self.state.currentQuestion = nil
                    self.state.isWaiting = false

                    // Jump to the specified script (e.g., repeat_induction)
                    do {
                        try self.loadScript(named: jumpTarget)
                        print("Awareness test (inv): user clicked, jumped to script '\(jumpTarget)'")
                    } catch {
                        print("Error jumping to awareness test script '\(jumpTarget)': \(error)")
                    }

                    continuation.resume()
                },
                onTimeout: {
                    // User didn't notice - they're in trance, continue inline
                    self.state.currentQuestion = nil
                    self.state.isWaiting = false
                    print("Awareness test (inv): timeout, user in trance, continuing")
                    continuation.resume()
                }
            )
            state.isWaiting = true
        }
    }

    // MARK: - Camera Methods

    /// Capture a photo and save it to the CapturedImages directory
    private func captureAndSavePhoto() async {
        let cameraManager = CameraManager.shared

        // Capture the photo
        guard let cgImage = await cameraManager.capturePhoto() else {
            print("Camera capture failed: \(cameraManager.lastError ?? "Unknown error")")
            return
        }

        // Get save location
        guard let capturedDir = iCloudResourceManager.shared.getCapturedImagesURL() else {
            print("Could not get captured images directory")
            return
        }

        // Generate filename and save
        let filename = iCloudResourceManager.shared.generateCapturedImageFilename()
        let saveURL = capturedDir.appendingPathComponent(filename)

        if cameraManager.saveImage(cgImage, to: saveURL) {
            state.lastCapturedImage = cgImage
            state.lastCapturedImageURL = saveURL
            print("Saved camera capture to: \(saveURL.path)")
        } else {
            print("Failed to save camera capture: \(cameraManager.lastError ?? "Unknown error")")
        }
    }

    /// Load the most recent captured image into state
    private func loadLastCapturedImage() async {
        // Check if we already have a captured image in state
        if state.lastCapturedImage != nil {
            return
        }

        // Try to load the most recent captured image from disk
        guard let lastURL = iCloudResourceManager.shared.getLastCapturedImageURL() else {
            print("No captured images found")
            return
        }

        if let cgImage = CameraManager.loadImage(from: lastURL) {
            state.lastCapturedImage = cgImage
            state.lastCapturedImageURL = lastURL
            print("Loaded last captured image: \(lastURL.lastPathComponent)")
        } else {
            print("Could not load image from: \(lastURL.path)")
        }
    }
}

// MARK: - SpeechSynthesizerDelegate

extension SpiralEngine: SpeechSynthesizerDelegate {
    func synthesizer(_ synthesizer: SpeechSynthesizerProtocol, didSpeakWord word: String) {
        // Strip markup and trailing punctuation from the word before displaying it
        var strippedWord = stripMarkup(word)
        // Remove trailing punctuation (period, comma, exclamation, question mark)
        while let last = strippedWord.last, ".!?,;:".contains(last) {
            strippedWord.removeLast()
        }
        state.currentWord = strippedWord
        state.spokenWord = strippedWord
    }

    func synthesizerDidFinish(_ synthesizer: SpeechSynthesizerProtocol) {
        state.spokenWord = ""

        // Process queue items until we hit a sentence (to speak) or queue is empty
        Task {
            await processNextQueueItem()
        }
    }

    /// Process items from the speech queue - execute commands, speak sentences
    private func processNextQueueItem() async {
        while !speechQueue.isEmpty {
            let item = speechQueue.removeFirst()

            switch item {
            case .sentence(let text):
                // Speak this sentence and return (will continue when speech finishes)
                speechSynthesizer.speak(text)
                // state.isSpeaking stays true
                return

            case .command(let commandString):
                // Execute the command and wait for it to complete before continuing
                await executeCommand(commandString)
            }
        }

        // Queue is empty
        state.isSpeaking = false

        // Only clear displayed word if words were on during speech
        if state.drawWords {
            state.currentWord = ""
        }
    }
}
