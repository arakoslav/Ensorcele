//
//  SpeechRecognizer.swift
//  HypnoticSpiral
//
//  Speech recognition using Apple's Speech framework
//

import Foundation
import Speech
import AVFoundation

/// Delegate protocol for speech recognition events
@MainActor
protocol SpeechRecognizerDelegate: AnyObject {
    func speechRecognizer(_ recognizer: SpeechRecognizer, didRecognize text: String)
    func speechRecognizerDidStop(_ recognizer: SpeechRecognizer)
    func speechRecognizer(_ recognizer: SpeechRecognizer, didFailWithError error: String)
}

/// Speech recognizer using Apple's Speech framework
@MainActor
class SpeechRecognizer: NSObject {
    weak var delegate: SpeechRecognizerDelegate?

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    private(set) var isListening: Bool = false
    private(set) var isAuthorized: Bool = false

    override init() {
        self.speechRecognizer = SFSpeechRecognizer()
        super.init()
        updateAuthorizationStatus()
    }

    private func updateAuthorizationStatus() {
        let speechAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
        #if os(iOS)
        let micAuthorized = AVAudioSession.sharedInstance().recordPermission == .granted
        #else
        let micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        #endif
        isAuthorized = speechAuthorized && micAuthorized
    }

    /// Request all necessary permissions
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        requestMicrophonePermission { [weak self] micGranted in
            guard micGranted else {
                self?.isAuthorized = false
                completion(false)
                return
            }

            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    let authorized = status == .authorized
                    self?.isAuthorized = authorized && micGranted
                    completion(authorized)
                }
            }
        }
    }

    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        #if os(iOS)
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { completion(granted) }
        }
        #else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
        #endif
    }

    func startListening() {
        guard !isListening else { return }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            delegate?.speechRecognizer(self, didFailWithError: "Speech recognition not available")
            return
        }

        guard isAuthorized else {
            delegate?.speechRecognizer(self, didFailWithError: "Speech recognition not authorized")
            return
        }

        cleanup()

        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.delegate?.speechRecognizer(self, didRecognize: text)
                    if result.isFinal {
                        self.stopListening()
                    }
                }

                if let error = error {
                    let nsError = error as NSError
                    // Ignore cancellation (216) and no speech (1110) errors
                    if nsError.code != 216 && nsError.code != 1110 {
                        self.delegate?.speechRecognizer(self, didFailWithError: error.localizedDescription)
                    }
                    self.stopListening()
                }
            }
        }

        // Configure audio
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            delegate?.speechRecognizer(self, didFailWithError: "Audio session error: \(error.localizedDescription)")
            return
        }
        #endif

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            delegate?.speechRecognizer(self, didFailWithError: "Could not create audio engine")
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            delegate?.speechRecognizer(self, didFailWithError: "Invalid audio format")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            cleanup()
            delegate?.speechRecognizer(self, didFailWithError: "Audio engine error: \(error.localizedDescription)")
        }
    }

    func stopListening() {
        guard isListening else { return }
        cleanup()
        delegate?.speechRecognizerDidStop(self)
    }

    private func cleanup() {
        isListening = false

        if let audioEngine = audioEngine {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil
    }
}
