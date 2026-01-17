//
//  SpiralView.swift
//  HypnoticSpiral
//
//  Main spiral display view with rendering pipeline
//

import SwiftUI
import Combine

struct SpiralView: View {
    let config: SpiralConfig
    let savedState: SavedSessionState?
    @StateObject private var state = SpiralState()
    @StateObject private var engine: SpiralEngine
    @State private var isLoading = true
    @State private var windowSize: CGSize = .zero
    @State private var showUI = false  // Start with UI hidden
    @State private var mouseIdleTimer: Timer?
    @State private var tempoMultiplier: Double = 1.0
    @Environment(\.dismiss) private var dismiss

    init(config: SpiralConfig, savedState: SavedSessionState? = nil) {
        self.config = config
        self.savedState = savedState
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
                    loadingView
                } else {
                    SpiralRenderView(state: state, config: config)
                }

                if showUI {
                    overlayControlsView
                }

                mouseTrackingOverlay

                questionDialogView
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
            .onChange(of: state.activeSpiralType) { oldType, newType in
                Task {
                    await regenerateSpiral(size: windowSize)
                }
            }
            .onChange(of: state.runtimeImageDir) { oldDir, newDir in
                if let newDir = newDir {
                    Task {
                        await reloadImages(from: newDir)
                    }
                }
            }
        }
        .task {
            await loadResources()
        }
        .onChange(of: state.programEnded) { _, ended in
            if ended {
                dismiss()
            }
        }
        .onReceive(state.$currentQuestion) { newQuestion in
            // Hide UI when awareness test begins (user should focus on spiral)
            if case .awarenessTest = newQuestion {
                withAnimation(.easeOut(duration: 0.3)) {
                    showUI = false
                }
                mouseIdleTimer?.invalidate()
            }
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

    // MARK: - Extracted Sub-Views

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            Text("Loading \(config.name)...")
                .foregroundColor(.white)
                .font(.title2)
        }
    }

    @ViewBuilder
    private var overlayControlsView: some View {
        topBarView
        bottomTempoView
        leftSidebarView
        rightSidebarView
    }

    private var topBarView: some View {
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
        #else
        .simultaneousGesture(TapGesture().onEnded { onUserInteraction() })
        #endif
    }

    private var bottomTempoView: some View {
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
                    Slider(value: $tempoMultiplier, in: 0.5...5.0, step: 0.1)
                        .frame(maxWidth: 300)
                        .onChange(of: tempoMultiplier) { oldValue, newValue in
                            adjustTempo(newValue)
                        }
                    Text("5.0x")
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
        #else
        .simultaneousGesture(TapGesture().onEnded { onUserInteraction() })
        #endif
    }

    private var leftSidebarView: some View {
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
        #else
        .simultaneousGesture(TapGesture().onEnded { onUserInteraction() })
        #endif
    }

    private var rightSidebarView: some View {
        HStack {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text("Controls")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 4)

                spiralTypePicker
                imagesToggleButton
                speakingToggleButton
            }
            .frame(width: 150)
            .padding()
            .background(Color.black.opacity(0.5))
            .cornerRadius(8)
            .padding(.trailing, 20)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
        #if os(macOS)
        .onContinuousHover { _ in onMouseMoved() }
        #else
        .simultaneousGesture(TapGesture().onEnded { onUserInteraction() })
        #endif
    }

    private var spiralTypePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Spiral")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))

            ForEach(SpiralType.allCases, id: \.self) { type in
                Button {
                    state.activeSpiralType = type
                } label: {
                    HStack(spacing: 6) {
                        Text(type.rawValue.capitalized)
                            .font(.caption)
                        Spacer()
                        if state.activeSpiralType == type {
                            Image(systemName: "checkmark")
                                .font(.caption2)
                        }
                    }
                    .foregroundColor(state.activeSpiralType == type ? .white : .white.opacity(0.6))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(state.activeSpiralType == type ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var imagesToggleButton: some View {
        Button(action: {
            state.drawImages.toggle()
        }) {
            HStack(spacing: 6) {
                Image(systemName: state.drawImages ? "photo.fill" : "photo")
                    .font(.caption)
                Text("Images")
                    .font(.caption)
            }
            .foregroundColor(state.drawImages ? .white : .white.opacity(0.5))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(state.drawImages ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private var speakingToggleButton: some View {
        Button(action: {
            state.speakWords.toggle()
        }) {
            HStack(spacing: 6) {
                Image(systemName: state.speakWords ? "speaker.wave.2.fill" : "speaker.slash")
                    .font(.caption)
                Text("Speaking")
                    .font(.caption)
            }
            .foregroundColor(state.speakWords ? .white : .white.opacity(0.5))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(state.speakWords ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var mouseTrackingOverlay: some View {
        #if os(macOS)
        Color.clear
            .contentShape(Rectangle())
            .allowsHitTesting(!showUI && !isAwarenessTestActive)
            .onContinuousHover { phase in
                switch phase {
                case .active(_):
                    onMouseMoved()
                case .ended:
                    break
                }
            }
        #else
        if !showUI && !isAwarenessTestActive {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    onUserInteraction()
                }
        }
        #endif
    }

    @ViewBuilder
    private var questionDialogView: some View {
        if let question = state.currentQuestion {
            switch question {
            case .prompt(let message, let completion):
                PromptDialog(message: message, onDismiss: completion)

            case .openQuestion(let prompt, let variableName, let completion):
                OpenQuestionDialog(prompt: prompt, variableName: variableName, onSubmit: completion)

            case .yesNo(let question, let onYes, let onNo, let timeoutSeconds, let timeoutDefault):
                YesNoQuestionDialog(question: question, onYes: onYes, onNo: onNo,
                                    timeoutSeconds: timeoutSeconds, timeoutDefault: timeoutDefault)

            case .challenge(let prompt, let variableName, let completion):
                ChallengeDialog(prompt: prompt, variableName: variableName, onSubmit: completion)

            case .setPref(let prompt, let variableName, let completion):
                SetPrefDialog(prompt: prompt, variableName: variableName, onSubmit: completion)

            case .mantra(let expectedText, let timeoutSeconds, let autoStartMic, let onComplete, let onTimeout):
                MantraDialog(expectedText: expectedText, timeoutSeconds: timeoutSeconds, autoStartMic: autoStartMic, onComplete: onComplete, onTimeout: onTimeout)

            case .awarenessTest(let message, let timeoutSeconds, let onDismiss, let onTimeout):
                AwarenessTestDialog(message: message, timeoutSeconds: timeoutSeconds, onDismiss: onDismiss, onTimeout: onTimeout)
            }
        }
    }

    /// Check if an awareness test is currently showing (suppress UI in this case)
    private var isAwarenessTestActive: Bool {
        if case .awarenessTest = state.currentQuestion {
            return true
        }
        return false
    }

    /// Handle user interaction - show UI and reset hide timer
    private func onUserInteraction() {
        // Don't show UI during awareness test - user should keep staring at spiral
        guard !isAwarenessTestActive else { return }

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

    /// Regenerate spiral for new window size or type change
    private func regenerateSpiral(size: CGSize) async {
        guard size != .zero else { return }
        let spiralType = state.activeSpiralType
        print("Regenerating spiral for size: \(size), type: \(spiralType)")
        await Task {
            // Rings type uses Canvas-based rendering (no bitmap needed)
            if spiralType == .rings {
                state.spiralImage = nil
                state.counterSpiralImage = nil
                state.spiralFrames = []
                print("Using Canvas-based rendering for rings")
            } else {
                state.spiralFrames = []
                state.spiralImage = SpiralRenderer.generateSpiral(config: config, size: size, spiralType: spiralType)
                // Generate counter-rotating layer for twist spirals
                state.counterSpiralImage = SpiralRenderer.generateCounterSpiral(config: config, size: size, spiralType: spiralType)
            }
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

        // Check if we're resuming from saved state
        if let saved = savedState {
            // Restore saved session
            engine.restoreSession(from: saved)
            state.config = config
            state.initializeFrequencies(from: config)
            state.activeSpiralType = config.properties.spiralType

            // Merge saved variables with shared variables (saved takes precedence for session vars)
            var mergedVars = SharedVariables.shared.asDictionary()
            for (key, value) in saved.variables {
                mergedVars[key] = value
            }
            state.variables = mergedVars

            print("Resumed session for '\(config.name)' at word \(saved.wordsIndex)")
        } else {
            // Fresh start - load initial script (usually "text")
            do {
                try engine.loadScript(named: "text")
            } catch {
                print("Warning: Could not load 'text' script: \(error)")
            }

            // Initialize state
            state.config = config
            state.initializeFrequencies(from: config)
            state.drawSpiral = true
            state.drawWords = true
            state.drawImages = false  // Start with images off, turn on with !images_on()
            state.activeSpiralType = config.properties.spiralType

            // Load shared variables (name, master, gender)
            state.variables = SharedVariables.shared.asDictionary()

            // Clear any old saved state for fresh start
            SessionStateManager.shared.clearState(for: config.name)
        }

        isLoading = false

        // Start the animation engine
        engine.start()
    }

    /// Reload images from a new directory (called when runtimeImageDir changes)
    private func reloadImages(from directory: String) async {
        await Task {
            let (images, unshuffledImages, filenames) = ImageLoader.loadImages(
                from: directory,
                shuffle: config.properties.shuffleImages
            )
            state.images = images
            state.unshuffledImages = unshuffledImages
            state.imageFilenames = filenames
            print("Reloaded \(images.count) images from \(directory)")
        }.value
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
            if state.drawSpiral {
                // Use Canvas-based rendering for rings type (hardware accelerated)
                if state.activeSpiralType == .rings {
                    RingsCanvasView(state: state, config: config)
                        .opacity(Double(state.getEffectiveSpiralAlpha()) / 255.0)
                } else if let spiral = state.spiralImage {
                    // Bitmap-based rendering for other spiral types
                    spiralImageView(spiral, rotation: state.spiralRotation,
                                   tiltX: state.spiralTiltX, tiltY: state.spiralTiltY)

                    // Counter-rotating layer for twist spirals (separate wobble surface)
                    if let counterSpiral = state.counterSpiralImage {
                        spiralImageView(counterSpiral, rotation: state.counterSpiralRotation,
                                       tiltX: state.counterSpiralTiltX, tiltY: state.counterSpiralTiltY)
                            .blendMode(.screen)  // Blend with main spiral
                    }
                }
            }

            // Background text (large, faded, vertically centered to full screen)
            if !state.backgroundText.isEmpty {
                VStack {
                    Spacer()
                    ConfiguredText(state.backgroundText, config: config,
                                   fontSize: state.getEffectiveBackgroundFontSize(), state: state)
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
                    ConfiguredText(state.persistentText, config: config,
                                   fontSize: state.getEffectiveFontSize(), state: state)
                    Spacer()
                }
                .ignoresSafeArea()
            }

            // Main word display (center of full screen)
            if state.drawWords && !state.currentWord.isEmpty {
                ConfiguredText(state.currentWord, config: config,
                               fontSize: state.getEffectiveFontSize(), state: state)
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
    private func spiralImageView(_ spiral: CGImage, rotation: Double, tiltX: Double, tiltY: Double) -> some View {
        GeometryReader { geometry in
            Image(decorative: spiral, scale: 1.0)
                .opacity(Double(config.properties.alpha) / 255.0)
                .rotationEffect(.degrees(rotation))
                .scaleEffect(state.spiralScale)
                .rotation3DEffect(
                    .degrees(tiltX),
                    axis: (x: 1.0, y: 0.0, z: 0.0)
                )
                .rotation3DEffect(
                    .degrees(tiltY),
                    axis: (x: 0.0, y: 1.0, z: 0.0)
                )
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .ignoresSafeArea()
    }

    /// Current image
    @ViewBuilder
    private var currentImageView: some View {
        // Priority: camera captured image > held image > cycling image
        let imageToShow: CGImage? = {
            // First priority: show last captured camera image if requested
            if state.showLastCamImage, let camImage = state.lastCapturedImage {
                return camImage
            }
            // Second priority: held image from hold_image command
            if state.holdImageIndex >= 0 && state.holdImageIndex < state.unshuffledImages.count {
                return state.unshuffledImages[state.holdImageIndex]
            }
            // Default: cycling image from shuffled array
            if state.imageIndex < state.images.count {
                return state.images[state.imageIndex]
            }
            return nil
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
    @State private var viewSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            // Use runtime overrides if available, otherwise fall back to config
            let subliminalColor = state.getEffectiveSubliminalColor() ?? config.properties.subliminalColor
            let subliminalAlpha = state.getEffectiveSubliminalAlpha() ?? config.properties.subliminalAlpha

            if let subliminalColor = subliminalColor,
               let subliminalAlpha = subliminalAlpha {

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
                        viewSize = geometry.size
                        randomizePosition()
                    }
                    .onChange(of: geometry.size) { _, newSize in
                        viewSize = newSize
                        randomizePosition()
                    }
                    .onChange(of: state.subliminalText) { _, _ in
                        // Potentially reposition when text changes based on probability
                        let moveProbability = state.getEffectiveSubliminalMoveProbability()
                        if Int.random(in: 1...100) <= moveProbability {
                            randomizePosition()
                        }
                    }
            }
        }
    }

    private func randomizePosition() {
        // Use scatter from state (supports runtime override)
        let scatter = CGFloat(state.getEffectiveSubliminalScatter())
        let centerX = viewSize.width / 2
        let centerY = viewSize.height / 2

        // Randomize position within scatter distance from center
        position = CGPoint(
            x: centerX + CGFloat.random(in: -scatter...scatter),
            y: centerY + CGFloat.random(in: -scatter...scatter)
        )
    }
}

/// Hardware-accelerated concentric rings using SwiftUI Canvas + TimelineView
/// Rings expand smoothly outward from center
struct RingsCanvasView: View {
    @ObservedObject var state: SpiralState
    let config: SpiralConfig

    var body: some View {
        TimelineView(.animation) { _ in
            let phase = state.ringsPhase
            let rotation = state.spiralRotation

            GeometryReader { geometry in
                // Use diagonal size to prevent clipping during rotation
                let diagonal = sqrt(geometry.size.width * geometry.size.width +
                                   geometry.size.height * geometry.size.height)
                let canvasSize = diagonal * 1.2

                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let maxRadius = diagonal / 2
                    let baseSpacing = config.properties.ringsSpacing
                    let lineWidth = config.properties.ringsLineWidth
                    let pulseWave = config.properties.ringsPulseWave

                    // Base color from config
                    let baseR = Double(config.properties.color[0]) / 255.0
                    let baseG = Double(config.properties.color[1]) / 255.0
                    let baseB = Double(config.properties.color[2]) / 255.0

                    // Calculate ring positions relative to continuously increasing phase
                    // Ring i's radius = phase - birthPosition[i]
                    // birthPosition[i] = cumulative spacing of all rings born before it

                    var birthPosition: Double = 0
                    var ringIndex = 0
                    let maxRings = Int(maxRadius / (baseSpacing * 0.3)) + 20  // Safety limit

                    while ringIndex < maxRings {
                        let radius = phase - birthPosition

                        // Stop if this ring hasn't been born yet (would be negative)
                        if radius < 0 { break }

                        // Calculate wave position for this ring (same as spacing calc)
                        let wavePos = Double(ringIndex) / 4.0
                        let waveFactor = sin(wavePos * 2.0 * .pi)  // -1 to 1

                        // Color varies with wave: troughs are warmer (red/yellow), peaks are cooler (blue/cyan)
                        // Subtle shift - blend base color with wave-based tint
                        let colorShift = waveFactor * 0.3 * pulseWave
                        let r = min(1.0, max(0.0, baseR + colorShift * 0.5))
                        let g = min(1.0, max(0.0, baseG - abs(colorShift) * 0.2))
                        let b = min(1.0, max(0.0, baseB - colorShift * 0.5))
                        let ringColor = Color(red: r, green: g, blue: b)

                        // Only draw if on screen
                        if radius > 0 && radius < maxRadius + baseSpacing {
                            let rect = CGRect(
                                x: center.x - radius,
                                y: center.y - radius,
                                width: radius * 2,
                                height: radius * 2
                            )

                            context.stroke(
                                Circle().path(in: rect),
                                with: .color(ringColor),
                                lineWidth: lineWidth
                            )
                        }

                        // Calculate spacing to next ring (when it was born)
                        var spacing = baseSpacing
                        if pulseWave > 0 {
                            spacing = baseSpacing * (1.0 + pulseWave * 0.7 * waveFactor)
                            spacing = max(spacing, baseSpacing * 0.2)
                        }

                        birthPosition += spacing
                        ringIndex += 1
                    }
                }
                .frame(width: canvasSize, height: canvasSize)
                .rotationEffect(.degrees(rotation))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .ignoresSafeArea()
        }
    }
}
