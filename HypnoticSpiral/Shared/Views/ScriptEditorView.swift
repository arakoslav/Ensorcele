//
//  ScriptEditorView.swift
//  HypnoticSpiral
//
//  JSON editor for spiral configuration scripts with friendly text editing
//

import SwiftUI

struct ScriptEditorView: View {
    let config: SpiralConfig
    let sourceURL: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(ConfigListViewModel.self) private var viewModel

    @State private var propertiesText: String = ""
    @State private var scriptsText: [String: String] = [:]  // section name -> friendly text
    @State private var selectedScript: String = "text"
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var showingSaveSuccess: Bool = false
    @State private var isReadOnly: Bool = false
    @State private var showRawJSON: Bool = false
    @State private var rawJSONText: String = ""

    private var scriptNames: [String] {
        Array(scriptsText.keys).sorted()
    }

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    // MARK: - macOS Layout
    #if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Edit: \(config.name)")
                    .font(.headline)

                Spacer()

                Toggle("Raw JSON", isOn: $showRawJSON)
                    .toggleStyle(.checkbox)

                Button {
                    saveConfig()
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || isLoading)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Error banner
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") {
                        errorMessage = nil
                    }
                    .font(.caption)
                }
                .padding(8)
                .background(Color.red.opacity(0.2))
            }

            // Read-only banner
            if isReadOnly {
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.orange)
                    Text("This config is in the app bundle. Saving will create a copy in your iCloud folder.")
                        .font(.caption)
                    Spacer()
                }
                .padding(8)
                .background(Color.orange.opacity(0.2))
            }

            // Editor
            if isLoading {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else if showRawJSON {
                TextEditor(text: $rawJSONText)
                    .font(.system(.body, design: .monospaced))
            } else {
                friendlyEditor
            }
        }
        .frame(width: 800, height: 700)
        .task {
            await loadConfig()
        }
        .alert("Saved", isPresented: $showingSaveSuccess) {
            Button("OK") {
                viewModel.reload()
                dismiss()
            }
        } message: {
            Text("Configuration saved successfully.")
        }
        .onChange(of: showRawJSON) { _, newValue in
            if newValue {
                // Switching to raw JSON - rebuild from current edits
                rebuildRawJSON()
            } else {
                // Switching to friendly - parse raw JSON
                parseRawJSON()
            }
        }
    }
    #endif

    // MARK: - iOS Layout
    #if os(iOS)
    private var iOSBody: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Error banner
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(error)
                            .font(.caption)
                        Spacer()
                        Button("Dismiss") {
                            errorMessage = nil
                        }
                        .font(.caption)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.2))
                }

                // Read-only banner
                if isReadOnly {
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.orange)
                        Text("This config is in the app bundle. Saving will create a copy in your iCloud folder.")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.2))
                }

                // Editor
                if isLoading {
                    Spacer()
                    ProgressView("Loading...")
                    Spacer()
                } else if showRawJSON {
                    TextEditor(text: $rawJSONText)
                        .font(.system(.body, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                } else {
                    friendlyEditor
                }
            }
            .navigationTitle("Edit: \(config.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    Toggle("Raw JSON", isOn: $showRawJSON)
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveConfig()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving || isLoading)
                }
            }
            .alert("Saved", isPresented: $showingSaveSuccess) {
                Button("OK") {
                    viewModel.reload()
                    dismiss()
                }
            } message: {
                Text("Configuration saved successfully.")
            }
        }
        .task {
            await loadConfig()
        }
        .onChange(of: showRawJSON) { _, newValue in
            if newValue {
                rebuildRawJSON()
            } else {
                parseRawJSON()
            }
        }
    }
    #endif

    // MARK: - Friendly Editor

    private var friendlyEditor: some View {
        HSplitView {
            // Left: Properties JSON
            VStack(alignment: .leading, spacing: 4) {
                Text("Properties (JSON)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $propertiesText)
                    .font(.system(.body, design: .monospaced))
            }
            .frame(minWidth: 250)
            .padding(.leading, 8)
            .padding(.vertical, 8)

            // Right: Scripts
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Script:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Script", selection: $selectedScript) {
                        ForEach(scriptNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)

                    Spacer()

                    Text("Separate words with spaces or newlines. Commands like !pause(3) and [[voice]] stay together.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let binding = bindingForScript(selectedScript) {
                    TextEditor(text: binding)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .frame(minWidth: 400)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
        }
    }

    private func bindingForScript(_ name: String) -> Binding<String>? {
        guard scriptsText[name] != nil else { return nil }
        return Binding(
            get: { scriptsText[name] ?? "" },
            set: { scriptsText[name] = $0 }
        )
    }

    // MARK: - Parsing

    private func loadConfig() async {
        isLoading = true
        errorMessage = nil

        isReadOnly = !iCloudResourceManager.shared.isConfigWritable(sourceURL)

        do {
            let data = try iCloudResourceManager.shared.readConfigData(from: sourceURL)

            guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                errorMessage = "Invalid JSON structure"
                isLoading = false
                return
            }

            // Store raw JSON for raw mode
            if let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                rawJSONText = prettyString
            }

            // Extract properties (everything except "scripts", "name", "description", "base")
            var props: [String: Any] = [:]
            if let p = jsonObject["properties"] as? [String: Any] {
                props = p
            }
            if let propsData = try? JSONSerialization.data(withJSONObject: props, options: [.prettyPrinted, .sortedKeys]),
               let propsString = String(data: propsData, encoding: .utf8) {
                propertiesText = propsString
            }

            // Extract scripts and convert to friendly text
            if let scripts = jsonObject["scripts"] as? [String: [String]] {
                for (name, words) in scripts {
                    scriptsText[name] = wordsToFriendlyText(words)
                }
            }

            if !scriptNames.contains(selectedScript), let first = scriptNames.first {
                selectedScript = first
            }

        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Convert array of words to space-separated friendly text
    private func wordsToFriendlyText(_ words: [String]) -> String {
        words.joined(separator: " ")
    }

    /// Parse friendly text back to array of words
    /// Keeps !commands(with args) and [[voice commands]] as single items
    private func friendlyTextToWords(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var i = text.startIndex

        while i < text.endIndex {
            let c = text[i]

            if c == "!" {
                // Start of a bang command - read until end of command
                if !current.trimmingCharacters(in: .whitespaces).isEmpty {
                    words.append(contentsOf: splitSimpleText(current))
                    current = ""
                }
                let cmd = readBangCommand(from: text, at: &i)
                if !cmd.isEmpty {
                    words.append(cmd)
                }
            } else if c == "[" && text.index(after: i) < text.endIndex && text[text.index(after: i)] == "[" {
                // Start of [[voice command]]
                if !current.trimmingCharacters(in: .whitespaces).isEmpty {
                    words.append(contentsOf: splitSimpleText(current))
                    current = ""
                }
                let voice = readVoiceCommand(from: text, at: &i)
                if !voice.isEmpty {
                    words.append(voice)
                }
            } else {
                current.append(c)
                i = text.index(after: i)
            }
        }

        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            words.append(contentsOf: splitSimpleText(current))
        }

        return words
    }

    /// Split simple text on whitespace
    private func splitSimpleText(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Read a !command(args) from text, advancing index past it
    private func readBangCommand(from text: String, at i: inout String.Index) -> String {
        var result = ""
        var parenDepth = 0
        var inCommand = true

        while i < text.endIndex && inCommand {
            let c = text[i]
            result.append(c)

            if c == "(" {
                parenDepth += 1
            } else if c == ")" {
                parenDepth -= 1
                if parenDepth == 0 {
                    i = text.index(after: i)
                    return result
                }
            } else if c.isWhitespace && parenDepth == 0 {
                // End of command without parens
                return result.trimmingCharacters(in: .whitespaces)
            }

            i = text.index(after: i)
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Read a [[voice command]] from text, advancing index past it
    private func readVoiceCommand(from text: String, at i: inout String.Index) -> String {
        var result = ""
        var bracketDepth = 0

        while i < text.endIndex {
            let c = text[i]
            result.append(c)

            if c == "[" {
                bracketDepth += 1
            } else if c == "]" {
                bracketDepth -= 1
                if bracketDepth == 0 {
                    i = text.index(after: i)
                    return result
                }
            }

            i = text.index(after: i)
        }

        return result
    }

    // MARK: - Raw JSON sync

    private func rebuildRawJSON() {
        do {
            guard var jsonObject = try JSONSerialization.jsonObject(with: rawJSONText.data(using: .utf8) ?? Data()) as? [String: Any] else {
                return
            }

            // Update properties
            if let propsData = propertiesText.data(using: .utf8),
               let props = try? JSONSerialization.jsonObject(with: propsData) as? [String: Any] {
                jsonObject["properties"] = props
            }

            // Update scripts
            var scripts: [String: [String]] = [:]
            for (name, text) in scriptsText {
                scripts[name] = friendlyTextToWords(text)
            }
            jsonObject["scripts"] = scripts

            if let data = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                rawJSONText = str
            }
        } catch {
            // Keep existing raw JSON
        }
    }

    private func parseRawJSON() {
        guard let data = rawJSONText.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            errorMessage = "Invalid JSON"
            showRawJSON = true
            return
        }

        // Extract properties
        if let props = jsonObject["properties"] as? [String: Any],
           let propsData = try? JSONSerialization.data(withJSONObject: props, options: [.prettyPrinted, .sortedKeys]),
           let propsString = String(data: propsData, encoding: .utf8) {
            propertiesText = propsString
        }

        // Extract scripts
        if let scripts = jsonObject["scripts"] as? [String: [String]] {
            scriptsText = [:]
            for (name, words) in scripts {
                scriptsText[name] = wordsToFriendlyText(words)
            }
        }
    }

    // MARK: - Save

    private func saveConfig() {
        isSaving = true
        errorMessage = nil

        do {
            let jsonObject: [String: Any]

            if showRawJSON {
                // Save from raw JSON
                guard let data = rawJSONText.data(using: .utf8),
                      let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    errorMessage = "Invalid JSON"
                    isSaving = false
                    return
                }
                jsonObject = obj
            } else {
                // Build JSON from friendly editor
                guard let data = rawJSONText.data(using: .utf8),
                      var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    errorMessage = "Invalid base JSON"
                    isSaving = false
                    return
                }

                // Update properties
                if let propsData = propertiesText.data(using: .utf8),
                   let props = try JSONSerialization.jsonObject(with: propsData) as? [String: Any] {
                    obj["properties"] = props
                }

                // Update scripts
                var scripts: [String: [String]] = [:]
                for (name, text) in scriptsText {
                    scripts[name] = friendlyTextToWords(text)
                }
                obj["scripts"] = scripts

                jsonObject = obj
            }

            // Generate the "Edited" filename
            let editedFilename = iCloudResourceManager.shared.generateEditedFilename(from: sourceURL)

            // Update the name in the JSON
            var finalObject = jsonObject
            let baseName = editedFilename.replacingOccurrences(of: ".json", with: "")
            finalObject["name"] = baseName

            // Convert to data
            let updatedData = try JSONSerialization.data(withJSONObject: finalObject, options: [.prettyPrinted, .sortedKeys])

            // Save
            try iCloudResourceManager.shared.saveConfig(data: updatedData, to: editedFilename)

            showingSaveSuccess = true
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }
}

#Preview {
    let mockConfig = try! JSONDecoder().decode(SpiralConfig.self, from: """
    {
        "name": "Preview",
        "description": "Preview config",
        "properties": {},
        "scripts": {"text": ["hello", "world", "!pause(3)", "[[speak slowly]]", "test"]}
    }
    """.data(using: .utf8)!)

    ScriptEditorView(
        config: mockConfig,
        sourceURL: URL(fileURLWithPath: "/tmp/test.json")
    )
    .environment(ConfigListViewModel())
}
