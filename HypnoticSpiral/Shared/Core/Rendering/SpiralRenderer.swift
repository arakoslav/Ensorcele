//
//  SpiralRenderer.swift
//  HypnoticSpiral
//
//  Generates hypnotic spiral images using Core Graphics
//  Supports multiple spiral types: Fermat, Logarithmic, Filled, and Twist
//

import Foundation
import CoreGraphics

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Generates spiral images for animation
/// Each spiral type produces a static image that SwiftUI rotates via GPU
class SpiralRenderer {

    // MARK: - Public API

    /// Generate a spiral image based on config settings
    /// - Parameters:
    ///   - config: Configuration with spiral parameters
    ///   - size: Target image size (actual window dimensions)
    ///   - spiralType: Optional type override (uses config's type if nil)
    /// - Returns: Base spiral image (or tuple for twist type)
    static func generateSpiral(config: SpiralConfig, size: CGSize, spiralType: SpiralType? = nil) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        let effectiveType = spiralType ?? config.properties.spiralType

        print("Generating spiral: window=\(width)x\(height), type=\(effectiveType)")

        // Check if we should load a spiral image instead of generating (only if using config's type)
        if spiralType == nil && !config.properties.spiralImage.isEmpty {
            if let loadedImage = loadSpiralImage(named: config.properties.spiralImage, targetSize: size) {
                print("Loaded spiral image: \(config.properties.spiralImage)")
                return loadedImage
            } else {
                print("Failed to load spiral image '\(config.properties.spiralImage)', generating instead")
            }
        }

