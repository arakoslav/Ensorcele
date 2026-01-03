//
//  SpiralView.swift
//  HypnoticSpiral
//
//  Main spiral display view with rendering pipeline
//

import SwiftUI

struct SpiralView: View {
    let config: SpiralConfig
    @StateObject private var state = SpiralState()
    @StateObject private var engine: SpiralEngine
    @State private var isLoading = true
    @State private var windowSize: CGSize = .zero
    @State private var showUI = false  // Start with UI hidden
    @State private var mouseIdleTimer: Timer?
    @State private var tempoMultiplier: Double = 1.0
    @Environment(\.dismiss) private var dismiss

    init(config: SpiralConfig) {
        self.config = config
        let state = SpiralState()
        _state = StateObject(wrappedValue: state)
        _engine = StateObject(wrappedValue: SpiralEngine(state: state, config: config))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                if isLoading {
                    // Loading screen
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Loading \(config.name)...")
                            .foregroundColor(.white)
                            .font(.title2)
                    }
                } else {
                    // Main spiral rendering view
                    SpiralRenderView(state: state, config: config)
                }

                // Overlay controls (auto-hide on mouse idle)
                if showUI {
                    // Top bar with title and close button
                    VStack {
                        HStack {
                            Text(config.name)
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.7))
                                .padding()
                            Spacer()
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .padding()
                        }
                        .background(Color.black.opacity(0.5))
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    #if os(macOS)
                    .onContinuousHover { _ in onMouseMoved() }
                    #endif

