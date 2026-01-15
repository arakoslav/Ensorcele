//
//  iCloudResourceManager.swift
//  HypnoticSpiral
//
//  Manages resources - currently uses bundle/local files
//  iCloud support can be re-enabled later by setting USE_ICLOUD = true
//

import Foundation

// Set to true to enable iCloud syncing (disabled for now to reduce complexity)
private let USE_ICLOUD = false

@MainActor
class iCloudResourceManager {
    static let shared = iCloudResourceManager()

    private let fileManager = FileManager.default
    private var localContainerURL: URL?

    // Subdirectory names
    private let configsDir = "Configs"
    private let musicDir = "Music"
    private let imagesDir = "Images"
    private let spiralsDir = "Spirals"
    private let capturedImagesDir = "CapturedImages"

    private init() {
        setupLocalStorage()
    }

    private func setupLocalStorage() {
        // Use local documents directory
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            localContainerURL = documentsURL.appendingPathComponent("HypnoticSpiral")
            print("Local storage URL: \(localContainerURL?.path ?? "nil")")
        }
    }

    /// Initialize local directories for user-created content
    func initializeResources() async throws {
        guard let containerURL = localContainerURL else {
            return // Bundle resources don't need initialization
        }

        // Create local directories for user content (captured images, edited configs)
        try? createDirectoryIfNeeded(containerURL)
        try? createDirectoryIfNeeded(containerURL.appendingPathComponent(configsDir))
        try? createDirectoryIfNeeded(containerURL.appendingPathComponent(capturedImagesDir))

        print("Initialized local storage directories")
    }

    private func createDirectoryIfNeeded(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            print("Created directory: \(url.lastPathComponent)")
        }
    }

    // MARK: - Public Resource Access (Bundle-first)

    /// Get URL for local configs directory (for saving edited configs)
    func getConfigsURL() -> URL? {
        return localContainerURL?.appendingPathComponent(configsDir)
    }

    /// Get URL for local captured images directory
    func getCapturedImagesURL() -> URL? {
        return localContainerURL?.appendingPathComponent(capturedImagesDir)
    }

    /// Get URL for bundle images directory (for debugging)
    func getImagesURL() -> URL? {
        return Bundle.main.url(forResource: imagesDir, withExtension: nil)
    }

    /// Get URL for specific config file (checks local first, then bundle)
    func getConfigURL(named name: String) -> URL? {
        let fileName = name.hasSuffix(".json") ? name : "\(name).json"

        // First check local storage (for user-edited configs)
        if let localURL = localContainerURL?.appendingPathComponent(configsDir).appendingPathComponent(fileName),
           fileManager.fileExists(atPath: localURL.path) {
            return localURL
        }

        // Fallback to bundle
        let baseName = fileName.hasSuffix(".json") ? String(fileName.dropLast(5)) : fileName
        return Bundle.main.url(forResource: baseName, withExtension: "json", subdirectory: configsDir)
    }

    /// Get URL for specific music file (bundle only for now)
    func getMusicURL(named name: String) -> URL? {
        let ext = (name as NSString).pathExtension
        let baseName = (name as NSString).deletingPathExtension
        return Bundle.main.url(forResource: baseName, withExtension: ext, subdirectory: musicDir)
    }

    /// Get URL for specific image directory (bundle only for now)
    /// Handles paths like "Images/alt/", "images/", or just "alt"
    func getImageDirURL(named name: String) -> URL? {
        var dirName = name

        // Strip "Images/" prefix if present (case-insensitive)
        if dirName.lowercased().hasPrefix("images/") {
            dirName = String(dirName.dropFirst(7))
        }

        // Strip trailing slash
        if dirName.hasSuffix("/") {
            dirName = String(dirName.dropLast())
        }

        // Handle empty string (default to "images")
        if dirName.isEmpty {
            dirName = "images"
        }

        let url = Bundle.main.url(forResource: dirName, withExtension: nil, subdirectory: imagesDir)
        print("getImageDirURL: '\(name)' -> '\(dirName)' -> \(url?.path ?? "nil")")
        return url
    }

    /// Get URL for specific spiral directory (bundle only for now)
    func getSpiralDirURL(named name: String) -> URL? {
        return Bundle.main.url(forResource: name, withExtension: nil, subdirectory: spiralsDir)
    }

    /// List all available config files (bundle preferred, plus local-only configs)
    func listConfigs() -> [URL] {
        var configsByName: [String: URL] = [:]

        // First, add local configs (user-created or edited)
        if let localConfigsURL = getConfigsURL() {
            if let localFiles = try? fileManager.contentsOfDirectory(
                at: localConfigsURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) {
                for file in localFiles where file.pathExtension == "json" {
                    configsByName[file.lastPathComponent] = file
                }
            }
        }

        // Then, add/override with bundle configs (bundle takes precedence)
        if let bundleConfigsURL = Bundle.main.url(forResource: configsDir, withExtension: nil) {
            if let bundleFiles = try? fileManager.contentsOfDirectory(
                at: bundleConfigsURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) {
                for file in bundleFiles where file.pathExtension == "json" {
                    configsByName[file.lastPathComponent] = file
                }
            }
        }

        return Array(configsByName.values)
    }

    /// Generate an "Edited" filename for saving modifications
    /// "Standard.json" -> "StandardEdited.json"
    func generateEditedFilename(from originalURL: URL) -> String {
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        // If already ends with "Edited", don't double it
        if baseName.hasSuffix("Edited") {
            return originalURL.lastPathComponent
        }
        return "\(baseName)Edited.json"
    }

    // MARK: - Config Saving

    /// Save JSON data to a config file in local storage
    func saveConfig(data: Data, to filename: String) throws {
        guard let configsURL = getConfigsURL() else {
            throw ResourceError.storageUnavailable
        }

        // Ensure directory exists
        try? createDirectoryIfNeeded(configsURL)

        let fileURL = configsURL.appendingPathComponent(filename)
        try data.write(to: fileURL)
        print("Saved config to: \(fileURL.path)")
    }

    /// Save JSON data to a specific URL
    func saveConfig(data: Data, to url: URL) throws {
        try data.write(to: url)
        print("Saved config to: \(url.path)")
    }

    /// Read raw JSON data from a config file URL
    func readConfigData(from url: URL) throws -> Data {
        return try Data(contentsOf: url)
    }

    /// Check if a config URL is writable (not in bundle)
    func isConfigWritable(_ url: URL) -> Bool {
        return !url.path.contains(Bundle.main.bundlePath)
    }

    /// Get writable URL for a config (copies from bundle to local if needed)
    func getWritableConfigURL(for config: SpiralConfig, originalURL: URL) throws -> URL {
        guard let configsURL = getConfigsURL() else {
            throw ResourceError.storageUnavailable
        }

        // If already writable, return as-is
        if isConfigWritable(originalURL) {
            return originalURL
        }

        // Copy from bundle to local storage
        let filename = originalURL.lastPathComponent
        let destURL = configsURL.appendingPathComponent(filename)

        // Ensure directory exists
        try? createDirectoryIfNeeded(configsURL)

        // Copy the file if not already there
        if !fileManager.fileExists(atPath: destURL.path) {
            try fileManager.copyItem(at: originalURL, to: destURL)
            print("Copied config to local storage: \(destURL.path)")
        }

        return destURL
    }

    // MARK: - Camera Capture Helpers

    /// Generate a unique filename for a new captured image
    func generateCapturedImageFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        return "capture_\(timestamp).jpg"
    }

    /// Get URL for the last captured image (most recent file)
    func getLastCapturedImageURL() -> URL? {
        guard let capturedURL = getCapturedImagesURL() else { return nil }

        guard let files = try? fileManager.contentsOfDirectory(
            at: capturedURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        let imageFiles = files.filter { url in
            let ext = url.pathExtension.lowercased()
            return ["jpg", "jpeg", "png"].contains(ext)
        }

        let sorted = imageFiles.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            return date1 > date2
        }

        return sorted.first
    }
}

enum ResourceError: Error {
    case storageUnavailable
    case resourceNotFound(String)

    // Keep old name for compatibility
    static var iCloudUnavailable: ResourceError { .storageUnavailable }
}
