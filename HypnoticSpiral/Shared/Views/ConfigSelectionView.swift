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
    @State private var editingConfig: SpiralConfig?
    @State private var editingURL: URL?
    @State private var showingResumeDialog = false
    @State private var savedStateToResume: SavedSessionState?
    @State private var resumeConfig: SpiralConfig?
    @State private var navigateToConfig: SpiralConfig?
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var launchingFromRegimen: TrainingRegimen?

    /// Filter regimens based on search text
    private var filteredRegimens: [TrainingRegimen] {
        guard !searchText.isEmpty else {
            return viewModel.regimens
        }

        let query = searchText.lowercased()
        return viewModel.regimens.filter { regimen in
            regimen.name.lowercased().contains(query) ||
            (regimen.description?.lowercased().contains(query) ?? false)
        }
    }

    /// Filter categorized configs based on search text
    private var filteredCategorizedConfigs: [CategorizedConfigs] {
        guard !searchText.isEmpty else {
            return viewModel.categorizedConfigs
        }

        let query = searchText.lowercased()

        return viewModel.categorizedConfigs.compactMap { categorized in
            let matchingConfigs = categorized.configs.filter { config in
                config.name.lowercased().contains(query) ||
                (config.description?.lowercased().contains(query) ?? false)
            }

            guard !matchingConfigs.isEmpty else { return nil }

            return CategorizedConfigs(
                category: categorized.category,
                configs: matchingConfigs
            )
        }
    }

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Hypnotic Spiral")
                #if os(macOS)
                .navigationSubtitle("\(viewModel.configs.count) configurations")
                #endif
                .toolbar { toolbarContent }
                .searchable(text: $searchText, prompt: "Filter configs")
                .searchFocused($isSearchFocused)
                .onAppear {
                    // Focus search on initial appear
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isSearchFocused = true
                    }
                }
                .onChange(of: navigateToConfig) { oldValue, newValue in
                    // When returning from a session (navigateToConfig becomes nil), refocus search
                    if oldValue != nil && newValue == nil {
                        searchText = ""
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isSearchFocused = true
                        }
                    }
                }
                .sheet(isPresented: $showingVariables) { variablesSheet }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showingFullscreen) { fullscreenContent }
        .onChange(of: showingFullscreen) { oldValue, newValue in
            // When returning from fullscreen session on iOS, refocus search
            if oldValue == true && newValue == false {
                searchText = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isSearchFocused = true
                }
            }
        }
        #endif
        .sheet(item: $editingConfig) { config in
            editorSheet(for: config)
        }
        .alert("Resume Session?", isPresented: $showingResumeDialog) {
            resumeDialogButtons
        } message: {
            resumeDialogMessage
        }
    }

    // MARK: - View Components

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView("Loading configurations...")
            } else if viewModel.configs.isEmpty {
                emptyStateView
            } else {
                configListView
            }
        }
    }

    private var emptyStateView: some View {
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
    }

    private var configListView: some View {
        List {
            // Training Programs section (masked and random regimens)
            let maskedRegimens = filteredRegimens.filter { $0.type == .masked || $0.type == .random }
            if !maskedRegimens.isEmpty {
                Section {
                    ForEach(maskedRegimens) { regimen in
                        regimenRow(regimen)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Training Programs")
                            .font(.headline)
                        Text("Automated program selection")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                }
            }

            // Progressive regimens (show as sections with unlocked/locked configs)
            ForEach(filteredRegimens.filter { $0.type == .progressive }) { regimen in
                progressiveRegimenSection(regimen)
            }

            // Regular config categories
            ForEach(filteredCategorizedConfigs) { categorized in
                Section {
                    ForEach(categorized.configs) { config in
                        configRowWithEditButton(config: config)
                    }
                } header: {
                    sectionHeader(for: categorized)
                }
            }
        }
        .navigationDestination(item: $navigateToConfig) { config in
            SpiralView(config: config, savedState: savedStateToResume)
        }
    }

    // MARK: - Regimen Views

    private func regimenRow(_ regimen: TrainingRegimen) -> some View {
        Button {
            selectRegimen(regimen)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(regimen.name)
                        .font(.headline)
                    Image(systemName: regimen.type == .random ? "dice" : "wand.and.stars")
                        .font(.caption)
                        .foregroundColor(.purple)
                }

                if let description = regimen.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Label(
                    regimen.type == .random ? "Random selection" : "Automated selection",
                    systemImage: regimen.type == .random ? "shuffle" : "gearshape.2"
                )
                .font(.caption2)
                .foregroundColor(.purple)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func progressiveRegimenSection(_ regimen: TrainingRegimen) -> some View {
        let unlocked = viewModel.unlockedConfigs(for: regimen)
        let locked = viewModel.lockedConfigInfo(for: regimen)

        Section {
            // Unlocked configs
            ForEach(unlocked) { config in
                Button {
                    launchingFromRegimen = regimen
                    selectConfig(config)
                } label: {
                    ConfigRow(config: config, hasSavedSession: SessionStateManager.shared.hasSavedSession(for: config.name))
                }
                .buttonStyle(.plain)
            }

            // Locked configs (shown but disabled)
            ForEach(locked, id: \.name) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.name)
                                .font(.headline)
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(item.requirement)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .opacity(0.5)
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(regimen.name)
                        .font(.headline)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                if let description = regimen.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .textCase(nil)
        }
    }

    /// Handle regimen selection (for masked/random types)
    private func selectRegimen(_ regimen: TrainingRegimen) {
        guard let config = viewModel.configForRegimen(regimen) else {
            print("Failed to get config for regimen: \(regimen.name)")
            return
        }
        launchingFromRegimen = regimen
        selectConfig(config)
    }

    private func configRowWithEditButton(config: SpiralConfig) -> some View {
        HStack {
            Button {
                selectConfig(config)
            } label: {
                ConfigRow(config: config, hasSavedSession: SessionStateManager.shared.hasSavedSession(for: config.name))
            }
            .buttonStyle(.plain)

            Button {
                if let url = viewModel.sourceURL(for: config) {
                    editingURL = url
                    editingConfig = config
                }
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionHeader(for categorized: CategorizedConfigs) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(categorized.category.name)
                .font(.headline)
            Text(categorized.category.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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

    private var variablesSheet: some View {
        NavigationStack {
            VariablesConfigView()
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 300)
        #endif
    }

    #if os(iOS)
    @ViewBuilder
    private var fullscreenContent: some View {
        if let config = selectedConfig {
            SpiralView(config: config, savedState: savedStateToResume)
                .statusBarHidden()
        }
    }
    #endif

    @ViewBuilder
    private func editorSheet(for config: SpiralConfig) -> some View {
        if let url = editingURL {
            ScriptEditorView(config: config, sourceURL: url)
                .environment(viewModel)
        }
    }

    @ViewBuilder
    private var resumeDialogButtons: some View {
        Button("Resume") {
            if let config = resumeConfig {
                launchConfig(config)
            }
        }
        Button("Restart") {
            if let config = resumeConfig {
                SessionStateManager.shared.clearState(for: config.name)
                savedStateToResume = nil
                launchConfig(config)
            }
        }
        Button("Cancel", role: .cancel) {
            resumeConfig = nil
            savedStateToResume = nil
        }
    }

    @ViewBuilder
    private var resumeDialogMessage: some View {
        if let saved = savedStateToResume {
            Text("You have a saved session from \(formatTimeAgo(saved.savedAt)). Would you like to resume where you left off?")
        }
    }

    private func formatTimeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Handle config selection - check for saved state and show dialog if needed
    private func selectConfig(_ config: SpiralConfig) {
        if let savedState = SessionStateManager.shared.loadState(for: config.name),
           savedState.hasProgress {
            // Has saved progress - show resume dialog
            resumeConfig = config
            savedStateToResume = savedState
            showingResumeDialog = true
        } else {
            // No saved state - launch directly
            launchConfig(config)
        }
    }

    /// Launch the config (navigates or shows fullscreen cover)
    private func launchConfig(_ config: SpiralConfig) {
        // Record usage (regimen is tracked via launchingFromRegimen state)
        viewModel.recordUsage(config: config, regimen: launchingFromRegimen)

        #if os(iOS)
        if config.properties.fullscreen {
            selectedConfig = config
            showingFullscreen = true
        } else {
            navigateToConfig = config
        }
        #else
        navigateToConfig = config
        #endif

        // Clear regimen tracking after launch
        launchingFromRegimen = nil
    }
}

struct ConfigRow: View {
    let config: SpiralConfig
    var hasSavedSession: Bool = false

    /// Check if config contains a specific command in any of its scripts
    private func containsCommand(_ commandName: String) -> Bool {
        for (_, elements) in config.scripts {
            for element in elements {
                if case .word(let word) = element {
                    if word.hasPrefix("!\(commandName)(") {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Check if config uses typing-only mantra (!mantra)
    private var hasTypingMantra: Bool {
        containsCommand("mantra")
    }

    /// Check if config uses speech mantra (!speak_mantra)
    private var hasSpeechMantra: Bool {
        containsCommand("speak_mantra")
    }

    /// Check if config uses speaking (!speaking_on)
    private var hasSpeaking: Bool {
        containsCommand("speaking_on")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(config.name)
                    .font(.headline)
                if hasSavedSession {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
            }

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

                if hasSpeaking {
                    Label("Voice", systemImage: "speaker.wave.2")
                        .font(.caption2)
                        .foregroundColor(.green)
                }

                if hasTypingMantra {
                    Label("Typing", systemImage: "keyboard")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                if hasSpeechMantra {
                    Label("Mic", systemImage: "mic.fill")
                        .font(.caption2)
                        .foregroundColor(.cyan)
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
