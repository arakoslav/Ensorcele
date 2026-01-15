//
//  UsageTracker.swift
//  HypnoticSpiral
//
//  Tracks config usage history for training regimen decisions
//

import Foundation

/// Record of a single config usage
struct UsageRecord: Codable {
    let configName: String
    let regimenName: String?  // If launched via a regimen
    let timestamp: Date
}

/// Tracks config usage for regimen rule evaluation
class UsageTracker {
    static let shared = UsageTracker()

    private var records: [UsageRecord] = []
    private let storageKey = "HypnoticSpiral.UsageHistory"

    private init() {
        loadRecords()
    }

    // MARK: - Recording Usage

    /// Record that a config was used
    func recordUsage(config: String, regimen: String? = nil) {
        let record = UsageRecord(
            configName: config,
            regimenName: regimen,
            timestamp: Date()
        )
        records.append(record)
        saveRecords()
    }

    // MARK: - Querying Usage

    /// Count how many times a config was used within the last N days
    func usageCount(config: String, withinDays days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return records.filter { record in
            record.configName == config && record.timestamp >= cutoff
        }.count
    }

    /// Count total uses of a config (all time)
    func totalUsageCount(config: String) -> Int {
        return records.filter { $0.configName == config }.count
    }

    /// Get all usage records for a config
    func usageHistory(config: String) -> [UsageRecord] {
        return records.filter { $0.configName == config }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Get recent usage records
    func recentUsage(limit: Int = 20) -> [UsageRecord] {
        return Array(records.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    // MARK: - Rule Evaluation

    /// Evaluate a rule condition
    func evaluate(_ condition: RuleCondition) -> Bool {
        switch condition {
        case .usageLessThan(let config, let days, let count):
            return usageCount(config: config, withinDays: days) < count
        case .usageAtLeast(let config, let days, let count):
            return usageCount(config: config, withinDays: days) >= count
        case .totalUsageLessThan(let config, let count):
            return totalUsageCount(config: config) < count
        case .totalUsageAtLeast(let config, let count):
            return totalUsageCount(config: config) >= count
        }
    }

    // MARK: - Persistence

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([UsageRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded
    }

    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    /// Clear all usage history (for testing/reset)
    func clearAllHistory() {
        records = []
        saveRecords()
    }

    /// Prune old records (older than N days) to prevent unbounded growth
    func pruneOldRecords(olderThanDays days: Int = 365) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        records = records.filter { $0.timestamp >= cutoff }
        saveRecords()
    }
}