                    // Bottom tempo slider
                    VStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Text("Tempo: \(String(format: "%.1f", tempoMultiplier))x")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))

                            HStack {
                                Text("0.5x")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.5))
                                Slider(value: $tempoMultiplier, in: 0.5...2.0, step: 0.1)
                                    .frame(maxWidth: 300)
                                    .onChange(of: tempoMultiplier) { oldValue, newValue in
                                        adjustTempo(newValue)
                                    }
                                Text("2.0x")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                        .padding(.bottom, 20)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    #if os(macOS)
                    .onContinuousHover { _ in onMouseMoved() }
                    #endif

                    // Left sidebar with table of contents
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scripts")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.bottom, 4)

                            ScrollView {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(Array(config.scripts.keys.sorted()), id: \.self) { scriptName in
                                        Button(action: {
                                            jumpToScript(scriptName)
                                        }) {
                                            Text(scriptName)
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.7))
                                                .padding(.vertical, 4)
                                                .padding(.horizontal, 8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(4)
                                    }
                                }
                            }
                        }
                        .frame(width: 150)
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                        .padding(.leading, 20)

                        Spacer()
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    #if os(macOS)
                    .onContinuousHover { _ in onMouseMoved() }
                    #endif
                }

                // Invisible overlay to track mouse movement (only blocks when UI is hidden)
                #if os(macOS)
                Color.clear
                    .contentShape(Rectangle())
                    .allowsHitTesting(!showUI)  // Don't block interaction when UI is visible
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(_):
                            onMouseMoved()
                        case .ended:
                            break
                        }
                    }
                #else
                // On iOS, use tap gesture to show/reset UI
                Color.clear
                    .contentShape(Rectangle())
                    .allowsHitTesting(!showUI)  // Don't block interaction when UI is visible
                    .onTapGesture {
                        onUserInteraction()
                    }
                #endif

                // Question dialogs (modal overlays)
                if let question = state.currentQuestion {
                    Color.black.opacity(0.8)
                        .ignoresSafeArea()

                    switch question {
                    case .prompt(let message, let completion):
                        PromptDialog(message: message, onDismiss: completion)

                    case .openQuestion(let prompt, let variableName, let completion):
                        OpenQuestionDialog(prompt: prompt, variableName: variableName, onSubmit: completion)

                    case .yesNo(let question, let onYes, let onNo):
                        YesNoQuestionDialog(question: question, onYes: onYes, onNo: onNo)

                    case .challenge(let prompt, let variableName, let completion):
                        ChallengeDialog(prompt: prompt, variableName: variableName, onSubmit: completion)

                    case .setPref(let prompt, let variableName, let completion):
                        SetPrefDialog(prompt: prompt, variableName: variableName, onSubmit: completion)
                    }
                }
            }
            .onAppear {
                windowSize = geometry.size
            }
            .onChange(of: geometry.size) { oldSize, newSize in
                windowSize = newSize
                Task {
                    await regenerateSpiral(size: newSize)
                }
            }
        }
        .task {
            await loadResources()
        }
        .onAppear {
            #if os(iOS)
            // Prevent screen from sleeping during spiral playback
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
        }
        .onDisappear {
            engine.stop()
            mouseIdleTimer?.invalidate()

            #if os(iOS)
            // Re-enable screen sleep when leaving spiral view
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
        #if os(macOS)
        .toolbar(showUI ? .visible : .hidden, for: .windowToolbar)
        .navigationTitle(config.properties.fullscreen ? "" : config.name)
        .requestFullscreen(config.properties.fullscreen)
        #endif
    }

    /// Handle user interaction - show UI and reset hide timer
    private func onUserInteraction() {
        withAnimation(.easeOut(duration: 0.3)) {
            showUI = true
        }

        // Cancel existing timer
        mouseIdleTimer?.invalidate()

        // Platform-specific timeout: 3s on macOS (mouse movement), 10s on iOS (tap)
        #if os(macOS)
        let timeout = 3.0
        #else
        let timeout = 10.0
        #endif

        // Start new timer to hide UI after timeout
        mouseIdleTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                showUI = false
            }
        }
    }

    /// Handle mouse movement on macOS
    private func onMouseMoved() {
        onUserInteraction()
    }

    /// Adjust playback tempo
    private func adjustTempo(_ multiplier: Double) {
        // Update the engine's effective time scale
        // The engine uses config.properties.timeScale, but we can adjust it dynamically
        engine.tempoMultiplier = multiplier
    }

    /// Jump to a specific script
    private func jumpToScript(_ scriptName: String) {
        do {
            try engine.loadScript(named: scriptName)
        } catch {
            print("Error loading script '\(scriptName)': \(error)")
        }
    }

    /// Regenerate spiral for new window size
    private func regenerateSpiral(size: CGSize) async {
        guard size != .zero else { return }
        print("Regenerating spiral for size: \(size)")
        await Task {
            state.spiralImage = SpiralRenderer.generateSpiral(config: config, size: size)
        }.value
    }

    /// Load spiral frames and initialize state
    private func loadResources() async {
        // Wait for window size to be set (with timeout)
        var attempts = 0
        while windowSize == .zero && attempts < 50 {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            attempts += 1
        }

        // Fallback to config size if geometry not detected
        let targetSize = windowSize == .zero
            ? CGSize(width: config.properties.size[0], height: config.properties.size[1])
            : windowSize

        print("Loading resources with size: \(targetSize)")

        // Generate single spiral image for real-time rotation
        await regenerateSpiral(size: targetSize)

        // Load images from directory
        await Task {
            let (images, unshuffledImages, filenames) = ImageLoader.loadImages(
                from: config.properties.imageDir,
                shuffle: config.properties.shuffleImages
            )
            state.images = images
            state.unshuffledImages = unshuffledImages
            state.imageFilenames = filenames
        }.value

        // Load initial script (usually "body")
        do {
            try engine.loadScript(named: "body")
        } catch {
            print("Warning: Could not load 'body' script: \(error)")
        }

        // Initialize state
        state.config = config
        state.initializeFrequencies(from: config)
        state.drawSpiral = true
        state.drawWords = true
        state.drawImages = false  // Start with images off, turn on with !images_on()

        // Load shared variables (name, master, gender)
        state.variables = SharedVariables.shared.asDictionary()

        isLoading = false

        // Start the animation engine
        engine.start()
    }
}

/// Main rendering view for spiral, text, and images
struct SpiralRenderView: View {
    @ObservedObject var state: SpiralState
    let config: SpiralConfig

