//
//  SpiralState.swift
//  HypnoticSpiral
//
//  Observable runtime state for the spiral application
//  Replaces pygame's imperative state machine with SwiftUI's declarative model
//

import Foundation
import SwiftUI
import CoreGraphics
import Combine

/// Main runtime state for the hypnotic spiral application
/// All properties are published for SwiftUI reactivity
@MainActor
class SpiralState: ObservableObject {
    // MARK: - Rendering Flags

    @Published var drawSpiral: Bool = false
    @Published var drawWords: Bool = false
    @Published var drawImages: Bool = false
    @Published var speakWords: Bool = false
    @Published var activeSpiralType: SpiralType = .fermat

    // MARK: - Current Indices

    @Published var imageIndex: Int = 0
    @Published var wordsIndex: Int = 0
    @Published var holdImageIndex: Int = -1  // Index of held image, -1 if none
    var isCapturingImageName: Bool = false  // Capturing image name after hold_image_start

    // MARK: - Runtime State

    @Published var isRunning: Bool = false
    @Published var isWaiting: Bool = false  // Waiting for user input
    @Published var isSpeaking: Bool = false
    @Published var isFullscreen: Bool = false
    @Published var programEnded: Bool = false  // Program finished, should exit to config picker

    // MARK: - Speech State

    var currentSpeechRate: Int? = nil  // Accumulated speech rate setting

    // MARK: - Text Display

    @Published var currentWord: String = ""
    @Published var persistentText: String = ""
    @Published var backgroundText: String = ""
    @Published var subliminalText: String = ""
    @Published var spokenWord: String = ""  // Currently speaking word

    // MARK: - Cycling Word Lists

    var backgroundWords: [String] = []  // Words to cycle through as background text
    var backgroundWordIndex: Int = 0
    var subliminalWords: [String] = []  // Words to cycle through as subliminal text
    var subliminalWordIndex: Int = 0

    // MARK: - Variables (for $name substitution)

    var variables: [String: String] = [:]

    // MARK: - Runtime Property Overrides
    // These override config properties when set via !set_property()

    var runtimeImageAlpha: Int? = nil
    var runtimeTextAlpha: Int? = nil
    var runtimeSpiralAlpha: Int? = nil
    var runtimeSubliminalAlpha: Int? = nil
    var runtimeTextColor: [Int]? = nil      // RGB array [r, g, b]
    var runtimeSpiralColor: [Int]? = nil    // RGB array [r, g, b]
    var runtimeFontSize: CGFloat? = nil     // Font size for main text display
    var runtimeBackgroundFontSize: CGFloat? = nil  // Font size for background text
    var runtimeSubliminalColor: [Int]? = nil  // RGB array for subliminals
    @Published var runtimeImageDir: String? = nil  // Override image directory (triggers reload when set)

    // Timing overrides
    var runtimeWordFrequency: Int? = nil        // How often words change (lower = faster)
    var runtimeImageFrequency: Int? = nil       // How often images change
    var runtimeSpiralSpeed: Double? = nil       // Spiral rotation speed multiplier (1.0 = normal)

    // Spiral appearance overrides
    var runtimeSpiralLineWidth: Double? = nil
    var runtimeSpiralTightness: Double? = nil
    var runtimeSpiralArms: Int? = nil

    // Subliminal behavior overrides
    var runtimeSubliminalScatter: Int? = nil
    var runtimeSubliminalMoveProbability: Int? = nil
    var runtimeSubliminalDisplayProbability: Int? = nil
    var runtimeSubliminalChangeProbability: Int? = nil

    // Rings/Colors specific overrides
    var runtimeRingsLineWidth: Double? = nil
    var runtimeRingsSpacing: Double? = nil
    var runtimeRingsExpansionRate: Double? = nil

    /// Get effective image alpha (runtime override or config default)
    func getEffectiveImageAlpha() -> Int {
        return runtimeImageAlpha ?? config?.properties.imageAlpha ?? 255
    }

    /// Get effective text alpha (runtime override or config default)
    func getEffectiveTextAlpha() -> Int {
        return runtimeTextAlpha ?? config?.properties.textAlpha ?? 254
    }

    /// Get effective spiral alpha (runtime override or config default)
    func getEffectiveSpiralAlpha() -> Int {
        return runtimeSpiralAlpha ?? config?.properties.alpha ?? 127
    }

    /// Get effective subliminal alpha (runtime override or config default)
    func getEffectiveSubliminalAlpha() -> Int? {
        return runtimeSubliminalAlpha ?? config?.properties.subliminalAlpha
    }

    /// Get effective text color (runtime override or config default)
    func getEffectiveTextColor() -> [Int] {
        return runtimeTextColor ?? config?.properties.textColor ?? [0, 51, 204]
    }

