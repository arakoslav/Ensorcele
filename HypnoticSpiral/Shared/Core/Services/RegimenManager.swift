//
//  RegimenManager.swift
//  HypnoticSpiral
//
//  Loads and manages training regimens, determines which config to run
//

import Foundation

/// Manages training regimens and determines which configs to run
class RegimenManager {
    static let shared = RegimenManager()

    private var regimens: [TrainingRegimen] = []
    private let configLoader = ConfigLoader()

    private init() {
        loadRegimens()
    }

    // MARK: - Loading

    /// Load all regimens from the TrainingRegimens.json file
    func loadRegimens() {
        guard let url = iCloudResourceManager.shared.getConfigURL(named: "TrainingRegimens.json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(TrainingRegimensData.self, from: data) else {
            print("No TrainingRegimens.json found or failed to decode")
            regimens = []
            return
        }
        regimens = decoded.regimens
    }

    /// Get all loaded regimens
    func getAllRegimens() -> [TrainingRegimen] {
        return regimens
    }

    /// Reload regimens from disk
    func reload() {
        loadRegimens()
    }

    // MARK: - Config Selection

    /// Determine which config to run for a masked regimen
    func selectConfig(for regimen: TrainingRegimen) -> String? {
        switch regimen.type {
        case .masked:
            return selectMaskedConfig(rules: regimen.rules ?? [])
        case .random:
            return selectRandomConfig(pool: regimen.randomPool ?? [])
        case .progressive:
            // Progressive regimens show multiple configs, not handled here
            return nil
        }
    }

    /// Select config based on rules (first matching rule wins)
    private func selectMaskedConfig(rules: [SelectionRule]) -> String? {
        for rule in rules {
            // If no condition, this is the fallback/default
            guard let condition = rule.condition else {
                return rule.config
            }

            // Evaluate the condition
            if UsageTracker.shared.evaluate(condition) {
                return rule.config
            }
        }
        return nil
    }

    /// Select a random config from the pool
    private func selectRandomConfig(pool: [String]) -> String? {
        return pool.randomElement()
    }

    // MARK: - Progressive Regimens

    /// Get the current unlocked stage for a progressive regimen
    func currentStage(for regimen: TrainingRegimen) -> Int {
        guard regimen.type == .progressive,
              let stages = regimen.stages else {
            return 0
        }

        var currentStage = 0

        for (index, stage) in stages.enumerated() {
            // Check if this stage's unlock condition is met
            guard let unlockCondition = stage.unlockAfter else {
                // No unlock condition = final stage, stay here
                break
            }

            let uses = UsageTracker.shared.totalUsageCount(config: unlockCondition.config)
            if uses >= unlockCondition.uses {
                // Condition met, can advance to next stage
                currentStage = index + 1
            } else {
                // Condition not met, stop here
                break
            }
        }

        return min(currentStage, stages.count - 1)
    }

    /// Get all unlocked configs for a progressive regimen (includes all prior stages)
    func unlockedConfigs(for regimen: TrainingRegimen) -> [String] {
        guard regimen.type == .progressive,
              let stages = regimen.stages else {
            return []
        }

        let maxStage = currentStage(for: regimen)
        var configs: [String] = []

        for index in 0...maxStage {
            configs.append(contentsOf: stages[index].configs)
        }

        return configs
    }

    /// Get configs that are still locked for a progressive regimen
    func lockedConfigs(for regimen: TrainingRegimen) -> [(config: String, requirement: String)] {
        guard regimen.type == .progressive,
              let stages = regimen.stages else {
            return []
        }

        let maxStage = currentStage(for: regimen)
        var locked: [(config: String, requirement: String)] = []

        // Get the unlock condition for the next locked stage
        if maxStage < stages.count - 1,
           let unlockCondition = stages[maxStage].unlockAfter {
            let currentUses = UsageTracker.shared.totalUsageCount(config: unlockCondition.config)
            let remaining = unlockCondition.uses - currentUses
            let requirement = "Use \(unlockCondition.config) \(remaining) more time\(remaining == 1 ? "" : "s")"

            // All configs in stages after current are locked
            for index in (maxStage + 1)..<stages.count {
                for config in stages[index].configs {
                    locked.append((config: config, requirement: requirement))
                }
            }
        }

        return locked
    }

    // MARK: - Load Actual Config

    /// Load a SpiralConfig by name
    func loadConfig(named name: String) -> SpiralConfig? {
        return try? configLoader.loadConfig(named: name)
    }
}
