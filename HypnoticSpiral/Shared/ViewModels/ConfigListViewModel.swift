//
//  ConfigListViewModel.swift
//  HypnoticSpiral
//
//  ViewModel for configuration selection
//

import Foundation
import SwiftUI

@MainActor
@Observable
class ConfigListViewModel {
    var configs: [SpiralConfig] = []
    var categorizedConfigs: [CategorizedConfigs] = []
    var configURLs: [UUID: URL] = [:]  // Map config ID to source URL
    var regimens: [TrainingRegimen] = []
    var isLoading: Bool = false
    var errorMessage: String?

    private let configLoader = ConfigLoader()

    init() {
        loadConfigs()
    }

    func loadConfigs() {
        isLoading = true
        errorMessage = nil

        let results = configLoader.loadAllConfigsWithInfo()
        configs = results.map { $0.config }
        configURLs = Dictionary(uniqueKeysWithValues: results.map { ($0.config.id, $0.url) })
        categorizedConfigs = categorizeConfigs(results)

        // Load training regimens
        RegimenManager.shared.reload()
        regimens = RegimenManager.shared.getAllRegimens()

        isLoading = false
    }

    /// Get the source URL for a config
    func sourceURL(for config: SpiralConfig) -> URL? {
        return configURLs[config.id]
    }

    func reload() {
        loadConfigs()
    }

    private func categorizeConfigs(_ loadedConfigs: [ConfigLoader.LoadedConfigInfo]) -> [CategorizedConfigs] {
        // Group configs by subdirectory
        var configsBySubdir: [String?: [ConfigLoader.LoadedConfigInfo]] = [:]
        for info in loadedConfigs {
            configsBySubdir[info.subdirectory, default: []].append(info)
        }

        var result: [CategorizedConfigs] = []
        var usedConfigNames = Set<String>()

        // First, process root-level configs using main ConfigCategories.json
        if let rootConfigs = configsBySubdir[nil] {
            let rootCategorized = categorizeRootConfigs(rootConfigs.map { $0.config })
            result.append(contentsOf: rootCategorized)
            usedConfigNames.formUnion(rootConfigs.map { $0.config.name })
        }

        // Then, process each subdirectory
        let subdirs = configsBySubdir.keys.compactMap { $0 }.sorted()
        for subdir in subdirs {
            guard let subdirConfigs = configsBySubdir[subdir] else { continue }

            let subdirCategorized = categorizeSubdirectory(
                name: subdir,
                configs: subdirConfigs.map { $0.config }
            )
            result.append(contentsOf: subdirCategorized)
            usedConfigNames.formUnion(subdirConfigs.map { $0.config.name })
        }

        return result
    }

    /// Categorize root-level configs using main ConfigCategories.json
    private func categorizeRootConfigs(_ allConfigs: [SpiralConfig]) -> [CategorizedConfigs] {
        // Load category definitions from iCloud/local storage (same location as configs)
        guard let categoriesURL = iCloudResourceManager.shared.getConfigURL(named: "ConfigCategories.json"),
              let categoriesData = try? Data(contentsOf: categoriesURL),
              let categoryData = try? JSONDecoder().decode(ConfigCategoryData.self, from: categoriesData) else {
            // If categories file doesn't exist, return all configs in one category
            if allConfigs.isEmpty { return [] }
            let defaultCategory = ConfigCategory(
                name: "All Programs",
                description: "All available programs",
                configs: allConfigs.map { $0.name }
            )
            return [CategorizedConfigs(category: defaultCategory, configs: allConfigs)]
        }

        // Create a dictionary for fast config lookup by name
        let configsByName = Dictionary(uniqueKeysWithValues: allConfigs.map { ($0.name, $0) })

        var result: [CategorizedConfigs] = []
        var usedConfigNames = Set<String>()

        // Process each category
        for category in categoryData.categories {
            let categoryConfigs = category.configs.compactMap { configName -> SpiralConfig? in
                if let config = configsByName[configName] {
                    usedConfigNames.insert(configName)
                    return config
                }
                return nil
            }

            if !categoryConfigs.isEmpty {
                result.append(CategorizedConfigs(category: category, configs: categoryConfigs))
            }
        }

        // Add uncategorized root configs
        let uncategorizedConfigs = allConfigs.filter { !usedConfigNames.contains($0.name) }
        if !uncategorizedConfigs.isEmpty {
            let otherCategory = ConfigCategory(
                name: "Other Programs",
                description: "Additional programs",
                configs: uncategorizedConfigs.map { $0.name }
            )
            result.append(CategorizedConfigs(category: otherCategory, configs: uncategorizedConfigs))
        }

        return result
    }

