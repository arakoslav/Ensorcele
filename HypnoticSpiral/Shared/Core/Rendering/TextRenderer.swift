//
//  TextRenderer.swift
//  HypnoticSpiral
//
//  SwiftUI views for rendering outlined text similar to pygame font rendering
//

import SwiftUI

/// Renders text with an outline (stroke) effect
struct OutlinedText: View {
    let text: String
    let fontSize: CGFloat
    let textColor: Color
    let outlineColor: Color
    let outlineWidth: CGFloat

    init(
        _ text: String,
        fontSize: CGFloat = 48,
        textColor: Color = Color(red: 0, green: 51.0/255.0, blue: 204.0/255.0),
        outlineColor: Color = .white,
        outlineWidth: CGFloat = 2
    ) {
        self.text = text
        self.fontSize = fontSize
        self.textColor = textColor
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
    }

    var body: some View {
        // Replace \n with actual newlines
        let processedText = text.replacingOccurrences(of: "\\n", with: "\n")

        ZStack {
            // Outline layer (white stroke)
            Text(processedText)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(outlineColor)
                .shadow(color: outlineColor, radius: outlineWidth)
                .shadow(color: outlineColor, radius: outlineWidth)
                .multilineTextAlignment(.center)

            // Main text layer (colored fill)
            Text(processedText)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)
        }
    }
}

/// Renders text from SpiralConfig color settings
struct ConfiguredText: View {
    let text: String
    let config: SpiralConfig
    let fontSize: CGFloat

    init(_ text: String, config: SpiralConfig, fontSize: CGFloat = 48) {
        self.text = text
        self.config = config
        self.fontSize = fontSize
    }

    var body: some View {
        let textColor = Color(
            red: Double(config.properties.textColor[0]) / 255.0,
            green: Double(config.properties.textColor[1]) / 255.0,
            blue: Double(config.properties.textColor[2]) / 255.0
        )
        let textAlpha = Double(config.properties.textAlpha) / 255.0

        OutlinedText(
            text,
            fontSize: fontSize,
            textColor: textColor.opacity(textAlpha)
        )
    }
}

#Preview {
    ZStack {
        Color.black
        VStack(spacing: 40) {
            OutlinedText("Relax and focus")
            OutlinedText("Deeper and deeper", fontSize: 64)
            OutlinedText(
                "You are getting sleepy",
                fontSize: 56,
                textColor: .purple,
                outlineColor: .cyan
            )
        }
    }
    .ignoresSafeArea()
}
