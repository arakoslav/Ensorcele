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

    /// Generate a counter-rotating spiral layer (for twist and rings types)
    /// Returns nil if type doesn't support counter-rotation
    static func generateCounterSpiral(config: SpiralConfig, size: CGSize, spiralType: SpiralType? = nil) -> CGImage? {
        let effectiveType = spiralType ?? config.properties.spiralType

        switch effectiveType {
        case .twist:
            // Generate thin white line spiral for counter-rotation
            return generateTwistCounterSpiral(config: config, size: size)
        case .colors:
            // Generate counter-rotating spoke layer for colors
            return generateColorsCounterSpiral(config: config, size: size)
        default:
            return nil
        }
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
        case .chromatic:
            // Shader-style spiral with chromatic aberration
            return generateChromaticSpiral(config: config, size: size)
        case .colors:
            // Color-shifting bands flowing outward (formerly "rings")
            return generateColorsSpiral(config: config, size: size)
        case .rings:
            // Concentric rings expanding from center with optional texture
            return generateExpandingRingsSpiral(config: config, size: size)
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

    // MARK: - Colors Spiral (Concentric flowing color bands)
    // Color-shifting bands with irregular texture, colors blending and shifting outward
    // Optional spoked wheel texture with wheels rotating in different directions

    private static func generateColorsSpiral(config: SpiralConfig, size: CGSize) -> CGImage? {
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
            print("Failed to create CGContext for colors spiral")
            return nil
        }

        guard let data = context.data else {
            print("Failed to get pixel data for colors spiral")
            return nil
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let centerX = Double(width) / 2.0
        let centerY = Double(height) / 2.0
        let maxDist = diagonal / 2.0

        // Configuration parameters
        let bandCount = Double(config.properties.colorsBandCount)
        let spokeCount = config.properties.colorsSpokes
        let expansionRate = config.properties.colorsExpansionRate

        // Use a seeded random for consistent "irregular" texture
        // The irregularity comes from varying band widths
        var bandPhases: [Double] = []
        var bandWidths: [Double] = []
        for i in 0..<Int(bandCount) {
            // Pseudo-random based on band index for reproducibility
            let phase = sin(Double(i) * 2.7183) * 0.5 + 0.5
            bandPhases.append(phase)
            // Width varies - inner rings narrower, outer rings broader (until they meet)
            let baseWidth = 1.0 / bandCount
            let widthVariation = 0.3 + 0.7 * (Double(i) / bandCount)  // 30% to 100%
            bandWidths.append(baseWidth * widthVariation)
        }

        // Normalize band widths so they sum to 1.0
        let totalWidth = bandWidths.reduce(0, +)
        bandWidths = bandWidths.map { $0 / totalWidth }

        // Calculate cumulative positions for bands
        var bandPositions: [Double] = [0.0]
        for width in bandWidths {
            bandPositions.append(bandPositions.last! + width)
        }

        // Process each pixel
        for y in 0..<height {
            for x in 0..<width {
                let px = Double(x) - centerX
                let py = Double(y) - centerY

                // Polar coordinates
                let dist = sqrt(px * px + py * py)
                let normalizedDist = dist / maxDist
                let angle = atan2(py, px)

                // Add spiral twist to distance for "flowing" effect when rotated
                // This makes colors appear to flow outward during rotation
                let spiralTwist = angle * expansionRate / (2.0 * .pi)
                let flowDist = (normalizedDist + spiralTwist).truncatingRemainder(dividingBy: 1.0)
                let effectiveDist = flowDist < 0 ? flowDist + 1.0 : flowDist

                // Determine which band this pixel falls in
                var bandIndex = 0
                for i in 0..<Int(bandCount) {
                    if effectiveDist >= bandPositions[i] && effectiveDist < bandPositions[i + 1] {
                        bandIndex = i
                        break
                    }
                }

                // Position within the band (0 to 1)
                let bandStart = bandPositions[bandIndex]
                let bandEnd = bandPositions[bandIndex + 1]
                let posInBand = (effectiveDist - bandStart) / (bandEnd - bandStart)

                // Calculate hue - shifts through spectrum based on band + position
                // Each band has a different base hue, creating color diversity
                let baseHue = Double(bandIndex) / bandCount
                let hueShift = posInBand * 0.1  // Subtle shift within band
                let hue = (baseHue + hueShift + bandPhases[bandIndex] * 0.2).truncatingRemainder(dividingBy: 1.0)

                // Saturation varies for texture - stronger at band centers
                let distFromBandCenter = abs(posInBand - 0.5) * 2.0
                let saturation = 0.7 + 0.3 * (1.0 - distFromBandCenter)

                // Value/brightness - creates the ring definition
                // Darker at band edges for definition, brighter at centers
                let edgeFade = 1.0 - pow(distFromBandCenter, 2.0) * 0.4
                var value = edgeFade

                // Add irregular "pulse" texture based on angle and band
                let pulseFreq = 3.0 + Double(bandIndex) * 0.5
                let pulse = sin(angle * pulseFreq + bandPhases[bandIndex] * 10.0) * 0.1 + 0.9
                value *= pulse

                // Optional spokes - create radial wheel texture
                if spokeCount > 0 {
                    // Different bands have spokes at different rotation offsets
                    // This creates the "wheels rotating different directions" effect
                    let spokeOffset = bandPhases[bandIndex] * 2.0 * .pi
                    let effectiveAngle = angle + spokeOffset

                    // Calculate spoke intensity
                    let spokeAngle = effectiveAngle * Double(spokeCount) / 2.0
                    let spokeIntensity = pow(cos(spokeAngle), 2.0)

                    // Blend spoke pattern - stronger in middle bands for layered effect
                    let bandCenteredness = 1.0 - abs(Double(bandIndex) - bandCount / 2.0) / (bandCount / 2.0)
                    let spokeBlend = 0.3 * bandCenteredness

                    value = value * (1.0 - spokeBlend) + spokeIntensity * spokeBlend
                }

                // Convert HSV to RGB
                let (r, g, b) = hsvToRgb(h: hue, s: saturation, v: value)

                // Write RGBA
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(max(0, min(255, r * 255)))
                pixels[offset + 1] = UInt8(max(0, min(255, g * 255)))
                pixels[offset + 2] = UInt8(max(0, min(255, b * 255)))
                pixels[offset + 3] = 255
            }
        }

        return context.makeImage()
    }

    /// Generate a counter-rotating spoke layer for colors (when spokes are enabled)
    /// This creates "wheels rotating in different directions" effect
    static func generateColorsCounterSpiral(config: SpiralConfig, size: CGSize) -> CGImage? {
        let spokeCount = config.properties.colorsSpokes
        guard spokeCount > 0 else { return nil }

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
            return nil
        }

        guard let data = context.data else { return nil }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let centerX = Double(width) / 2.0
        let centerY = Double(height) / 2.0
        let maxDist = diagonal / 2.0
        let bandCount = Double(config.properties.colorsBandCount)

        // Generate an alternating spoke pattern for counter-rotation layer
        for y in 0..<height {
            for x in 0..<width {
                let px = Double(x) - centerX
                let py = Double(y) - centerY

                let dist = sqrt(px * px + py * py)
                let normalizedDist = dist / maxDist
                let angle = atan2(py, px)

                // Determine which band region (outer half only for counter-rotation)
                let bandIndex = Int(normalizedDist * bandCount)
                let isOuterHalf = bandIndex > Int(bandCount) / 2

                // Only draw spokes in outer region for this counter layer
                guard isOuterHalf else {
                    let offset = (y * width + x) * 4
                    pixels[offset] = 0
                    pixels[offset + 1] = 0
                    pixels[offset + 2] = 0
                    pixels[offset + 3] = 0
                    continue
                }

                // Spoke pattern
                let spokeAngle = angle * Double(spokeCount) / 2.0
                let spokeIntensity = pow(cos(spokeAngle), 4.0)

                // Fade in from middle to edge
                let fadeFactor = (normalizedDist - 0.5) * 2.0

                let alpha = UInt8(spokeIntensity * fadeFactor * 180)

                let offset = (y * width + x) * 4
                pixels[offset] = 255
                pixels[offset + 1] = 255
                pixels[offset + 2] = 255
                pixels[offset + 3] = alpha
            }
        }

        return context.makeImage()
    }

    // MARK: - Expanding Rings (True concentric circles)
    // Actual circles expanding from center - NOT a spiral
    // Texture shows rotation when image spins, rings stay as circles
    // Generate multiple frames for smooth expansion animation

    /// Generate all frames for expanding rings animation
    static func generateRingsFrames(config: SpiralConfig, size: CGSize, frameCount: Int = 30) -> [CGImage] {
        var frames: [CGImage] = []
        let spacing = config.properties.ringsSpacing

        for i in 0..<frameCount {
            // Phase goes from 0 to spacing over all frames
            let phase = spacing * Double(i) / Double(frameCount)
            if let frame = generateExpandingRingsFrame(config: config, size: size, phaseOffset: phase) {
                frames.append(frame)
            }
        }

        return frames
    }

    /// Generate a single frame of the rings animation (called by dispatcher for preview)
    private static func generateExpandingRingsSpiral(config: SpiralConfig, size: CGSize) -> CGImage? {
        return generateExpandingRingsFrame(config: config, size: size, phaseOffset: 0)
    }

    /// Generate a single frame with rings at a specific phase offset
    private static func generateExpandingRingsFrame(config: SpiralConfig, size: CGSize, phaseOffset: Double) -> CGImage? {
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
            print("Failed to create CGContext for expanding rings")
            return nil
        }

        guard let data = context.data else {
            print("Failed to get pixel data for expanding rings")
            return nil
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let centerX = Double(width) / 2.0
        let centerY = Double(height) / 2.0

        // Configuration parameters
        let lineWidth = config.properties.ringsLineWidth
        let spacing = config.properties.ringsSpacing
        let pulseWave = config.properties.ringsPulseWave
        let textured = config.properties.ringsTextured

        // Ring color from config
        let r = Double(config.properties.color[0]) / 255.0
        let g = Double(config.properties.color[1]) / 255.0
        let b = Double(config.properties.color[2]) / 255.0

        // Process each pixel
        for y in 0..<height {
            for x in 0..<width {
                let px = Double(x) - centerX
                let py = Double(y) - centerY

                // Pure distance from center - no angle component for ring position
                // This keeps rings as true circles
                let dist = sqrt(px * px + py * py)
                let angle = atan2(py, px)

                // Apply phase offset for expansion animation
                // Subtracting phase makes rings appear to move outward as phase increases
                // (a ring at distance d in frame 0 appears at distance d+phase in frame n)
                let effectiveDist = dist - phaseOffset

                // Calculate spacing with optional pulse wave (denser ring areas)
                var currentSpacing = spacing
                if pulseWave > 0 {
                    // Create waves of denser rings that pulse outward
                    let pulsePhase = effectiveDist / (spacing * 5.0)
                    let pulseFactor = 1.0 - pulseWave * 0.5 * (sin(pulsePhase * 2.0 * .pi) + 1.0) / 2.0
                    currentSpacing = spacing * max(0.3, pulseFactor)
                }

                // Distance to nearest ring center (true circles)
                // Use effectiveDist for ring position calculation
                var ringPhase = effectiveDist.truncatingRemainder(dividingBy: currentSpacing)
                if ringPhase < 0 { ringPhase += currentSpacing }  // Handle negative values near center
                let distToRingCenter = min(ringPhase, currentSpacing - ringPhase)

                // Which ring number is this?
                let ringNum = Int(max(0, effectiveDist) / currentSpacing)

                // Ring intensity based on distance to ring center
                var intensity: Double = 0.0
                if distToRingCenter < lineWidth / 2.0 {
                    // Inside the ring line - soft edges
                    let edgeDist = distToRingCenter / (lineWidth / 2.0)
                    intensity = 1.0 - edgeDist * edgeDist
                }

                // Add radial texture if enabled - this shows rotation when image spins
                // Without texture, spinning just looks like zooming
                if textured && intensity > 0 {
                    // Different texture frequency for each ring creates depth
                    let textureFreq = 12.0 + Double(ringNum % 3) * 6.0
                    // Phase offset per ring makes them appear to spin at different rates
                    let texturePhase = Double(ringNum) * 1.2
                    // Radial modulation - varies brightness around the ring
                    let texture = 0.5 + 0.5 * cos(angle * textureFreq + texturePhase)

                    intensity *= texture
                }

                // Write RGBA (clamp all values to valid UInt8 range)
                let offset = (y * width + x) * 4
                let clampedIntensity = max(0.0, min(1.0, intensity))
                pixels[offset] = UInt8(r * clampedIntensity * 255)
                pixels[offset + 1] = UInt8(g * clampedIntensity * 255)
                pixels[offset + 2] = UInt8(b * clampedIntensity * 255)
                pixels[offset + 3] = UInt8(clampedIntensity * 255)
            }
        }

        return context.makeImage()
    }

    /// Convert HSV to RGB (h, s, v all in 0-1 range)
    private static func hsvToRgb(h: Double, s: Double, v: Double) -> (Double, Double, Double) {
        if s == 0 {
            return (v, v, v)
        }

        let h6 = h * 6.0
        let i = Int(h6)
        let f = h6 - Double(i)
        let p = v * (1.0 - s)
        let q = v * (1.0 - s * f)
        let t = v * (1.0 - s * (1.0 - f))

        switch i % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        case 5: return (v, p, q)
        default: return (v, v, v)
        }
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
