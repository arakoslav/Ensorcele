//
//  SpeechSynthesizeriOS.swift
//  HypnoticSpiral
//
//  iOS speech synthesis using AVSpeechSynthesizer
//  Provides word-by-word callbacks
//

#if os(iOS)
import Foundation
import AVFoundation

class SpeechSynthesizeriOS: NSObject, SpeechSynthesizerProtocol {
    weak var delegate: SpeechSynthesizerDelegate?
    private var synthesizer: AVSpeechSynthesizer
    private var currentUtterance: AVSpeechUtterance?
    private var currentText: String = ""
    private var selectedVoice: AVSpeechSynthesisVoice?
    private var currentSpeechManagerRate: Int = 22000  // Track rate in Speech Manager scale (0-65535)

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self

        print("Speech synthesizer initialized (iOS)")
        print("  Initial rate: SM=22000 → \(speechManagerRateToAVRate(22000)) AVRate")
    }

    func setVoice(_ voiceName: String?) {
        guard let voiceName = voiceName else { return }

        // Try to find voice by name
        let voices = AVSpeechSynthesisVoice.speechVoices()
        for voice in voices {
            if voice.name.lowercased().contains(voiceName.lowercased()) {
                selectedVoice = voice
                print("Set voice to: \(voice.name)")
                return
            }
        }

        print("Warning: Voice '\(voiceName)' not found, using default")
    }

    func speak(_ text: String) {
        currentText = text
        let utterance = AVSpeechUtterance(string: text)

        // Apply selected voice
        utterance.voice = selectedVoice

        // Convert Speech Manager rate to AVSpeechUtterance rate
        utterance.rate = speechManagerRateToAVRate(currentSpeechManagerRate)

        currentUtterance = utterance
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Set speech rate using Speech Manager scale (0-65535)
    /// AVSpeechUtterance.rate ranges from 0.0 to 1.0, where:
    /// - AVSpeechUtteranceMinimumSpeechRate (0.0) is slowest
    /// - AVSpeechUtteranceDefaultSpeechRate (~0.5) is normal
    /// - AVSpeechUtteranceMaximumSpeechRate (1.0) is fastest
    func setSpeechManagerRate(_ rate: Int, relative: Bool = false) {
        if relative {
            // Relative adjustment: add to current rate
            currentSpeechManagerRate += rate
        } else {
            // Absolute: set directly
            currentSpeechManagerRate = rate
        }

        // Clamp to valid range
        currentSpeechManagerRate = max(0, min(65535, currentSpeechManagerRate))

        let avRate = speechManagerRateToAVRate(currentSpeechManagerRate)
        print("Set speech rate: SM=\(currentSpeechManagerRate) → \(avRate) AVRate")
    }

    /// Get current rate in Speech Manager scale
    func getCurrentSpeechManagerRate() -> Int {
        return currentSpeechManagerRate
    }

    /// Convert Speech Manager rate (0-65535) to AVSpeechUtterance rate (0.0-1.0)
    /// Speech Manager maps to 50-500 WPM, we'll map proportionally to AV's 0.0-1.0
    private func speechManagerRateToAVRate(_ smRate: Int) -> Float {
        // Map Speech Manager 0-65535 to AV 0.0-1.0
        // Using a slightly compressed range to avoid extremes
        let normalized = Float(smRate) / 65535.0
        return Float(AVSpeechUtteranceMinimumSpeechRate) +
               normalized * (Float(AVSpeechUtteranceMaximumSpeechRate) - Float(AVSpeechUtteranceMinimumSpeechRate))
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechSynthesizeriOS: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let word = (utterance.speechString as NSString).substring(with: characterRange)
        // Only report whole words, not individual phonemes
        if word.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 {
            delegate?.synthesizer(self, didSpeakWord: word)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        delegate?.synthesizerDidFinish(self)
    }
}
#endif
