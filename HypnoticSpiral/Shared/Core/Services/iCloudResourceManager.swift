//
//  iCloudResourceManager.swift
//  HypnoticSpiral
//
//  Manages resources in iCloud Drive for cross-device syncing
//

import Foundation

@MainActor
class iCloudResourceManager {
    static let shared = iCloudResourceManager()

    private let fileManager = FileManager.default
    private var iCloudContainerURL: URL?

    // Subdirectory names in iCloud
    private let configsDir = "Configs"
    private let musicDir = "Music"
    private let imagesDir = "Images"
    private let spiralsDir = "Spirals"

    // Minimal default resources to ship in bundle
    private let defaultConfigName = "Standard.json"
    private let defaultMusicName = "music6.mp3"
    private let defaultImagesDir = "mindbox"
    private let defaultSpiralName = "hypnoticswirl"

    private init() {
        setupiCloud()
    }

    /// Get iCloud container URL and verify access
    private func setupiCloud() {
        // Get the ubiquity container URL (iCloud Drive)
        // This will be nil if iCloud is not available or user is not signed in
        if let url = fileManager.url(forUbiquityContainerIdentifier: nil) {
            iCloudContainerURL = url.appendingPathComponent("Documents")
            print("iCloud container URL: \(iCloudContainerURL?.path ?? "nil")")
        } else {
            print("Warning: iCloud not available. Using local storage fallback.")
            // Fallback to local documents directory
            if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                iCloudContainerURL = documentsURL.appendingPathComponent("HypnoticSpiral")
            }
        }
    }

    /// Initialize iCloud directories and copy defaults if needed
    func initializeResources() async throws {
        guard let containerURL = iCloudContainerURL else {
            throw ResourceError.iCloudUnavailable
        }

        print("Initializing resources in iCloud...")

        // Create subdirectories if they don't exist
        try createDirectoryIfNeeded(containerURL.appendingPathComponent(configsDir))
        try createDirectoryIfNeeded(containerURL.appendingPathComponent(musicDir))
        try createDirectoryIfNeeded(containerURL.appendingPathComponent(imagesDir))
        try createDirectoryIfNeeded(containerURL.appendingPathComponent(spiralsDir))

        // Check if this is first launch (no configs present)
        let configsURL = containerURL.appendingPathComponent(configsDir)
        let existingConfigs = try? fileManager.contentsOfDirectory(at: configsURL, includingPropertiesForKeys: nil)

        if existingConfigs?.isEmpty ?? true {
            print("First launch detected. Copying default resources to iCloud...")
            try await copyDefaultResources()
        } else {
            print("Found existing resources in iCloud (\(existingConfigs?.count ?? 0) configs)")
        }
    }

    /// Copy minimal default resources from bundle to iCloud
    private func copyDefaultResources() async throws {
        guard let containerURL = iCloudContainerURL else {
            throw ResourceError.iCloudUnavailable
        }

        // Copy Standard.json
        if let bundleConfigURL = Bundle.main.url(forResource: "Standard", withExtension: "json", subdirectory: "Configs") {
            let destURL = containerURL.appendingPathComponent(configsDir).appendingPathComponent(defaultConfigName)
            try? fileManager.removeItem(at: destURL)  // Remove if exists
            try fileManager.copyItem(at: bundleConfigURL, to: destURL)
            print("Copied \(defaultConfigName) to iCloud")
        }

        // Copy music6.mp3
        if let bundleMusicURL = Bundle.main.url(forResource: "music6", withExtension: "mp3", subdirectory: "Music") {
            let destURL = containerURL.appendingPathComponent(musicDir).appendingPathComponent(defaultMusicName)
            try? fileManager.removeItem(at: destURL)
            try fileManager.copyItem(at: bundleMusicURL, to: destURL)
            print("Copied \(defaultMusicName) to iCloud")
        }

        // Copy mindbox images directory
        if let bundleImagesURL = Bundle.main.url(forResource: defaultImagesDir, withExtension: nil, subdirectory: "Images") {
            let destURL = containerURL.appendingPathComponent(imagesDir).appendingPathComponent(defaultImagesDir)
            try? fileManager.removeItem(at: destURL)
            try fileManager.copyItem(at: bundleImagesURL, to: destURL)
            print("Copied \(defaultImagesDir) images to iCloud")
        }

        // Copy hypnoticswirl spiral directory
        if let bundleSpiralURL = Bundle.main.url(forResource: defaultSpiralName, withExtension: nil, subdirectory: "Spirals") {
            let destURL = containerURL.appendingPathComponent(spiralsDir).appendingPathComponent(defaultSpiralName)
            try? fileManager.removeItem(at: destURL)
            try fileManager.copyItem(at: bundleSpiralURL, to: destURL)
            print("Copied \(defaultSpiralName) spiral to iCloud")
        }
    }

    /// Create directory if it doesn't exist
    private func createDirectoryIfNeeded(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            print("Created directory: \(url.lastPathComponent)")
        }
    }

    // MARK: - Public Resource Access

    /// Get URL for configs directory
    func getConfigsURL() -> URL? {
        return iCloudContainerURL?.appendingPathComponent(configsDir)
    }

    /// Get URL for music directory
    func getMusicURL() -> URL? {
        return iCloudContainerURL?.appendingPathComponent(musicDir)
    }

    /// Get URL for images directory
    func getImagesURL() -> URL? {
        return iCloudContainerURL?.appendingPathComponent(imagesDir)
    }

    /// Get URL for spirals directory
    func getSpiralsURL() -> URL? {
        return iCloudContainerURL?.appendingPathComponent(spiralsDir)
    }

    /// Get URL for specific config file
    func getConfigURL(named name: String) -> URL? {
        guard let configsURL = getConfigsURL() else { return nil }
        return configsURL.appendingPathComponent(name)
    }

    /// Get URL for specific music file
    func getMusicURL(named name: String) -> URL? {
        guard let musicURL = getMusicURL() else { return nil }
        return musicURL.appendingPathComponent(name)
    }

    /// Get URL for specific image directory
    func getImageDirURL(named name: String) -> URL? {
        guard let imagesURL = getImagesURL() else { return nil }
        return imagesURL.appendingPathComponent(name)
    }

    /// Get URL for specific spiral directory
    func getSpiralDirURL(named name: String) -> URL? {
        guard let spiralsURL = getSpiralsURL() else { return nil }
        return spiralsURL.appendingPathComponent(name)
    }

    /// List all available config files
    func listConfigs() -> [URL] {
        guard let configsURL = getConfigsURL() else { return [] }

        do {
            let files = try fileManager.contentsOfDirectory(
                at: configsURL,
                includingPropertiesForKeys: [.nameKey, .isDirectoryKey],
                options: .skipsHiddenFiles
            )
            return files.filter { $0.pathExtension == "json" }
        } catch {
            print("Error listing configs: \(error)")
            return []
        }
    }
}

enum ResourceError: Error {
    case iCloudUnavailable
    case resourceNotFound(String)
}
