//
//  HypnoticSpiralApp.swift
//  HypnoticSpiral
//
//  Main entry point for the hypnotic spiral universal app
//

import SwiftUI

@main
struct HypnoticSpiralApp: App {
    @State private var configListViewModel = ConfigListViewModel()
    @State private var isInitializing = true

    init() {
        // Initialize iCloud resources on app launch
        Task {
            do {
                try await iCloudResourceManager.shared.initializeResources()
                print("iCloud resources initialized successfully")
            } catch {
                print("Error initializing iCloud resources: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ConfigSelectionView()
                .environment(configListViewModel)
        }
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {}  // Remove New Window
        }
        #endif
    }
}