    /// Categorize configs from a subdirectory
    /// Uses ConfigCategories.json from the subdirectory if present, otherwise creates category from directory name
    private func categorizeSubdirectory(name subdirName: String, configs: [SpiralConfig]) -> [CategorizedConfigs] {
        guard !configs.isEmpty else { return [] }

        // Try to load ConfigCategories.json from subdirectory
        if let categoriesURL = iCloudResourceManager.shared.getSubdirectoryCategoriesURL(subdirectory: subdirName),
           let categoriesData = try? Data(contentsOf: categoriesURL),
           let categoryData = try? JSONDecoder().decode(ConfigCategoryData.self, from: categoriesData) {
            // Use subdirectory's category definitions
            let configsByName = Dictionary(uniqueKeysWithValues: configs.map { ($0.name, $0) })

            var result: [CategorizedConfigs] = []
            var usedConfigNames = Set<String>()

            for category in categoryData.categories {
                let categoryConfigs = category.configs.compactMap { configName -> SpiralConfig? in
                    if let config = configsByName[configName] {
                        usedConfigNames.insert(configName)
                        return config
                    }
                    return nil
                }

                if !categoryConfigs.isEmpty {
                    result.append(CategorizedConfigs(category: category, configs: categoryConfigs))
                }
            }

            // Add uncategorized configs from this subdirectory
            let uncategorizedConfigs = configs.filter { !usedConfigNames.contains($0.name) }
            if !uncategorizedConfigs.isEmpty {
                let otherCategory = ConfigCategory(
                    name: "\(subdirName) - Other",
                    description: "Additional programs from \(subdirName)",
                    configs: uncategorizedConfigs.map { $0.name }
                )
                result.append(CategorizedConfigs(category: otherCategory, configs: uncategorizedConfigs))
            }

            return result
        }

        // No ConfigCategories.json - create a category from the directory name
        let category = ConfigCategory(
            name: subdirName,
            description: "Programs from \(subdirName)",
            configs: configs.map { $0.name }
        )
        return [CategorizedConfigs(category: category, configs: configs)]
    }

    // MARK: - Training Regimens

    /// Get the config to launch for a masked or random regimen
    func configForRegimen(_ regimen: TrainingRegimen) -> SpiralConfig? {
        guard let configName = RegimenManager.shared.selectConfig(for: regimen) else {
            return nil
        }
        return RegimenManager.shared.loadConfig(named: configName)
    }

    /// Get unlocked configs for a progressive regimen
    func unlockedConfigs(for regimen: TrainingRegimen) -> [SpiralConfig] {
        let names = RegimenManager.shared.unlockedConfigs(for: regimen)
        return names.compactMap { RegimenManager.shared.loadConfig(named: $0) }
    }

    /// Get locked config info for a progressive regimen
    func lockedConfigInfo(for regimen: TrainingRegimen) -> [(name: String, requirement: String)] {
        return RegimenManager.shared.lockedConfigs(for: regimen).map { ($0.config, $0.requirement) }
    }

    /// Record that a config was used (call when launching)
    func recordUsage(config: SpiralConfig, regimen: TrainingRegimen? = nil) {
        UsageTracker.shared.recordUsage(config: config.name, regimen: regimen?.name)
    }
}
