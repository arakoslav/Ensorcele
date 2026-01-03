//
//  ConfigSelectionView.swift
//  HypnoticSpiral
//
//  Configuration selection screen with modern SwiftUI list
//

import SwiftUI

struct ConfigSelectionView: View {
    @Environment(ConfigListViewModel.self) var viewModel
    @State private var selectedConfig: SpiralConfig?
    @State private var showingFullscreen = false
    @State private var showingVariables = false

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading {
                    ProgressView("Loading configurations...")
                } else if viewModel.configs.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No configurations found")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Add .json config files to the Configs folder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Reload") {
                            viewModel.reload()
                        }
                    }
                } else {
                    List {
                        ForEach(viewModel.categorizedConfigs) { categorized in
                            Section {
                                ForEach(categorized.configs) { config in
                                    #if os(macOS)
                                    // On macOS, use NavigationLink for all configs
                                    NavigationLink {
                                        SpiralView(config: config)
                                    } label: {
                                        ConfigRow(config: config)
                                    }
                                    #else
                                    // On iOS, use fullScreenCover for fullscreen configs
                                    if config.properties.fullscreen {
                                        Button {
                                            selectedConfig = config
                                            showingFullscreen = true
                                        } label: {
                                            ConfigRow(config: config)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        NavigationLink {
                                            SpiralView(config: config)
                                        } label: {
                                            ConfigRow(config: config)
                                        }
                                    }
                                    #endif
                                }
                            } header: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(categorized.category.name)
                                        .font(.headline)
                                    Text(categorized.category.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .textCase(nil) // Prevent automatic uppercase
                            }
                        }
                    }
                }
            }
            .navigationTitle("Hypnotic Spiral")
            #if os(macOS)
            .navigationSubtitle("\(viewModel.configs.count) configurations")
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingVariables = true }) {
                        Label("Variables", systemImage: "text.word.spacing")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: { viewModel.reload() }) {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showingVariables) {
                NavigationStack {
                    VariablesConfigView()
                }
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 300)
                #endif
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showingFullscreen) {
            if let config = selectedConfig {
                SpiralView(config: config)
                    .statusBarHidden()
            }
        }
        #endif
    }
}

struct ConfigRow: View {
    let config: SpiralConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(config.name)
                .font(.headline)

            if let description = config.description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                if config.base != nil {
                    Label("Inherits from \(config.base!)", systemImage: "arrow.up.doc")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }

                if config.properties.fullscreen {
                    Label("Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2)
                        .foregroundColor(.purple)
                }

                if config.properties.voice != nil {
                    Label("Voice", systemImage: "speaker.wave.2")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    @Previewable @State var viewModel = ConfigListViewModel()
    ConfigSelectionView()
        .environment(viewModel)
}