    var body: some View {
        ZStack {
            // Background color
            Color.black

            // Image layer (bottom) - fill entire screen including title bar area
            if state.drawImages && !state.images.isEmpty {
                currentImageView
                    .ignoresSafeArea()
            }

            // Spiral layer (middle)
            if state.drawSpiral, let spiral = state.spiralImage {
                spiralImageView(spiral)
            }

            // Background text (large, faded, vertically centered to full screen)
            if !state.backgroundText.isEmpty {
                VStack {
                    Spacer()
                    ConfiguredText(state.backgroundText, config: config, fontSize: 300)
                        .opacity(0.3)
                        .minimumScaleFactor(0.1)
                        .lineLimit(nil)
                    Spacer()
                }
                .ignoresSafeArea()
            }

            // Persistent text (held text - vertically centered to full screen)
            if !state.persistentText.isEmpty {
                VStack {
                    Spacer()
                    ConfiguredText(state.persistentText, config: config, fontSize: 64)
                    Spacer()
                }
                .ignoresSafeArea()
            }

            // Main word display (center of full screen)
            if state.drawWords && !state.currentWord.isEmpty {
                ConfiguredText(state.currentWord, config: config, fontSize: 64)
                    .ignoresSafeArea()
            }

            // Subliminal text (speaker.py feature - random position)
            if !state.subliminalText.isEmpty {
                SubliminalTextView(state: state, config: config)
                    .ignoresSafeArea()
            }

            // Spoken word indicator
            if state.isSpeaking && !state.spokenWord.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(state.spokenWord)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                            .padding(8)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                            .padding()
                    }
                }
            }
        }
    }

    /// Spiral image with real-time rotation, scale pulsing, and wobble
    private func spiralImageView(_ spiral: CGImage) -> some View {
        GeometryReader { geometry in
            Image(decorative: spiral, scale: 1.0)
                .opacity(Double(config.properties.alpha) / 255.0)
                .rotationEffect(.degrees(state.spiralRotation))
                .scaleEffect(state.spiralScale)
                .rotation3DEffect(
                    .degrees(state.spiralTiltX),
                    axis: (x: 1.0, y: 0.0, z: 0.0)
                )
                .rotation3DEffect(
                    .degrees(state.spiralTiltY),
                    axis: (x: 0.0, y: 1.0, z: 0.0)
                )
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .ignoresSafeArea()
    }

    /// Current image
    @ViewBuilder
    private var currentImageView: some View {
        // If hold_image is active, show the held image from unshuffled array (doesn't cycle)
        // Otherwise show the normally cycling image from shuffled array
        let imageToShow: CGImage? = {
            if state.holdImageIndex >= 0 && state.holdImageIndex < state.unshuffledImages.count {
                return state.unshuffledImages[state.holdImageIndex]
            } else if state.imageIndex < state.images.count {
                return state.images[state.imageIndex]
            } else {
                return nil
            }
        }()

        if let image = imageToShow {
            Image(decorative: image, scale: 1.0)
                .resizable()
                .scaledToFit()
                .opacity(Double(config.properties.imageAlpha) / 255.0)
        }
    }
}

/// Subliminal text with random positioning (speaker.py feature)
struct SubliminalTextView: View {
    @ObservedObject var state: SpiralState
    let config: SpiralConfig
    @State private var position: CGPoint = .zero

    var body: some View {
        if let subliminalColor = config.properties.subliminalColor,
           let subliminalAlpha = config.properties.subliminalAlpha {

            let textColor = Color(
                red: Double(subliminalColor[0]) / 255.0,
                green: Double(subliminalColor[1]) / 255.0,
                blue: Double(subliminalColor[2]) / 255.0
            )

            Text(state.subliminalText)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(textColor.opacity(Double(subliminalAlpha) / 255.0))
                .position(position)
                .onAppear {
                    randomizePosition()
                }
        }
    }

    private func randomizePosition() {
        // TODO: Implement probabilistic repositioning based on config
        let scatter = config.properties.subliminalScatter ?? 200
        position = CGPoint(
            x: CGFloat.random(in: 100...700),
            y: CGFloat.random(in: 100...500)
        )
    }
}
