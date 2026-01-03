//
//  SpeechSynthesizer.swift
//  HypnoticSpiral
//
//  Platform-independent speech synthesis protocol
//  Implemented by macOS (NSSpeechSynthesizer) and iOS (AVSpeechSynthesizer)
//

import Foundation

/// Protocol for speech synthesis across platforms
protocol SpeechSynthesizerProtocol: AnyObject {
    var delegate: SpeechSynthesizerDelegate? { get set }
    var isSpeaking: Bool { get }

    func setVoice(_ voiceName: String?)
    func speak(_ text: String)
    func stop()
}

/// Delegate protocol for speech events
protocol SpeechSynthesizerDelegate: AnyObject {
    func synthesizer(_ synthesizer: SpeechSynthesizerProtocol, didSpeakWord word: String)
    func synthesizerDidFinish(_ synthesizer: SpeechSynthesizerProtocol)
}
