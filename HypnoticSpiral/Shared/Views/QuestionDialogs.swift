//
//  QuestionDialogs.swift
//  HypnoticSpiral
//
//  Overlay dialogs for in-session questions and prompts
//

import SwiftUI
import Speech
#if os(macOS)
import AVFoundation
#endif

/// Simple message prompt with OK button
struct PromptDialog: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(message)
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding()

            Button("OK") {
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .background(Color(white: 0.1))
        .cornerRadius(12)
        .shadow(radius: 20)
    }
}

/// Text input question that stores answer in a variable
struct OpenQuestionDialog: View {
    let prompt: String
    let variableName: String
    let onSubmit: (String) -> Void

    @State private var answer: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text(prompt)
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding()

            TextField("Your answer", text: $answer)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    submitAnswer()
                }
                .frame(width: 300)

            Button("Submit") {
                submitAnswer()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(answer.isEmpty)
        }
        .padding(40)
        .background(Color(white: 0.1))
        .cornerRadius(12)
        .shadow(radius: 20)
        .onAppear {
            // Auto-focus the text field
            isFocused = true
        }
    }

    private func submitAnswer() {
        guard !answer.isEmpty else { return }
        onSubmit(answer)
    }
}

/// Yes/No question that branches to different scripts
struct YesNoQuestionDialog: View {
    let question: String
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(question)
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding()

            HStack(spacing: 20) {
                Button("No") {
                    onNo()
                }
                .keyboardShortcut("n")
                .buttonStyle(.bordered)

                Button("Yes") {
                    onYes()
                }
                .keyboardShortcut("y")
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .background(Color(white: 0.1))
        .cornerRadius(12)
        .shadow(radius: 20)
    }
}

/// Challenge question (like open_question but for interactive challenges)
struct ChallengeDialog: View {
    let prompt: String
    let variableName: String
    let onSubmit: (String) -> Void

    @State private var answer: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text(prompt)
                .font(.title2)
                .multilineTextAlignment(.center)
                .foregroundColor(.orange)
                .padding()

            TextField("Your answer", text: $answer)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    submitAnswer()
                }
                .frame(width: 300)

            Button("Submit") {
                submitAnswer()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .background(Color(white: 0.1))
        .cornerRadius(12)
        .shadow(radius: 20)
        .onAppear {
            isFocused = true
        }
    }

    private func submitAnswer() {
        onSubmit(answer)
    }
}

/// Persistent preference question - saves to SharedVariables
struct SetPrefDialog: View {
    let prompt: String
    let variableName: String
    let onSubmit: (String) -> Void

    @State private var answer: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(prompt)
                    .font(.title2)
                    .multilineTextAlignment(.center)

                Text("(This will be saved for future sessions)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            TextField("Your answer", text: $answer)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    submitAnswer()
                }
                .frame(width: 300)

            Button("Save") {
                submitAnswer()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(answer.isEmpty)
        }
        .padding(40)
        .background(Color(white: 0.1))
        .cornerRadius(12)
        .shadow(radius: 20)
        .onAppear {
            isFocused = true
        }
    }

    private func submitAnswer() {
        guard !answer.isEmpty else { return }
        onSubmit(answer)
    }
}

/// Mantra dialog - user must type or speak exact text to proceed
/// Spiral keeps animating, only word advancement is paused
/// Optional timeout triggers onTimeout callback
/// Supports speech recognition as alternative to typing
struct MantraDialog: View {
    let expectedText: String
    let timeoutSeconds: Int?
    let autoStartMic: Bool  // If true, microphone starts automatically
    let onComplete: () -> Void
    let onTimeout: (() -> Void)?

    @State private var userInput: String = ""
    @State private var remainingSeconds: Int = 0
    @State private var timer: Timer?
    @State private var isListening: Bool = false
    @State private var speechError: String?
    @State private var speechRecognizer: SpeechRecognizer?
    @State private var recognizedText: String = ""
    @FocusState private var isFocused: Bool

    /// Check if user input matches expected text (case-insensitive, trimmed)
    private var inputMatches: Bool {
        let input = userInput.trimmingCharacters(in: .whitespaces).lowercased()
        let expected = expectedText.trimmingCharacters(in: .whitespaces).lowercased()
        return input == expected
    }

    /// Check if spoken text matches (more lenient - removes punctuation)
    private var spokenMatches: Bool {
        let spoken = normalizeForSpeech(recognizedText)
        let expected = normalizeForSpeech(expectedText)
        return spoken == expected
    }

    /// Whether we have an active timeout
    private var hasTimeout: Bool {
        timeoutSeconds != nil && onTimeout != nil
    }

    var body: some View {
        VStack(spacing: 20) {
            // Timeout indicator
            if hasTimeout && remainingSeconds > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundColor(remainingSeconds <= 5 ? .red : .orange)
                    Text("\(remainingSeconds)s")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(remainingSeconds <= 5 ? .red : .orange)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(remainingSeconds <= 5 ? Color.red.opacity(0.2) : Color.orange.opacity(0.2))
                )
                .animation(.easeInOut(duration: 0.3), value: remainingSeconds <= 5)
            }

