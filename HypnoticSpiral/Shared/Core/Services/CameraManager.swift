//
//  CameraManager.swift
//  HypnoticSpiral
//
//  Camera capture service for taking snapshots
//

import Foundation
import AVFoundation
import CoreGraphics

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Manages camera capture functionality
@MainActor
class CameraManager: NSObject, Observable {
    static let shared = CameraManager()

    // MARK: - Published State

    var isAuthorized: Bool = false
    var isCaptureInProgress: Bool = false
    var lastError: String? = nil

    // MARK: - Capture Session

    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var captureCompletion: ((CGImage?) -> Void)?

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Authorization

    /// Check and request camera authorization
    func requestAuthorization() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            isAuthorized = true
            return true

        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isAuthorized = granted
            return granted

        case .denied, .restricted:
            isAuthorized = false
            lastError = "Camera access denied. Please enable in Settings."
            return false

        @unknown default:
            isAuthorized = false
            return false
        }
    }

    // MARK: - Session Setup

    /// Initialize the capture session
    func setupCaptureSession() async -> Bool {
        guard await requestAuthorization() else {
            return false
        }

        // Create session
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        // Find camera device (prefer front camera for this use case)
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
              ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
              ?? AVCaptureDevice.default(for: .video) else {
            lastError = "No camera available"
            return false
        }

        // Add input
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                lastError = "Could not add camera input"
                return false
            }
        } catch {
            lastError = "Camera input error: \(error.localizedDescription)"
            return false
        }

        // Add photo output
        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            photoOutput = output
        } else {
            lastError = "Could not add photo output"
            return false
        }

        captureSession = session
        return true
    }

    // MARK: - Capture

    /// Capture a photo and return the CGImage
    func capturePhoto() async -> CGImage? {
        // Ensure session is set up
        if captureSession == nil {
            guard await setupCaptureSession() else {
                return nil
            }
        }

        guard let session = captureSession, let output = photoOutput else {
            lastError = "Capture session not initialized"
            return nil
        }

        isCaptureInProgress = true
        lastError = nil

        // Start session if not running
        if !session.isRunning {
            session.startRunning()
            // Give the camera time to warm up
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        // Capture photo using continuation
        let image = await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            self.captureCompletion = { cgImage in
                continuation.resume(returning: cgImage)
            }

            let settings = AVCapturePhotoSettings()
            output.capturePhoto(with: settings, delegate: self)
        }

        isCaptureInProgress = false
        return image
    }

    /// Stop the capture session to save resources
    func stopSession() {
        captureSession?.stopRunning()
    }

    // MARK: - Image Saving

    /// Save a CGImage to the captured images directory
    func saveImage(_ image: CGImage, to url: URL) -> Bool {
        #if os(iOS)
        let uiImage = UIImage(cgImage: image)
        guard let data = uiImage.jpegData(compressionQuality: 0.9) else {
            lastError = "Could not convert image to JPEG"
            return false
        }
        #else
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            lastError = "Could not convert image to JPEG"
            return false
        }
        #endif

        do {
            try data.write(to: url)
            return true
        } catch {
            lastError = "Could not save image: \(error.localizedDescription)"
            return false
        }
    }

    /// Load a CGImage from URL
    static func loadImage(from url: URL) -> CGImage? {
        #if os(iOS)
        guard let uiImage = UIImage(contentsOfFile: url.path) else { return nil }
        return uiImage.cgImage
        #else
        guard let nsImage = NSImage(contentsOf: url) else { return nil }
        var rect = CGRect(origin: .zero, size: nsImage.size)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                  didFinishProcessingPhoto photo: AVCapturePhoto,
                                  error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.lastError = "Photo capture failed: \(error.localizedDescription)"
                self.captureCompletion?(nil)
                return
            }

            guard let imageData = photo.fileDataRepresentation() else {
                self.lastError = "Could not get image data"
                self.captureCompletion?(nil)
                return
            }

            #if os(iOS)
            guard let uiImage = UIImage(data: imageData) else {
                self.lastError = "Could not create image from data"
                self.captureCompletion?(nil)
                return
            }
            self.captureCompletion?(uiImage.cgImage)
            #else
            guard let nsImage = NSImage(data: imageData) else {
                self.lastError = "Could not create image from data"
                self.captureCompletion?(nil)
                return
            }
            var rect = CGRect(origin: .zero, size: nsImage.size)
            let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            self.captureCompletion?(cgImage)
            #endif
        }
    }
}
