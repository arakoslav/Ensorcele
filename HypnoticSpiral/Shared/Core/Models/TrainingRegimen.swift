//
//  TrainingRegimen.swift
//  HypnoticSpiral
//
//  Training regimen model for automated config selection
//  Supports masked (single entry dispatching), progressive (unlocking), and random selection
//

import Foundation

/// A training regimen that determines which config to run based on rules
struct TrainingRegimen: Codable, Identifiable {
    var id: String { name }
    let name: String
    let description: String?
    let type: RegimenType

    // For masked type - rules evaluated in order, first match wins
    let rules: [SelectionRule]?

    // For progressive type - stages that unlock based on usage
    let stages: [ProgressiveStage]?

    // For random type - pool of configs to pick from
    let randomPool: [String]?

    enum RegimenType: String, Codable {
        case masked      // Single entry, secretly dispatches to computed config
        case progressive // Shows configs as they unlock
        case random      // Picks randomly from pool
    }

    enum CodingKeys: String, CodingKey {
        case name, description, type, rules, stages
        case randomPool = "random_pool"
    }
}

/// A rule for selecting a config in a masked regimen
struct SelectionRule: Codable {
    let config: String
    let condition: RuleCondition?  // nil = default/fallback

    enum CodingKeys: String, CodingKey {
        case config, condition
    }
}

/// Conditions for rule evaluation
enum RuleCondition: Codable {
    case usageLessThan(config: String, days: Int, count: Int)
    case usageAtLeast(config: String, days: Int, count: Int)
    case totalUsageLessThan(config: String, count: Int)
    case totalUsageAtLeast(config: String, count: Int)

    enum CodingKeys: String, CodingKey {
        case type, config, days, count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let config = try container.decode(String.self, forKey: .config)
        let count = try container.decode(Int.self, forKey: .count)

        switch type {
        case "usage_less_than":
            let days = try container.decode(Int.self, forKey: .days)
            self = .usageLessThan(config: config, days: days, count: count)
        case "usage_at_least":
            let days = try container.decode(Int.self, forKey: .days)
            self = .usageAtLeast(config: config, days: days, count: count)
        case "total_usage_less_than":
            self = .totalUsageLessThan(config: config, count: count)
        case "total_usage_at_least":
            self = .totalUsageAtLeast(config: config, count: count)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown condition type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .usageLessThan(let config, let days, let count):
            try container.encode("usage_less_than", forKey: .type)
            try container.encode(config, forKey: .config)
            try container.encode(days, forKey: .days)
            try container.encode(count, forKey: .count)
        case .usageAtLeast(let config, let days, let count):
            try container.encode("usage_at_least", forKey: .type)
            try container.encode(config, forKey: .config)
            try container.encode(days, forKey: .days)
            try container.encode(count, forKey: .count)
        case .totalUsageLessThan(let config, let count):
            try container.encode("total_usage_less_than", forKey: .type)
            try container.encode(config, forKey: .config)
            try container.encode(count, forKey: .count)
        case .totalUsageAtLeast(let config, let count):
            try container.encode("total_usage_at_least", forKey: .type)
            try container.encode(config, forKey: .config)
            try container.encode(count, forKey: .count)
        }
    }
}

/// A stage in a progressive regimen
struct ProgressiveStage: Codable {
    let configs: [String]           // Configs available at this stage
    let unlockAfter: UnlockCondition?  // Condition to unlock next stage (nil = final stage)

    enum CodingKeys: String, CodingKey {
        case configs
        case unlockAfter = "unlock_after"
    }
}

/// Condition to unlock the next progressive stage
struct UnlockCondition: Codable {
    let config: String  // Which config must be used
    let uses: Int       // How many times
}

/// Container for regimens JSON file
struct TrainingRegimensData: Codable {
    let regimens: [TrainingRegimen]
}