    /// Get effective spiral color (runtime override or config default)
    func getEffectiveSpiralColor() -> [Int] {
        return runtimeSpiralColor ?? config?.properties.color ?? [255, 255, 255]
    }

    /// Get effective font size (runtime override or default)
    func getEffectiveFontSize() -> CGFloat {
        return runtimeFontSize ?? 64
    }

    /// Get effective background font size (runtime override or default)
    func getEffectiveBackgroundFontSize() -> CGFloat {
        return runtimeBackgroundFontSize ?? 300
    }

    /// Get effective subliminal color (runtime override or config default)
    func getEffectiveSubliminalColor() -> [Int]? {
        return runtimeSubliminalColor ?? config?.properties.subliminalColor
    }

    /// Get effective word frequency (runtime override or config default)
    func getEffectiveWordFrequency() -> Int {
        return runtimeWordFrequency ?? config?.properties.frequencies.words ?? 40
    }

    /// Get effective image frequency (runtime override or config default)
    func getEffectiveImageFrequency() -> Int {
        return runtimeImageFrequency ?? config?.properties.frequencies.images ?? 50
    }

    /// Get effective spiral speed multiplier (runtime override or default 1.0)
    func getEffectiveSpiralSpeed() -> Double {
        return runtimeSpiralSpeed ?? 1.0
    }

    /// Get effective spiral line width
    func getEffectiveSpiralLineWidth() -> Double {
        return runtimeSpiralLineWidth ?? config?.properties.spiralLineWidth ?? 3.0
    }

    /// Get effective spiral tightness
    func getEffectiveSpiralTightness() -> Double {
        return runtimeSpiralTightness ?? config?.properties.spiralTightness ?? 0.15
    }

    /// Get effective spiral arms count
    func getEffectiveSpiralArms() -> Int {
        return runtimeSpiralArms ?? config?.properties.spiralArms ?? 2
    }

    /// Get effective subliminal scatter
    func getEffectiveSubliminalScatter() -> Int {
        return runtimeSubliminalScatter ?? config?.properties.subliminalScatter ?? 200
    }

    /// Get effective subliminal move probability
    func getEffectiveSubliminalMoveProbability() -> Int {
        return runtimeSubliminalMoveProbability ?? config?.properties.subliminalMoveProbability ?? 100
    }

    /// Get effective subliminal display probability
    func getEffectiveSubliminalDisplayProbability() -> Int {
        return runtimeSubliminalDisplayProbability ?? config?.properties.subliminalDisplayProbability ?? 100
    }

    /// Get effective subliminal change probability
    func getEffectiveSubliminalChangeProbability() -> Int {
        return runtimeSubliminalChangeProbability ?? config?.properties.subliminalChangeProbability ?? 100
    }

    /// Get effective rings line width
    func getEffectiveRingsLineWidth() -> Double {
        return runtimeRingsLineWidth ?? config?.properties.ringsLineWidth ?? 2.0
    }

    /// Get effective rings spacing
    func getEffectiveRingsSpacing() -> Double {
        return runtimeRingsSpacing ?? config?.properties.ringsSpacing ?? 30.0
    }

    /// Get effective rings expansion rate
    func getEffectiveRingsExpansionRate() -> Double {
        return runtimeRingsExpansionRate ?? config?.properties.ringsExpansionRate ?? 1.0
    }

    // MARK: - Loaded Resources

    var textSequence: [String] = []
    var spiralImage: CGImage? = nil  // Single base spiral image
    var counterSpiralImage: CGImage? = nil  // Counter-rotating spiral for twist type
    var spiralFrames: [CGImage] = []  // Multiple frames for animated types (e.g., expanding rings)
    @Published var ringsFrameIndex: Int = 0  // Current frame for rings animation (legacy)
    @Published var ringsPhase: Double = 0.0  // Continuous phase for Canvas-based ring expansion (0 to spacing)
    @Published var spiralRotation: Double = 0.0  // Current rotation angle in degrees
    @Published var counterSpiralRotation: Double = 0.0  // Counter rotation (opposite direction)
    @Published var spiralScale: Double = 1.0  // Pulsing scale effect
    @Published var spiralTiltX: Double = 0.0  // Wobble tilt on X axis
    @Published var spiralTiltY: Double = 0.0  // Wobble tilt on Y axis
    @Published var counterSpiralTiltX: Double = 0.0  // Counter spiral wobble X
    @Published var counterSpiralTiltY: Double = 0.0  // Counter spiral wobble Y
    var images: [CGImage] = []  // Shuffled images for cycling
    var unshuffledImages: [CGImage] = []  // Unshuffled for hold_image lookup
    var imageFilenames: [String] = []  // Filenames corresponding to unshuffled images
    var subliminalList: [String] = []

