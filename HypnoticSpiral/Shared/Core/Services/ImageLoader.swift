//
//  ImageLoader.swift
//  HypnoticSpiral
//
//  Loads and processes images from bundle directories
//  Handles scaling and shuffling based on config
//

import Foundation
import CoreGraphics

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Loads images from bundle directories
class ImageLoader {

    /// Load all images from a directory in iCloud
    /// - Parameters:
    ///   - directory: Directory name within Images folder
    ///   - shuffle: Whether to randomize image order
    ///   - maxSize: Maximum dimension for scaled images
    /// - Returns: Tuple of (shuffled images, unshuffled images, filenames)
    static func loadImages(from directory: String, shuffle: Bool = true, maxSize: CGFloat = 1200) -> (images: [CGImage], unshuffled: [CGImage], filenames: [String]) {
        var unshuffledImages: [CGImage] = []
        var filenames: [String] = []

        // Get iCloud resource URL for the directory
        guard let directoryURL = iCloudResourceManager.shared.getImageDirURL(named: directory) else {
            print("Warning: Could not find directory '\(directory)' in iCloud Images")
            return ([], [], [])
        }

        print("Looking for images in: \(directoryURL.path)")

        // Check if directory exists
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)

        if !exists {
            print("  ERROR: Directory does not exist!")
            // List what IS in Images directory
            if let imagesURL = iCloudResourceManager.shared.getImagesURL() {
                print("  Contents of Images:")
                if let contents = try? fileManager.contentsOfDirectory(atPath: imagesURL.path) {
                    for item in contents.prefix(20) {
                        print("    - \(item)")
                    }
                }
            }
            return ([], [], [])
        }

        if !isDirectory.boolValue {
            print("  ERROR: Path exists but is not a directory!")
            return ([], [], [])
        }

        // Get all image files
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            print("Warning: Could not read contents of '\(directory)'")
            return ([], [], [])
        }

        // Filter to image extensions
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"]
        let imageURLs = fileURLs.filter { url in
            imageExtensions.contains(url.pathExtension.lowercased())
        }

        print("Found \(imageURLs.count) images in \(directory)")

        // Always load unshuffled first (sorted by path for consistency)
        let sortedURLs = imageURLs.sorted { $0.path < $1.path }

        // Load unshuffled images
        for url in sortedURLs {
            if let image = loadImage(from: url, maxSize: maxSize) {
                unshuffledImages.append(image)
                filenames.append(url.lastPathComponent)
            }
        }

        // Create shuffled version for cycling display
        let shuffledImages = shuffle ? unshuffledImages.shuffled() : unshuffledImages

        print("Successfully loaded \(unshuffledImages.count) images (shuffled: \(shuffle))")
        return (shuffledImages, unshuffledImages, filenames)
    }

    /// Load and optionally scale a single image
    private static func loadImage(from url: URL, maxSize: CGFloat) -> CGImage? {
        #if os(macOS)
        guard let nsImage = NSImage(contentsOf: url) else {
            print("Warning: Could not load image from \(url.lastPathComponent)")
            return nil
        }

        // Get CGImage from NSImage
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // Scale if needed
        return scaleImageIfNeeded(cgImage, maxSize: maxSize)

        #else
        guard let uiImage = UIImage(contentsOfFile: url.path) else {
            print("Warning: Could not load image from \(url.lastPathComponent)")
            return nil
        }

        guard let cgImage = uiImage.cgImage else {
            return nil
        }

        // Scale if needed
        return scaleImageIfNeeded(cgImage, maxSize: maxSize)
        #endif
    }

    /// Scale image if it exceeds maxSize
    private static func scaleImageIfNeeded(_ image: CGImage, maxSize: CGFloat) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let maxDimension = max(width, height)

        // No scaling needed
        if maxDimension <= maxSize {
            return image
        }

        // Calculate scale factor
        let scale = maxSize / maxDimension
        let newWidth = Int(width * scale)
        let newHeight = Int(height * scale)

        // Create scaled context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: newWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return image
        }

        // Draw scaled
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        return context.makeImage()
    }
}