            // Instruction
            Text(isListening ? "Speak now:" : (autoStartMic ? "Speak or type:" : "Type below:"))
                .font(.caption)
                .foregroundColor(isListening ? .green : .secondary)

            // Expected text (what user must type/say)
            Text(expectedText)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Input area with optional mic button
            HStack(spacing: 12) {
                // Text input field
                TextField("", text: $userInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 20))
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .onSubmit {
                        if inputMatches {
                            completeMantra()
                        }
                    }
                    .frame(width: 300)
                    .disabled(isListening)
                    #if os(iOS)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    #endif

                // Microphone button - only shown for speak_mantra (autoStartMic=true)
                if autoStartMic {
                    Button {
                        toggleSpeechRecognition()
                    } label: {
                        Image(systemName: isListening ? "mic.fill" : "mic.slash")
                            .font(.system(size: 24))
                            .foregroundColor(isListening ? .green : .gray)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(isListening ? Color.green.opacity(0.3) : Color.white.opacity(0.1))
                            )
                            .overlay(
                                // Pulsing ring when listening
                                Circle()
                                    .stroke(isListening ? Color.green : Color.clear, lineWidth: 2)
                                    .scaleEffect(isListening ? 1.4 : 1.0)
                                    .opacity(isListening ? 0 : 1)
                                    .animation(
                                        isListening ? Animation.easeOut(duration: 1.0).repeatForever(autoreverses: false) : .default,
                                        value: isListening
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(isListening ? "Mute microphone" : "Unmute microphone")
                }
            }

            // Recognized speech display
            if !recognizedText.isEmpty {
                Text("\"\(recognizedText)\"")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(spokenMatches ? .green : .white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(spokenMatches ? Color.green.opacity(0.2) : Color.white.opacity(0.1))
                    )
            } else if isListening {
                // Subtle listening indicator when no text yet
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Circle().fill(Color.green.opacity(0.6)).frame(width: 6, height: 6)
                    Circle().fill(Color.green.opacity(0.3)).frame(width: 6, height: 6)
                }
                .padding(.vertical, 8)
            }

            // Error display
            if let error = speechError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            // Visual feedback - show checkmark when match
            if inputMatches || spokenMatches {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
                    .transition(.scale.combined(with: .opacity))
            } else if !userInput.isEmpty && !isListening {
                Text("Keep typing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Submit button (enabled when text or speech matches)
            Button("Continue") {
                completeMantra()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!inputMatches && !spokenMatches)
        }
        .padding(40)
        .background(Color(white: 0.1).opacity(0.95))
        .cornerRadius(12)
        .shadow(radius: 20)
        .animation(.easeInOut(duration: 0.2), value: inputMatches)
        .animation(.easeInOut(duration: 0.2), value: spokenMatches)
        .animation(.easeInOut(duration: 0.2), value: isListening)
        .onAppear {
            isFocused = !autoStartMic  // Focus text field only if not auto-starting mic
            startTimer()
            // Auto-start mic for speak_mantra command
            if autoStartMic {
                requestSpeechPermissionsAndStart()
            }
        }
        .onDisappear {
            stopTimer()
            stopSpeechRecognition()
        }
    }

    // MARK: - Speech Recognition

