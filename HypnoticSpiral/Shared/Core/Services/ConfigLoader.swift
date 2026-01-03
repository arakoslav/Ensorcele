//
//  ConfigLoader.swift
//  HypnoticSpiral
//
//  Loads JSON configuration files with inheritance resolution
//  Ports Python config_loader.py functionality to Swift
//

import Foundation

/// Loads and manages JSON configuration files with inheritance
class ConfigLoader {
    private var configCache: [String: SpiralConfig] = [:]
    private var jsonCache: [String: Data] = [:]

    /// Load all available configurations from iCloud
    func loadAllConfigs() -> [SpiralConfig] {
        let urls = iCloudResourceManager.shared.listConfigs()

        if urls.isEmpty {
            print("Warning: No config files found in iCloud")
            return []
        }

        var configs: [SpiralConfig] = []
        for url in urls {
            do {
                let config = try loadConfig(from: url)
                configs.append(config)
            } catch {
                print("Warning: Failed to load config from \(url.lastPathComponent): \(error)")
            }
        }

        return configs.sorted { $0.name < $1.name }
    }

    /// Load a configuration by name (without .json extension)
    func loadConfig(named name: String) throws -> SpiralConfig {
        // Check cache first
        if let cached = configCache[name] {
            return cached
        }

        // Find the config file in iCloud
        let fileName = name.hasSuffix(".json") ? name : "\(name).json"
        guard let url = iCloudResourceManager.shared.getConfigURL(named: fileName) else {
            throw ConfigError.configNotFound(name)
        }

        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigError.configNotFound(name)
        }

        return try loadConfig(from: url)
    }

    /// Load a configuration from a URL
    func loadConfig(from url: URL) throws -> SpiralConfig {
        let configName = url.deletingPathExtension().lastPathComponent

        // Check cache
        if let cached = configCache[configName] {
            return cached
        }

        // Load JSON as dictionary first
        let data = try Data(contentsOf: url)
        guard var jsonDict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError.configNotFound(configName)
        }

        // Resolve inheritance by merging with base JSON
        if let baseName = jsonDict["base"] as? String {
            let baseConfig = try loadConfig(named: baseName)

            // Merge properties from base
            if let baseProps = try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(baseConfig.properties)
            ) as? [String: Any] {
                var childProps = jsonDict["properties"] as? [String: Any] ?? [:]

                // Merge: parent properties + child overrides
                for (key, value) in baseProps {
                    if childProps[key] == nil {
                        childProps[key] = value
                    }
                }
                jsonDict["properties"] = childProps
            }

            // Merge scripts from base
            if let baseScripts = try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(baseConfig.scripts)
            ) as? [String: Any] {
                var childScripts = jsonDict["scripts"] as? [String: Any] ?? [:]

                // Merge: parent scripts + child overrides
                for (key, value) in baseScripts {
                    if childScripts[key] == nil {
                        childScripts[key] = value
                    }
                }
                jsonDict["scripts"] = childScripts
            }
        }

        // Now decode the merged JSON
        let mergedData = try JSONSerialization.data(withJSONObject: jsonDict)
        let config = try JSONDecoder().decode(SpiralConfig.self, from: mergedData)

        // Cache and return
        configCache[configName] = config
        return config
    }

    /// Resolve a script by name, handling self.X and parent.X references
    func resolveScript(
        named scriptName: String,
        in config: SpiralConfig
    ) throws -> [String] {
        guard let elements = config.scripts[scriptName] else {
            throw ConfigError.scriptNotFound(scriptName, config.name)
        }

        return try elements.flatMap { element -> [String] in
            switch element {
            case .word(let word):
                return [word]

            case .command(let data):
                return [formatCommand(data)]

            case .reference(let ref):
                return try resolveReference(ref, in: config)
            }
        }
    }

    /// Resolve a reference like "self.body" or "parent.body"
    private func resolveReference(_ ref: String, in config: SpiralConfig) throws -> [String] {
        if ref.hasPrefix("self.") {
            // Reference to script in same config
            let scriptName = String(ref.dropFirst(5))
            return try resolveScript(named: scriptName, in: config)

        } else if ref.hasPrefix("parent.") {
            // Reference to script in parent config
            guard let baseName = config.base else {
                throw ConfigError.noParentConfig(config.name)
            }

            let parentConfig = try loadConfig(named: baseName)
            let scriptName = String(ref.dropFirst(7))
            return try resolveScript(named: scriptName, in: parentConfig)

        } else {
            // Unknown reference format
            throw ConfigError.invalidReference(ref)
        }
    }

    /// Format a command as a string for execution
    private func formatCommand(_ data: SpiralConfig.ScriptElement.CommandData) -> String {
        if let args = data.args, !args.isEmpty {
            let argsString = args.map { formatArg($0) }.joined(separator: ", ")
            return "!\(data.cmd)(\(argsString))"
        } else {
            return "!\(data.cmd)()"
        }
    }

    /// Format an argument for command string
    private func formatArg(_ arg: AnyCodable) -> String {
        switch arg.value {
        case let string as String:
            return "'\(string)'"
        case let int as Int:
            return "\(int)"
        case let double as Double:
            return "\(double)"
        case let bool as Bool:
            return "\(bool)"
        case let array as [Any]:
            let items = array.map { formatArg(AnyCodable($0)) }.joined(separator: ", ")
            return "[\(items)]"
        default:
            return "\(arg.value)"
        }
    }
}

// MARK: - Config Errors

enum ConfigError: Error, LocalizedError {
    case configNotFound(String)
    case scriptNotFound(String, String)  // script name, config name
    case noParentConfig(String)
    case invalidReference(String)

    var errorDescription: String? {
        switch self {
        case .configNotFound(let name):
            return "Configuration '\(name)' not found"
        case .scriptNotFound(let script, let config):
            return "Script '\(script)' not found in config '\(config)'"
        case .noParentConfig(let config):
            return "Config '\(config)' has no parent but references parent scripts"
        case .invalidReference(let ref):
            return "Invalid script reference: '\(ref)'"
        }
    }
}



