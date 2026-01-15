//
//  ScriptEditorView.swift
//  HypnoticSpiral
//
//  JSON editor for spiral configuration scripts
//

import SwiftUI

struct ScriptEditorView: View {
    let config: SpiralConfig
    let sourceURL: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(ConfigListViewModel.self) private var viewModel

    @State private var jsonText: String = ""
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var showingSaveSuccess: Bool = false
    @State private var isReadOnly: Bool = false
    @State private var writableURL: URL?

    var body: some View {
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
                } else {
                    #if os(iOS)
                    TextEditor(text: $jsonText)
                        .font(.system(.body, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    #else
                    ScrollView {
                        TextEditor(text: $jsonText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    #endif
                }
            }
            .navigationTitle("Edit: \(config.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
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

                #if os(macOS)
                ToolbarItem(placement: .automatic) {
                    Button {
                        formatJSON()
                    } label: {
                        Label("Format", systemImage: "text.alignleft")
                    }
                    .help("Format JSON")
                }
                #endif
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
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
    }

    private func loadConfig() async {
        isLoading = true
        errorMessage = nil

        // Check if writable
        isReadOnly = !iCloudResourceManager.shared.isConfigWritable(sourceURL)

        do {
            let data = try iCloudResourceManager.shared.readConfigData(from: sourceURL)

            // Pretty-print the JSON
            if let jsonObject = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                jsonText = prettyString
            } else if let rawString = String(data: data, encoding: .utf8) {
                jsonText = rawString
            } else {
                errorMessage = "Could not decode file as text"
            }
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func saveConfig() {
        isSaving = true
        errorMessage = nil

        // Validate JSON first
        guard let jsonData = jsonText.data(using: .utf8) else {
            errorMessage = "Could not encode text"
            isSaving = false
            return
        }

        do {
            // Validate it's valid JSON
            guard var jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                errorMessage = "Invalid JSON structure"
                isSaving = false
                return
            }

            // Generate the "Edited" filename
            let editedFilename = iCloudResourceManager.shared.generateEditedFilename(from: sourceURL)

            // Update the name in the JSON to reflect the edited version
            let baseName = editedFilename.replacingOccurrences(of: ".json", with: "")
            jsonObject["name"] = baseName

            // Convert back to data
            let updatedData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])

            // Save to local storage with the edited filename
            try iCloudResourceManager.shared.saveConfig(data: updatedData, to: editedFilename)

            showingSaveSuccess = true
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }

    /// The filename that will be used when saving
    private var saveFilename: String {
        iCloudResourceManager.shared.generateEditedFilename(from: sourceURL)
    }

    private func formatJSON() {
        guard let data = jsonText.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            errorMessage = "Invalid JSON - cannot format"
            return
        }
        jsonText = prettyString
    }
}

#Preview {
    // Create a mock config for preview
    let mockConfig = try! JSONDecoder().decode(SpiralConfig.self, from: """
    {
        "name": "Preview",
        "description": "Preview config",
        "properties": {},
        "scripts": {"text": ["hello", "world"]}
    }
    """.data(using: .utf8)!)

    return ScriptEditorView(
        config: mockConfig,
        sourceURL: URL(fileURLWithPath: "/tmp/test.json")
    )
    .environment(ConfigListViewModel())
}