    // MARK: - Camera Capture State

    var lastCapturedImage: CGImage? = nil  // Last camera-captured image
    @Published var showLastCamImage: Bool = false  // Display the last captured camera image
    var lastCapturedImageURL: URL? = nil  // URL of the saved camera image

    // MARK: - Timing (Frequency Counters)

    var frequencies: [String: Int] = [
        "spiral": 0,
        "images": 0,
        "words": 0,
        "backgroundWords": 0,
        "subliminals": 0
    ]

    // MARK: - Configuration Reference

    var config: SpiralConfig?

    // MARK: - User Input State

    @Published var currentQuestion: QuestionType? = nil

    enum QuestionType {
        case prompt(message: String, completion: () -> Void)
        case openQuestion(prompt: String, variableName: String, completion: (String) -> Void)
        /// Yes/No question with optional timeout that auto-selects an answer
        /// timeoutSeconds: if set, auto-selects after this many seconds
        /// timeoutDefault: "yes" or "no" - which answer to auto-select on timeout
        case yesNo(question: String, onYes: () -> Void, onNo: () -> Void, timeoutSeconds: Int?, timeoutDefault: String?)
        case challenge(prompt: String, variableName: String, completion: (String) -> Void)
        case setPref(prompt: String, variableName: String, completion: (String) -> Void)
        case mantra(expectedText: String, timeoutSeconds: Int?, autoStartMic: Bool, onComplete: () -> Void, onTimeout: (() -> Void)?)
        /// Peripheral awareness test - appears at bottom of screen, user must click to dismiss
        /// If timeout expires without click, onTimeout is called (typically jumps to deeper script)
        case awarenessTest(message: String, timeoutSeconds: Int, onDismiss: () -> Void, onTimeout: () -> Void)
    }

    // MARK: - Helper Methods

    /// Reset state for new configuration
    func reset() {
        drawSpiral = false
        drawWords = false
        drawImages = false
        speakWords = false
        activeSpiralType = .fermat

        imageIndex = 0
        wordsIndex = 0
        holdImageIndex = -1
        isCapturingImageName = false
        spiralRotation = 0.0
        counterSpiralRotation = 0.0
        spiralScale = 1.0
        spiralTiltX = 0.0
        spiralTiltY = 0.0
        counterSpiralTiltX = 0.0
        counterSpiralTiltY = 0.0

        isRunning = false
        isWaiting = false
        isSpeaking = false
        programEnded = false

        currentSpeechRate = nil

        currentWord = ""
        persistentText = ""
        backgroundText = ""
        subliminalText = ""
        spokenWord = ""

        // Cycling word lists
        backgroundWords = []
        backgroundWordIndex = 0
        subliminalWords = []
        subliminalWordIndex = 0

        variables = [:]
        textSequence = []
        currentQuestion = nil

        // Runtime property overrides
        runtimeImageAlpha = nil
        runtimeTextAlpha = nil
        runtimeSpiralAlpha = nil
        runtimeSubliminalAlpha = nil
        runtimeTextColor = nil
        runtimeSpiralColor = nil
        runtimeFontSize = nil
        runtimeBackgroundFontSize = nil
        runtimeSubliminalColor = nil
        runtimeImageDir = nil

        // Timing overrides
        runtimeWordFrequency = nil
        runtimeImageFrequency = nil
        runtimeSpiralSpeed = nil

        // Spiral appearance overrides
        runtimeSpiralLineWidth = nil
        runtimeSpiralTightness = nil
        runtimeSpiralArms = nil

        // Subliminal behavior overrides
        runtimeSubliminalScatter = nil
        runtimeSubliminalMoveProbability = nil
        runtimeSubliminalDisplayProbability = nil
        runtimeSubliminalChangeProbability = nil

        // Rings/Colors overrides
        runtimeRingsLineWidth = nil
        runtimeRingsSpacing = nil
        runtimeRingsExpansionRate = nil

        // Camera state
        lastCapturedImage = nil
        showLastCamImage = false
        // Note: lastCapturedImageURL is preserved across sessions
    }

    /// Initialize frequency counters from config
    func initializeFrequencies(from config: SpiralConfig) {
        frequencies["spiral"] = config.properties.frequencies.spiral
        frequencies["images"] = config.properties.frequencies.images
        frequencies["words"] = config.properties.frequencies.words
        frequencies["backgroundWords"] = config.properties.frequencies.backgroundWords
        frequencies["subliminals"] = config.properties.frequencies.subliminals
    }
}
