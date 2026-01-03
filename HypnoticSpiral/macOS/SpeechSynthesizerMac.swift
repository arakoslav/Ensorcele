//
//  SpeechSynthesizerMac.swift
//  HypnoticSpiral
//
//  macOS speech synthesis using NSSpeechSynthesizer
//  Provides word-by-word callbacks
//

#if os(macOS)
import Foundation
import AppKit

class SpeechSynthesizerMac: NSObject, SpeechSynthesizerProtocol {
    weak var delegate: SpeechSynthesizerDelegate?
    private var synthesizer: NSSpeechSynthesizer?
    private var currentText: String = ""
    private var currentSpeechManagerRate: Int = 22000  // Track rate in Speech Manager scale (0-65535)

    var isSpeaking: Bool {
        synthesizer?.isSpeaking ?? false
    }

    override init() {
        super.init()
        synthesizer = NSSpeechSynthesizer()
        synthesizer?.delegate = self

        // Enable processing of embedded speech commands like [[rate +1000]]
        synthesizer?.usesFeedbackWindow = false  // Don't show feedback window

        // Set initial rate to 22000 (Speech Manager scale)
        setSpeechManagerRate(22000)

        print("Speech synthesizer initialized")
        print("  Initial rate: SM=22000 → \(Int(synthesizer?.rate ?? 0)) WPM")
    }

    func setVoice(_ voiceName: String?) {
        guard let voiceName = voiceName else { return }

        // Try to find voice by name
        let availableVoices = NSSpeechSynthesizer.availableVoices
        for voice in availableVoices {
            let attributes = NSSpeechSynthesizer.attributes(forVoice: voice)
            if let name = attributes[.name] as? String, name.lowercased().contains(voiceName.lowercased()) {
                synthesizer?.setVoice(voice)
                print("Set voice to: \(name)")
                return
            }
        }

        print("Warning: Voice '\(voiceName)' not found, using default")
    }

    func speak(_ text: String) {
        currentText = text
        synthesizer?.startSpeaking(text)
    }

    func stop() {
        synthesizer?.stopSpeaking()
    }

    /// Set speech rate using Speech Manager scale (0-65535 maps to 50-500 WPM)
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

        // Convert Speech Manager rate (0-65535) to WPM (50-500)
        // Linear mapping: WPM = 50 + (rate / 65535) * 450
        let wpm = Float(50.0 + (Float(currentSpeechManagerRate) / 65535.0) * 450.0)

        synthesizer?.rate = wpm
        print("Set speech rate: SM=\(currentSpeechManagerRate) → \(Int(wpm)) WPM")
    }

    /// Get current rate in Speech Manager scale
    func getCurrentSpeechManagerRate() -> Int {
        return currentSpeechManagerRate
    }
}

// MARK: - NSSpeechSynthesizerDelegate

extension SpeechSynthesizerMac: NSSpeechSynthesizerDelegate {
    func speechSynthesizer(_ sender: NSSpeechSynthesizer, willSpeakWord characterRange: NSRange, of string: String) {
        let word = (string as NSString).substring(with: characterRange)
        delegate?.synthesizer(self, didSpeakWord: word)
    }

    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        delegate?.synthesizerDidFinish(self)
    }
}
#endif
