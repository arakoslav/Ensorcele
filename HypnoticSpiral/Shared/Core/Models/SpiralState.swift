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

    // MARK: - Speech State

    var currentSpeechRate: Int? = nil  // Accumulated speech rate setting

    // MARK: - Text Display

    @Published var currentWord: String = ""
    @Published var persistentText: String = ""
    @Published var backgroundText: String = ""
    @Published var subliminalText: String = ""
    @Published var spokenWord: String = ""  // Currently speaking word

    // MARK: - Variables (for $name substitution)

    var variables: [String: String] = [:]

    // MARK: - Loaded Resources

    var textSequence: [String] = []
    var spiralImage: CGImage? = nil  // Single base spiral image
    @Published var spiralRotation: Double = 0.0  // Current rotation angle in degrees
    @Published var spiralScale: Double = 1.0  // Pulsing scale effect
    @Published var spiralTiltX: Double = 0.0  // Wobble tilt on X axis
    @Published var spiralTiltY: Double = 0.0  // Wobble tilt on Y axis
    var images: [CGImage] = []  // Shuffled images for cycling
    var unshuffledImages: [CGImage] = []  // Unshuffled for hold_image lookup
    var imageFilenames: [String] = []  // Filenames corresponding to unshuffled images
    var subliminalList: [String] = []

    // MARK: - Timing (Frequency Counters)

    var frequencies: [String: Int] = [
        "spiral": 0,
        "images": 0,
        "words": 0
    ]

    // MARK: - Configuration Reference

    var config: SpiralConfig?

    // MARK: - User Input State

    @Published var currentQuestion: QuestionType? = nil

    enum QuestionType {
        case prompt(message: String, completion: () -> Void)
        case openQuestion(prompt: String, variableName: String, completion: (String) -> Void)
        case yesNo(question: String, onYes: () -> Void, onNo: () -> Void)
        case challenge(prompt: String, variableName: String, completion: (String) -> Void)
        case setPref(prompt: String, variableName: String, completion: (String) -> Void)
    }

    // MARK: - Helper Methods

    /// Reset state for new configuration
    func reset() {
        drawSpiral = false
        drawWords = false
        drawImages = false
        speakWords = false

        imageIndex = 0
        wordsIndex = 0
        holdImageIndex = -1
        isCapturingImageName = false
        spiralRotation = 0.0
        spiralScale = 1.0
        spiralTiltX = 0.0
        spiralTiltY = 0.0

        isRunning = false
        isWaiting = false
        isSpeaking = false

        currentSpeechRate = nil

        currentWord = ""
        persistentText = ""
        backgroundText = ""
        subliminalText = ""
        spokenWord = ""

        variables = [:]
        textSequence = []
        currentQuestion = nil
    }

    /// Initialize frequency counters from config
    func initializeFrequencies(from config: SpiralConfig) {
        frequencies["spiral"] = config.properties.frequencies.spiral
        frequencies["images"] = config.properties.frequencies.images
        frequencies["words"] = config.properties.frequencies.words
    }
}
