//
//  SpiralConfig.swift
//  HypnoticSpiral
//
//  Codable configuration model for hypnotic spiral programs
//  Supports JSON loading with inheritance
//

import Foundation

/// Main configuration structure loaded from JSON files
struct SpiralConfig: Codable, Identifiable {
    let id = UUID()
    let name: String
    let description: String?
    let base: String?  // Parent config for inheritance
    let properties: Properties
    let scripts: [String: [ScriptElement]]

    /// Configuration properties controlling behavior and appearance
    struct Properties: Codable {
        // Display properties
        let size: [Int]
        let fullscreen: Bool
        let brokenFonts: Bool

        // Spiral properties
        let color: [Int]  // RGB values
        let alpha: Int  // 0-255
        let spiralImage: String
        let spiralRange: Int  // Degrees before repeating
        let spiralStep: Int   // Degrees per frame
        let scale: Int        // Generation scale factor

        // Text properties
        let textColor: [Int]
        let textAlpha: Int

        // Timing properties
        let frameRate: Int
        let timeScale: Int
        let frequencies: Frequencies
        let minimumDelay: Int
        let maximumDelay: Int

        // Content properties
        let music: String?
        let imageDir: String
        let imageAlpha: Int
        let shuffleImages: Bool

        // Voice properties (speaker.py only)
        let voice: String?
        let subliminalAlpha: Int?
        let subliminalColor: [Int]?
        let subliminalScatter: Int?
        let subliminalMoveProbability: Int?
        let subliminalDisplayProbability: Int?
        let subliminalChangeProbability: Int?

        struct Frequencies: Codable {
            let spiral: Int
            let images: Int
            let words: Int
        }

        // Custom decoder with default values for missing fields
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Decode with defaults
            size = try container.decodeIfPresent([Int].self, forKey: .size) ?? [1280, 800]
            fullscreen = try container.decodeIfPresent(Bool.self, forKey: .fullscreen) ?? false
            brokenFonts = try container.decodeIfPresent(Bool.self, forKey: .brokenFonts) ?? false

            color = try container.decodeIfPresent([Int].self, forKey: .color) ?? [255, 255, 255]
            alpha = try container.decodeIfPresent(Int.self, forKey: .alpha) ?? 127
            spiralImage = try container.decodeIfPresent(String.self, forKey: .spiralImage) ?? ""
            spiralRange = try container.decodeIfPresent(Int.self, forKey: .spiralRange) ?? 90
            spiralStep = try container.decodeIfPresent(Int.self, forKey: .spiralStep) ?? 1
            scale = try container.decodeIfPresent(Int.self, forKey: .scale) ?? 10

            textColor = try container.decodeIfPresent([Int].self, forKey: .textColor) ?? [0, 51, 204]
            textAlpha = try container.decodeIfPresent(Int.self, forKey: .textAlpha) ?? 254

            frameRate = try container.decodeIfPresent(Int.self, forKey: .frameRate) ?? 60
            timeScale = try container.decodeIfPresent(Int.self, forKey: .timeScale) ?? 2
            frequencies = try container.decodeIfPresent(Frequencies.self, forKey: .frequencies) ?? Frequencies(spiral: 1, images: 50, words: 40)
            minimumDelay = try container.decodeIfPresent(Int.self, forKey: .minimumDelay) ?? 0
            maximumDelay = try container.decodeIfPresent(Int.self, forKey: .maximumDelay) ?? 0

            music = try container.decodeIfPresent(String.self, forKey: .music)
            imageDir = try container.decodeIfPresent(String.self, forKey: .imageDir) ?? "images/"
            imageAlpha = try container.decodeIfPresent(Int.self, forKey: .imageAlpha) ?? 255
            shuffleImages = try container.decodeIfPresent(Bool.self, forKey: .shuffleImages) ?? true

            voice = try container.decodeIfPresent(String.self, forKey: .voice)
            subliminalAlpha = try container.decodeIfPresent(Int.self, forKey: .subliminalAlpha)
            subliminalColor = try container.decodeIfPresent([Int].self, forKey: .subliminalColor)
            subliminalScatter = try container.decodeIfPresent(Int.self, forKey: .subliminalScatter)
            subliminalMoveProbability = try container.decodeIfPresent(Int.self, forKey: .subliminalMoveProbability)
            subliminalDisplayProbability = try container.decodeIfPresent(Int.self, forKey: .subliminalDisplayProbability)
            subliminalChangeProbability = try container.decodeIfPresent(Int.self, forKey: .subliminalChangeProbability)
        }

        enum CodingKeys: String, CodingKey {
            case size, fullscreen, color, alpha, music, scale
            case brokenFonts = "broken_fonts"
            case textColor = "text_color"
            case textAlpha = "text_alpha"
            case frameRate = "frame_rate"
            case timeScale = "time_scale"
            case frequencies
            case minimumDelay = "minimum_delay"
            case maximumDelay = "maximum_delay"
            case imageDir = "image_dir"
            case imageAlpha = "image_alpha"
            case shuffleImages = "shuffle_images"
            case spiralImage = "spiral_image"
            case spiralRange = "spiral_range"
            case spiralStep = "spiral_step"
            case voice
            case subliminalAlpha = "subliminal_alpha"
            case subliminalColor = "subliminal_color"
            case subliminalScatter = "subliminal_scatter"
            case subliminalMoveProbability = "subliminal_moveprobability"
            case subliminalDisplayProbability = "subliminal_displayprobability"
            case subliminalChangeProbability = "subliminal_changeprobability"
        }
    }

    /// Script elements: words, commands, or references
    enum ScriptElement: Codable {
        case word(String)
        case command(CommandData)
        case reference(String)

        struct CommandData: Codable {
            let cmd: String
            let args: [AnyCodable]?
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            // Try to decode as string first (most common: plain words)
            if let word = try? container.decode(String.self) {
                self = .word(word)
                return
            }

            // Try to decode as command object
            if let commandDict = try? container.decode([String: AnyCodable].self) {
                if let cmdName = commandDict["cmd"]?.value as? String {
                    let args = (commandDict["args"]?.value as? [Any])?.map { AnyCodable($0) }
                    self = .command(CommandData(cmd: cmdName, args: args))
                    return
                }

                if let refString = commandDict["ref"]?.value as? String {
                    self = .reference(refString)
                    return
                }
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode ScriptElement"
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .word(let string):
                try container.encode(string)
            case .command(let data):
                try container.encode(data)
            case .reference(let ref):
                try container.encode(["ref": ref])
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, description, base, properties, scripts
    }
}

/// Type-erased wrapper for heterogeneous codable values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode AnyCodable"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Cannot encode AnyCodable value"
                )
            )
        }
    }
}