        // Generate spiral based on type
        return generateSpiralByType(config: config, size: size, spiralType: effectiveType)
    }

    /// Generate a counter-rotating spiral layer (for twist type)
    /// Returns nil if not a twist spiral
    static func generateCounterSpiral(config: SpiralConfig, size: CGSize, spiralType: SpiralType? = nil) -> CGImage? {
        let effectiveType = spiralType ?? config.properties.spiralType
        guard effectiveType == .twist else {
            return nil
        }

        // Generate thin white line spiral for counter-rotation
        return generateTwistCounterSpiral(config: config, size: size)
    }

    // MARK: - Spiral Type Dispatcher

    private static func generateSpiralByType(config: SpiralConfig, size: CGSize, spiralType: SpiralType) -> CGImage? {
        switch spiralType {
        case .fermat:
            return generateFermatSpiral(config: config, size: size)
        case .logarithmic:
            return generateLogarithmicSpiral(config: config, size: size, inverted: false)
        case .filled:
            return generateFilledSpiral(config: config, size: size)
        case .twist:
            // For twist, the primary layer is a filled purple spiral
            return generateTwistPrimarySpiral(config: config, size: size)
        case .nimja:
            // Nimja-style curved wedge spiral
            return generateNimjaSpiral(config: config, size: size)
        case .chromatic:
            // Shader-style spiral with chromatic aberration
            return generateChromaticSpiral(config: config, size: size)
        }
    }

    // MARK: - Fermat Spiral (Original)
    // r = t², θ = t — expanding spacing, your existing "great" spiral

    private static func generateFermatSpiral(config: SpiralConfig, size: CGSize) -> CGImage? {
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        let spiralSize = CGSize(width: diagonal, height: diagonal)

        let width = Int(spiralSize.width)
        let height = Int(spiralSize.height)

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
            print("Failed to create CGContext for Fermat spiral")
            return nil
        }

        // Enable anti-aliasing for smooth lines
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        // Black background
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let centerX = spiralSize.width / 2.0
        let centerY = spiralSize.height / 2.0
        let maxRadius = diagonal / 2
        let scale = config.properties.scale
        let arms = config.properties.spiralArms

        // Spiral color
        let r = Double(config.properties.color[0]) / 255.0
        let g = Double(config.properties.color[1]) / 255.0
        let b = Double(config.properties.color[2]) / 255.0

        context.setStrokeColor(red: r, green: g, blue: b, alpha: 1.0)
        context.setLineWidth(config.properties.spiralLineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setBlendMode(.plusLighter)

        // Fermat spiral: r = t², θ = t
        // Use dense line segments with anti-aliasing for smooth appearance
        let maxT = sqrt(maxRadius) * Double(scale)
        let stepSize = 0.05 / Double(scale)  // Small steps for smoothness

        for arm in 0..<arms {
            let angleOffset = Double(arm) * 2.0 * .pi / Double(arms)

            context.beginPath()

            var first = true
            for t in stride(from: 0.5, to: maxT, by: stepSize) {
                let x = t * t * cos(t + angleOffset) + centerX
                let y = t * t * sin(t + angleOffset) + centerY

                if first {
                    context.move(to: CGPoint(x: x, y: y))
                    first = false
                } else {
                    context.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.strokePath()
        }

        return context.makeImage()
    }

    // MARK: - Logarithmic Spiral (Constant Angle / Swoopy)
    // r = a * e^(b*θ) — classic "swoopy" spiral with constant angle crossings

    private static func generateLogarithmicSpiral(config: SpiralConfig, size: CGSize, inverted: Bool) -> CGImage? {
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        let spiralSize = CGSize(width: diagonal, height: diagonal)

        let width = Int(spiralSize.width)
        let height = Int(spiralSize.height)

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
            print("Failed to create CGContext for logarithmic spiral")
            return nil
        }

        // Enable anti-aliasing
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        // Black background
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let centerX = spiralSize.width / 2.0
        let centerY = spiralSize.height / 2.0
        let tightness = config.properties.spiralTightness
        let maxRadius = diagonal / 2
        let maxTheta = CoreGraphics.log(maxRadius) / tightness
        let arms = config.properties.spiralArms
        let direction: Double = inverted ? -1.0 : 1.0

        // Spiral color
        let r = Double(config.properties.color[0]) / 255.0
        let g = Double(config.properties.color[1]) / 255.0
        let b = Double(config.properties.color[2]) / 255.0

        context.setStrokeColor(red: r, green: g, blue: b, alpha: 1.0)
        context.setLineWidth(config.properties.spiralLineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setBlendMode(.plusLighter)

        // Logarithmic spiral: r = e^(b*θ)
        // Use dense line segments with anti-aliasing
        let stepSize = 0.02  // Small angular steps for smoothness

        for arm in 0..<arms {
            let angleOffset = Double(arm) * 2.0 * .pi / Double(arms)

            context.beginPath()

            var first = true
            for theta in stride(from: 0.0, to: maxTheta, by: stepSize) {
                let r_val = exp(tightness * theta)
                let angle = theta * direction + angleOffset
                let x = r_val * cos(angle) + centerX
                let y = r_val * sin(angle) + centerY

                if first {
                    context.move(to: CGPoint(x: x, y: y))
                    first = false
                } else {
                    context.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.strokePath()
        }

        return context.makeImage()
    }

    // MARK: - Filled Spiral (Half-Screen Tint)
    // Alternating filled sectors between spiral arms

    private static func generateFilledSpiral(config: SpiralConfig, size: CGSize) -> CGImage? {
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        let spiralSize = CGSize(width: diagonal, height: diagonal)

        let width = Int(spiralSize.width)
        let height = Int(spiralSize.height)

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
            print("Failed to create CGContext for filled spiral")
            return nil
        }

        // Enable anti-aliasing
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        // Black background
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let centerX = spiralSize.width / 2.0
        let centerY = spiralSize.height / 2.0
        let center = CGPoint(x: centerX, y: centerY)

        // Fill color (default to purple if not specified)
        let fillColor = config.properties.spiralFillColor ?? [128, 0, 128]
        let fr = Double(fillColor[0]) / 255.0
        let fg = Double(fillColor[1]) / 255.0
        let fb = Double(fillColor[2]) / 255.0

        // Line color
        //let lr = Double(config.properties.color[0]) / 255.0
        //let lg = Double(config.properties.color[1]) / 255.0
        //let lb = Double(config.properties.color[2]) / 255.0

        let arms = config.properties.spiralArms
        let tightness = config.properties.spiralTightness
        let maxRadius = diagonal / 2
        let maxTheta = CoreGraphics.log(maxRadius) / tightness
        let stepSize = 0.02  // Dense steps for smooth curves

        // Draw filled wedges using logarithmic spiral boundaries
        for arm in 0..<(arms * 2) {
            // Only fill every other sector
            guard arm % 2 == 0 else { continue }

            let startAngleOffset = Double(arm) * .pi / Double(arms)
            let endAngleOffset = Double(arm + 1) * .pi / Double(arms)

            let path = CGMutablePath()
            path.move(to: center)

            // First edge: spiral curve outward with dense line segments
            for theta in stride(from: 0.0, to: maxTheta, by: stepSize) {
                let r = exp(tightness * theta)
                let angle = theta + startAngleOffset
                let x = r * cos(angle) + centerX
                let y = r * sin(angle) + centerY
                path.addLine(to: CGPoint(x: x, y: y))
            }

            // Arc at outer edge
            let outerR = exp(tightness * maxTheta)
            path.addArc(center: center, radius: outerR,
                       startAngle: maxTheta + startAngleOffset,
                       endAngle: maxTheta + endAngleOffset,
                       clockwise: false)

            // Second edge: spiral curve back to center
            for theta in stride(from: maxTheta, to: 0.0, by: -stepSize) {
                let r = exp(tightness * theta)
                let angle = theta + endAngleOffset
                let x = r * cos(angle) + centerX
                let y = r * sin(angle) + centerY
                path.addLine(to: CGPoint(x: x, y: y))
            }

            path.closeSubpath()

            context.addPath(path)
            context.setFillColor(red: fr, green: fg, blue: fb, alpha: 1.0)
            context.fillPath()
        }

        // No stroke lines - just the filled sectors
        return context.makeImage()
    }

    // MARK: - Twist Spiral (Counter-rotating layers)
    // Primary: filled purple, Counter: thin white line

    /// Generate the primary twist layer - filled purple spiral (no stroke)
    private static func generateTwistPrimarySpiral(config: SpiralConfig, size: CGSize) -> CGImage? {
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        let spiralSize = CGSize(width: diagonal, height: diagonal)

        let width = Int(spiralSize.width)
        let height = Int(spiralSize.height)

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
            print("Failed to create CGContext for twist primary spiral")
            return nil
        }

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        // Transparent background (so counter spiral shows through)
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        let centerX = spiralSize.width / 2.0
        let centerY = spiralSize.height / 2.0
        let center = CGPoint(x: centerX, y: centerY)

        // Fill color (default to purple)
        let fillColor = config.properties.spiralFillColor ?? [128, 0, 128]
        let fr = Double(fillColor[0]) / 255.0
        let fg = Double(fillColor[1]) / 255.0
        let fb = Double(fillColor[2]) / 255.0

        let arms = config.properties.spiralArms
        let tightness = config.properties.spiralTightness
        let maxRadius = diagonal / 2
        let maxTheta = CoreGraphics.log(maxRadius) / tightness
        let stepSize = 0.02

        // Draw filled wedges
        for arm in 0..<(arms * 2) {
            guard arm % 2 == 0 else { continue }

            let startAngleOffset = Double(arm) * .pi / Double(arms)
            let endAngleOffset = Double(arm + 1) * .pi / Double(arms)

            let path = CGMutablePath()
            path.move(to: center)

            for theta in stride(from: 0.0, to: maxTheta, by: stepSize) {
                let r = exp(tightness * theta)
                let angle = theta + startAngleOffset
                let x = r * cos(angle) + centerX
                let y = r * sin(angle) + centerY
                path.addLine(to: CGPoint(x: x, y: y))
            }

            let outerR = exp(tightness * maxTheta)
            path.addArc(center: center, radius: outerR,
                       startAngle: maxTheta + startAngleOffset,
                       endAngle: maxTheta + endAngleOffset,
                       clockwise: false)

            for theta in stride(from: maxTheta, to: 0.0, by: -stepSize) {
                let r = exp(tightness * theta)
                let angle = theta + endAngleOffset
                let x = r * cos(angle) + centerX
                let y = r * sin(angle) + centerY
                path.addLine(to: CGPoint(x: x, y: y))
            }

            path.closeSubpath()

            context.addPath(path)
            context.setFillColor(red: fr, green: fg, blue: fb, alpha: 1.0)
            context.fillPath()
        }

        return context.makeImage()
    }

    /// Generate the counter twist layer - thin white line spiral
    private static func generateTwistCounterSpiral(config: SpiralConfig, size: CGSize) -> CGImage? {
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        let spiralSize = CGSize(width: diagonal, height: diagonal)

        let width = Int(spiralSize.width)
        let height = Int(spiralSize.height)

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
            print("Failed to create CGContext for twist counter spiral")
            return nil
        }

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        // Transparent background
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        let centerX = spiralSize.width / 2.0
        let centerY = spiralSize.height / 2.0
        let tightness = config.properties.spiralTightness
        let maxRadius = diagonal / 2
        let maxTheta = CoreGraphics.log(maxRadius) / tightness
        let arms = config.properties.spiralArms
        let stepSize = 0.02

        // Thin white line
        context.setStrokeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        context.setLineWidth(2.0)  // Thin line
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Same winding as primary - rotation handles the counter direction
        for arm in 0..<arms {
            let angleOffset = Double(arm) * 2.0 * .pi / Double(arms)

            context.beginPath()

            var first = true
            for theta in stride(from: 0.0, to: maxTheta, by: stepSize) {
                let r = exp(tightness * theta)
                let angle = theta + angleOffset  // Same winding, rotation is opposite
                let x = r * cos(angle) + centerX
                let y = r * sin(angle) + centerY

                if first {
                    context.move(to: CGPoint(x: x, y: y))
                    first = false
                } else {
                    context.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.strokePath()
        }

        return context.makeImage()
    }

    // MARK: - Nimja Spiral (Curved Wedge Sectors)
    // Classic hypno.nimja.com style: curved wedges that create strong "pulling in" effect

    private static func generateNimjaSpiral(config: SpiralConfig, size: CGSize) -> CGImage? {
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        let spiralSize = CGSize(width: diagonal, height: diagonal)

        let width = Int(spiralSize.width)
        let height = Int(spiralSize.height)

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
            print("Failed to create CGContext for nimja spiral")
            return nil
        }

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        // Black background
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let centerX = spiralSize.width / 2.0
        let centerY = spiralSize.height / 2.0
        let center = CGPoint(x: centerX, y: centerY)

        // Primary color from config, secondary is white
        let r1 = Double(config.properties.color[0]) / 255.0
        let g1 = Double(config.properties.color[1]) / 255.0
        let b1 = Double(config.properties.color[2]) / 255.0

        // Fill color for alternating sectors (default white)
        let fillColor = config.properties.spiralFillColor ?? [255, 255, 255]
        let r2 = Double(fillColor[0]) / 255.0
        let g2 = Double(fillColor[1]) / 255.0
        let b2 = Double(fillColor[2]) / 255.0

        let arms = config.properties.spiralArms
        let tightness = config.properties.spiralTightness
        let maxRadius = diagonal / 2

        // Nimja spiral uses radial sectors that twist as they extend outward
        // The key is that each sector boundary follows an Archimedean spiral
        // r = a + b*θ, creating a constant-spacing effect

        let numSectors = arms * 2  // Double for alternating colors
        let sectorAngle = 2.0 * .pi / Double(numSectors)

        // How much each sector twists as it goes outward
        let twistFactor = tightness * 10.0  // Amplify tightness for visible twist

        // Number of radial steps for smooth curves
        let radialSteps = 100
        let radiusStep = maxRadius / Double(radialSteps)

        // Draw each sector as a series of small trapezoids from center outward
        for sector in 0..<numSectors {
            // Alternating colors
            let isEven = sector % 2 == 0
            if isEven {
                context.setFillColor(red: r1, green: g1, blue: b1, alpha: 1.0)
            } else {
                context.setFillColor(red: r2, green: g2, blue: b2, alpha: 1.0)
            }

            let baseAngle = Double(sector) * sectorAngle

            // Build the sector path from center to edge
            let path = CGMutablePath()
            path.move(to: center)

            // Trace outward along the leading edge (with twist)
            for step in 0...radialSteps {
                let radius = Double(step) * radiusStep
                // The twist increases with radius
                let twist = (radius / maxRadius) * twistFactor
                let angle = baseAngle + twist

                let x = radius * cos(angle) + centerX
                let y = radius * sin(angle) + centerY
                path.addLine(to: CGPoint(x: x, y: y))
            }

            // Trace back inward along the trailing edge (with twist)
            for step in stride(from: radialSteps, through: 0, by: -1) {
                let radius = Double(step) * radiusStep
                let twist = (radius / maxRadius) * twistFactor
                let angle = baseAngle + sectorAngle + twist

                let x = radius * cos(angle) + centerX
                let y = radius * sin(angle) + centerY
                path.addLine(to: CGPoint(x: x, y: y))
            }

            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
        }

        return context.makeImage()
    }

    // MARK: - Chromatic Spiral (Shader-style with RGB aberration)
    // Based on hypno.nimja.com/visual/131 - sine wave pattern with chromatic aberration

    private static func generateChromaticSpiral(config: SpiralConfig, size: CGSize) -> CGImage? {
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        let spiralSize = CGSize(width: diagonal, height: diagonal)

        let width = Int(spiralSize.width)
        let height = Int(spiralSize.height)

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
            print("Failed to create CGContext for chromatic spiral")
            return nil
        }

        // Get pixel buffer for direct manipulation
        guard let data = context.data else {
            print("Failed to get pixel data for chromatic spiral")
            return nil
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let centerX = Double(width) / 2.0
        let centerY = Double(height) / 2.0
        let maxDist = diagonal / 2.0

        // Parameters from config
        let arms = Double(config.properties.spiralArms)  // Number of spiral arms
        let turns = config.properties.spiralTightness * 15.0  // How tightly wound (turns multiplier)
        let aberration = 0.5  // Chromatic aberration amount (could be made configurable)

        // Process each pixel
        for y in 0..<height {
            for x in 0..<width {
                // Normalized coordinates from center (-1 to 1 range)
                let px = (Double(x) - centerX) / maxDist
                let py = (Double(y) - centerY) / maxDist

                // Polar coordinates
                let length = sqrt(px * px + py * py)
                let angle = atan2(py, px)

                // Distance with power curve (creates the hypnotic density gradient)
                let dist = pow(length * 2.0, 0.25)

                // Calculate each color channel with slight angle offset for chromatic aberration
                // sin(dist * turns + angle * arms) creates the spiral pattern
                let baseCalc = dist * turns

                // Red channel - offset angle slightly
                let rAngle = angle - aberration * 0.1
                let rValue = sin(baseCalc + rAngle * arms)
                let r = UInt8(max(0, min(255, (rValue * 0.5 + 0.5) * 255)))

                // Green channel - no offset
                let gValue = sin(baseCalc + angle * arms)
                let g = UInt8(max(0, min(255, (gValue * 0.5 + 0.5) * 255)))

                // Blue channel - offset angle opposite direction
                let bAngle = angle + aberration * 0.1
                let bValue = sin(baseCalc + bAngle * arms)
                let b = UInt8(max(0, min(255, (bValue * 0.5 + 0.5) * 255)))

                // Write RGBA
                let offset = (y * width + x) * 4
                pixels[offset] = r
                pixels[offset + 1] = g
                pixels[offset + 2] = b
                pixels[offset + 3] = 255  // Full alpha
            }
        }

        return context.makeImage()
    }

    // MARK: - Image Loading

    /// Load a spiral image from the Spirals directory
    private static func loadSpiralImage(named filename: String, targetSize: CGSize) -> CGImage? {
        guard let bundle = Bundle.main.resourceURL else { return nil }

        // Handle both "hypnoticswirl.jpg" and "Spirals/hypnoticswirl.jpg" formats
        let spiralsURL: URL
        if filename.lowercased().hasPrefix("spirals/") {
            spiralsURL = bundle.appendingPathComponent(filename)
        } else {
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
