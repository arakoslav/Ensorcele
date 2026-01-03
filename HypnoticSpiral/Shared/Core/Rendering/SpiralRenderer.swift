//
//  SpiralRenderer.swift
//  HypnoticSpiral
//
//  Generates hypnotic spiral images using Core Graphics
//  Ports the parametric spiral equation from Python: x = t²cos(t), y = t²sin(t)
//

import Foundation
import CoreGraphics

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Generates spiral frame sequences for animation
class SpiralRenderer {

    // MARK: - Public API

    /// Generate or load a single base spiral image for real-time rotation
    /// - Parameters:
    ///   - config: Configuration with spiral parameters
    ///   - size: Target image size (actual window dimensions)
    /// - Returns: Base spiral image
    static func generateSpiral(config: SpiralConfig, size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)

        print("Generating spiral: window=\(width)x\(height)")

        // Check if we should load a spiral image or generate one
        if !config.properties.spiralImage.isEmpty {
            // Load spiral image from file
            if let loadedImage = loadSpiralImage(named: config.properties.spiralImage, targetSize: size) {
                print("Loaded spiral image: \(config.properties.spiralImage)")
                return loadedImage
            } else {
                print("Failed to load spiral image '\(config.properties.spiralImage)', generating instead")
            }
        }

        // Generate spiral from scratch
        print("Generating spiral from parametric equations")
        return generateBaseSpiralImage(size: size, config: config)
    }

    /// Load a spiral image from the Spirals directory
    private static func loadSpiralImage(named filename: String, targetSize: CGSize) -> CGImage? {
        guard let bundle = Bundle.main.resourceURL else { return nil }

        // Handle both "hypnoticswirl.jpg" and "Spirals/hypnoticswirl.jpg" formats
        let spiralsURL: URL
        if filename.lowercased().hasPrefix("spirals/") {
            // Path already includes Spirals/ prefix
            spiralsURL = bundle.appendingPathComponent(filename)
        } else {
            // Just a filename, add Spirals/ prefix
            spiralsURL = bundle.appendingPathComponent("Spirals").appendingPathComponent(filename)
        }

        print("Loading spiral image from: \(spiralsURL.path)")

        #if os(macOS)
        guard let image = NSImage(contentsOf: spiralsURL) else {
            print("Failed to load NSImage from: \(spiralsURL.path)")
            return nil
        }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Failed to convert NSImage to CGImage")
            return nil
        }
        #else
        guard let image = UIImage(contentsOfFile: spiralsURL.path) else {
            print("Failed to load UIImage from: \(spiralsURL.path)")
            return nil
        }
        guard let cgImage = image.cgImage else {
            print("Failed to convert UIImage to CGImage")
            return nil
        }
        #endif

        // Scale to cover the diagonal (so rotation doesn't show corners)
        let diagonal = sqrt(targetSize.width * targetSize.width + targetSize.height * targetSize.height)
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let targetDimension = 1.2 * diagonal
        let scale = targetDimension / min(imageSize.width, imageSize.height)

        return scaleImage(cgImage, scale: scale)
    }

    /// Generate the base spiral image from scratch
    private static func generateBaseSpiralImage(size: CGSize, config: SpiralConfig) -> CGImage? {
        // Calculate diagonal - this is how far the spiral needs to extend
        let diagonal = sqrt(size.width * size.width + size.height * size.height)

        // Make the spiral canvas square, sized to the diagonal
        // This ensures full coverage even when rotated
        let spiralSize = CGSize(width: diagonal, height: diagonal)

        let spiralPath = generateSpiralPath(canvasSize: spiralSize, maxRadius: diagonal / 2, scale: config.properties.scale)

        // Render base spiral with 4-way symmetry
        return renderBaseSpiralWithSymmetry(
            path: spiralPath,
            canvasSize: spiralSize,
            color: config.properties.color
        )
    }

    /// Scale an image
    private static func scaleImage(_ image: CGImage, scale: Double) -> CGImage? {
        let width = Int(Double(image.width) * scale)
        let height = Int(Double(image.height) * scale)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()
    }

    // MARK: - Spiral Path Generation

    /// Generate the spiral path using parametric equations
    /// x = t² * cos(t), y = t² * sin(t)
    private static func generateSpiralPath(canvasSize: CGSize, maxRadius: Double, scale: Int) -> [(x: Double, y: Double)] {
        var points: [(x: Double, y: Double)] = []

        let centerX = canvasSize.width / 2.0
        let centerY = canvasSize.height / 2.0

        // Calculate maxT based on the radius we need to reach
        // Since r = t², we need t = sqrt(maxRadius)
        let maxT = sqrt(maxRadius) * Double(scale)

        // Generate spiral points with parametric equations
        // Step size determines smoothness - smaller = smoother but more points
        let stepSize = 0.5 / Double(scale)

        for t in stride(from: 1.0, to: maxT, by: stepSize) {
            // Parametric spiral: r = t², θ = t
            let x = t * t * cos(t) + centerX
            let y = t * t * sin(t) + centerY

            points.append((x: x, y: y))
        }

        return points
    }

    // MARK: - Frame Rendering

    /// Render the base spiral image with 4-way symmetry
    private static func renderBaseSpiralWithSymmetry(
        path: [(x: Double, y: Double)],
        canvasSize: CGSize,
        color: [Int]
    ) -> CGImage? {

        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)

        // Create bitmap context at exact canvas dimensions
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            print("Failed to create CGContext")
            return nil
        }

        // Set black background
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Set spiral color (alpha will be applied when rendering)
        let r = Double(color[0]) / 255.0
        let g = Double(color[1]) / 255.0
        let b = Double(color[2]) / 255.0

        context.setStrokeColor(red: r, green: g, blue: b, alpha: 1.0)
        context.setLineWidth(4.0)

        // Use blend mode ADD for accumulating light (4-way symmetry creates bright center)
        context.setBlendMode(.plusLighter)

        let centerX = canvasSize.width / 2.0
        let centerY = canvasSize.height / 2.0

        // Draw spiral with 4-way rotational symmetry (at 0, 90, 180, 270 degrees)
        for symmetry in 0..<4 {
            let symmetryAngle = Double(symmetry) * .pi / 2.0

            context.beginPath()

            for (index, point) in path.enumerated() {
                // Translate to origin
                let dx = point.x - centerX
                let dy = point.y - centerY

                // Rotate
                let rotatedX = dx * cos(symmetryAngle) - dy * sin(symmetryAngle)
                let rotatedY = dx * sin(symmetryAngle) + dy * cos(symmetryAngle)

                // Translate back
                let finalX = rotatedX + centerX
                let finalY = rotatedY + centerY

                if index == 0 {
                    context.move(to: CGPoint(x: finalX, y: finalY))
                } else {
                    context.addLine(to: CGPoint(x: finalX, y: finalY))
                }
            }

            context.strokePath()
        }

        // Create image from context
        return context.makeImage()
    }
}

// MARK: - Helper Extensions

extension SpiralRenderer {
    /// Convenience method to generate spiral for a SpiralConfig
    static func generateSpiral(for config: SpiralConfig) -> CGImage? {
        let size = CGSize(
            width: config.properties.size[0],
            height: config.properties.size[1]
        )
        return generateSpiral(config: config, size: size)
    }
}
