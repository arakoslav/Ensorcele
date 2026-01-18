//
//  ShaderSpiralView.swift
//  HypnoticSpiral
//
//  Real-time Metal shader rendering for custom spiral effects
//  Supports loading GLSL-style shaders from files
//

import SwiftUI
import MetalKit

/// A view that renders custom Metal shaders for spiral effects
/// Shaders receive time, resolution, and spiral color as uniforms
struct ShaderSpiralView: View {
    let shaderName: String
    let color: Color
    let alpha: Double
    let speed: Double

    @State private var startTime: Date = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsedTime = timeline.date.timeIntervalSince(startTime) * speed

            ShaderRenderView(
                shaderName: shaderName,
                time: Float(elapsedTime),
                color: color,
                alpha: alpha
            )
        }
    }
}

/// Metal-based shader rendering view using MetalKit
struct ShaderRenderView: View {
    let shaderName: String
    let time: Float
    let color: Color
    let alpha: Double

    var body: some View {
        GeometryReader { geometry in
            MetalShaderRepresentable(
                shaderName: shaderName,
                time: time,
                size: geometry.size,
                color: color,
                alpha: alpha
            )
        }
    }
}

// MARK: - MetalKit Fallback for older OS versions

#if os(macOS)
import AppKit
typealias ViewRepresentable = NSViewRepresentable
typealias ViewType = NSView
#else
import UIKit
typealias ViewRepresentable = UIViewRepresentable
typealias ViewType = UIView
#endif

/// MetalKit-based shader view for older OS versions
struct MetalShaderRepresentable: ViewRepresentable {
    let shaderName: String
    let time: Float
    let size: CGSize
    let color: Color
    let alpha: Double

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    #if os(macOS)
    func makeNSView(context: Context) -> MTKView {
        makeMetalView(context: context)
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        updateMetalView(nsView, context: context)
    }
    #else
    func makeUIView(context: Context) -> MTKView {
        makeMetalView(context: context)
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        updateMetalView(uiView, context: context)
    }
    #endif

    private func makeMetalView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.preferredFramesPerSecond = 60
        mtkView.framebufferOnly = false
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        // Enable transparency so images show through
        #if os(macOS)
        mtkView.layer?.isOpaque = false
        mtkView.layer?.backgroundColor = .clear
        #else
        mtkView.isOpaque = false
        mtkView.backgroundColor = .clear
        #endif

        // Set up the render pipeline
        if let device = mtkView.device {
            context.coordinator.setupPipeline(device: device, shaderName: shaderName)
        }

        return mtkView
    }

    private func updateMetalView(_ mtkView: MTKView, context: Context) {
        context.coordinator.time = time
        context.coordinator.size = size
        context.coordinator.color = color
        context.coordinator.alpha = alpha

        // Rebuild pipeline if shader changed
        if context.coordinator.currentShaderName != shaderName,
           let device = mtkView.device {
            context.coordinator.setupPipeline(device: device, shaderName: shaderName)
        }
    }

    class Coordinator: NSObject, MTKViewDelegate {
        var pipelineState: MTLRenderPipelineState?
        var commandQueue: MTLCommandQueue?
        var currentShaderName: String = ""
        var time: Float = 0
        var size: CGSize = .zero
        var color: Color = .white
        var alpha: Double = 1.0

        func setupPipeline(device: MTLDevice, shaderName: String) {
            currentShaderName = shaderName
            commandQueue = device.makeCommandQueue()

            // Try to load the shader from the default library
            guard let library = device.makeDefaultLibrary() else {
                print("Failed to load Metal library - ensure SpiralShaders.metal is added to the target")
                return
            }

            guard let vertexFunction = library.makeFunction(name: "spiralVertexShader") else {
                print("Failed to load vertex shader 'spiralVertexShader'")
                return
            }

            var fragmentFunction = library.makeFunction(name: shaderName)
            if fragmentFunction == nil {
                print("Shader '\(shaderName)' not found, falling back to hypnoticSpiralShader")
                fragmentFunction = library.makeFunction(name: "hypnoticSpiralShader")
            }

            guard let fragment = fragmentFunction else {
                print("Failed to load any fragment shader")
                return
            }

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragment
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            // Additive RGB blending - spiral colors add to background for vibrant colors
            // while still showing images through transparent areas
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
            // Alpha blending (standard for transparency)
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            do {
                pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                print("Successfully created pipeline for shader: \(shaderName)")
            } catch {
                print("Failed to create pipeline state: \(error)")
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            self.size = size
        }

        func draw(in view: MTKView) {
            guard let pipelineState = pipelineState,
                  let commandQueue = commandQueue,
                  let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }

            renderEncoder.setRenderPipelineState(pipelineState)

            // Set uniforms
            var uniforms = ShaderUniforms(
                time: time,
                resolution: SIMD2<Float>(Float(size.width), Float(size.height)),
                color: SIMD4<Float>(
                    Float(color.components.red),
                    Float(color.components.green),
                    Float(color.components.blue),
                    Float(alpha / 255.0)
                )
            )
            renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 0)

            // Draw fullscreen quad
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

/// Uniform data passed to shaders
struct ShaderUniforms {
    var time: Float
    var resolution: SIMD2<Float>
    var color: SIMD4<Float>
}

// MARK: - Color Extension for component access

extension Color {
    var components: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        #if os(macOS)
        let nsColor = NSColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
        #else
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
        #endif
    }
}

// MARK: - Preview

#Preview {
    ShaderSpiralView(
        shaderName: "hypnoticSpiralShader",
        color: .white,
        alpha: 255,
        speed: 1.0
    )
    .frame(width: 400, height: 400)
    .background(.black)
}