    private func requestSpeechPermissionsAndStart() {
        // Request permissions in stages so we can see where it fails
        NSLog("MantraDialog: Step 1 - Requesting microphone permission...")

        #if os(macOS)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { micGranted in
                if micGranted {
                    self.requestSpeechRecognitionPermission()
                } else {
                    Task { @MainActor in
                        self.speechError = "Microphone permission denied"
                    }
                }
            }
        } else if micStatus == .authorized {
            requestSpeechRecognitionPermission()
        } else {
            speechError = "Microphone permission denied"
        }
        #else
        // iOS - request microphone then speech
        let audioSession = AVAudioSession.sharedInstance()
        audioSession.requestRecordPermission { micGranted in
            guard micGranted else {
                Task { @MainActor in
                    self.speechError = "Microphone permission denied"
                }
                return
            }
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    if status == .authorized {
                        let recognizer = SpeechRecognizer()
                        self.speechRecognizer = recognizer
                        self.startSpeechRecognition()
                    } else {
                        self.speechError = "Speech permission denied"
                    }
                }
            }
        }
        #endif
    }

    #if os(macOS)
    private func requestSpeechRecognitionPermission() {
        NSLog("MantraDialog: Step 2 - Requesting speech recognition permission...")

        // Check current status first
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        NSLog("MantraDialog: Current speech status: \(speechStatus.rawValue)")

        if speechStatus == .notDetermined {
            NSLog("MantraDialog: Calling SFSpeechRecognizer.requestAuthorization...")
            SFSpeechRecognizer.requestAuthorization { status in
                NSLog("MantraDialog: Speech permission result: \(status.rawValue)")
                Task { @MainActor in
                    if status == .authorized {
                        self.createRecognizerAndStart()
                    } else {
                        self.speechError = "Speech recognition denied"
                    }
                }
            }
        } else if speechStatus == .authorized {
            NSLog("MantraDialog: Speech already authorized")
            Task { @MainActor in
                self.createRecognizerAndStart()
            }
        } else {
            Task { @MainActor in
                self.speechError = "Speech recognition denied"
            }
        }
    }

    private func createRecognizerAndStart() {
        NSLog("MantraDialog: Step 3 - Creating speech recognizer...")

        // Wait a moment for macOS to fully process permissions
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            NSLog("MantraDialog: Step 4 - Actually creating recognizer now...")
            let recognizer = SpeechRecognizer()
            self.speechRecognizer = recognizer
            NSLog("MantraDialog: Step 5 - Starting speech recognition...")
            self.startSpeechRecognition()
        }
    }
    #endif

    private func toggleSpeechRecognition() {
        if isListening {
            stopSpeechRecognition()
        } else {
            // If no recognizer exists yet, request permissions and create one
            if speechRecognizer == nil {
                requestSpeechPermissionsAndStart()
            } else {
                startSpeechRecognition()
            }
        }
    }

    private func startSpeechRecognition() {
        guard let recognizer = speechRecognizer else {
            // This shouldn't happen if toggleSpeechRecognition is used properly
            speechError = "Tap microphone to enable speech"
            return
        }

        guard recognizer.isAuthorized else {
            // Try requesting again
            recognizer.requestAuthorization { authorized in
                if authorized {
                    startSpeechRecognition()
                } else {
                    speechError = "Please enable speech recognition in Settings"
                }
            }
            return
        }

        speechError = nil
        recognizedText = ""
        isListening = true
        isFocused = false

        // Set up delegate using a coordinator
        let coordinator = SpeechCoordinator { text in
            recognizedText = text
            // Auto-complete if speech matches
            if normalizeForSpeech(text) == normalizeForSpeech(expectedText) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if spokenMatches {
                        completeMantra()
                    }
                }
            }
        } onStop: {
            isListening = false
            // Auto-restart listening if we haven't completed yet
            // (speech recognition times out after periods of silence)
            if speechRecognizer != nil && !spokenMatches && !inputMatches {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if !spokenMatches && !inputMatches {
                        startSpeechRecognition()
                    }
                }
            }
        } onError: { error in
            // Don't show transient errors, just restart
            if error.contains("not authorized") {
                speechError = error
            }
            isListening = false
            // Auto-restart on error (unless auth issue)
            if !error.contains("not authorized") && !spokenMatches && !inputMatches {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !spokenMatches && !inputMatches {
                        startSpeechRecognition()
                    }
                }
            }
        }

        speechCoordinator = coordinator
        recognizer.delegate = coordinator
        recognizer.startListening()
    }

    @State private var speechCoordinator: SpeechCoordinator?

    private func stopSpeechRecognition() {
        speechRecognizer?.stopListening()
        speechRecognizer = nil  // Prevent auto-restart
        isListening = false
    }

    /// Normalize text for speech comparison (remove punctuation, lowercase, collapse spaces)
    private func normalizeForSpeech(_ text: String) -> String {
        let lowercased = text.lowercased()
        let noPunctuation = lowercased.filter { $0.isLetter || $0.isWhitespace || $0.isNumber }
        let collapsed = noPunctuation.split(separator: " ").joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Timer

    private func startTimer() {
        guard let timeout = timeoutSeconds, onTimeout != nil else { return }

        remainingSeconds = timeout
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if remainingSeconds > 1 {
                remainingSeconds -= 1
            } else {
                stopTimer()
                stopSpeechRecognition()
                onTimeout?()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func completeMantra() {
        stopTimer()
        stopSpeechRecognition()
        onComplete()
    }
}

/// Coordinator class to act as SpeechRecognizerDelegate
@MainActor
private class SpeechCoordinator: SpeechRecognizerDelegate {
    let onRecognize: (String) -> Void
    let onStop: () -> Void
    let onError: (String) -> Void

    init(onRecognize: @escaping (String) -> Void, onStop: @escaping () -> Void, onError: @escaping (String) -> Void) {
        self.onRecognize = onRecognize
        self.onStop = onStop
        self.onError = onError
    }

    func speechRecognizer(_ recognizer: SpeechRecognizer, didRecognize text: String) {
        onRecognize(text)
    }

    func speechRecognizerDidStop(_ recognizer: SpeechRecognizer) {
        onStop()
    }

    func speechRecognizer(_ recognizer: SpeechRecognizer, didFailWithError error: String) {
        onError(error)
    }
}
