//
//  FullscreenModifier.swift
//  HypnoticSpiral
//
//  macOS fullscreen support using AppKit
//

#if os(macOS)
import SwiftUI
import AppKit

struct FullscreenModifier: ViewModifier {
    let isFullscreen: Bool
    @State private var enteredFullscreen = false

    func body(content: Content) -> some View {
        content
            .background(FullscreenWindowAccessor(isFullscreen: isFullscreen, enteredFullscreen: $enteredFullscreen))
    }
}

struct FullscreenWindowAccessor: NSViewRepresentable {
    let isFullscreen: Bool
    @Binding var enteredFullscreen: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        if isFullscreen && !enteredFullscreen {
            // Try to get the window and toggle fullscreen
            DispatchQueue.main.async {
                if let window = view.window {
                    if !window.styleMask.contains(.fullScreen) {
                        window.toggleFullScreen(nil)
                        enteredFullscreen = true
                    }
                } else {
                    // Window not ready, try again
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let window = view.window {
                            if !window.styleMask.contains(.fullScreen) {
                                window.toggleFullScreen(nil)
                                enteredFullscreen = true
                            }
                        }
                    }
                }
            }
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func requestFullscreen(_ enabled: Bool) -> some View {
        modifier(FullscreenModifier(isFullscreen: enabled))
    }
}
#endif
