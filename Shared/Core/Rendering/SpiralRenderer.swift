//
//  SpiralRenderer.swift
//  HypnoticSpiral
//
//  Generates spiral images using Core Graphics
//  Ports Python spiral generation: x = t*t*cos(t), y = t*t*sin(t)
//

import Foundation
import CoreGraphics
import SwiftUI

/// Generates spiral frames using Core Graphics
class SpiralRenderer {
    /// Generate spiral frames based on configuration
    /// Returns array of pre-rendered CGImage frames for cycling
    static func generateSpiral(config: SpiralConfig, size: CGSize) -> [CGImage] {
        let properties = config.properties

        // Use custom spiral image if specified
        if !properties.spiralImage.isEmpty {
            return loadCustomSpiral(named: properties.spiralImage, config: config)
        }

        // Generate spiral programmatically
        return generateSpiralFrames(
            size: size,
            color: properties.color,
            alpha: properties.alpha,
            spiralRange: properties.spiralRange,
            spiralStep: properties.spiralStep,
            scale: properties.scale
        )
    }

    /// Generate spiral frames programmatically
    private static func generateSpiralFrames(
        size: CGSize,
        color: [Int],
        alpha: Int,
        spiralRange: Int,
        spiralStep: Int,
        scale: Int
    ) -> [CGImage] {
        var frames: [CGImage] = []

        // Calculate spiral size (larger than screen to ensure coverage)
        let spiralSize = max(size.width, size.height) * 1.2

        // Generate base spiral path
        let spiralPath = generateSpiralPath(size: spiralSize, scale: scale)

        // Create frames for each rotation angle
        let angleCount = spiralRange / spiralStep
        for i in 0..<angleCount {
            let angle = Double(i * spiralStep) * .pi / 180.0

            if let image = renderSpiralFrame(
                path: spiralPath,
                size: size,
                angle: angle,
                color: color,
                alpha: alpha
            ) {
                frames.append(image)
            }
        }

        print("Generated \(frames.count) spiral frames")
        return frames
    }

    /// Generate spiral path using parametric equations
    /// Python: x = t*t*cos(t), y = t*t*sin(t)
    private static func generateSpiralPath(size: CGFloat, scale: Int) -> [CGPoint] {
        var points: [CGPoint] = []
        let center = CGPoint(x: size / 2, y: size / 2)

        // Generate spiral points
        let maxT = size * CGFloat(scale)
        let step = 0.5 / CGFloat(scale)

        var t: CGFloat = 1.0
        while t < maxT {
            // Parametric spiral equations
            let x = t * t * cos(t) + center.x
            let y = t * t * sin(t) + center.y

            points.append(CGPoint(x: x, y: y))

            t += step
        }

        return points
    }

    /// Render a single spiral frame with rotation
    private static func renderSpiralFrame(
        path: [CGPoint],
        size: CGSize,
        angle: Double,
        color: [Int],
        alpha: Int
    ) -> CGImage? {
        // Create bitmap context
        let width = Int(size.width)
        let height = Int(size.height)
        let bitsPerComponent = 8
        let bytesPerRow = width * 4

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Clear background (black)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))

        // Set spiral color
        let r = CGFloat(color[0]) / 255.0
        let g = CGFloat(color[1]) / 255.0
        let b = CGFloat(color[2]) / 255.0
        let a = CGFloat(alpha) / 255.0

        context.setStrokeColor(CGColor(red: r, green: g, blue: b, alpha: a))
        context.setLineWidth(2.0)
        context.setBlendMode(.normal)

        // Apply rotation transform
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.rotate(by: angle)
        context.translateBy(x: -size.width / 2, y: -size.height / 2)

        // Draw spiral with 4-way symmetry (like Python BLEND_ADD)
        drawSymmetricSpiral(context: context, path: path, size: size)

        return context.makeImage()
    }

    /// Draw spiral with 4-way rotational symmetry
    private static func drawSymmetricSpiral(
        context: CGContext,
        path: [CGPoint],
        size: CGSize
    ) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // Draw spiral 4 times with 90° rotation for symmetry
        for rotation in 0..<4 {
            let angle = Double(rotation) * .pi / 2

            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: angle)
            context.translateBy(x: -center.x, y: -center.y)

            // Draw the spiral path
            guard let firstPoint = path.first else { continue }
            context.move(to: firstPoint)

            for point in path.dropFirst() {
                context.addLine(to: point)
            }

            context.strokePath()
            context.restoreGState()
        }
    }

    /// Load custom spiral image from bundle
    private static func loadCustomSpiral(
        named name: String,
        config: SpiralConfig
    ) -> [CGImage] {
        // TODO: Load and rotate custom spiral image
        print("Loading custom spiral: \(name)")

        // For now, fall back to generated spiral
        return []
    }
}

// MARK: - Color Helpers

extension SpiralRenderer {
    /// Convert RGB array to CGColor
    static func cgColor(from rgb: [Int], alpha: Int = 255) -> CGColor {
        let r = CGFloat(rgb[0]) / 255.0
        let g = CGFloat(rgb[1]) / 255.0
        let b = CGFloat(rgb[2]) / 255.0
        let a = CGFloat(alpha) / 255.0
        return CGColor(red: r, green: g, blue: b, alpha: a)
    }
}
