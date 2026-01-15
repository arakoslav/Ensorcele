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
    var isLoading: Bool = false
    var errorMessage: String?

    private let configLoader = ConfigLoader()

    init() {
        loadConfigs()
    }

    func loadConfigs() {
        isLoading = true
        errorMessage = nil

        let results = configLoader.loadAllConfigsWithURLs()
        configs = results.map { $0.config }
        configURLs = Dictionary(uniqueKeysWithValues: results.map { ($0.config.id, $0.url) })
        categorizedConfigs = categorizeConfigs(configs)
        isLoading = false
    }

    /// Get the source URL for a config
    func sourceURL(for config: SpiralConfig) -> URL? {
        return configURLs[config.id]
    }

    func reload() {
        loadConfigs()
    }

    private func categorizeConfigs(_ allConfigs: [SpiralConfig]) -> [CategorizedConfigs] {
        // Load category definitions from iCloud/local storage (same location as configs)
        guard let categoriesURL = iCloudResourceManager.shared.getConfigURL(named: "ConfigCategories.json"),
              let categoriesData = try? Data(contentsOf: categoriesURL),
              let categoryData = try? JSONDecoder().decode(ConfigCategoryData.self, from: categoriesData) else {
            // If categories file doesn't exist, return all configs in one category
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

        // Add uncategorized configs
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
}
