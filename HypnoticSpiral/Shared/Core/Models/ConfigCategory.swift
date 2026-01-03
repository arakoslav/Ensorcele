//
//  ConfigCategory.swift
//  HypnoticSpiral
//
//  Model for organizing configs into categories
//

import Foundation

struct ConfigCategory: Codable, Identifiable {
    var id: String { name }
    let name: String
    let description: String
    let configs: [String]  // Config names
}

struct ConfigCategoryData: Codable {
    let categories: [ConfigCategory]
}

struct CategorizedConfigs: Identifiable {
    var id: String { category.name }
    let category: ConfigCategory
    let configs: [SpiralConfig]
}
